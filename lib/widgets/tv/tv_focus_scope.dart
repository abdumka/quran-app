// Tristate is a dart:ui type; SemanticsData.flagsCollection returns it.
import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../services/tv_popup_observer.dart';
import '../../services/tv_service.dart';

/// Makes an arbitrary screen drivable by a TV remote without rewriting it.
///
/// Wrap any existing page and on Android TV it gains D-pad navigation, Select
/// activation, and a gold ring over the current target. Off TV it is a
/// pass-through.
///
/// **Why the semantics tree and not Flutter focus.** The first version walked
/// the focus tree, which only reaches widgets that can hold focus. Most of this
/// app's settings rows are plain `GestureDetector`s, and collapsible sections
/// like "إعدادات متقدمة" and "إعدادات التلاوة والتفسير" have tappable headers
/// that never take focus — so they were simply unreachable, as was every
/// confirmation dialog (تحميل الهوامش could be started but never confirmed).
/// Every tappable widget publishes a semantics node with a tap action, which is
/// exactly what an accessibility service drives, so that is what this uses.
///
/// Collection is from the *global* semantics root, narrowed to the innermost
/// route scope. That means a dialog opened above a wrapped page is driven by
/// the page's scope — no extra wrapping needed at each `showDialog` call site.
/// Identifies the focus ring in the widget tree, for tests.
const Key kTvFocusRingKey = ValueKey('tvFocusRing');

class TvFocusScope extends StatefulWidget {
  const TvFocusScope({super.key, required this.child}) : popupsOnly = false;

  /// The single app-wide driver for dialogs and modal bottom sheets.
  ///
  /// Placed above the navigator in main(), it stands down entirely except
  /// while a [PopupRoute] is on top — see [TvPopupObserver] for why that is
  /// the right trigger. Without it a popup opened from a screen that drives
  /// its own D-pad (the reader, الفهرس) had nothing driving it at all, and
  /// since Select is blocked app-wide its buttons did literally nothing.
  const TvFocusScope.popupDriver({super.key, required this.child})
    : popupsOnly = true;

  final Widget child;

  /// Whether this scope only engages while a popup route is on top.
  final bool popupsOnly;

  @override
  State<TvFocusScope> createState() => _TvFocusScopeState();
}

class _TvFocusScopeState extends State<TvFocusScope> {
  /// Only the innermost wrapper reacts, so nested scopes do not double-handle.
  static final List<_TvFocusScopeState> _stack = [];

  SemanticsHandle? _semantics;

  /// The target is remembered by POSITION, not by semantics node id: ids are
  /// recycled whenever the tree updates, so an id-based target silently reset
  /// to the first item (the back arrow) and Select then closed the page.
  Rect? _anchor;

  /// Vertical presses that arrived while a scrolled step was still waiting
  /// for its frame. Applied together rather than discarded.
  int _pendingSteps = 0;
  TraversalDirection? _pendingDir;
  bool _stepScheduled = false;

  /// Semantics id of the current target. Used ONLY to correct that node's
  /// rect after a scroll -- never to find the target, because ids are
  /// recycled when the tree rebuilds.
  int? _targetId;

  /// Global coordinates. The ring lives in the ROOT overlay, not in this
  /// subtree: a dialog or sheet paints above the wrapped page, so a ring drawn
  /// inside the page is hidden behind it -- the margins confirm dialog was
  /// being targeted correctly but looked unreachable.
  Rect? _highlight;
  OverlayEntry? _ringEntry;

  /// Which route scope (page, dialog, dropdown menu) the targets came from,
  /// plus where the highlight was in each scope we stepped out of. When a
  /// menu opens we remember the control that opened it; when it closes we go
  /// back there. Without this, picking a surah in تكرار مقطع left the
  /// highlight wherever the chosen row had been (it landed on ×5).
  ///
  /// Each scope is recognised by its on-screen RECT. Node ids are recycled
  /// when a dialog rebuilds under an open menu, and counting scopes fails too:
  /// routes under a modal barrier drop out of the semantics tree entirely, so
  /// the count swings 2 -> 0 -> 1 while a menu is up. A dialog occupies the
  /// same rectangle before and after, which is what identifies it.
  Rect? _scopeRect;
  Rect? _lastScopeRect;
  final List<(Rect, Rect?)> _scopeStack = [];

  bool get _active => TvService.instance.isTv;
  bool get _isTop => _stack.isNotEmpty && identical(_stack.last, this);

  /// The popup driver waits for a popup; every other scope is always open.
  /// A scope wrapping a page is nearer the popup in the nesting than the root
  /// driver is, so [_isTop] hands that page's scope the dialog as before and
  /// the root one stays out of it.
  bool get _gateOpen =>
      !widget.popupsOnly || TvPopupObserver.instance.popupOnTop.value;

  bool get _drives => _active && _isTop && _gateOpen;

  @override
  void initState() {
    super.initState();
    if (!_active) return;
    // Semantics are off unless something asks for them; the tree we navigate
    // does not exist otherwise.
    _semantics = SemanticsBinding.instance.ensureSemantics();
    _stack.add(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    if (widget.popupsOnly) {
      TvPopupObserver.instance.popupOnTop.addListener(_onPopupChanged);
    }
    // Semantics are not built on the first frame, so retry briefly rather than
    // making the user spend an arrow press waking the highlight up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _retarget(null));
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted && _anchor == null) _retarget(null);
    });
  }

  @override
  void dispose() {
    if (_active) {
      HardwareKeyboard.instance.removeHandler(_onKey);
      if (widget.popupsOnly) {
        TvPopupObserver.instance.popupOnTop.removeListener(_onPopupChanged);
      }
      _stack.remove(this);
      _ringEntry?.remove();
      _ringEntry = null;
      _semantics?.dispose();
    }
    super.dispose();
  }

  /// A popup opened or closed: pick up its first target, or drop the ring.
  void _onPopupChanged() {
    if (!mounted || !_active) return;
    // Rebuild: the arrow barrier in build() is gated on the same flag.
    setState(() {});
    // A popup above a wrapped page is driven by that page's scope, not by
    // this one -- resolving a target here would only produce a second ring.
    if (!_isTop) {
      _anchor = null;
      _highlight = null;
      _syncRing();
      return;
    }
    if (!TvPopupObserver.instance.popupOnTop.value) {
      _anchor = null;
      _highlight = null;
      _scopeRect = null;
      _lastScopeRect = null;
      _scopeStack.clear();
      _syncRing();
      return;
    }
    // A route's semantics are not built on the frame it is pushed, and a
    // dialog animates in, so retry briefly rather than showing no ring until
    // the first arrow press.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _retarget(null);
    });
    for (final ms in const [120, 300, 500]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted && _anchor == null) _retarget(null);
      });
    }
  }

  // ---- semantics walking -------------------------------------------------

  /// Tappable nodes of the innermost route scope, with global rects.
  List<_TvTarget> _targets() {
    final owner = context.findRenderObject()?.owner?.semanticsOwner;
    final root = owner?.rootSemanticsNode;
    if (root == null) return const [];

    // A dialog or sheet pushes its own route scope; the last one in tree order
    // is what the user is actually looking at.
    SemanticsNode scope = root;
    Rect scopeRect = root.rect;
    bool foundScope = false;
    void findScope(SemanticsNode n, Matrix4 inherited) {
      final m = Matrix4.copy(inherited);
      if (n.transform != null) m.multiply(n.transform!);
      if (n.getSemanticsData().flagsCollection.scopesRoute) {
        scope = n;
        scopeRect = MatrixUtils.transformRect(m, n.rect);
        foundScope = true;
      }
      n.visitChildren((c) {
        findScope(c, m);
        return true;
      });
    }

    findScope(root, Matrix4.identity());
    // Mid-transition (a menu opening or closing) there is briefly no route
    // scope at all. Treat that frame as "nothing to target" rather than as a
    // full-screen scope, which would match the page underneath and throw
    // away where the user was.
    if (!foundScope) return const [];
    _lastScopeRect = scopeRect;

    final out = <_TvTarget>[];
    // A node's rect is in its own space and `transform` maps that to its
    // parent, so the global rect needs the ancestors' transforms accumulated
    // on the way down. SemanticsNode has no getTransformTo().
    void walk(SemanticsNode n, Matrix4 inherited) {
      final m = Matrix4.copy(inherited);
      if (n.transform != null) m.multiply(n.transform!);
      final data = n.getSemanticsData();
      final bool hidden = data.flagsCollection.isHidden;
      final bool tappable = data.hasAction(SemanticsAction.tap);
      final bool adjustable =
          data.hasAction(SemanticsAction.increase) ||
          data.hasAction(SemanticsAction.decrease);
      final flags = data.flagsCollection;
      // isSelected is a Tristate in this Flutter version.
      final bool selected = flags.isSelected == Tristate.isTrue;
      if ((tappable || adjustable) && !hidden && !n.rect.isEmpty) {
        final r = MatrixUtils.transformRect(m, n.rect);
        if (r.width > 1 && r.height > 1) {
          out.add(
            _TvTarget(n.id, r, adjustable: adjustable, selected: selected),
          );
        }
      }
      n.visitChildren((c) {
        walk(c, m);
        return true;
      });
    }

    walk(scope, Matrix4.identity());

    // Reading order: top to bottom, then right to left (the UI is RTL).
    out.sort((a, b) {
      final dy = a.rect.top.compareTo(b.rect.top);
      if (dy != 0 && (a.rect.top - b.rect.top).abs() > 8) return dy;
      return b.rect.left.compareTo(a.rect.left);
    });
    return out;
  }

  /// Returns true when the highlight moved to a different target.
  bool _retarget(TraversalDirection? dir) {
    if (!mounted) return false;
    final targets = _targets();
    if (targets.isEmpty) {
      if (_highlight != null) {
        _highlight = null;
        _syncRing();
      }
      return false;
    }

    // Entering a new scope: remember where we were and start fresh on the
    // new scope's current value. Returning to an earlier scope: restore it.
    final sr = _lastScopeRect;
    final prev = _scopeRect;
    if (sr != null && prev != null && !_sameRect(sr, prev)) {
      final back = _scopeStack.lastIndexWhere((e) => _sameRect(e.$1, sr));
      if (back >= 0) {
        // Back to a scope we left (a menu closed): return to what opened it.
        _anchor = _scopeStack[back].$2;
        _scopeStack.removeRange(back, _scopeStack.length);
      } else {
        // A new scope (a menu or dialog opened): start on its current value.
        _scopeStack.add((prev, _anchor));
        _anchor = null;
      }
    }
    _scopeRect = sr;

    // By id first. The snapshot below may be a frame or two behind a scroll,
    // and matching by position against stale rects is what used to pick the
    // neighbouring row and compound the error step after step.
    _TvTarget? current;
    final wantId = _targetId;
    if (wantId != null) {
      for (final t in targets) {
        if (t.id == wantId) {
          current = t;
          break;
        }
      }
    }
    current ??= _resolve(targets);

    // How far this snapshot is behind the screen. Every rect in it comes from
    // the same frame, so the snapshot is internally consistent even when it
    // is stale: one offset, measured against the rect we know is current,
    // converts any of them to real screen coordinates. That is what makes the
    // next row's rect right immediately instead of half a second later.
    double lag = 0;
    if (current != null && _highlight != null) {
      lag = _highlight!.top - current.rect.top;
    }

    final _TvTarget next;
    if (current == null || dir == null) {
      // Fresh target set (a chooser just opened): start on the current value
      // if one is marked, otherwise the first entry.
      next =
          current ??
          targets.firstWhere((t) => t.selected, orElse: () => targets.first);
    } else {
      next = _nearest(targets, current, dir) ?? current;
    }

    var nextRect = lag == 0 ? next.rect : next.rect.shift(Offset(0, lag));
    // A row scrolled in on this very frame can still carry a collapsed rect:
    // the node exists but has not been laid out. Painting it is what put a
    // "small box" on screen for the half second before a correction arrived,
    // and holding the arrow down outran that correction. Keep the previous
    // rect instead -- the ring stays on the old row for a frame rather than
    // flashing something wrong, and _correctRect moves it as soon as the real
    // geometry exists.
    final lastRect = _highlight;
    if (lastRect != null &&
        current != null &&
        nextRect.height < current.rect.height * 0.6) {
      nextRect = lastRect;
    }
    _anchor = nextRect;
    _highlight = nextRect;
    _targetId = next.id;
    _syncRing();
    // Routes animate. A dialog scales in, a bottom sheet slides up, a
    // dropdown expands -- so the rect read on the frame the target is chosen
    // is a rect in motion, and the ring was left wherever the animation
    // happened to be. That is why it straddled the title of خيارات التلاوة
    // instead of wrapping القارئ. Correcting afterwards costs nothing and
    // covers every animated surface at once.
    _resyncFromSemantics();
    return current == null || next.id != current.id;
  }

  static bool _sameRect(Rect a, Rect b) =>
      (a.left - b.left).abs() < 4 &&
      (a.top - b.top).abs() < 4 &&
      (a.right - b.right).abs() < 4 &&
      (a.bottom - b.bottom).abs() < 4;

  /// Re-finds the remembered target after a rebuild by nearest position.
  _TvTarget? _resolve(List<_TvTarget> targets) {
    final anchor = _anchor;
    if (anchor == null) return null;
    _TvTarget? best;
    double bestD = double.infinity;
    for (final t in targets) {
      final d = (t.rect.center - anchor.center).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = t;
      }
    }
    // Too far means the old target is gone (a dialog opened, a list scrolled
    // right past it); start fresh rather than jumping somewhere arbitrary.
    if (best != null && bestD > 400 * 400) return null;
    return best;
  }

  /// Keeps the ring in the root overlay so it paints above dialogs and sheets.
  ///
  /// Only the scope that is actually driving may show one. Scopes are nested
  /// -- the popup driver sits above the whole app and a wrapped page sits
  /// inside it -- and every one of them owns an overlay entry, so without
  /// this the user sees TWO rings: the real one tracking the arrows, plus a
  /// stale one parked wherever the idle scope last resolved. That is the
  /// "weird small box" next to the تكرار مقطع pickers.
  void _syncRing() {
    if (!_drives && _ringEntry != null) {
      _ringEntry!.remove();
      _ringEntry = null;
      return;
    }
    if (!_drives) return;
    _syncRingInner();
  }

  void _syncRingInner() {
    // The popup driver sits ABOVE the navigator, so there is no Overlay
    // ancestor to find from its context; fall back to the one the app's
    // navigator owns, which is where the dialogs it drives are painted.
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ??
        kAppNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    if (_highlight == null) {
      _ringEntry?.remove();
      _ringEntry = null;
      return;
    }
    if (_ringEntry == null) {
      _ringEntry = OverlayEntry(
        builder: (_) {
          final r = _highlight;
          if (r == null) return const SizedBox.shrink();
          return Positioned.fromRect(
            rect: r.inflate(4),
            child: IgnorePointer(
              // Keyed so a test can measure where the ring actually landed
              // and compare it with the row it is meant to wrap.
              key: kTvFocusRingKey,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD2B97E), width: 3),
                  color: const Color(0xFFD2B97E).withValues(alpha: 0.14),
                ),
              ),
            ),
          );
        },
      );
      overlay.insert(_ringEntry!);
    } else {
      _ringEntry!.markNeedsBuild();
    }
  }

  /// Up/Down step through reading order; Left/Right move geometrically.
  ///
  /// Vertical movement is deliberately ordinal rather than geometric. On a
  /// hand-built settings page, "nearest above" regularly found nothing —
  /// collapsed section headers sit in cards of their own and a row of buttons
  /// at the bottom trapped the highlight. Stepping the sorted list guarantees
  /// every target is reachable by holding Down, which matters more here than
  /// spatial purity.
  _TvTarget? _nearest(
    List<_TvTarget> all,
    _TvTarget from,
    TraversalDirection dir,
  ) {
    final idx = all.indexWhere((t) => t.id == from.id);
    if (idx < 0) return null;

    if (dir == TraversalDirection.down || dir == TraversalDirection.up) {
      final next = dir == TraversalDirection.down ? idx + 1 : idx - 1;
      if (next < 0 || next >= all.length) return null;
      return all[next];
    }

    // Horizontal: prefer a target on roughly the same line.
    final sameRow = all.where(
      (t) =>
          t.id != from.id &&
          (t.rect.center.dy - from.rect.center.dy).abs() < from.rect.height,
    );
    _TvTarget? best;
    double bestD = double.infinity;
    for (final t in sameRow) {
      final dx = t.rect.center.dx - from.rect.center.dx;
      final wanted = dir == TraversalDirection.left ? dx < 0 : dx > 0;
      if (!wanted) continue;
      if (dx.abs() < bestD) {
        bestD = dx.abs();
        best = t;
      }
    }
    if (best != null) return best;
    // Fall back to reading order so Left/Right never dead-ends either.
    final next = dir == TraversalDirection.left ? idx + 1 : idx - 1;
    if (next < 0 || next >= all.length) return null;
    return all[next];
  }

  // ---- keys --------------------------------------------------------------

  bool _onKey(KeyEvent event) {
    if (!mounted || !_drives) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final key = event.logicalKey;
    TraversalDirection? dir;
    if (key == LogicalKeyboardKey.arrowDown) dir = TraversalDirection.down;
    if (key == LogicalKeyboardKey.arrowUp) dir = TraversalDirection.up;
    if (key == LogicalKeyboardKey.arrowLeft) dir = TraversalDirection.left;
    if (key == LogicalKeyboardKey.arrowRight) dir = TraversalDirection.right;

    if (dir != null) {
      // On a slider, Left/Right change the value instead of moving on. The
      // bar fills from the right in this RTL layout, so Left is "more".
      if (dir == TraversalDirection.left || dir == TraversalDirection.right) {
        final target = _resolve(_targets());
        if (target != null && target.adjustable) {
          context.findRenderObject()?.owner?.semanticsOwner?.performAction(
            target.id,
            dir == TraversalDirection.left
                ? SemanticsAction.increase
                : SemanticsAction.decrease,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) => _retarget(null));
          return true;
        }
      }
      final vertical =
          dir == TraversalDirection.up || dir == TraversalDirection.down;
      // Scroll rather than step out of the list the highlight is in, while
      // that list still has somewhere to go. See _stepLeavesScrollable.
      if (vertical && _stepLeavesScrollable(dir) && _scrollPage(dir)) {
        // The step has to wait a frame for the newly scrolled-in rows to
        // exist, but the presses must not be LOST while it waits. Holding
        // the arrow down used to drop every press that happened to land in
        // this branch, so the ring fell a row behind and looked like it had
        // drifted off the list. Count them and apply the whole backlog once
        // the rows are there.
        _pendingSteps++;
        _pendingDir = dir;
        if (!_stepScheduled) {
          _stepScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _stepScheduled = false;
            if (!mounted) return;
            final n = _pendingSteps;
            final d = _pendingDir;
            _pendingSteps = 0;
            if (d == null) return;
            for (int i = 0; i < n; i++) {
              _retarget(d);
            }
            _ensureVisible();
          });
        }
        return true;
      }
      final moved = _retarget(dir);
      if (!moved && vertical && _scrollPage(dir)) {
        // Long lists (the 114-surah picker in تكرار مقطع) only build the rows
        // that are on screen, so the last visible row looked like the end of
        // the list and Down went nowhere. Scroll to build the next rows, then
        // take the step again.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _retarget(dir);
          _ensureVisible();
        });
        return true;
      }
      _ensureVisible();
      return true;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      final target = _resolve(_targets());
      if (target != null) {
        // The anchor is deliberately KEPT. Clearing it here sent the highlight
        // back to the top of the list after every toggle. Material also places
        // a dropdown so its selected row sits under the button, so keeping the
        // anchor is what makes a chooser open on the current value.

        context.findRenderObject()?.owner?.semanticsOwner?.performAction(
          target.id,
          SemanticsAction.tap,
        );
        // The tap may expand a section or open a menu. The new subtree's
        // semantics are not built on the very next frame, so retry briefly --
        // otherwise a dropdown opens with no highlight at all.
        WidgetsBinding.instance.addPostFrameCallback((_) => _retarget(null));
        // Menus also animate CLOSED (~300 ms), so keep retrying past that —
        // otherwise the ring only reappears on the next key press.
        for (final ms in const [120, 300, 500, 800]) {
          Future.delayed(Duration(milliseconds: ms), () {
            if (mounted) _retarget(null);
          });
        }
      }
      return true;
    }
    return false;
  }

  /// Scrolls the target into view, using the scrollable that actually
  /// CONTAINS it.
  ///
  /// The first version grabbed the first Scrollable inside this subtree, which
  /// for a Material dropdown meant scrolling the settings page *behind* the
  /// open menu — the background slid, the ring drifted out of alignment with
  /// the rows, and the last entry could never be reached. Searching from the
  /// root element covers overlay routes (dropdowns, sheets) as well.
  void _ensureVisible() {
    final rect = _highlight;
    if (rect == null) return;
    final hit = _scrollableContaining(rect);
    if (hit == null) return;
    final (pos, viewport) = hit;

    const margin = 40.0;
    double delta = 0;
    if (rect.top < viewport.top + margin) {
      delta = rect.top - (viewport.top + margin);
    } else if (rect.bottom > viewport.bottom - margin) {
      delta = rect.bottom - (viewport.bottom - margin);
    }
    if (delta == 0) return;

    final target = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    final applied = target - pos.pixels;
    if (applied == 0) return;
    pos.jumpTo(target);
    // Provisional: good enough for one frame if the flush below cannot run.
    _anchor = _anchor?.shift(Offset(0, -applied));
    _highlight = _highlight?.shift(Offset(0, -applied));
    _syncRing();
    _resyncFromSemantics();
  }

  /// Re-reads the current target's rect from the semantics tree on the next
  /// frame, replacing whatever the scroll arithmetic guessed.
  ///
  /// Shifting the cached rect by the applied scroll delta is only an
  /// estimate: the semantics tree is a frame behind the jump, so each step
  /// carries a small error and the errors ADD UP. On the تكرار مقطع surah
  /// picker the ring sat exactly on 8. الأنفال, slid further off the row
  /// through 9, 10 and 11, then snapped back onto 12. يوسف when a larger
  /// relayout happened to resync it. Reading the real rect once the frame is
  /// laid out means the error can never accumulate past a single step.
  void _resyncFromSemantics() {
    final id = _targetId;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _correctRect(id));
    // Past the end of the usual Material animations, so a ring that was
    // placed while something was still moving ends up where it belongs.
    for (final ms in const [120, 320, 600]) {
      Future.delayed(Duration(milliseconds: ms), () => _correctRect(id));
    }
  }

  void _correctRect(int id) {
    if (!mounted || !_drives) return;
    if (_targetId != id) return;
    // Look the SAME node up by id and take its settled rect. Re-resolving by
    // nearest-centre instead would let the ring jump to a different, smaller
    // node that happens to sit near the anchor -- which is exactly what
    // collapsed it to a little box beside the تكرار مقطع pickers.
    for (final t in _targets()) {
      if (t.id != id) continue;
      if (_highlight != null && _sameRect(t.rect, _highlight!)) return;
      _anchor = t.rect;
      _highlight = t.rect;
      _syncRing();
      return;
    }
  }

  /// Whether one vertical step would take the highlight out of the scrollable
  /// it is currently in, while that scrollable can still scroll that way.
  ///
  /// Vertical movement walks the sorted target list, and that list only holds
  /// semantics nodes that EXIST. A lazy list does not build the rows scrolled
  /// off above it, so from the topmost built row of إعدادات the previous entry
  /// in reading order was the app bar's back arrow: pressing Up jumped
  /// straight out of the list and the rows above it could not be reached by
  /// remote at all. Scrolling first puts those rows in the tree, and the step
  /// then lands where the user expects.
  ///
  /// Returns false once the list is at its end in that direction, so the
  /// highlight can still leave for the app bar (or whatever is below) the
  /// moment there is genuinely nothing more to scroll to.
  bool _stepLeavesScrollable(TraversalDirection dir) {
    final targets = _targets();
    if (targets.isEmpty) return false;
    final current = _resolve(targets);
    if (current == null) return false;
    final hit = _scrollableContaining(current.rect);
    if (hit == null) return false;
    final (pos, viewport) = hit;
    final atEnd = dir == TraversalDirection.down
        ? pos.pixels >= pos.maxScrollExtent - 1
        : pos.pixels <= pos.minScrollExtent + 1;
    if (atEnd) return false;
    final next = _nearest(targets, current, dir);
    // No next target at all is the other caller's case (scroll, then retry).
    if (next == null) return false;
    return !viewport.contains(next.rect.center);
  }

  /// Scrolls the list holding the current target by half a viewport in
  /// [dir]. Returns false when there is no such list or it is already at that
  /// end -- i.e. the highlight really is on the last entry.
  bool _scrollPage(TraversalDirection dir) {
    final rect = _highlight;
    if (rect == null) return false;
    final hit = _scrollableContaining(rect);
    if (hit == null) return false;
    final (pos, viewport) = hit;
    final step =
        viewport.height * 0.5 * (dir == TraversalDirection.down ? 1 : -1);
    final target = (pos.pixels + step).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    final applied = target - pos.pixels;
    if (applied.abs() < 1) return false;
    pos.jumpTo(target);
    _anchor = _anchor?.shift(Offset(0, -applied));
    _highlight = _highlight?.shift(Offset(0, -applied));
    _syncRing();
    return true;
  }

  /// Innermost scrollable whose viewport contains [target], with its rect.
  (ScrollPosition, Rect)? _scrollableContaining(Rect target) {
    ScrollPosition? bestPos;
    Rect? bestRect;
    double bestArea = double.infinity;
    void visit(Element el) {
      if (el.widget is Scrollable) {
        final st = (el as StatefulElement).state;
        if (st is ScrollableState && st.position.hasPixels) {
          final box = st.context.findRenderObject();
          if (box is RenderBox && box.hasSize && box.attached) {
            final r = box.localToGlobal(Offset.zero) & box.size;
            if (r.contains(target.center)) {
              final area = r.width * r.height;
              if (area < bestArea) {
                bestArea = area;
                bestPos = st.position;
                bestRect = r;
              }
            }
          }
        }
      }
      el.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    visit(root);
    final p = bestPos;
    final r = bestRect;
    if (p == null || r == null) return null;
    return (p, r);
  }

  @override
  Widget build(BuildContext context) {
    // The ring is an overlay entry, so nothing visual wraps the child. Focus
    // is excluded instead: this scope activates targets through the semantics
    // tree, which needs no Flutter focus, and removing focus is what stops a
    // Material Switch or Slider from reacting to the arrows itself. Doing it
    // here rather than app-wide keeps the D-pad alive on every other screen.
    //
    // Two things it must NOT do. Off TV it has to be a pure pass-through, or
    // it would quietly make the pages it wraps unfocusable on phones. And the
    // popup driver sits above the whole app, so excluding focus there would
    // take every text field in it with it -- a dialog that asks for a bookmark
    // name could not be typed into. Popups rarely hold a Switch or a Slider,
    // which is what the exclusion is for, so that trade goes the other way.
    if (!_active) return widget.child;
    if (widget.popupsOnly) {
      // The popup driver cannot exclude focus, but it must still stop the
      // arrows reaching Flutter's directional traversal while a popup is up,
      // or there are TWO cursors.
      //
      // Seen on the تكرار مقطع surah pickers: a Material dropdown menu opens
      // in its OWN route, so no scope's ExcludeFocus covers it, and the menu
      // moved its own grey highlight on every arrow press while this scope
      // moved the gold ring. They drifted apart -- grey on 15. الحجر, ring on
      // 19. مريم -- and Select fired on the ring, so the picker looked like
      // it was skipping surahs. Blocking the arrows here is narrow: it lasts
      // only while a popup is on top, which is also the only time this driver
      // is awake, so every other screen keeps its traversal.
      if (!_gateOpen) return widget.child;
      return Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowUp):
              DoNothingAndStopPropagationIntent(),
          SingleActivator(LogicalKeyboardKey.arrowDown):
              DoNothingAndStopPropagationIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              DoNothingAndStopPropagationIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              DoNothingAndStopPropagationIntent(),
        },
        child: widget.child,
      );
    }
    return ExcludeFocus(child: widget.child);
  }
}

class _TvTarget {
  const _TvTarget(
    this.id,
    this.rect, {
    this.adjustable = false,
    this.selected = false,
  });
  final int id;
  final Rect rect;

  /// Marked selected/checked in semantics — where the highlight should start
  /// when a chooser opens, so the remote lands on the current value rather
  /// than at the top of the list.
  final bool selected;

  /// Sliders expose increase/decrease instead of a meaningful tap, so
  /// Left/Right adjust them rather than moving the highlight away.
  final bool adjustable;
}

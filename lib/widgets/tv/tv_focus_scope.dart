import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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
class TvFocusScope extends StatefulWidget {
  const TvFocusScope({super.key, required this.child});

  final Widget child;

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
  /// Global coordinates. The ring lives in the ROOT overlay, not in this
  /// subtree: a dialog or sheet paints above the wrapped page, so a ring drawn
  /// inside the page is hidden behind it -- the margins confirm dialog was
  /// being targeted correctly but looked unreachable.
  Rect? _highlight;
  OverlayEntry? _ringEntry;

  bool get _active => TvService.instance.isTv;
  bool get _isTop => _stack.isNotEmpty && identical(_stack.last, this);

  @override
  void initState() {
    super.initState();
    if (!_active) return;
    // Semantics are off unless something asks for them; the tree we navigate
    // does not exist otherwise.
    _semantics = SemanticsBinding.instance.ensureSemantics();
    _stack.add(this);
    HardwareKeyboard.instance.addHandler(_onKey);
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
      _stack.remove(this);
      _ringEntry?.remove();
      _ringEntry = null;
      _semantics?.dispose();
    }
    super.dispose();
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
    void findScope(SemanticsNode n) {
      if (n.getSemanticsData().flagsCollection.scopesRoute) scope = n;
      n.visitChildren((c) {
        findScope(c);
        return true;
      });
    }
    findScope(root);

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
      final bool adjustable = data.hasAction(SemanticsAction.increase) ||
          data.hasAction(SemanticsAction.decrease);
      if ((tappable || adjustable) && !hidden && !n.rect.isEmpty) {
        final r = MatrixUtils.transformRect(m, n.rect);
        if (r.width > 1 && r.height > 1) {
          out.add(_TvTarget(n.id, r, adjustable: adjustable));
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

  void _retarget(TraversalDirection? dir) {
    if (!mounted) return;
    final targets = _targets();
    if (targets.isEmpty) {
      if (_highlight != null) {
        _highlight = null;
        _syncRing();
      }
      return;
    }

    final current = _resolve(targets);
    final next = (current == null || dir == null)
        ? (current ?? targets.first)
        : (_nearest(targets, current, dir) ?? current);

    _anchor = next.rect;
    _highlight = next.rect;
    _syncRing();
  }

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
  void _syncRing() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFD2B97E),
                    width: 3,
                  ),
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
    if (!mounted || !_active || !_isTop) return false;
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
      _retarget(dir);
      _ensureVisible();
      return true;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      final target = _resolve(_targets());
      if (target != null) {
        context
            .findRenderObject()
            ?.owner
            ?.semanticsOwner
            ?.performAction(target.id, SemanticsAction.tap);
        // The tap may expand a section or open a dialog, so re-read the tree.
        WidgetsBinding.instance.addPostFrameCallback((_) => _retarget(null));
      }
      return true;
    }
    return false;
  }

  /// Scrolls the target into view. The target is remembered by position, so
  /// after scrolling the anchor is shifted by the same delta rather than being
  /// re-resolved — re-resolving would just pick whatever row slid into that
  /// spot and undo the move.
  void _ensureVisible() {
    final rect = _highlight;
    if (rect == null) return;
    final self = context.findRenderObject();
    if (self is! RenderBox || !self.hasSize) return;
    final top = self.localToGlobal(Offset.zero).dy;
    final h = self.size.height;
    const margin = 90.0;
    final localTop = rect.top - top;
    final localBottom = rect.bottom - top;
    double delta = 0;
    if (localTop < margin) delta = localTop - margin;
    if (localBottom > h - margin) delta = localBottom - (h - margin);
    if (delta == 0) return;

    final pos = _firstScrollPosition();
    if (pos == null) return;
    final target = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    final applied = target - pos.pixels;
    if (applied == 0) return;
    pos.jumpTo(target);
    _anchor = _anchor?.shift(Offset(0, -applied));
    _highlight = _highlight?.shift(Offset(0, -applied));
    _syncRing();
  }

  /// Our own context is usually above the Scrollable, so find one beneath us.
  ScrollPosition? _firstScrollPosition() {
    ScrollPosition? found;
    void visit(Element el) {
      if (found != null) return;
      final w = el.widget;
      if (w is Scrollable) {
        final st = (el as StatefulElement).state;
        if (st is ScrollableState && st.position.hasPixels) {
          found = st.position;
          return;
        }
      }
      el.visitChildren(visit);
    }
    (context as Element).visitChildren(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    // The ring is an overlay entry, so nothing visual wraps the child. Focus
    // is excluded instead: this scope activates targets through the semantics
    // tree, which needs no Flutter focus, and removing focus is what stops a
    // Material Switch or Slider from reacting to the arrows itself. Doing it
    // here rather than app-wide keeps the D-pad alive on every other screen.
    return ExcludeFocus(child: widget.child);
  }
}

class _TvTarget {
  const _TvTarget(this.id, this.rect, {this.adjustable = false});
  final int id;
  final Rect rect;

  /// Sliders expose increase/decrease instead of a meaningful tap, so
  /// Left/Right adjust them rather than moving the highlight away.
  final bool adjustable;
}

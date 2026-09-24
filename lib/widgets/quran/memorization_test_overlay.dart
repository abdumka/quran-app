import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/ayah_region_data.dart';
import '../../models/word_region_data.dart';
import '../../services/ayah_region_service.dart';
import '../../services/memorization_test_service.dart';
import '../../services/word_region_service.dart';
import '../../utils/quran_word_aligner.dart';

/// The reveal layer of the memorization test: covers every not-yet-recited
/// ayah with paper-colored boxes drawn directly on top of the page image, so
/// hidden ayahs are indistinguishable from blank paper. The ayah-end markers
/// sit between the region rects and stay visible, so the reciter keeps their
/// place on the concealed page.
///
/// Must be placed inside the same box that renders the page `Image` (the
/// image uses `BoxFit.fill`, so this widget's own layout size IS the page
/// image's size and ratio coordinates map straight onto it — the same
/// convention as `AyahHighlightRect`). It also has to sit under the reader's
/// `ColorFiltered`, so the masks are re-tinted exactly like the paper in
/// dark mode and the paper-color themes.
///
/// Rendering rules per [AyahRevealState]:
///  * `hidden` — opaque paper-colored mask.
///  * `current` — masked too, with a faint gold border as a "you are here"
///    hint (position only; reveals nothing of the text).
///  * `revealed` — nothing drawn; the ayah on the page shows through.
///  * `flagged` — translucent amber wash over the now-visible ayah.
class MemorizationTestOverlay extends StatelessWidget {
  const MemorizationTestOverlay({
    super.key,
    required this.pageNumber,
    this.marginView = false,
  });

  /// The 1-based mushaf page this overlay sits on. It draws the live masks
  /// only while the service's session is on this page, and a full cover
  /// while this is the NEXT page, so a page the session is about to flow
  /// into is already hidden when it slides in.
  final int pageNumber;

  /// True when the box under this overlay shows the margin-view (هوامش)
  /// image instead of the bundled page image: every ratio coordinate is
  /// then mapped through the page's placement inside that image.
  final bool marginView;

  /// Sampled from blank paper inside the page scans (the scan's paper tone,
  /// NOT the 0xFFFAF6EE used behind the image widget — the image fully
  /// covers that, so masks must match the scan itself).
  static const Color _paperColor = Color(0xFFFCFCD8);

  static const Color _flaggedWash = Color(0x59E09000);
  // Opaque tinted paper for words that must stay hidden but flagged.
  static const Color _mistakeMask = Color(0xFFF2C4B8);
  static const Color _skippedMask = Color(0xFFF0D9A6);
  static const Color _unclearMask = Color(0xFFF6EBC4);
  static const Color _currentBorder = Color(0x80B99B5B);

  @override
  Widget build(BuildContext context) {
    final service = MemorizationTestService.instance;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable: Listenable.merge([service.status, service.revision]),
          builder: (context, _) {
            final cover = _NextPageCover(
              pageNumber: pageNumber,
              marginView: marginView,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            );
            if (!service.isActive || service.activePage != pageNumber) {
              return cover;
            }
            final regions = service.regions;
            if (regions == null || regions.page != pageNumber) return cover;

            final states = service.ayahStates;
            if (states.length != regions.ayahs.length) return cover;
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;

            // Ratio -> page-box mapping. In the margin view the page image
            // occupies only `marginRect` of the shown image; without that
            // rect the masks cannot be placed, so nothing is drawn there.
            final margin = marginView ? service.wordMarginRect : null;
            if (marginView && margin == null) return cover;
            final map = _RatioMapper(width, height, margin);

            final masks = <MaskPiece>[];
            final frames = <Rect>[];
            for (var i = 0; i < regions.ayahs.length; i++) {
              _collectAyah(
                regions.ayahs[i],
                states[i],
                map,
                wordBoxes: service.wordBoxesFor(i),
                wordStatuses: service.wordStatusesOf(i),
                masks: masks,
                frames: frames,
              );
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: MemorizationMaskPainter(
                        masks,
                        frames,
                        _currentBorder,
                      ),
                    ),
                  ),
                ),
                // Live feedback + help buttons, floating near the bottom of
                // the page area (over the page's lower margin).
                // The bar floats over the page; the reciter drags it (long
                // press) wherever it is in the way least.
                Positioned.fill(child: _SessionBar(service: service)),
              ],
            );
          },
        );
      },
    );
  }

  void _collectAyah(
    AyahRegion ayah,
    AyahRevealState state,
    _RatioMapper map, {
    required List<WordBox>? wordBoxes,
    required List<WordStatus> wordStatuses,
    required List<MaskPiece> masks,
    required List<Rect> frames,
  }) {
    if (state == AyahRevealState.revealed) return;

    // Word-level rendering wherever word boxes exist: each box is the set
    // of small rects covering the word's own ink (letters and marks), so
    // masking them hides exactly that word without clipping the marks of
    // the lines above and below that reach into its bounding box. Hidden
    // ayahs mask every word; the ayah being recited masks the words still
    // to come; a mistake or a skip stays fully covered, shown by its tint.
    if (wordBoxes != null &&
        wordBoxes.isNotEmpty &&
        wordBoxes.length == wordStatuses.length) {
      for (var w = 0; w < wordBoxes.length; w++) {
        if (wordStatuses[w] == WordStatus.correct) continue;
        // A revealed word stays visible under a translucent amber wash.
        final color = switch (wordStatuses[w]) {
          WordStatus.mistake => _mistakeMask,
          WordStatus.skipped => _skippedMask,
          WordStatus.unclear => _unclearMask,
          WordStatus.revealed => _flaggedWash,
          _ => _paperColor,
        };
        final parts = wordBoxes[w].parts.isEmpty
            ? [wordBoxes[w].bounds]
            : wordBoxes[w].parts;
        final unit = Object();
        for (final p in parts) {
          masks.add(MaskPiece(map.rect(p), color, unit));
        }
      }
      if (state == AyahRevealState.current) {
        // Position hint only (no fill): a faint gold frame around the
        // ayah being recited.
        for (final r in ayah.rects) {
          frames.add(
            map.rect(Rect.fromLTWH(r.x, r.y, r.width, r.height), slackX: 0.006),
          );
        }
      }
      return;
    }

    for (final r in ayah.rects) {
      // The rects span the full line height already; a little horizontal
      // slack hides glyph tails that lean into the marker gap without ever
      // reaching the marker itself.
      final rect = map.rect(
        Rect.fromLTWH(r.x, r.y, r.width, r.height),
        slackX: 0.006,
      );
      final unit = Object();
      switch (state) {
        case AyahRevealState.flagged:
          masks.add(MaskPiece(rect, _flaggedWash, unit));
        case AyahRevealState.current:
          masks.add(MaskPiece(rect, _paperColor, unit));
          frames.add(rect);
        default:
          masks.add(MaskPiece(rect, _paperColor, unit));
      }
    }
  }
}

/// Maps page-image ratios onto the overlay's box, through the page's
/// placement inside the margin-view image when that is what is shown.
class _RatioMapper {
  const _RatioMapper(this.width, this.height, this.margin);

  final double width;
  final double height;
  final Rect? margin;

  Rect rect(Rect r, {double slackX = 0}) {
    var left = r.left - slackX;
    var right = r.right + slackX;
    var top = r.top;
    var bottom = r.bottom;
    final m = margin;
    if (m != null) {
      left = m.left + left * m.width;
      right = m.left + right * m.width;
      top = m.top + top * m.height;
      bottom = m.top + bottom * m.height;
    }
    return Rect.fromLTRB(
      left * width,
      top * height,
      right * width,
      bottom * height,
    );
  }
}

/// One filled rectangle of the mask layer: a part of a word's ink box or an
/// ayah line rect, with the paper colour or the tint of its status.
class MaskPiece {
  const MaskPiece(this.rect, this.color, this.unit);
  final Rect rect;
  final Color color;

  /// The word or ayah rect this piece belongs to (a word is several parts).
  final Object unit;
}

/// Paints every mask rect (opaque paper or a tint) and the gold frames of
/// the ayah being recited. One painter for the whole page keeps the widget
/// tree flat however many word parts there are.
class MemorizationMaskPainter extends CustomPainter {
  const MemorizationMaskPainter(this.masks, this.frames, this.frameColor);

  final List<MaskPiece> masks;
  final List<Rect> frames;
  final Color frameColor;

  /// How many words (word-level ayahs) and line rects (ayah-level ayahs)
  /// are currently masked; a word counts once however many parts it has.
  int get maskedUnits => masks.map((m) => m.unit).toSet().length;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final m in masks) {
      paint.color = m.color;
      canvas.drawRect(m.rect, paint);
    }
    if (frames.isNotEmpty) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = frameColor;
      for (final f in frames) {
        canvas.drawRect(f, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(MemorizationMaskPainter old) => true;
}

/// Covers every ayah of a page the session has not reached yet (the page
/// after the live one), from the same region data the live masks use.
class _NextPageCover extends StatelessWidget {
  const _NextPageCover({
    required this.pageNumber,
    required this.marginView,
    required this.width,
    required this.height,
  });

  final int pageNumber;
  final bool marginView;
  final double width;
  final double height;

  static final Map<int, Future<(AyahRegionPageData?, WordRegionPageData?)>>
  _cache = {};

  @override
  Widget build(BuildContext context) {
    final future = _cache.putIfAbsent(pageNumber, () async {
      final r = await AyahRegionService.forPage(pageNumber);
      final w = await WordRegionService.forPage(pageNumber);
      return (r, w);
    });
    if (_cache.length > 6) _cache.remove(_cache.keys.first);
    return FutureBuilder<(AyahRegionPageData?, WordRegionPageData?)>(
      future: future,
      builder: (context, snap) {
        final regions = snap.data?.$1;
        final margin = marginView ? snap.data?.$2?.marginRect : null;
        if (regions == null || (marginView && margin == null)) {
          if (snap.connectionState == ConnectionState.done) {
            return const SizedBox.shrink(); // no geometry for this page
          }
          return IgnorePointer(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.04,
                vertical: height * 0.03,
              ),
              child: const ColoredBox(
                color: MemorizationTestOverlay._paperColor,
                child: SizedBox.expand(),
              ),
            ),
          );
        }
        final map = _RatioMapper(width, height, margin);
        final unit = Object();
        final masks = <MaskPiece>[
          for (final a in regions.ayahs)
            for (final r in a.rects)
              MaskPiece(
                map.rect(
                  Rect.fromLTWH(r.x, r.y, r.width, r.height),
                  slackX: 0.006,
                ),
                MemorizationTestOverlay._paperColor,
                unit,
              ),
        ];
        return IgnorePointer(
          child: CustomPaint(
            size: Size(width, height),
            painter: MemorizationMaskPainter(
              masks,
              const [],
              const Color(0x00000000),
            ),
          ),
        );
      },
    );
  }
}

/// The session bar at the foot of the page: every action one tap away, the
/// current message above it only while there is one, and a handle that folds
/// the whole bar into a small dot so the last line stays readable. What the
/// recognizer heard is not shown (it stays in the logs).
class _SessionBar extends StatefulWidget {
  const _SessionBar({required this.service});

  final MemorizationTestService service;

  @override
  State<_SessionBar> createState() => _SessionBarState();
}

class _SessionBarState extends State<_SessionBar> {
  static bool _collapsed = false;

  /// Where the bar sits, as fractions of the page box (top-left corner);
  /// null = the default place, bottom centre. Kept across sessions.
  static Offset? _pos;
  static bool _posLoaded = false;
  static const String _posPref = 'tasmee_bar_pos';

  final GlobalKey _barKey = GlobalKey();
  Offset? _dragOrigin; // bar top-left (px) when the drag started
  Offset? _dragStart; // finger (global) when the drag started

  @override
  void initState() {
    super.initState();
    if (!_posLoaded) {
      _posLoaded = true;
      SharedPreferences.getInstance().then((prefs) {
        final v = prefs.getString(_posPref);
        if (v == null) return;
        final parts = v.split(',');
        if (parts.length != 2) return;
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        if (x != null && y != null && mounted) setState(() => _pos = Offset(x, y));
      });
    }
  }

  static Future<void> _savePos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = _pos;
      if (p == null) {
        await prefs.remove(_posPref);
      } else {
        await prefs.setString(_posPref, '${p.dx},${p.dy}');
      }
    } catch (_) {}
  }

  RenderBox? get _pageBox => context.findRenderObject() as RenderBox?;
  RenderBox? get _barBox =>
      _barKey.currentContext?.findRenderObject() as RenderBox?;

  /// Pixel top-left of the bar right now, from its render box.
  Offset? _currentTopLeft() {
    final page = _pageBox;
    final bar = _barBox;
    if (page == null || bar == null || !page.hasSize || !bar.hasSize) return null;
    return page.globalToLocal(bar.localToGlobal(Offset.zero));
  }

  /// Keeps the bar inside the page box; [center] puts it in the middle
  /// horizontally when it would run off the right edge (the folded dot is
  /// narrow and may sit where the unfolded bar cannot).
  Offset _clamp(Offset topLeft, {bool center = false}) {
    final page = _pageBox;
    final bar = _barBox;
    if (page == null || bar == null || !page.hasSize || !bar.hasSize) {
      return topLeft;
    }
    final maxX = (page.size.width - bar.size.width).clamp(0.0, double.infinity);
    final maxY = (page.size.height - bar.size.height).clamp(0.0, double.infinity);
    var x = topLeft.dx;
    if (center && x > maxX) x = maxX / 2;
    return Offset(x.clamp(0.0, maxX), topLeft.dy.clamp(0.0, maxY));
  }

  void _setPosPx(Offset topLeft, {bool center = false}) {
    final page = _pageBox;
    if (page == null || !page.hasSize) return;
    final c = _clamp(topLeft, center: center);
    setState(() => _pos = Offset(c.dx / page.size.width, c.dy / page.size.height));
  }

  void _onDragStart(LongPressStartDetails d) {
    final tl = _currentTopLeft();
    if (tl == null) return;
    _dragOrigin = tl;
    _dragStart = d.globalPosition;
    HapticFeedback.selectionClick();
    service.logUi('barDragStart');
  }

  void _onDragMove(LongPressMoveUpdateDetails d) {
    final origin = _dragOrigin;
    final start = _dragStart;
    if (origin == null || start == null) return;
    _setPosPx(origin + (d.globalPosition - start));
  }

  void _onDragEnd(LongPressEndDetails d) {
    _dragOrigin = null;
    _dragStart = null;
    _savePos();
  }

  /// After the bar unfolds it may be wider than the room to its right:
  /// once laid out, pull it back onto the page (to the centre).
  void _unfold() {
    setState(() => _collapsed = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pos == null) return;
      final tl = _currentTopLeft();
      if (tl == null) return;
      final page = _pageBox;
      final bar = _barBox;
      if (page == null || bar == null) return;
      if (tl.dx + bar.size.width > page.size.width + 0.5 ||
          tl.dy + bar.size.height > page.size.height + 0.5) {
        _setPosPx(tl, center: true);
        _savePos();
      }
    });
  }

  /// Places [child] at the saved spot, or bottom centre by default.
  Widget _place(Widget child) {
    final page = _pageBox;
    final p = _pos;
    final movable = GestureDetector(
      key: _barKey,
      behavior: HitTestBehavior.opaque,
      onLongPressStart: _onDragStart,
      onLongPressMoveUpdate: _onDragMove,
      onLongPressEnd: _onDragEnd,
      child: child,
    );
    if (p == null || page == null || !page.hasSize) {
      return Stack(
        children: [
          Positioned(
            left: 6,
            right: 6,
            bottom: page != null && page.hasSize ? page.size.height * 0.006 : 6,
            child: Center(child: movable),
          ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned(
          left: p.dx * page.size.width,
          top: p.dy * page.size.height,
          child: movable,
        ),
      ],
    );
  }

  static const Color _gold = Color(0xFF8A6D2F);
  static const Color _good = Color(0xFF2E7D32);
  static const Color _wrong = Color(0xFFB3261E);
  static const Color _unclear = Color(0xFFB26A00);

  MemorizationTestService get service => widget.service;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        service.status,
        service.audioLevel,
        service.engineBusy,
        service.feedback,
        service.lastSessionFiles,
        service.drillLabel,
      ]),
      builder: (context, _) {
        final status = service.status.value;
        if (status != MemorizationTestStatus.listening &&
            status != MemorizationTestStatus.completed &&
            status != MemorizationTestStatus.preparing) {
          return const SizedBox.shrink();
        }
        final fb = service.feedback.value;
        final listening = status == MemorizationTestStatus.listening;
        final completed = status == MemorizationTestStatus.completed;
        final message =
            fb?.message ??
            service.drillLabel.value ??
            switch (status) {
              MemorizationTestStatus.preparing => 'جارٍ التحضير…',
              MemorizationTestStatus.completed => 'اكتملت الصفحة',
              _ => null,
            };
        final messageColor = switch (fb?.kind) {
          FeedbackKind.good => _good,
          FeedbackKind.wrong => _wrong,
          FeedbackKind.unclear || FeedbackKind.silent => _unclear,
          _ => _gold,
        };

        if (_collapsed) {
          // Folded: a dot that still shows the mic level and turns red on
          // a mistake; tap to unfold.
          return _place(
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _unfold,
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 12, 10, 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: _decoration(fb?.kind == FeedbackKind.wrong),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _statusDot(status, fb?.kind == FeedbackKind.wrong),
                    const Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: _gold,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // The pad around the bar swallows the taps that just miss a button:
        // they used to fall through to the page and pull the app's menus up
        // over the bar.
        return _place(
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => service.logUi('barMiss'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
              child: _bar(
                context,
                status,
                message,
                messageColor,
                listening,
                completed,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bar(
    BuildContext context,
    MemorizationTestStatus status,
    String? message,
    Color messageColor,
    bool listening,
    bool completed,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message != null)
            Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: _decoration(false),
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: messageColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          DecoratedBox(
            decoration: _decoration(false),
            // Scales down on a narrow screen instead of overflowing.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.rtl,
                children: [
                  const SizedBox(width: 4),
                  _statusDot(status, false),
                  if (listening) ...[
                    _action(
                      Icons.lightbulb_outline_rounded,
                      'كلمة',
                      service.showHint,
                    ),
                    _action(
                      Icons.visibility_rounded,
                      'الآية',
                      service.revealCurrentAyah,
                    ),
                    _action(
                      Icons.replay_circle_filled_rounded,
                      'أعد الآية',
                      service.repeatAyah,
                    ),
                    _action(
                      Icons.skip_next_rounded,
                      'تخطَّ',
                      service.skipCurrentAyah,
                    ),
                  ],
                  if (listening || completed)
                    _action(
                      Icons.restart_alt_rounded,
                      'الصفحة',
                      () => service.restart(),
                    ),
                  if (completed && service.lastSessionFiles.value.isNotEmpty)
                    _action(
                      Icons.ios_share_rounded,
                      'السجل',
                      () => _shareSession(context),
                    ),
                  _action(Icons.close_rounded, 'إنهاء', () => service.stop()),
                  _action(
                    Icons.keyboard_arrow_down_rounded,
                    'إخفاء',
                    () => setState(() => _collapsed = true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _decoration(bool alarm) => BoxDecoration(
    color: alarm ? const Color(0xF2FFE3DE) : const Color(0xE6FFFDF3),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: (alarm ? _wrong : _gold).withValues(alpha: 0.4)),
    boxShadow: const [
      BoxShadow(color: Color(0x22000000), blurRadius: 5, offset: Offset(0, 2)),
    ],
  );

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        service.logUi('bar', {'action': label});
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 23, color: _gold),
            Text(
              label,
              style: const TextStyle(
                color: _gold,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(MemorizationTestStatus status, bool alarm) {
    final level = service.audioLevel.value;
    final color = alarm
        ? _wrong
        : switch (status) {
            MemorizationTestStatus.completed => _good,
            MemorizationTestStatus.preparing => _unclear,
            _ => service.engineBusy.value ? _unclear : _good,
          };
    final size = 9.0 + 8.0 * level.clamp(0.0, 1.0);
    return SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Future<void> _shareSession(BuildContext context) async {
    final files = service.lastSessionFiles.value;
    if (files.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [for (final f in files) XFile(f)],
          subject: 'سجل جلسة التسميع',
          text: 'تسجيل جلسة التسميع وسجل القرارات (للتحليل).',
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذّرت مشاركة سجل الجلسة')));
    }
  }
}

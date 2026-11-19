import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../services/audio_service.dart';
import '../../services/ayah_region_service.dart';
import '../../services/word_region_service.dart';
import 'playing_ayah_highlight.dart';

/// Keeping the ayah being recited in front of the reader when the page is
/// bigger than the screen: the landscape reader (the page fits the width, so
/// a third of it shows at a time) and a pinch-zoomed page.
///
/// Before this the landscape reader moved only when the recitation turned the
/// page, to the new page's top, and the tinted ayah walked off the bottom of
/// the screen while the reader looked at the first lines (owner's recording,
/// 2026-11-19, page 356).

/// The (surah, ayah) pairs the recitation is tinting right now, or an empty
/// set when there is nothing to follow (no ayah, or the bar is closed).
Set<(int, int)> recitedAyatToFollow() {
  final audio = AudioService.instance;
  final playing = audio.currentAyah.value;
  if (playing == null || !audio.isRecitationBarVisible.value) return const {};
  return highlightedAyat(playing.surah, playing.ayah, [
    for (final g in audio.currentAyahGroup.value) (g.surah, g.ayah),
  ]);
}

/// The line boxes of [keys] on 1-based page [pageNumber], in pixels of a page
/// box of [box] (the same box the highlight paints in), top to bottom and,
/// on one line, right to left. Empty when none of [keys] is printed on the
/// page; null when the page's region data is not available.
Future<List<Rect>?> ayahLineBoxes({
  required int pageNumber,
  required Set<(int, int)> keys,
  required Size box,
  required bool marginView,
}) async {
  final regions = await AyahRegionService.forPage(pageNumber);
  if (regions == null) return null;
  Rect? margin;
  if (marginView) {
    margin = (await WordRegionService.forPage(pageNumber))?.marginRect;
    if (margin == null) return null;
  }
  final rects = highlightRects(regions, keys);
  if (rects.isEmpty) return const [];
  return orderedLines(
    PlayingAyahHighlightPainter(rects, margin, false).boxes(box),
  );
}

/// [boxes] in reading order: by line, then right to left.
List<Rect> orderedLines(List<Rect> boxes) {
  final out = [...boxes];
  out.sort((a, b) {
    final sameLine =
        math.min(a.bottom, b.bottom) - math.max(a.top, b.top) >
        0.5 * math.min(a.height, b.height);
    if (!sameLine) return a.top.compareTo(b.top);
    return b.right.compareTo(a.right);
  });
  return out;
}

/// Which of [lines] (reading order) the reciter is on, [progress] (0 to 1)
/// of the way through them. Estimated from the share of the ayah's ink each
/// line holds, which is close enough to decide when to scroll.
int readingLineIndex(List<Rect> lines, double progress) {
  if (lines.length <= 1) return 0;
  final total = lines.fold<double>(0, (sum, r) => sum + r.width);
  if (total <= 0) return 0;
  final goal = progress.clamp(0.0, 1.0) * total;
  var acc = 0.0;
  for (var i = 0; i < lines.length; i++) {
    acc += lines[i].width;
    if (acc >= goal) return i;
  }
  return lines.length - 1;
}

/// The stretch (top, bottom) of an ayah that has to be on screen.
///
/// The whole ayah when it fits in [room]. When it does not, the line being
/// recited (from [progress]) and the one before it, so the screen moves on
/// as the recitation goes down the ayah rather than staying on its head.
(double, double) followSpan(List<Rect> lines, double room, double? progress) {
  final top = lines.map((r) => r.top).reduce(math.min);
  final bottom = lines.map((r) => r.bottom).reduce(math.max);
  if (bottom - top <= room || lines.length == 1) return (top, bottom);
  final i = readingLineIndex(lines, progress ?? 0);
  final from = i > 0 ? lines[i - 1] : lines[i];
  return (math.min(from.top, lines[i].top), lines[i].bottom);
}

/// The scroll offset that brings the stretch [targetTop]..[targetBottom]
/// (scroll coordinates) into view, or null when it is in view already.
///
/// The view is "in view" between [topInset] and [bottomInset] (the
/// recitation bar floats over the bottom of the page). When the stretch has
/// to be brought in, its top goes [lead] below the top of the view, so the
/// lines that follow are on screen too and the view moves as rarely as
/// possible. [minOffset] keeps the view from going above the top of the
/// stretch's page when that costs nothing: the reader reports the page at
/// the top of the view as the page it is on.
double? revealScrollOffset({
  required double offset,
  required double viewport,
  required double maxScroll,
  required double targetTop,
  required double targetBottom,
  double minOffset = 0,
  double topInset = 0,
  double bottomInset = 0,
  double lead = 12,
}) {
  final visibleTop = offset + topInset;
  final visibleBottom = offset + viewport - bottomInset;
  if (targetTop >= visibleTop - 0.5 && targetBottom <= visibleBottom + 0.5) {
    return null;
  }
  var desired = targetTop - topInset - lead;
  // Not above the page's top unless the stretch itself needs it.
  desired = math.max(desired, math.min(minOffset, targetTop - topInset));
  desired = desired.clamp(0.0, math.max(0.0, maxScroll));
  if ((desired - offset).abs() < 2) return null;
  return desired;
}

/// The upright reader with the page pinch-zoomed: the same follow as the
/// landscape reader, by panning the zoomed page up and down (the zoom and
/// the sideways position are left as the reader set them). Without it the
/// tinted ayah went on down the page out of the zoomed view, exactly as in
/// landscape. The recitation's page turn resets the zoom, so only the page
/// on screen matters here.
class ZoomedPageFollower {
  ZoomedPageFollower({
    required this.controller,
    required this.active,
    required this.pageNumber,
    required this.pageBox,
    required this.viewportHeight,
    required this.obscuredBottom,
    required this.marginView,
  });

  final TransformationController controller;

  /// A single page, zoomed in, in the paged reader, with no Tasmee session.
  final bool Function() active;

  /// The 1-based page on screen.
  final int Function() pageNumber;

  /// The page box (where the highlight paints) inside the zoomed child, at
  /// scale 1. The child is the size of the screen area the reader fills.
  final Rect Function() pageBox;

  /// Pixels at the bottom of the screen area under the recitation bar.
  final double Function() obscuredBottom;
  final bool Function() marginView;

  /// Height of the screen area the zoomed page is seen through.
  final double Function() viewportHeight;

  static const double _lead = 12;
  static const Duration _grace = Duration(seconds: 3);

  Timer? _progressTimer;
  Timer? _panTimer;
  Matrix4? _ours;
  DateTime _userMovedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _gen = 0;

  bool get _userRecentlyMoved =>
      DateTime.now().difference(_userMovedAt) < _grace;

  /// The ayah being recited changed, or the recitation started or ended.
  void recitationChanged() {
    _progressTimer?.cancel();
    _progressTimer = null;
    unawaited(_reveal());
  }

  /// [controller] changed: when not by this, the reader pinched or panned,
  /// and that wins for a few seconds.
  void transformChanged() {
    if (_ours != null && controller.value == _ours) return;
    _userMovedAt = DateTime.now();
    _panTimer?.cancel();
    _panTimer = null;
    _ours = null;
  }

  void dispose() {
    _progressTimer?.cancel();
    _panTimer?.cancel();
  }

  Future<void> _reveal() async {
    if (!active()) return;
    final keys = recitedAyatToFollow();
    if (keys.isEmpty) return;
    final box = pageBox();
    final gen = ++_gen;
    final lines = await ayahLineBoxes(
      pageNumber: pageNumber(),
      keys: keys,
      box: box.size,
      marginView: marginView(),
    );
    if (gen != _gen || lines == null || lines.isEmpty || !active()) return;
    final placed = [for (final r in lines) r.shift(box.topLeft)];
    if (!_userRecentlyMoved) _follow(placed);

    final scale = controller.value.getMaxScaleOnAxis();
    final top = placed.map((r) => r.top).reduce(math.min);
    final bottom = placed.map((r) => r.bottom).reduce(math.max);
    if ((bottom - top) * scale > _room && placed.length > 1) {
      _progressTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        if (!active()) {
          _progressTimer?.cancel();
          _progressTimer = null;
          return;
        }
        if (!AudioService.instance.isPlaying.value || _userRecentlyMoved) {
          return;
        }
        _follow(placed);
      });
    }
  }

  double get _room => viewportHeight() - obscuredBottom() - _lead;

  void _follow(List<Rect> lines) {
    final m = controller.value;
    final scale = m.getMaxScaleOnAxis();
    final h = viewportHeight();
    if (h <= 0 || scale <= 1.01) return;
    final scaled = [
      for (final r in lines)
        Rect.fromLTRB(r.left * scale, r.top * scale, r.right * scale,
            r.bottom * scale),
    ];
    final (top, bottom) = followSpan(
      scaled,
      _room,
      AudioService.instance.currentAyahProgress,
    );
    final target = revealScrollOffset(
      offset: -m.getTranslation().y,
      viewport: h,
      maxScroll: scale * h - h,
      targetTop: top,
      targetBottom: bottom,
      bottomInset: obscuredBottom(),
      lead: _lead,
    );
    if (target == null) return;
    _panTo(-target);
  }

  /// Glides the page's vertical position to [ty] (screen pixels).
  void _panTo(double ty) {
    _panTimer?.cancel();
    final from = controller.value.getTranslation().y;
    const steps = 18; // ~300 ms
    var step = 0;
    void apply(double y) {
      final t = controller.value.getTranslation();
      final next = controller.value.clone()..setTranslationRaw(t.x, y, t.z);
      _ours = next;
      controller.value = next;
    }

    _panTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      // Moved by the reader since the last step: theirs now.
      if (_ours != null && controller.value != _ours) {
        timer.cancel();
        return;
      }
      step++;
      final f = Curves.easeInOutCubic.transform(step / steps);
      apply(from + (ty - from) * f);
      if (step >= steps) timer.cancel();
    });
  }
}

/// The upright scroll mode, where each page is one screen tall: the offset
/// that shows the ayah [ayahTop]..[ayahBottom] of the page at [pageTop], or
/// null when it shows already. The whole page when that shows the ayah (the
/// view the paged reader would give); else the ayah at the top.
double? pageScrollRevealOffset({
  required double offset,
  required double viewport,
  required double maxScroll,
  required double pageTop,
  required double ayahTop,
  required double ayahBottom,
  double bottomInset = 0,
  double lead = 12,
}) {
  final visibleBottom = offset + viewport - bottomInset;
  if (ayahTop >= offset - 0.5 && ayahBottom <= visibleBottom + 0.5) {
    return null;
  }
  final aligned = pageTop.clamp(0.0, math.max(0.0, maxScroll)).toDouble();
  if (ayahTop >= aligned && ayahBottom <= aligned + viewport - bottomInset) {
    return aligned;
  }
  return revealScrollOffset(
    offset: offset,
    viewport: viewport,
    maxScroll: maxScroll,
    targetTop: ayahTop,
    targetBottom: ayahBottom,
    minOffset: pageTop,
    bottomInset: bottomInset,
    lead: lead,
  );
}

import 'dart:math' as math;
import 'dart:ui';

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

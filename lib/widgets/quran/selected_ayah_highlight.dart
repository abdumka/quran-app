import 'package:flutter/material.dart';

import '../../services/ayah_region_service.dart';
import '../../services/word_region_service.dart';
import 'playing_ayah_highlight.dart';

/// The ayah a long press landed on, while its action menu is up.
class SelectedAyah {
  const SelectedAyah({
    required this.pageNumber,
    required this.surah,
    required this.ayah,
  });

  /// 1-based mushaf page.
  final int pageNumber;
  final int surah;
  final int ayah;
}

/// Tints the ayah the reader long-pressed, the same way the playing ayah is
/// tinted, for as long as [selected] holds it. Mounted in the same in-image
/// box as `PlayingAyahHighlight` so the ratio rects land on the page.
class SelectedAyahHighlight extends StatelessWidget {
  const SelectedAyahHighlight({
    super.key,
    required this.pageNumber,
    required this.dark,
    this.marginView = false,
  });

  /// 1-based mushaf page this sits on.
  final int pageNumber;
  final bool dark;
  final bool marginView;

  /// Set by the reader on a long press, cleared when its menu closes.
  static final ValueNotifier<SelectedAyah?> selected = ValueNotifier(null);

  /// The ayah under [ratio] (0..1 of the shown image box), or null when the
  /// press missed every ayah on [pageNumber] (a margin, a surah header...).
  /// In the margin view the page occupies only `marginRect` of the image.
  static Future<(int, int)?> hitTest(
    int pageNumber,
    Offset ratio, {
    bool marginView = false,
  }) async {
    final regions = await AyahRegionService.forPage(pageNumber);
    if (regions == null) return null;
    var x = ratio.dx;
    var y = ratio.dy;
    if (marginView) {
      final m = (await WordRegionService.forPage(pageNumber))?.marginRect;
      if (m == null) return null;
      x = (x - m.left) / m.width;
      y = (y - m.top) / m.height;
    }
    for (final a in regions.ayahs) {
      for (final r in a.rects) {
        if (x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height) {
          return (a.surah, a.ayah);
        }
      }
      final marker = a.marker;
      if (marker != null &&
          x >= marker.x &&
          x <= marker.x + marker.width &&
          y >= marker.y &&
          y <= marker.y + marker.height) {
        return (a.surah, a.ayah);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SelectedAyah?>(
      valueListenable: selected,
      builder: (context, sel, _) {
        if (sel == null || sel.pageNumber != pageNumber) {
          return const SizedBox.shrink();
        }
        return FutureBuilder<(List<Rect>, Rect?)>(
          future: _rectsFor(sel),
          builder: (context, snap) {
            final rects = snap.data?.$1;
            final margin = snap.data?.$2;
            if (rects == null || rects.isEmpty || (marginView && margin == null)) {
              return const SizedBox.shrink();
            }
            return IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: PlayingAyahHighlightPainter(rects, margin, dark),
              ),
            );
          },
        );
      },
    );
  }

  Future<(List<Rect>, Rect?)> _rectsFor(SelectedAyah sel) async {
    final regions = await AyahRegionService.forPage(sel.pageNumber);
    final margin = marginView
        ? (await WordRegionService.forPage(sel.pageNumber))?.marginRect
        : null;
    final rects = <Rect>[
      if (regions != null)
        for (final a in regions.ayahs)
          if (a.surah == sel.surah && a.ayah == sel.ayah)
            for (final r in a.rects) Rect.fromLTWH(r.x, r.y, r.width, r.height),
    ];
    return (rects, margin);
  }
}

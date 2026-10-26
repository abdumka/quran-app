import 'package:flutter/material.dart';

import '../../models/word_region_data.dart';
import '../../services/tanzilat_service.dart';
import '../../services/word_region_service.dart';

/// The colours of the tanzilat words, by [tanzilahBucket]: غريبة, 2, 3, 4,
/// then one colour for five and more. [single] is the one colour used when
/// the reader turns the colour-per-count off.
class TanzilatColors {
  static const List<Color> light = [
    Color(0xFFD50000), // غريبة: red
    Color(0xFF0D47A1), // 2: blue
    Color(0xFF3CB371), // 3: green (medium sea green)
    Color(0xFF8E24AA), // 4: purple
    Color(0xFFFB8C00), // 5+: orange
  ];

  /// The same colours as they should look on the dark (inverted) page.
  static const List<Color> dark = [
    Color(0xFFFF6E6E),
    Color(0xFF82B1FF),
    Color(0xFF7EDCA6),
    Color(0xFFCE93D8),
    Color(0xFFFFB74D),
  ];

  static const Color single = Color(0xFFD50000);
  static const Color singleDark = Color(0xFFFF6E6E);

  /// The colour a tanzilah of [count] places shows in.
  static Color of(int count, {required bool dark, required bool byCount}) {
    if (!byCount) return dark ? singleDark : single;
    return (dark ? TanzilatColors.dark : light)[tanzilahBucket(count)];
  }

  /// The legend's labels, in bucket order.
  static const List<String> labels = ['غريبة', '2', '3', '4', '5+'];
}

/// Colours the tanzilat words of one page: only the ink of each word turns
/// coloured, the paper stays as it is.
///
/// Placed like `PlayingAyahHighlight`: inside the box that renders the page
/// `Image` (`BoxFit.fill`), under the reader's `ColorFiltered`, so ratio
/// coordinates map straight onto the image. The word's mask parts are painted
/// with [BlendMode.lighten]: dark ink takes the colour, lighter paper wins and
/// is untouched. The dark theme inverts the page after this layer, so there
/// the inverse of the wanted colour is painted.
class TanzilatOverlay extends StatelessWidget {
  const TanzilatOverlay({
    super.key,
    required this.pageNumber,
    required this.dark,
    this.marginView = false,
  });

  final int pageNumber;
  final bool dark;
  final bool marginView;

  static final Map<int, Future<WordRegionPageData?>> _cache = {};
  static int _cacheRevision = -1;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        TanzilatSetting.enabled,
        TanzilatSetting.colorByCount,
        TanzilatService.instance.revision,
      ]),
      builder: (context, _) {
        if (!TanzilatSetting.enabled.value) return const SizedBox.shrink();
        // The data was swapped live (a server update): forget every page.
        final revision = TanzilatService.instance.revision.value;
        if (revision != _cacheRevision) {
          _cache.clear();
          _cacheRevision = revision;
        }
        final future = _cache.putIfAbsent(pageNumber, () async {
          await TanzilatService.instance.load();
          return WordRegionService.forPage(pageNumber);
        });
        if (_cache.length > 8) _cache.remove(_cache.keys.first);
        return FutureBuilder<WordRegionPageData?>(
          future: future,
          builder: (context, snap) {
            final words = snap.data;
            final margin = marginView ? words?.marginRect : null;
            if (words == null || (marginView && margin == null)) {
              return const SizedBox.shrink();
            }
            final marks = tanzilatMarks(
              words,
              byCount: TanzilatSetting.colorByCount.value,
              dark: dark,
            );
            if (marks.isEmpty) return const SizedBox.shrink();
            // Its own raster: the Tasmee masks above repaint at every
            // revealed word, and this layer must not be redrawn with them.
            return IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  isComplex: true,
                  willChange: false,
                  painter: TanzilatPainter(
                    marks,
                    margin,
                    dark,
                    holes: tanzilatHoles(words),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The ink parts to colour on one page, grouped by colour (as ratios of the
/// page image).
Map<Color, List<Rect>> tanzilatMarks(
  WordRegionPageData page, {
  required bool byCount,
  required bool dark,
}) {
  final service = TanzilatService.instance;
  final out = <Color, List<Rect>>{};
  for (final ayah in page.allAyahs) {
    final coloured = service.wordsOf(ayah.surah, ayah.ayah);
    if (coloured.isEmpty) continue;
    coloured.forEach((index, hit) {
      if (index >= ayah.words.length) return;
      final colour = TanzilatColors.of(hit.count, dark: dark, byCount: byCount);
      out.putIfAbsent(colour, () => []).addAll(ayah.words[index].parts);
    });
  }
  return out;
}

/// The rectangles on one page that stay uncoloured: the «صه» stop marks
/// above coloured words (never coloured, owner 2026-10-23).
List<Rect> tanzilatHoles(WordRegionPageData page) {
  final service = TanzilatService.instance;
  return [
    for (final ayah in page.allAyahs)
      for (final index in service.wordsOf(ayah.surah, ayah.ayah).keys)
        ...service.noPaintOf(ayah.surah, ayah.ayah, index),
  ];
}

class TanzilatPainter extends CustomPainter {
  const TanzilatPainter(
    this.marks,
    this.margin,
    this.dark, {
    this.holes = const [],
  });

  final Map<Color, List<Rect>> marks;
  final Rect? margin;
  final bool dark;

  /// Taken out of every colour (see [tanzilatHoles]).
  final List<Rect> holes;

  // Half a pixel of the 720 px source image around every part, so the
  // anti-aliased rim of the strokes is coloured with them.
  static const double _bleedX = 0.5 / WordRegionPageData.imageWidth;
  static const double _bleedY = 0.5 / WordRegionPageData.imageHeight;

  Rect _toCanvas(Rect r, Size size) {
    var box = r;
    final m = margin;
    if (m != null) {
      box = Rect.fromLTRB(
        m.left + box.left * m.width,
        m.top + box.top * m.height,
        m.left + box.right * m.width,
        m.top + box.bottom * m.height,
      );
    }
    return Rect.fromLTRB(
      box.left * size.width,
      box.top * size.height,
      box.right * size.width,
      box.bottom * size.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final holePath = Path();
    for (final h in holes) {
      holePath.addRect(_toCanvas(h, size));
    }
    marks.forEach((colour, rects) {
      final paint = Paint()
        ..color = dark
            ? Color.fromARGB(
                255,
                255 - (colour.r * 255).round(),
                255 - (colour.g * 255).round(),
                255 - (colour.b * 255).round(),
              )
            : colour
        ..blendMode = BlendMode.lighten;
      final path = Path();
      for (final r in rects) {
        var box = Rect.fromLTRB(
          r.left - _bleedX,
          r.top - _bleedY,
          r.right + _bleedX,
          r.bottom + _bleedY,
        );
        final m = margin;
        if (m != null) {
          box = Rect.fromLTRB(
            m.left + box.left * m.width,
            m.top + box.top * m.height,
            m.left + box.right * m.width,
            m.top + box.bottom * m.height,
          );
        }
        path.addRect(
          Rect.fromLTRB(
            box.left * size.width,
            box.top * size.height,
            box.right * size.width,
            box.bottom * size.height,
          ),
        );
      }
      canvas.drawPath(
        holes.isEmpty
            ? path
            : Path.combine(PathOperation.difference, path, holePath),
        paint,
      );
    });
  }

  @override
  bool shouldRepaint(TanzilatPainter old) =>
      old.marks != marks ||
      old.margin != margin ||
      old.dark != dark ||
      old.holes != holes;
}

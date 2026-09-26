import 'dart:ui' show Color, Rect;

/// Where one word of an ayah sits on a mushaf page image (page-relative
/// 0..1 ratios, `BoxFit.fill` convention like `AyahHighlightRect`).
///
/// [parts] are the small rectangles that together cover exactly this word's
/// ink (its strokes and its marks, each component's box), so masking them
/// hides the word without touching the marks of the neighbouring lines that
/// reach into its bounding box. [x]/[y]/[width]/[height] is the union box.
class WordBox {
  final double x;
  final double y;
  final double width;
  final double height;
  final List<Rect> parts;

  const WordBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.parts = const [],
  });

  Rect get bounds => Rect.fromLTWH(x, y, width, height);

  /// Builds a box from pixel rects `[x, y, w, h]` of a [pageWidth] x
  /// [pageHeight] image.
  factory WordBox.fromParts(
    List<dynamic> rects, {
    required double pageWidth,
    required double pageHeight,
  }) {
    final parts = <Rect>[];
    for (final r in rects) {
      final v = r as List<dynamic>;
      parts.add(Rect.fromLTWH(
        (v[0] as num) / pageWidth,
        (v[1] as num) / pageHeight,
        (v[2] as num) / pageWidth,
        (v[3] as num) / pageHeight,
      ));
    }
    if (parts.isEmpty) {
      return const WordBox(x: 0, y: 0, width: 0, height: 0);
    }
    var union = parts.first;
    for (final p in parts.skip(1)) {
      union = union.expandToInclude(p);
    }
    return WordBox(
      x: union.left,
      y: union.top,
      width: union.width,
      height: union.height,
      parts: List.unmodifiable(parts),
    );
  }
}

/// The word boxes of one ayah, in reading order -- the same order as the
/// ayah's words in `output.json`, so `words[i]` is the i-th word. Empty when
/// the generator could not place the ayah's words (the app then masks the
/// ayah as a whole).
class WordRegionAyah {
  final int surah;
  final int ayah;
  final List<WordBox> words;

  const WordRegionAyah({
    required this.surah,
    required this.ayah,
    required this.words,
  });

  factory WordRegionAyah.fromJson(
    Map<String, dynamic> json, {
    required double pageWidth,
    required double pageHeight,
  }) {
    final words = <WordBox>[];
    for (final w in json['words'] as List<dynamic>) {
      words.add(WordBox.fromParts(
        w as List<dynamic>,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
      ));
    }
    return WordRegionAyah(
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      words: List.unmodifiable(words),
    );
  }
}

/// All word boxes of one page, ayah by ayah in reading order, plus where
/// the page image sits inside the margin-view (هوامش) image.
class WordRegionPageData {
  final int page;
  final List<WordRegionAyah> ayahs;

  /// The bundled page image's rectangle inside the margin-view image of the
  /// same page, as ratios of that image (the app draws it `BoxFit.fill`
  /// too). Null when unknown; then the margin view gets no word masks.
  final Rect? marginRect;

  /// The paper colour of this page's scan inside the text area, and of its
  /// margin-view scan (tools/sample_paper.py). The masks are painted with
  /// it; the scans differ enough (blue 187-227) that one fixed colour shows
  /// as pale blocks on some pages. Null when not measured.
  final Color? paper;
  final Color? marginPaper;

  const WordRegionPageData({
    required this.page,
    required this.ayahs,
    this.marginRect,
    this.paper,
    this.marginPaper,
  });

  static Color? _color(Object? rgb) {
    if (rgb is! List || rgb.length != 3) return null;
    return Color.fromARGB(
      255,
      (rgb[0] as num).toInt(),
      (rgb[1] as num).toInt(),
      (rgb[2] as num).toInt(),
    );
  }

  /// Pixel size of the page images every box is measured on.
  static const double imageWidth = 720;
  static const double imageHeight = 1640;

  factory WordRegionPageData.fromJson(Map<String, dynamic> json) {
    final hw = json['hw'] as List<dynamic>?;
    return WordRegionPageData(
      page: json['page'] as int,
      ayahs: (json['ayahs'] as List<dynamic>)
          .map((a) => WordRegionAyah.fromJson(
                a as Map<String, dynamic>,
                pageWidth: imageWidth,
                pageHeight: imageHeight,
              ))
          .toList(growable: false),
      marginRect: hw == null
          ? null
          : Rect.fromLTWH(
              (hw[0] as num).toDouble(),
              (hw[1] as num).toDouble(),
              (hw[2] as num).toDouble(),
              (hw[3] as num).toDouble(),
            ),
      paper: _color(json['paper']),
      marginPaper: _color(json['hwPaper']),
    );
  }
}

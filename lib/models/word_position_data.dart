import 'dart:ui' show Rect;

/// A single word's bounding box on a mushaf page image, in page-relative
/// 0..1 ratios (same convention as `AyahHighlightRect` in
/// `ayah_position_data.dart`: multiply by the rendered page's width/height
/// directly -- the page `Image` uses `BoxFit.fill`, so ratios map 1:1 onto
/// the layout constraints).
///
/// Produced offline by `tools/generate_word_positions_page1.py` into
/// `assets/data/word_positions.json`; see that script for how the boxes
/// were derived and why they're hand-calibrated.
class WordPositionRect {
  /// 0-based position of this word within its ayah, joining against
  /// `QuranAyahData.text.split(RegExp(r'\s+'))` -- the app's ground truth
  /// for the expected word string is always `output.json` via
  /// `QuranJsonService`, never the [text] cached here.
  final int index;

  /// The word as it appeared in `output.json` when the positions were
  /// generated. For debugging/drift detection only (see
  /// `WordPositionService.loadWordPositions`), not a runtime source of
  /// truth.
  final String text;

  final double x;
  final double y;
  final double width;
  final double height;

  const WordPositionRect({
    required this.index,
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory WordPositionRect.fromJson(Map<String, dynamic> json) {
    return WordPositionRect(
      index: json['index'] as int,
      text: json['text'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'index': index,
      'text': text,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }

  /// Converts the ratio box to pixel coordinates for a page rendered at
  /// [pageWidth] x [pageHeight].
  Rect toPixelRect(double pageWidth, double pageHeight) {
    return Rect.fromLTWH(
      x * pageWidth,
      y * pageHeight,
      width * pageWidth,
      height * pageHeight,
    );
  }
}

/// All word boxes for one ayah on one page, in recitation (reading) order.
class AyahWordPositionData {
  final int surah;
  final int ayah;
  final List<WordPositionRect> words;

  const AyahWordPositionData({
    required this.surah,
    required this.ayah,
    required this.words,
  });

  factory AyahWordPositionData.fromJson(Map<String, dynamic> json) {
    return AyahWordPositionData(
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      words: (json['words'] as List<dynamic>)
          .map((item) => WordPositionRect.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'surah': surah,
      'ayah': ayah,
      'words': words.map((word) => word.toJson()).toList(),
    };
  }
}

/// All ayahs' word boxes for one page.
class WordPositionPageData {
  final int page;
  final List<AyahWordPositionData> ayahs;

  const WordPositionPageData({
    required this.page,
    required this.ayahs,
  });

  factory WordPositionPageData.fromJson(Map<String, dynamic> json) {
    return WordPositionPageData(
      page: json['page'] as int,
      ayahs: (json['ayahs'] as List<dynamic>)
          .map(
            (item) => AyahWordPositionData.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'page': page,
      'ayahs': ayahs.map((ayah) => ayah.toJson()).toList(),
    };
  }

  /// Every word box on the page flattened into recitation order (ayahs in
  /// order, words within each ayah in order) -- the same order the
  /// memorization-test aligner's expected-word list uses, so index N here
  /// corresponds to expected word N.
  List<WordPositionRect> get wordsInRecitationOrder =>
      [for (final ayah in ayahs) ...ayah.words];
}

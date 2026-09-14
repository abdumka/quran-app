/// Where one word of an ayah sits on a mushaf page image (page-relative
/// 0..1 ratios, `BoxFit.fill` convention like `AyahHighlightRect`).
class WordBox {
  final double x;
  final double y;
  final double width;
  final double height;

  const WordBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// The word boxes of one ayah, in reading order -- the same order as the
/// ayah's words in `output.json`, so `words[i]` is the i-th word.
class WordRegionAyah {
  final int surah;
  final int ayah;
  final List<WordBox> words;

  const WordRegionAyah({
    required this.surah,
    required this.ayah,
    required this.words,
  });

  factory WordRegionAyah.fromJson(Map<String, dynamic> json) {
    final words = <WordBox>[];
    for (final line in json['lines'] as List<dynamic>) {
      final l = line as Map<String, dynamic>;
      final lineY = (l['y'] as num).toDouble();
      final lineH = (l['h'] as num).toDouble();
      for (final w in l['words'] as List<dynamic>) {
        // [x, width, y, height]: the word's own ink box. Older data carried
        // only [x, width] and used the line band vertically.
        final xw = w as List<dynamic>;
        words.add(WordBox(
          x: (xw[0] as num).toDouble(),
          width: (xw[1] as num).toDouble(),
          y: xw.length > 2 ? (xw[2] as num).toDouble() : lineY,
          height: xw.length > 3 ? (xw[3] as num).toDouble() : lineH,
        ));
      }
    }
    return WordRegionAyah(
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      words: List.unmodifiable(words),
    );
  }
}

/// All word boxes of one page, ayah by ayah in reading order.
class WordRegionPageData {
  final int page;
  final List<WordRegionAyah> ayahs;

  const WordRegionPageData({required this.page, required this.ayahs});

  factory WordRegionPageData.fromJson(Map<String, dynamic> json) {
    return WordRegionPageData(
      page: json['page'] as int,
      ayahs: (json['ayahs'] as List<dynamic>)
          .map((a) => WordRegionAyah.fromJson(a as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

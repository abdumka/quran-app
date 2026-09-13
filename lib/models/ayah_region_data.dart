import 'ayah_position_data.dart' show AyahHighlightRect;

/// Where one ayah sits on a mushaf page image: one rect per printed line it
/// occupies (page-relative 0..1 ratios, `BoxFit.fill` convention like
/// [AyahHighlightRect]) plus the box of its ۝ end marker. The rects stop at
/// the marker on either side, so masking every rect leaves the markers
/// visible and the reciter keeps their place on a concealed page.
class AyahRegion {
  final int surah;
  final int ayah;
  final List<AyahHighlightRect> rects;

  /// Null only for an ayah that continues onto the next page (its marker is
  /// printed there).
  final AyahHighlightRect? marker;

  const AyahRegion({
    required this.surah,
    required this.ayah,
    required this.rects,
    required this.marker,
  });

  factory AyahRegion.fromJson(Map<String, dynamic> json) {
    final marker = json['marker'];
    return AyahRegion(
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      rects: (json['rects'] as List<dynamic>)
          .map((r) => AyahHighlightRect.fromJson(r as Map<String, dynamic>))
          .toList(growable: false),
      marker: marker == null
          ? null
          : AyahHighlightRect.fromJson(marker as Map<String, dynamic>),
    );
  }
}

/// All ayah regions of one page, in reading order (the same order as the
/// page's ayahs in `output.json`).
class AyahRegionPageData {
  final int page;
  final List<AyahRegion> ayahs;

  const AyahRegionPageData({required this.page, required this.ayahs});

  factory AyahRegionPageData.fromJson(Map<String, dynamic> json) {
    return AyahRegionPageData(
      page: json['page'] as int,
      ayahs: (json['ayahs'] as List<dynamic>)
          .map((a) => AyahRegion.fromJson(a as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

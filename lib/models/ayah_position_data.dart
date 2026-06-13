class AyahHighlightRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const AyahHighlightRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory AyahHighlightRect.fromJson(Map<String, dynamic> json) {
    return AyahHighlightRect(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'x': double.parse(x.toStringAsFixed(6)),
      'y': double.parse(y.toStringAsFixed(6)),
      'width': double.parse(width.toStringAsFixed(6)),
      'height': double.parse(height.toStringAsFixed(6)),
    };
  }
}

class AyahPositionData {
  final int surah;
  final int ayah;
  final List<AyahHighlightRect> rects;

  const AyahPositionData({
    required this.surah,
    required this.ayah,
    required this.rects,
  });

  factory AyahPositionData.fromJson(Map<String, dynamic> json) {
    return AyahPositionData(
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      rects: (json['rects'] as List<dynamic>)
          .map((item) => AyahHighlightRect.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'surah': surah,
      'ayah': ayah,
      'rects': rects.map((rect) => rect.toJson()).toList(),
    };
  }
}

class AyahPagePositionData {
  final int page;
  final List<AyahPositionData> ayahs;

  const AyahPagePositionData({
    required this.page,
    required this.ayahs,
  });

  factory AyahPagePositionData.fromJson(Map<String, dynamic> json) {
    return AyahPagePositionData(
      page: json['page'] as int,
      ayahs: (json['ayahs'] as List<dynamic>)
          .map((item) => AyahPositionData.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'page': page,
      'ayahs': ayahs.map((ayah) => ayah.toJson()).toList(),
    };
  }
}

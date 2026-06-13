import 'package:flutter/foundation.dart';

@immutable
class ReaderBookmark {
  final int slot;
  final int page;
  final double x;
  final double y;
  final String? label;
  final double? sourceWidth;
  final double? sourceHeight;

  const ReaderBookmark({
    required this.slot,
    required this.page,
    required this.x,
    required this.y,
    this.label,
    this.sourceWidth,
    this.sourceHeight,
  });

  double leftFor(double displayWidth) {
    if (sourceWidth == null || sourceWidth == 0) return x;
    return (x / sourceWidth!) * displayWidth;
  }

  double topFor(double displayHeight) {
    if (sourceHeight == null || sourceHeight == 0) return y;
    return (y / sourceHeight!) * displayHeight;
  }

  ReaderBookmark copyWith({
    int? slot,
    int? page,
    double? x,
    double? y,
    String? label,
    bool clearLabel = false,
    double? sourceWidth,
    double? sourceHeight,
  }) {
    return ReaderBookmark(
      slot: slot ?? this.slot,
      page: page ?? this.page,
      x: x ?? this.x,
      y: y ?? this.y,
      label: clearLabel ? null : (label ?? this.label),
      sourceWidth: sourceWidth ?? this.sourceWidth,
      sourceHeight: sourceHeight ?? this.sourceHeight,
    );
  }

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'page': page,
        'x': x,
        'y': y,
        'label': label,
        'sourceWidth': sourceWidth,
        'sourceHeight': sourceHeight,
      };

  factory ReaderBookmark.fromJson(Map<String, dynamic> json) {
    return ReaderBookmark(
      slot: json['slot'] as int,
      page: json['page'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      label: json['label'] as String?,
      sourceWidth: (json['sourceWidth'] as num?)?.toDouble(),
      sourceHeight: (json['sourceHeight'] as num?)?.toDouble(),
    );
  }
}

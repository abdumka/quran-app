import 'package:flutter/material.dart';

/// Colours of the أدوات الحفظ / Tasmee windows, following the app's light or
/// dark theme like the Tilawah options sheet does.
class HifzPalette {
  const HifzPalette._({
    required this.bg,
    required this.raised,
    required this.title,
    required this.onTitle,
    required this.text,
    required this.border,
    required this.good,
    required this.bad,
  });

  factory HifzPalette.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  static const _light = HifzPalette._(
    bg: Color(0xFFF8F1DE),
    raised: Color(0xFFFFFBEF),
    title: Color(0xFF8D6E3F),
    onTitle: Colors.white,
    text: Color(0xFF35250E),
    border: Color(0xFFE2D2A5),
    good: Color(0xFF2E7D32),
    bad: Color(0xFFB3261E),
  );

  static const _dark = HifzPalette._(
    bg: Color(0xFF1E1A12),
    raised: Color(0xFF2B2519),
    title: Color(0xFFD6B35D),
    onTitle: Colors.black,
    text: Colors.white,
    border: Color(0xFF53401F),
    good: Color(0xFF9AD69C),
    bad: Color(0xFFF0A59A),
  );

  /// Sheet / page background, and a slightly lifted surface (dropdown menus).
  final Color bg;
  final Color raised;

  /// Titles, icons and accents; [onTitle] is text on a [title]-filled button.
  final Color title;
  final Color onTitle;

  /// Body text; use [sub] for secondary lines.
  final Color text;
  Color get sub => text.withValues(alpha: 0.65);
  final Color border;

  final Color good;
  final Color bad;
}

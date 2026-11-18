import 'package:flutter/material.dart';

import '../../theme/app_surfaces.dart';

/// Colours of the أدوات الحفظ / Tasmee windows, following the app's light or
/// dark theme like the Tilawah options sheet does. In the new look (light)
/// they come from [AppSurfaces]; the previous look and night mode keep the
/// colours below.
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
    this.surfaces,
    Color? page,
    Color? heading,
    Color? icon,
    Color? button,
    Color? onButton,
    Color? selected,
    Color? onSelected,
    Color? sub,
  }) : _page = page,
       _heading = heading,
       _icon = icon,
       _button = button,
       _onButton = onButton,
       _selected = selected,
       _onSelected = onSelected,
       _sub = sub;

  factory HifzPalette.of(BuildContext context) {
    final s = AppSurfaces.maybeOf(context);
    if (s != null) return HifzPalette._fromSurfaces(s);
    return Theme.of(context).brightness == Brightness.dark ? _dark : _light;
  }

  factory HifzPalette._fromSurfaces(AppSurfaces s) => HifzPalette._(
    bg: s.sheet,
    raised: s.card,
    title: s.accent,
    onTitle: s.onButton,
    text: s.text,
    border: s.border,
    good: _light.good,
    bad: _light.bad,
    surfaces: s,
    page: s.page,
    heading: s.text,
    icon: s.icon,
    button: s.button,
    onButton: s.onButton,
    selected: s.selected,
    onSelected: s.onSelected,
    sub: s.muted,
  );

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

  /// The new look's colours, or null in the previous look and night mode
  /// (for the few pictures that draw fixed colours).
  final AppSurfaces? surfaces;

  /// Sheet background, and a slightly lifted surface (cards, dropdown menus).
  final Color bg;
  final Color raised;

  /// Behind a full page (stats, reports, logs, test setup) and its app bar.
  Color get page => _page ?? bg;
  final Color? _page;

  /// Accents (links, values, the chosen tab); [onTitle] is text on a
  /// [title]-filled shape.
  final Color title;
  final Color onTitle;

  /// Sheet and page titles, and the headings in them.
  Color get heading => _heading ?? title;
  final Color? _heading;

  /// Row and button icons.
  Color get icon => _icon ?? title;
  final Color? _icon;

  /// The primary button and its label.
  Color get button => _button ?? title;
  Color get onButton => _onButton ?? onTitle;
  final Color? _button;
  final Color? _onButton;

  /// The chosen chip, and the text on it.
  Color get selected => _selected ?? title;
  Color get onSelected => _onSelected ?? onTitle;
  final Color? _selected;
  final Color? _onSelected;

  /// Body text; use [sub] for secondary lines.
  final Color text;
  Color get sub => _sub ?? text.withValues(alpha: 0.65);
  final Color? _sub;
  final Color border;

  final Color good;
  final Color bad;

  /// A heading's weight: [old] as it was, a lighter 600 in the new look.
  FontWeight head(FontWeight old) =>
      surfaces == null ? old : FontWeight.w600;
}

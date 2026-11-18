import 'package:flutter/material.dart';

import '../services/app_look_service.dart';

/// The colours of the new look (2026-11 polish), in one place.
///
/// Every menu, sheet, dialog and page reads them through
/// [AppSurfaces.maybeOf]. It returns null in the previous look («شكل التطبيق:
/// السابق») and in night mode, so a screen keeps its existing colours there
/// with no extra code:
///
/// ```dart
/// final s = AppSurfaces.maybeOf(context);
/// color: s?.sheet ?? const Color(0xFFF8F1DE), // the old value stays as is
/// ```
///
/// The bars and the side drawer read [AppChrome.of], which also covers the
/// previous look and night mode.
///
/// Seven colours (owner, 2026-11-13; review Del/unslop_colour_themes_review.html).
/// ورقي and كريمي وذهبي match the first review demo; the others tint the
/// same light menus toward their bar colour.
@immutable
class AppSurfaces {
  const AppSurfaces({
    required this.sheet,
    required this.card,
    required this.page,
    required this.text,
    required this.muted,
    required this.icon,
    required this.tile,
    required this.hair,
    required this.border,
    required this.band,
    required this.selected,
    required this.onSelected,
    required this.accent,
    required this.button,
    required this.onButton,
    required this.buttonQuiet,
    required this.handle,
    required this.field,
    required this.highlight,
    required this.info,
  });

  /// Bottom sheets, dialogs and page backgrounds of menus.
  final Color sheet;

  /// Cards and rows that sit on [sheet].
  final Color card;

  /// Behind full-screen pages (search, index, settings).
  final Color page;

  /// Primary text.
  final Color text;

  /// Secondary text, hints, captions.
  final Color muted;

  /// Row icons.
  final Color icon;

  /// The small rounded tile behind a row icon.
  final Color tile;

  /// Hairline dividers.
  final Color hair;

  /// Card and field borders.
  final Color border;

  /// Header bands, tab strips.
  final Color band;

  /// The chosen chip or segment, and the text on it.
  final Color selected;
  final Color onSelected;

  /// The one accent: links, the chosen number, small emphasis. Darker than
  /// the bars' gold so it reads on the light sheets.
  final Color accent;

  /// The primary button and its label.
  final Color button;
  final Color onButton;

  /// A secondary button's fill.
  final Color buttonQuiet;

  /// The drag handle on top of sheets.
  final Color handle;

  /// Text fields.
  final Color field;

  /// Search hits and other marked text.
  final Color highlight;

  /// The small ⓘ buttons.
  final Color info;

  static const double radius = 16;
  static const double cardRadius = 12;

  static const AppSurfaces paper = AppSurfaces(
    sheet: Color(0xFFFBF8F1),
    card: Color(0xFFFFFDF8),
    page: Color(0xFFF4EFE4),
    text: Color(0xFF2B2116),
    muted: Color(0xFF7B7266),
    icon: Color(0xFF6B5332),
    tile: Color(0xFFEFE6D4),
    hair: Color(0x245C4522),
    border: Color(0x245C4522),
    band: Color(0xFFFBF8F1),
    selected: Color(0xFFD2B97E),
    onSelected: Color(0xFF2B2116),
    accent: Color(0xFF8A6420),
    button: Color(0xFF2B2116),
    onButton: Color(0xFFF7F3EA),
    buttonQuiet: Color(0xFFEFE9DF),
    handle: Color(0x385C4522),
    field: Color(0xFFFFFDF8),
    highlight: Color(0xFFF1E3BE),
    info: Color(0x8C8B7355),
  );

  static const AppSurfaces cream = AppSurfaces(
    sheet: Color(0xFFF8F1DE),
    card: Color(0xFFFFFBEF),
    page: Color(0xFFF6F1E5),
    text: Color(0xFF35250E),
    muted: Color(0xFF7A6A4F),
    icon: Color(0xFF8B7355),
    tile: Color(0xFFEFE3C3),
    hair: Color(0x3D8B7355),
    border: Color(0xFFE2D2A5),
    band: Color(0xFFEFE3C3),
    selected: Color(0xFFE6D09A),
    onSelected: Color(0xFF35250E),
    accent: Color(0xFF8B6A2E),
    button: Color(0xFF8B6A2E),
    onButton: Color(0xFFFFFFFF),
    buttonQuiet: Color(0xFFEFE3C3),
    handle: Color(0x598B7355),
    field: Color(0xFFFFFBEF),
    highlight: Color(0xFFEAD39A),
    info: Color(0x998B7355),
  );

  static const AppSurfaces olive = AppSurfaces(
    sheet: Color(0xFFF7F7F0),
    card: Color(0xFFFFFFFA),
    page: Color(0xFFEEF0E6),
    text: Color(0xFF1F2A21),
    muted: Color(0xFF67705F),
    icon: Color(0xFF3F5E48),
    tile: Color(0xFFE2E9D9),
    hair: Color(0x2423382C),
    border: Color(0x2423382C),
    band: Color(0xFFF7F7F0),
    selected: Color(0xFFC9D9BE),
    onSelected: Color(0xFF1F2A21),
    accent: Color(0xFF3D6B4C),
    button: Color(0xFF23382C),
    onButton: Color(0xFFF4F2E8),
    buttonQuiet: Color(0xFFE8ECDF),
    handle: Color(0x3823382C),
    field: Color(0xFFFFFFFA),
    highlight: Color(0xFFDCE8CC),
    info: Color(0x8C3F5E48),
  );

  static const AppSurfaces navy = AppSurfaces(
    sheet: Color(0xFFF7F7F5),
    card: Color(0xFFFFFFFF),
    page: Color(0xFFEDEFF2),
    text: Color(0xFF1A2233),
    muted: Color(0xFF636B79),
    icon: Color(0xFF34486B),
    tile: Color(0xFFE2E7F0),
    hair: Color(0x211A2436),
    border: Color(0x211A2436),
    band: Color(0xFFF7F7F5),
    selected: Color(0xFFD3DCEB),
    onSelected: Color(0xFF1A2233),
    accent: Color(0xFF2F4B7C),
    button: Color(0xFF1A2436),
    onButton: Color(0xFFF2F1EC),
    buttonQuiet: Color(0xFFE9ECF1),
    handle: Color(0x381A2436),
    field: Color(0xFFFFFFFF),
    highlight: Color(0xFFDCE4F2),
    info: Color(0x8C34486B),
  );

  static const AppSurfaces maroon = AppSurfaces(
    sheet: Color(0xFFFBF7F4),
    card: Color(0xFFFFFDFB),
    page: Color(0xFFF2EBE7),
    text: Color(0xFF2F1B1E),
    muted: Color(0xFF7A6567),
    icon: Color(0xFF73323B),
    tile: Color(0xFFF0E2E0),
    hair: Color(0x213D1C22),
    border: Color(0x213D1C22),
    band: Color(0xFFFBF7F4),
    selected: Color(0xFFEBD2D0),
    onSelected: Color(0xFF2F1B1E),
    accent: Color(0xFF8C3441),
    button: Color(0xFF3D1C22),
    onButton: Color(0xFFFBF3EE),
    buttonQuiet: Color(0xFFF2E8E5),
    handle: Color(0x383D1C22),
    field: Color(0xFFFFFDFB),
    highlight: Color(0xFFF3DCD8),
    info: Color(0x8C73323B),
  );

  static const AppSurfaces brown = AppSurfaces(
    sheet: Color(0xFFFAF6F0),
    card: Color(0xFFFFFCF7),
    page: Color(0xFFF1EADF),
    text: Color(0xFF2C2016),
    muted: Color(0xFF7A6B5C),
    icon: Color(0xFF6A4B30),
    tile: Color(0xFFEEE3D3),
    hair: Color(0x2433261C),
    border: Color(0x2433261C),
    band: Color(0xFFFAF6F0),
    selected: Color(0xFFE2CFAF),
    onSelected: Color(0xFF2C2016),
    accent: Color(0xFF7E5530),
    button: Color(0xFF33261C),
    onButton: Color(0xFFF8F1E6),
    buttonQuiet: Color(0xFFEFE7DB),
    handle: Color(0x3833261C),
    field: Color(0xFFFFFCF7),
    highlight: Color(0xFFEFDDBC),
    info: Color(0x8C6A4B30),
  );

  static const AppSurfaces graphite = AppSurfaces(
    sheet: Color(0xFFF6F6F6),
    card: Color(0xFFFFFFFF),
    page: Color(0xFFECEDEF),
    text: Color(0xFF1D1E21),
    muted: Color(0xFF6A6D74),
    icon: Color(0xFF4A4E57),
    tile: Color(0xFFE6E7EA),
    hair: Color(0x1F2B2D31),
    border: Color(0x1F2B2D31),
    band: Color(0xFFF6F6F6),
    selected: Color(0xFFD8DAE0),
    onSelected: Color(0xFF1D1E21),
    accent: Color(0xFF3F444D),
    button: Color(0xFF2B2D31),
    onButton: Color(0xFFF4F4F5),
    buttonQuiet: Color(0xFFECEDF0),
    handle: Color(0x382B2D31),
    field: Color(0xFFFFFFFF),
    // search hits need warmth to stand out on grey
    highlight: Color(0xFFF0E6C3),
    info: Color(0x8C4A4E57),
  );

  /// The menu colours of [palette].
  static AppSurfaces of(MenuPalette palette) => switch (palette) {
    MenuPalette.paper => paper,
    MenuPalette.cream => cream,
    MenuPalette.olive => olive,
    MenuPalette.navy => navy,
    MenuPalette.maroon => maroon,
    MenuPalette.brown => brown,
    MenuPalette.graphite => graphite,
  };

  /// The new look's colours, or null in the previous look and in night mode
  /// (keep the existing colours there). Rebuilds [context] when the reader
  /// changes the look.
  static AppSurfaces? maybeOf(BuildContext context) {
    AppLookScope.watch(context);
    final look = AppLookService.instance;
    if (look.isPrevious) return null;
    if (Theme.of(context).brightness == Brightness.dark) return null;
    return of(look.palette.value);
  }
}

/// The top bar, the bottom bar and the side drawer.
@immutable
class AppChrome {
  const AppChrome({
    required this.dark,
    required this.bar,
    required this.barText,
    required this.barIcon,
    required this.barSubtext,
    required this.barHair,
    required this.bottomIcon,
    required this.bottomText,
    required this.drawer,
    required this.drawerText,
    required this.drawerIcon,
    required this.drawerMuted,
    required this.drawerTitle,
    required this.drawerHair,
    required this.barAlpha,
  });

  /// Dark bars (status bar icons go light over them).
  final bool dark;

  /// The bars' fill, before [barAlpha].
  final Color bar;
  final Color barText;
  final Color barIcon;
  final Color barSubtext;

  /// A line under the top bar and over the bottom bar (light bars only).
  final Color barHair;
  final Color bottomIcon;
  final Color bottomText;

  final Color drawer;
  final Color drawerText;
  final Color drawerIcon;
  final Color drawerMuted;
  final Color drawerTitle;
  final Color drawerHair;

  /// How opaque the bars are.
  final double barAlpha;

  Color get barFill => bar.withValues(alpha: barAlpha);

  static const Color _charcoal = Color(0xFF1C1C1E);
  static const Color _gold = Color(0xFFD2B97E);

  /// The dark bars of one colour: [ink] is the bar and drawer colour,
  /// [title] the gold (silver for رمادي هادئ) of the bar text and the
  /// drawer title, [muted] the bottom bar and drawer icons.
  static AppChrome _darkOf({
    required Color ink,
    required Color title,
    Color? icon,
    required Color muted,
    required Color drawerText,
    required Color drawerMuted,
    required double alpha,
  }) => AppChrome(
    dark: true,
    bar: ink,
    barText: title,
    barIcon: icon ?? title,
    barSubtext: title.withValues(alpha: 0.72),
    barHair: Colors.transparent,
    bottomIcon: muted,
    bottomText: muted,
    drawer: ink,
    drawerText: drawerText,
    drawerIcon: muted,
    drawerMuted: drawerMuted,
    drawerTitle: title,
    drawerHair: drawerText.withValues(alpha: 0.08),
    barAlpha: alpha,
  );

  /// Charcoal and gold: ورقي, كريمي وذهبي, night mode, the previous look.
  static AppChrome _charcoalWith(double alpha) => _darkOf(
    ink: _charcoal,
    title: _gold,
    muted: const Color(0xFFA1A1A6),
    drawerText: const Color(0xFFEDEDED),
    drawerMuted: const Color(0xFF85858B),
    alpha: alpha,
  );

  static AppChrome _darkFor(MenuPalette palette, double alpha) =>
      switch (palette) {
        MenuPalette.paper || MenuPalette.cream => _charcoalWith(alpha),
        MenuPalette.olive => _darkOf(
          ink: const Color(0xFF23382C),
          title: const Color(0xFFD9C48E),
          muted: const Color(0xFFA9B5A6),
          drawerText: const Color(0xFFEEF0E8),
          drawerMuted: const Color(0xFF8C998A),
          alpha: alpha,
        ),
        MenuPalette.navy => _darkOf(
          ink: const Color(0xFF1A2436),
          title: _gold,
          muted: const Color(0xFFA3ABBA),
          drawerText: const Color(0xFFEDEFF3),
          drawerMuted: const Color(0xFF8790A0),
          alpha: alpha,
        ),
        MenuPalette.maroon => _darkOf(
          ink: const Color(0xFF3D1C22),
          title: const Color(0xFFD9BD86),
          muted: const Color(0xFFC3A9AC),
          drawerText: const Color(0xFFF6EEEE),
          drawerMuted: const Color(0xFFA88E91),
          alpha: alpha,
        ),
        MenuPalette.brown => _darkOf(
          ink: const Color(0xFF33261C),
          title: const Color(0xFFD7B982),
          muted: const Color(0xFFB3A595),
          drawerText: const Color(0xFFF3ECE3),
          drawerMuted: const Color(0xFF978A7B),
          alpha: alpha,
        ),
        MenuPalette.graphite => _darkOf(
          ink: const Color(0xFF2B2D31),
          title: const Color(0xFFE6E6E8),
          icon: const Color(0xFFC9CBD0),
          muted: const Color(0xFF9EA1A8),
          drawerText: const Color(0xFFEDEDEF),
          drawerMuted: const Color(0xFF85888F),
          alpha: alpha,
        ),
      };

  /// Light bars and drawer in the colour of the menus.
  static AppChrome _lightFor(MenuPalette palette, double alpha) {
    // ورقي and كريمي وذهبي keep the values the 2026-11-12 build shipped
    if (palette == MenuPalette.paper) {
      return AppChrome(
        dark: false,
        bar: const Color(0xFFFBF8F1),
        barText: const Color(0xFF2B2116),
        barIcon: const Color(0xFF8A6420),
        barSubtext: const Color(0xFF7B7266),
        barHair: const Color(0x245C4522),
        bottomIcon: const Color(0xFF6B5332),
        bottomText: const Color(0xFF5E554A),
        drawer: const Color(0xFFFBF8F1),
        drawerText: const Color(0xFF2B2116),
        drawerIcon: const Color(0xFF6B5332),
        drawerMuted: const Color(0xFF7B7266),
        drawerTitle: const Color(0xFF8A6420),
        drawerHair: const Color(0x245C4522),
        barAlpha: alpha,
      );
    }
    if (palette == MenuPalette.cream) {
      return AppChrome(
        dark: false,
        bar: const Color(0xFFF8F1DE),
        barText: const Color(0xFF35250E),
        barIcon: const Color(0xFF8B7355),
        barSubtext: const Color(0xFF7A6A4F),
        barHair: const Color(0xFFE2D2A5),
        bottomIcon: const Color(0xFF8B7355),
        bottomText: const Color(0xFF6E5837),
        drawer: const Color(0xFFF8F1DE),
        drawerText: const Color(0xFF35250E),
        drawerIcon: const Color(0xFF8B7355),
        drawerMuted: const Color(0xFF7A6A4F),
        drawerTitle: const Color(0xFF8B6A2E),
        drawerHair: const Color(0xFFE2D2A5),
        barAlpha: alpha,
      );
    }
    final s = AppSurfaces.of(palette);
    return AppChrome(
      dark: false,
      bar: s.sheet,
      barText: s.text,
      barIcon: s.accent,
      barSubtext: s.muted,
      barHair: s.hair,
      bottomIcon: s.icon,
      bottomText: s.muted,
      drawer: s.sheet,
      drawerText: s.text,
      drawerIcon: s.icon,
      drawerMuted: s.muted,
      drawerTitle: s.accent,
      drawerHair: s.hair,
      barAlpha: alpha,
    );
  }

  /// The bar colour of [palette] with dark bars, for its swatch in Settings.
  static Color swatchInk(MenuPalette palette) => _darkFor(palette, 1).bar;

  /// The previous look: the dark bars as they were, top bar at 65%.
  static final AppChrome previous = _charcoalWith(0.65);

  static double alphaOf(BarOpacity o) => switch (o) {
    BarOpacity.p65 => 0.65,
    BarOpacity.p80 => 0.80,
    BarOpacity.p94 => 0.94,
    BarOpacity.solid => 1.0,
  };

  /// The bars and drawer for the reader's choices. Night mode keeps the
  /// charcoal bars (with the chosen transparency) whatever the colour.
  /// Rebuilds [context] when the look changes.
  static AppChrome of(BuildContext context) {
    AppLookScope.watch(context);
    final look = AppLookService.instance;
    if (look.isPrevious) return previous;
    final alpha = alphaOf(look.barOpacity.value);
    if (Theme.of(context).brightness == Brightness.dark) {
      return _charcoalWith(alpha);
    }
    if (look.chromeIsDark) return _darkFor(look.palette.value, alpha);
    return _lightFor(look.palette.value, alpha);
  }
}

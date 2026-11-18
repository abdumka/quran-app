import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «شكل التطبيق» in Settings: the new look (the default since the 2026-11
/// polish) or the look the app had before it, kept whole for readers who
/// prefer it (owner, 2026-11-12). The previous look brings back the gear and
/// the hide-bar eye on the top bar (no side drawer), the old Settings cards
/// with their counts, the three cards at the bottom of Settings, and the
/// ✓ / ✕ in every switch.
enum AppLook { current, previous }

/// «لون التطبيق» in the new look (Settings › إعدادات العرض): the colour of
/// the bars and the side drawer, and the light tint of the menus, sheets and
/// pages. Menus stay light in every colour (owner, 2026-11-12); the bars turn
/// light too when «إبقاء الأشرطة والقائمة داكنة» is off. All seven ship
/// (owner, 2026-11-13).
enum MenuPalette { paper, cream, olive, navy, maroon, brown, graphite }

/// How much of the page shows through the top and bottom bars. The frosted
/// choice was dropped (owner, 2026-11-13): it blurred the page on every frame.
enum BarOpacity { p65, p80, p94, solid }

/// The Tasmee session bar in the new look: [recoloured] is today's bar in the
/// new colours, [hairline] adds a thin outline instead of the shadow and a
/// divider before «إنهاء», [slim] has smaller icons.
enum TasmeeBarStyle { recoloured, hairline, slim }

class AppLookService {
  AppLookService._();
  static final AppLookService instance = AppLookService._();

  static const String _lookPref = 'app_look';
  static const String _palettePref = 'app_look_palette';
  static const String _darkChromePref = 'app_look_dark_chrome';
  static const String _barOpacityPref = 'app_look_bar_opacity';
  static const String _tasmeeBarPref = 'app_look_tasmee_bar';

  final ValueNotifier<AppLook> look = ValueNotifier(AppLook.current);
  final ValueNotifier<MenuPalette> palette = ValueNotifier(MenuPalette.paper);

  /// «إبقاء الأشرطة والقائمة داكنة». Off gives light bars in any colour.
  final ValueNotifier<bool> darkChrome = ValueNotifier(true);
  final ValueNotifier<BarOpacity> barOpacity = ValueNotifier(BarOpacity.p94);
  final ValueNotifier<TasmeeBarStyle> tasmeeBar = ValueNotifier(
    TasmeeBarStyle.recoloured,
  );

  /// Fires when any of the choices above changes.
  late final Listenable changes = Listenable.merge([
    look,
    palette,
    darkChrome,
    barOpacity,
    tasmeeBar,
  ]);

  bool get isPrevious => look.value == AppLook.previous;

  /// Dark top bar, bottom bar and drawer: always in the previous look.
  bool get chromeIsDark => isPrevious || darkChrome.value;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      look.value = _byName(AppLook.values, prefs.getString(_lookPref), look.value);
      final savedPalette = prefs.getString(_palettePref);
      darkChrome.value = prefs.getBool(_darkChromePref) ?? darkChrome.value;
      if (savedPalette == 'light') {
        // build 144 had «فاتح بالكامل» as a colour: it is ورقي with light
        // bars, which the switch now gives in any colour
        palette.value = MenuPalette.paper;
        darkChrome.value = false;
        await prefs.setString(_palettePref, MenuPalette.paper.name);
        await prefs.setBool(_darkChromePref, false);
      } else {
        palette.value = _byName(MenuPalette.values, savedPalette, palette.value);
      }
      final savedOpacity = prefs.getString(_barOpacityPref);
      if (savedOpacity == 'frosted') {
        // «ضبابي» was 80% plus the blur
        barOpacity.value = BarOpacity.p80;
        await prefs.setString(_barOpacityPref, BarOpacity.p80.name);
      } else {
        barOpacity.value = _byName(
          BarOpacity.values,
          savedOpacity,
          barOpacity.value,
        );
      }
      tasmeeBar.value = _byName(
        TasmeeBarStyle.values,
        prefs.getString(_tasmeeBarPref),
        tasmeeBar.value,
      );
    } catch (_) {
      // keep the defaults
    }
  }

  Future<void> set(AppLook value) => _save(look, value, _lookPref);
  Future<void> setPalette(MenuPalette value) =>
      _save(palette, value, _palettePref);
  Future<void> setBarOpacity(BarOpacity value) =>
      _save(barOpacity, value, _barOpacityPref);
  Future<void> setTasmeeBar(TasmeeBarStyle value) =>
      _save(tasmeeBar, value, _tasmeeBarPref);

  Future<void> setDarkChrome(bool value) async {
    if (darkChrome.value == value) return;
    darkChrome.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_darkChromePref, value);
    } catch (_) {}
  }

  Future<void> _save<T extends Enum>(
    ValueNotifier<T> notifier,
    T value,
    String pref,
  ) async {
    if (notifier.value == value) return;
    notifier.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pref, value.name);
    } catch (_) {}
  }

  static T _byName<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}

/// Sits above the MaterialApp, so every screen that reads the look (through
/// [AppLookScope.isPrevious] or the theme in `lib/theme/app_surfaces.dart`)
/// is rebuilt when the reader changes it.
class AppLookScope extends InheritedNotifier<Listenable> {
  const AppLookScope({super.key, required super.notifier, required super.child});

  /// Registers [context] for rebuilds when any look choice changes.
  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AppLookScope>();
  }

  /// True when the reader chose the previous look. Widgets that call this
  /// rebuild when the choice changes. Outside a scope (tests) it reads the
  /// service directly.
  static bool isPrevious(BuildContext context) {
    watch(context);
    return AppLookService.instance.isPrevious;
  }
}

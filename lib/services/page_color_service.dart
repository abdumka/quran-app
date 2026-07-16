import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paper tints available for Quran page images in light mode.
enum PageColorTheme {
  classic('classic', 'أصلي', Color(0xFFF9F9D9)),
  white('white', 'أبيض', Color(0xFFFFFFFF)),
  cream('cream', 'كريمي', Color(0xFFFFDFA8)),
  sage('sage', 'أخضر هادئ', Color(0xFFDDEED2)),
  blue('blue', 'أزرق هادئ', Color(0xFFDCEAF5)),
  rose('rose', 'وردي هادئ', Color(0xFFF3DEDA));

  const PageColorTheme(this.storageValue, this.arabicLabel, this.color);

  final String storageValue;
  final String arabicLabel;
  final Color color;

  /// Re-maps the characteristic yellow-green scan paper to the chosen paper
  /// color. The transform is anchored at both the source paper and the dark
  /// green ink, so it changes the background much more clearly than a simple
  /// multiply tint while retaining ink contrast and the gold ayah markers.
  ColorFilter get lightModeFilter {
    if (this == PageColorTheme.classic) {
      return const ColorFilter.mode(Colors.white, BlendMode.multiply);
    }

    const sourcePaper = Color(0xFFF9F9D9);
    const sourceInk = Color(0xFF0A432D);
    const targetInk = Color(0xFF123C2C);

    final red = _anchoredChannel(
      sourceInk.r,
      sourcePaper.r,
      targetInk.r,
      color.r,
    );
    final green = _anchoredChannel(
      sourceInk.g,
      sourcePaper.g,
      targetInk.g,
      color.g,
    );
    final blue = _anchoredChannel(
      sourceInk.b,
      sourcePaper.b,
      targetInk.b,
      color.b,
    );

    return ColorFilter.matrix([
      red.$1,
      0,
      0,
      0,
      red.$2,
      0,
      green.$1,
      0,
      0,
      green.$2,
      0,
      0,
      blue.$1,
      0,
      blue.$2,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  static (double, double) _anchoredChannel(
    double sourceInk,
    double sourcePaper,
    double targetInk,
    double targetPaper,
  ) {
    final gain = (targetPaper - targetInk) / (sourcePaper - sourceInk);
    // Color components are normalized to 0–1, while ColorFilter matrix
    // offsets use the legacy 0–255 channel scale.
    final offset = (targetInk - (gain * sourceInk)) * 255;
    return (gain, offset);
  }

  static PageColorTheme fromStorageValue(String? value) {
    return PageColorTheme.values.firstWhere(
      (theme) => theme.storageValue == value,
      orElse: () => PageColorTheme.classic,
    );
  }
}

/// Stores and publishes the user's preferred Quran page paper color.
class PageColorService {
  PageColorService._();
  static final PageColorService instance = PageColorService._();

  static const String prefKey = 'quranPageColor';

  final ValueNotifier<PageColorTheme> selected = ValueNotifier<PageColorTheme>(
    PageColorTheme.classic,
  );

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    selected.value = PageColorTheme.fromStorageValue(prefs.getString(prefKey));
  }

  Future<void> setSelected(PageColorTheme value) async {
    if (selected.value == value) return;
    selected.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, value.storageValue);
  }

  Future<void> reset() async {
    selected.value = PageColorTheme.classic;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefKey);
  }
}

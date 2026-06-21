import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/image_config.dart';

/// User-selected quality for the rendered Qur'an page images.
///
/// All available image sets are 720x1640, so the levels differ by *rendering*
/// and *encoding fidelity*, not by resolution:
///   1 = Standard      — bundled images, ResizeImage(720) + FilterQuality.low
///                       (the original, lightest behaviour).
///   2 = Enhanced      — bundled images, native decode + FilterQuality.high
///                       (smoother upscaling; free, no download, no size change).
///   3 = HighFidelity  — the less-compressed downloaded pack (same 720px, fewer
///                       artifacts) + FilterQuality.high. Falls back to level 2
///                       rendering until the pack has been downloaded.
class PageQualityService {
  PageQualityService._();
  static final PageQualityService instance = PageQualityService._();

  static const String _prefKey = 'pageQualityLevel';

  static const int standard = 1;
  static const int enhanced = 2;
  static const int highFidelity = 3;

  /// Default level for a fresh install: high-fidelity when the HQ pack is
  /// bundled in the app, otherwise the lightest standard mode.
  static const int _defaultLevel =
      kBundleHighFidelityImages ? highFidelity : standard;

  /// Currently selected level. Listen to rebuild image widgets when it changes.
  final ValueNotifier<int> level = ValueNotifier<int>(_defaultLevel);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_prefKey) ?? _defaultLevel;
    level.value = _clamp(stored);
  }

  Future<void> setLevel(int value) async {
    final next = _clamp(value);
    if (level.value == next) return;
    level.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, next);
  }

  /// Levels 2 and 3 decode at native size and draw with a high-quality filter;
  /// level 1 keeps the original 720px resize + low filter.
  bool get nativeDecode => level.value != standard;

  FilterQuality get filterQuality =>
      level.value == standard ? FilterQuality.low : FilterQuality.high;

  int _clamp(int v) => (v < standard || v > highFidelity) ? standard : v;
}

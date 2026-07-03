import 'package:flutter/widgets.dart';

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

  static const int standard = 1;
  static const int enhanced = 2;
  static const int highFidelity = 3;

  /// The quality picker has been retired: page images are now always rendered
  /// at the highest fidelity ("فائق الجودة") and the level can no longer be
  /// changed by the user. The bundled HQ pack makes this free (no download).
  static const int _defaultLevel = highFidelity;

  /// Currently selected level. Fixed at [highFidelity]; kept as a notifier so
  /// image widgets that listen to it continue to work unchanged.
  final ValueNotifier<int> level = ValueNotifier<int>(_defaultLevel);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    // Always high fidelity, regardless of any value stored by older builds.
    level.value = _defaultLevel;
  }

  /// Retained for API compatibility; the level is now fixed so this is a no-op.
  Future<void> setLevel(int value) async {}

  /// Levels 2 and 3 decode at native size and draw with a high-quality filter;
  /// level 1 keeps the original 720px resize + low filter.
  bool get nativeDecode => level.value != standard;

  FilterQuality get filterQuality =>
      level.value == standard ? FilterQuality.low : FilterQuality.high;
}

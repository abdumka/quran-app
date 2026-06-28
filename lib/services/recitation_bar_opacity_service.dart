import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-selected opacity values for the recitation bottom bar's appearance:
/// the icons/buttons (play, next, previous, repeat, ayah number, close, help)
/// and the bar's own background.
///
/// 1.0 = fully opaque, 0.0 = fully transparent.
class RecitationBarOpacityService {
  RecitationBarOpacityService._();
  static final RecitationBarOpacityService instance =
      RecitationBarOpacityService._();

  static const String _iconPrefKey = 'recitationBarIconOpacity';
  static const double defaultIconOpacity = 0.85;

  static const String _backgroundPrefKey = 'recitationBarBackgroundOpacity';
  static const double defaultBackgroundOpacity = 0.16;

  /// Currently selected icon opacity. Listen to rebuild the bar when it changes.
  final ValueNotifier<double> opacity =
      ValueNotifier<double>(defaultIconOpacity);

  /// Currently selected background opacity. Listen to rebuild the bar when it changes.
  final ValueNotifier<double> backgroundOpacity =
      ValueNotifier<double>(defaultBackgroundOpacity);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final storedIcon = prefs.getDouble(_iconPrefKey) ?? defaultIconOpacity;
    opacity.value = _clamp(storedIcon);
    final storedBackground =
        prefs.getDouble(_backgroundPrefKey) ?? defaultBackgroundOpacity;
    backgroundOpacity.value = _clamp(storedBackground);
  }

  Future<void> setOpacity(double value) async {
    final next = _clamp(value);
    if (opacity.value == next) return;
    opacity.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_iconPrefKey, next);
  }

  Future<void> setBackgroundOpacity(double value) async {
    final next = _clamp(value);
    if (backgroundOpacity.value == next) return;
    backgroundOpacity.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_backgroundPrefKey, next);
  }

  double _clamp(double v) => v.clamp(0.0, 1.0);
}

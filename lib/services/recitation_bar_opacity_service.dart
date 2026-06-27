import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-selected opacity for the icons/buttons on the recitation bottom bar
/// (play, next, previous, repeat, ayah number, close, help).
///
/// 1.0 = fully opaque white, 0.0 = fully transparent.
class RecitationBarOpacityService {
  RecitationBarOpacityService._();
  static final RecitationBarOpacityService instance =
      RecitationBarOpacityService._();

  static const String _prefKey = 'recitationBarIconOpacity';
  static const double defaultOpacity = 0.85;

  /// Currently selected opacity. Listen to rebuild the bar when it changes.
  final ValueNotifier<double> opacity = ValueNotifier<double>(defaultOpacity);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble(_prefKey) ?? defaultOpacity;
    opacity.value = _clamp(stored);
  }

  Future<void> setOpacity(double value) async {
    final next = _clamp(value);
    if (opacity.value == next) return;
    opacity.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey, next);
  }

  double _clamp(double v) => v.clamp(0.0, 1.0);
}

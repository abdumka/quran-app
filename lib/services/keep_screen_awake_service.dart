import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preference for keeping the device screen awake while reading.
/// Defaults to on to preserve the app's current behaviour unless the user
/// explicitly turns it off.
class KeepScreenAwakeService {
  KeepScreenAwakeService._();
  static final KeepScreenAwakeService instance = KeepScreenAwakeService._();

  static const String prefKey = 'keepScreenAwakeEnabled';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(prefKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    if (enabled.value == value) return;
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, value);
  }
}

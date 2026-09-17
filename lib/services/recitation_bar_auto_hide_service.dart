import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hide the recitation bottom bar after a period of no input, so it stops
/// covering the mushaf while a long tilawah plays. Any input brings it
/// straight back; playback is never affected, only the bar's visibility.
///
/// On by default with a 15 s delay; both the switch and the delay live under
/// settings → إعدادات متقدمة (and the TV settings page).
class RecitationBarAutoHideService {
  RecitationBarAutoHideService._();

  static final RecitationBarAutoHideService instance =
      RecitationBarAutoHideService._();

  static const String _enabledKey = 'recitationBarAutoHide';
  static const String _delayKey = 'recitationBarAutoHideSeconds';

  static const int defaultDelaySeconds = 15;
  static const int minDelaySeconds = 5;
  static const int maxDelaySeconds = 120;

  /// Step used by the settings stepper.
  static const int delayStepSeconds = 5;

  /// Listen to rebuild the bar when the setting changes.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// Idle seconds before the bar hides. Clamped to
  /// [minDelaySeconds]..[maxDelaySeconds].
  final ValueNotifier<int> delaySeconds = ValueNotifier<int>(
    defaultDelaySeconds,
  );

  /// How long the bar waits before hiding itself.
  Duration get idleDelay => Duration(seconds: delaySeconds.value);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledKey) ?? true;
    delaySeconds.value = _clamp(prefs.getInt(_delayKey) ?? defaultDelaySeconds);
  }

  Future<void> setEnabled(bool value) async {
    if (enabled.value == value) return;
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<void> setDelaySeconds(int seconds) async {
    final clamped = _clamp(seconds);
    if (delaySeconds.value == clamped) return;
    delaySeconds.value = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_delayKey, clamped);
  }

  static int _clamp(int seconds) =>
      seconds.clamp(minDelaySeconds, maxDelaySeconds);
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preference: "ظلّ الكعب" — a soft shade along the spine edge of each
/// page in the normal (non-margin) view, so a right-hand page (odd) and a
/// left-hand page (even) can be told apart at a glance, like an open mushaf.
class SpineShadowService {
  SpineShadowService._();
  static final SpineShadowService instance = SpineShadowService._();

  static const String _prefKey = 'spineShadowEnabled';

  /// Listen to rebuild the reader and the settings toggle. Defaults to on
  /// unless the user explicitly turns it off.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  bool _loaded = false;

  /// The setting is hidden from users for now (the shade is simply on);
  /// a saved "off" from an earlier build is ignored while this is false.
  static const bool userSettable = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (!userSettable) {
      enabled.value = true;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_prefKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    if (enabled.value == value) return;
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }
}

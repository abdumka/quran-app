import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preference: keep the recitation playing when the app goes to the
/// background (e.g. the user pressed the home button). When off, the reader
/// pauses playback on backgrounding (the previous behaviour).
class BackgroundPlaybackService {
  BackgroundPlaybackService._();
  static final BackgroundPlaybackService instance =
      BackgroundPlaybackService._();

  static const String _prefKey = 'backgroundPlaybackEnabled';

  /// Whether recitation continues in the background. Listen to rebuild the
  /// settings toggle.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_prefKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    if (enabled.value == value) return;
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }
}

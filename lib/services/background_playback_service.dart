import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tv_service.dart';

/// User preference: keep the recitation playing when the app goes to the
/// background (e.g. the user pressed the home button). When off, the reader
/// pauses playback on backgrounding (the previous behaviour).
class BackgroundPlaybackService {
  BackgroundPlaybackService._();
  static final BackgroundPlaybackService instance =
      BackgroundPlaybackService._();

  static const String _prefKey = 'backgroundPlaybackEnabled';

  /// The default differs by device, see [defaultEnabled].
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// On by default on phones and tablets: the recitation should keep playing
  /// when the listener pockets the phone.
  ///
  /// **Off by default on TV.** Leaving a television playing Qur'an after the
  /// viewer has gone back to the launcher — or switched to another app, or
  /// pressed the remote's Home — is not what anyone expects from a TV, and it
  /// is far less obvious there than on a phone that something is still
  /// playing: no notification shade to notice it in, and whoever walks past
  /// may not know which app to stop. The toggle is still offered, so anyone
  /// who does want it can turn it on.
  static bool get defaultEnabled => !TvService.instance.isTv;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_prefKey) ?? defaultEnabled;
  }

  Future<void> setEnabled(bool value) async {
    if (enabled.value == value) return;
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }
}

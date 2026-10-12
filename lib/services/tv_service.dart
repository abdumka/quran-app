import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Human-visible marker for sideloaded TV builds. Downloader and the CDN both
/// cache by URL, so "I installed it but nothing changed" is otherwise
/// impossible to diagnose. Bump this with every APK you publish, and publish
/// under a matching filename.
const String kTvBuildStamp = 'TV build 36 — 2026-10-12';

/// Whether this process is running on an Android TV (leanback) device.
///
/// Resolved once at startup over a MethodChannel that asks PackageManager for
/// FEATURE_LEANBACK, because nothing on the Flutter side can tell a TV from a
/// phone: a 1080p TV reports 960x540 logical pixels at density 320, so the
/// shortestSide >= 600 test in [TabletLayoutHelper] sees 540 and calls it a
/// phone. The reader then picks its phone-landscape layout and scales a
/// portrait mushaf page to a 960px-wide viewport that is only 540px tall,
/// which shows the top quarter of the page border and no Quranic text at all.
///
/// [isTv] is false until [initialize] completes, so call it before runApp.
class TvService {
  TvService._();

  static final TvService instance = TvService._();

  static const MethodChannel _channel = MethodChannel(
    'com.mahfodqr.qalon_mushaf/platform',
  );

  /// Last answer the platform gave, kept so a launch on which the channel
  /// cannot be reached at all still comes up in the right mode.
  static const String _prefKey = 'tvService.isTv';

  /// How long to keep asking while the Activity has not registered its
  /// handler yet (see [initialize]). Registration is a few milliseconds away
  /// in practice; the cap only matters if something is badly wrong.
  static const Duration _handlerWait = Duration(seconds: 3);

  bool _isTv = false;

  /// True only on Android TV. Safe to read before [initialize] (returns false).
  bool get isTv => _isTv;

  /// Lets a test pretend to be a TV. Every TV behaviour is gated on [isTv],
  /// so without this seam none of it is reachable from a widget test — the
  /// remote navigation in particular, which is the part most worth testing
  /// and the part that cannot be checked by reading the code.
  @visibleForTesting
  set debugIsTv(bool value) => _isTv = value;

  /// Asks the platform once whether this is a TV. Never throws: any failure
  /// leaves [isTv] at the last known answer (false on a first launch), which
  /// is the phone/tablet behaviour the app already had.
  ///
  /// **Why this retries.** MainActivity registers the channel handler in
  /// `configureFlutterEngine`, but the Activity is an `AudioServiceActivity`,
  /// and audio_service creates the engine and starts the Dart entrypoint
  /// inside `provideFlutterEngine` -- which FlutterActivity calls *before*
  /// `configureFlutterEngine`. So on a cold start `main()` can reach this
  /// call a few milliseconds before the handler exists, and the platform
  /// answers `MissingPluginException`. Treating that as "not a TV" silently
  /// launched the whole phone UI on a television (five-item touch menu, the
  /// bookmark guide, the "what's new" popup, arrows that turn pages while the
  /// user is trying to walk the menu). Seen on two of two cold starts on the
  /// TV emulator on 2026-10-12. The handler is registered moments later in the
  /// same `onCreate`, so asking again is all it takes.
  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final stopwatch = Stopwatch()..start();
    bool resolved = false;
    while (true) {
      try {
        _isTv =
            await _channel
                .invokeMethod<bool>('isAndroidTv')
                .timeout(const Duration(seconds: 2)) ??
            false;
        resolved = true;
        break;
      } on MissingPluginException {
        if (stopwatch.elapsed >= _handlerWait) {
          debugPrint(
            'TvService.initialize: no handler after ${stopwatch.elapsed}',
          );
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      } catch (error, stack) {
        debugPrint('TvService.initialize failed: $error\n$stack');
        break;
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (resolved) {
        // Remembered, not awaited: nothing at startup depends on the write.
        unawaited(prefs.setBool(_prefKey, _isTv));
      } else {
        _isTv = prefs.getBool(_prefKey) ?? false;
      }
    } catch (error) {
      debugPrint('TvService.initialize: prefs unavailable: $error');
    }
  }
}

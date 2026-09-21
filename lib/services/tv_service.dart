import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Human-visible marker for sideloaded TV builds. Downloader and the CDN both
/// cache by URL, so "I installed it but nothing changed" is otherwise
/// impossible to diagnose. Bump this with every APK you publish, and publish
/// under a matching filename.
const String kTvBuildStamp = 'TV build 20 — 2026-09-18';

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

  bool _isTv = false;

  /// True only on Android TV. Safe to read before [initialize] (returns false).
  bool get isTv => _isTv;

  /// Asks the platform once whether this is a TV. Never throws: any failure
  /// leaves [isTv] false, which is the phone/tablet behaviour the app already
  /// had. Bounded by a timeout so a wedged channel cannot stall the splash.
  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _isTv =
          await _channel
              .invokeMethod<bool>('isAndroidTv')
              .timeout(const Duration(seconds: 2)) ??
          false;
    } catch (error, stack) {
      debugPrint('TvService.initialize failed: $error\n$stack');
      _isTv = false;
    }
  }
}

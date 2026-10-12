// TvService must survive asking the platform before the Activity has
// registered its handler.
//
// MainActivity registers the channel in configureFlutterEngine, but the app's
// Activity is audio_service's AudioServiceActivity, whose provideFlutterEngine
// creates the engine and starts the Dart entrypoint first. On a cold start
// main() can therefore reach the channel a few milliseconds early and get a
// MissingPluginException -- which used to be read as "not a TV", launching the
// phone UI on a television (seen on the TV emulator, 2026-10-12).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:islamic_dawah_mushaf/services/tv_service.dart';

const MethodChannel kChannel = MethodChannel(
  'com.mahfodqr.qalon_mushaf/platform',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    TvService.instance.debugIsTv = false;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(kChannel, null);
    debugDefaultTargetPlatformOverride = null;
    TvService.instance.debugIsTv = false;
  });

  test('a handler registered a moment late is still found', () async {
    // Nobody is listening yet: the call comes back MissingPluginException.
    messenger.setMockMethodCallHandler(kChannel, null);
    int asks = 0;
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      messenger.setMockMethodCallHandler(kChannel, (call) async {
        asks++;
        return call.method == 'isAndroidTv' ? true : null;
      });
    });

    await TvService.instance.initialize();

    expect(
      TvService.instance.isTv,
      isTrue,
      reason: 'the early MissingPluginException was taken as "not a TV"',
    );
    expect(asks, 1);
  });

  test('a phone answers false and stays false', () async {
    messenger.setMockMethodCallHandler(kChannel, (call) async => false);
    await TvService.instance.initialize();
    expect(TvService.instance.isTv, isFalse);
  });

  test(
    'with no handler at all, the last known answer is used',
    () async {
      SharedPreferences.setMockInitialValues({'tvService.isTv': true});
      messenger.setMockMethodCallHandler(kChannel, null);
      await TvService.instance.initialize();
      expect(TvService.instance.isTv, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// التلاوة must never go dead because one load never came back.
///
/// On the owner's phone (2026-10-07) an await on the player that never
/// returned kept `playPage` inside its page lock for good: closing the bar did
/// not release it, and every later tap on التلاوة returned at once without a
/// word until the app was force-stopped. Here the platform player answers
/// `load` only when the test says so, which recreates that hang on demand.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Every `load` the app sends to a platform player, in order.
  final loads = <({String player, Completer<Map<String, dynamic>> reply})>[];
  final events = <String, MockStreamHandlerEventSink>{};
  final playRequests = <String>[];

  late Directory support;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('page_lock_test');
    // al-Hudaifi: file name == displayed ayah (SSSAAA.mp3), so every ayah of
    // the page can be "downloaded" up front and nothing touches the network.
    final cache = Directory('${support.path}/audio_cache_hudaifi')
      ..createSync(recursive: true);
    for (var ayah = 1; ayah <= 227; ayah++) {
      File('${cache.path}/026${ayah.toString().padLeft(3, '0')}.mp3')
          .writeAsBytesSync(const [0]);
    }
    SharedPreferences.setMockInitialValues({
      'selectedReciterId': 'hudaifi_qaloun',
    });

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );
    for (final name in const [
      'com.ryanheise.audio_session',
      'com.ryanheise.android_audio_manager',
      'com.ryanheise.av_audio_session',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async => call.method == 'setActive' ? true : null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (call) async {
        if (call.method == 'init') {
          final id = (call.arguments as Map)['id'] as String;
          messenger.setMockMethodCallHandler(
            MethodChannel('com.ryanheise.just_audio.methods.$id'),
            (c) async {
              if (c.method == 'load') {
                final reply = Completer<Map<String, dynamic>>();
                loads.add((player: id, reply: reply));
                return reply.future;
              }
              if (c.method == 'play') playRequests.add(id);
              return <String, dynamic>{};
            },
          );
          messenger.setMockStreamHandler(
            EventChannel('com.ryanheise.just_audio.events.$id'),
            MockStreamHandler.inline(onListen: (_, sink) => events[id] = sink),
          );
          messenger.setMockStreamHandler(
            EventChannel('com.ryanheise.just_audio.data.$id'),
            MockStreamHandler.inline(onListen: (_, _) {}),
          );
        }
        return <String, dynamic>{};
      },
    );
  });

  tearDownAll(() async {
    try {
      await support.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(done(), isTrue, reason: 'timed out waiting for $what');
  }

  /// Answers load [i] the way the real player does: the reply, then a
  /// "ready" playback event, which is what just_audio waits for.
  void finish(int i) {
    const duration = 10000000; // µs
    loads[i].reply.complete({'duration': duration});
    events[loads[i].player]?.success({
      'processingState': 3, // ready
      'updateTime': DateTime.now().millisecondsSinceEpoch,
      'updatePosition': 0,
      'bufferedPosition': duration,
      'duration': duration,
      'currentIndex': 0,
    });
  }

  test('closing the bar frees التلاوة while a load never returns', () async {
    final audio = AudioService.instance;

    // التلاوة on page 368: the bar opens, then the first ayah's load hangs.
    unawaited(audio.playPage(367, autoPlay: false));
    await until(() => loads.length == 1, 'the first load');
    expect(audio.isRecitationBarVisible.value, isTrue);

    // Nothing plays, so the listener closes the bar…
    audio.stop();
    expect(audio.isRecitationBarVisible.value, isFalse);

    // …and taps التلاوة again. It has to open — this is what went dead.
    var reopened = false;
    unawaited(
      audio.playPage(367, autoPlay: false).whenComplete(() => reopened = true),
    );
    await until(() => loads.length == 2, 'the second التلاوة to load');
    expect(audio.isRecitationBarVisible.value, isTrue);
    finish(1);
    await until(() => reopened, 'the second التلاوة to finish loading');
    expect(audio.currentAyah.value?.ayah, 19);

    // The abandoned load finally comes back — aborted, the way a load that
    // lost its connection reports. It belongs to a recitation that was
    // closed: the "load again" recovery for aborted loads must not fire for
    // it (that would replace the new recitation's source), and nothing may
    // start playing.
    loads[0].reply.completeError(
      PlatformException(code: 'abort', message: 'Connection aborted'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(loads.length, 2, reason: 'the abandoned load must not retry');
    expect(playRequests, isEmpty);
    expect(audio.isRecitationBarVisible.value, isTrue);
    expect(audio.currentAyah.value?.ayah, 19);

    // And التلاوة still works after all that.
    audio.stop();
    unawaited(audio.playPage(367, autoPlay: false));
    await until(() => loads.length == 3, 'a third التلاوة to load');
    expect(audio.isRecitationBarVisible.value, isTrue);
    finish(2);
    audio.stop();
  });
}

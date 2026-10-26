import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «تلاوة» from an ayah's options (owner, 2026-10-25): «آية فقط» recites the
/// ayah and waits on it instead of going on, and an ayah the reciter joins to
/// the one before starts at the head of that clip.
///
/// Same fake platform player as audio_service_page_lock_test.dart: every
/// `load` is recorded and answered when the test says so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final loads =
      <({String player, String args, Completer<Map<String, dynamic>> reply})>[];
  final events = <String, MockStreamHandlerEventSink>{};
  final playRequests = <String>[];

  late Directory support;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('ayah_play_test');
    // al-Hudaifi: file name == displayed ayah, and 26:211 is one of his 24
    // ayat recited inside the file before it.
    final cache = Directory('${support.path}/audio_cache_hudaifi')
      ..createSync(recursive: true);
    for (var ayah = 1; ayah <= 227; ayah++) {
      File(
        '${cache.path}/026${ayah.toString().padLeft(3, '0')}.mp3',
      ).writeAsBytesSync(const [0]);
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
                loads.add((
                  player: id,
                  args: jsonEncode(c.arguments),
                  reply: reply,
                ));
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

  const duration = 10000000; // µs

  void sendState(int i, int processingState) {
    events[loads[i].player]?.success({
      'processingState': processingState,
      'updateTime': DateTime.now().millisecondsSinceEpoch,
      'updatePosition': processingState == 4 ? duration : 0,
      'bufferedPosition': duration,
      'duration': duration,
      'currentIndex': 0,
    });
  }

  /// Answers load [i] as the real player does: the reply, then "ready".
  void finish(int i) {
    loads[i].reply.complete({'duration': duration});
    sendState(i, 3);
  }

  test('«آية فقط» recites the ayah once and waits on it', () async {
    final audio = AudioService.instance;
    await audio.init();
    final page = audio.pageIndexForAyah(26, 20);
    expect(page, greaterThanOrEqualTo(0));

    unawaited(
      audio.playFromAyah(26, 20, onlyThisAyah: true, readerPageIndex: page),
    );
    await until(() => loads.length == 1, 'the ayah to load');
    expect(loads[0].args, contains('026020.mp3'));
    expect(audio.isRecitationBarVisible.value, isTrue);
    finish(0);
    await until(() => playRequests.isNotEmpty, 'the ayah to start');
    final playsSoFar = playRequests.length;

    // The file ends: not on to 26:21, back to the start of 26:20, paused.
    sendState(0, 4);
    await until(() => loads.length == 2, 'the park on the same ayah');
    expect(loads[1].args, contains('026020.mp3'));
    expect(loads[1].args, isNot(contains('026021.mp3')));
    finish(1);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(audio.currentAyah.value?.ayah, 20);
    expect(audio.isRecitationBarVisible.value, isTrue);
    expect(playRequests.length, playsSoFar, reason: 'it must wait, not play');
    audio.stop();
  });

  test('«متابعة» goes on to the next ayah', () async {
    final audio = AudioService.instance;
    final page = audio.pageIndexForAyah(26, 20);
    final first = loads.length;

    unawaited(
      audio.playFromAyah(26, 20, onlyThisAyah: false, readerPageIndex: page),
    );
    await until(() => loads.length == first + 1, 'the ayah to load');
    finish(first);
    await until(() => playRequests.isNotEmpty, 'the ayah to start');
    sendState(first, 4);
    await until(() => loads.length == first + 2, 'the next ayah to load');
    expect(loads[first + 1].args, contains('026021.mp3'));
    finish(first + 1);
    audio.stop();
  });

  test(
    'an ayah joined to the one before starts at the head of its clip',
    () async {
      final audio = AudioService.instance;
      final page = audio.pageIndexForAyah(26, 211);
      final first = loads.length;

      unawaited(
        audio.playFromAyah(26, 211, onlyThisAyah: true, readerPageIndex: page),
      );
      await until(() => loads.length == first + 1, 'the clip to load');
      expect(loads[first].args, contains('026210.mp3'));
      finish(first);
      await until(() => audio.currentAyah.value != null, 'the ayah to show');
      expect(audio.currentAyah.value?.ayah, 210);
      audio.stop();
    },
  );
}

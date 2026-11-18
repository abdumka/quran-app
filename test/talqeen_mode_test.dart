import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/audio_service.dart';
import 'package:islamic_dawah_mushaf/services/talqeen_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «تلقين - استمع ثم ردّد» (owner, 2026-11-11): after each listen the player
/// plays as much silence as was heard (times the chosen factor), then goes on
/// as it would have without the turn.
///
/// Same fake platform player as ayah_play_from_menu_test.dart: every `load`
/// is recorded and answered when the test says so. Each fake file is 10 s.
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
    support = await Directory.systemTemp.createTemp('talqeen_test');
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

  setUp(() {
    TalqeenSetting.enabled.value = true;
    TalqeenSetting.factor.value = 1.0;
    AudioService.instance.repeatMode.value = AyahRepeatMode.off;
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

  void finish(int i) {
    loads[i].reply.complete({'duration': duration});
    sendState(i, 3);
  }

  bool isSilence(int i) => loads[i].args.contains(TalqeenSilence.fileName);

  /// Starts 26:20 and lets it play to its end; returns the index of the
  /// load that follows (the turn's silence, when تلقين is on).
  Future<int> listenTo2620() async {
    final audio = AudioService.instance;
    await audio.init();
    final page = audio.pageIndexForAyah(26, 20);
    final first = loads.length;
    unawaited(
      audio.playFromAyah(26, 20, onlyThisAyah: false, readerPageIndex: page),
    );
    await until(() => loads.length == first + 1, 'the ayah to load');
    expect(loads[first].args, contains('026020.mp3'));
    finish(first);
    await until(() => playRequests.isNotEmpty, 'the ayah to start');
    sendState(first, 4);
    await until(() => loads.length == first + 2, 'what follows the ayah');
    return first + 1;
  }

  test('the turn is as long as the ayah, then the next ayah plays', () async {
    final audio = AudioService.instance;
    final silence = await listenTo2620();
    expect(isSilence(silence), isTrue, reason: loads[silence].args);
    expect(loads[silence].args, contains('$duration'));
    expect(audio.talqeenTurn.value, isNotNull);
    expect(audio.isTalqeenTurn.value, isTrue);
    expect(audio.currentAyah.value?.ayah, 20, reason: 'the turn is on 26:20');

    finish(silence);
    sendState(silence, 4); // the turn ran out
    await until(() => loads.length == silence + 2, 'the next ayah');
    expect(loads[silence + 1].args, contains('026021.mp3'));
    expect(audio.talqeenTurn.value, isNull);
    finish(silence + 1);
    audio.stop();
  });

  test('off: no turn, straight on to the next ayah', () async {
    TalqeenSetting.enabled.value = false;
    final next = await listenTo2620();
    expect(isSilence(next), isFalse);
    expect(loads[next].args, contains('026021.mp3'));
    finish(next);
    AudioService.instance.stop();
  });

  test('×2 makes the turn twice as long', () async {
    TalqeenSetting.factor.value = 2.0;
    final silence = await listenTo2620();
    expect(isSilence(silence), isTrue);
    expect(loads[silence].args, contains('${duration * 2}'));
    finish(silence);
    AudioService.instance.stop();
  });

  test('0.75× makes the turn shorter than the reciter', () async {
    TalqeenSetting.factor.value = 0.75;
    final silence = await listenTo2620();
    expect(isSilence(silence), isTrue);
    expect(loads[silence].args, contains('${duration * 3 ~/ 4}'));
    expect(TalqeenSetting.factorLabel(0.75), '0.75×');
    finish(silence);
    AudioService.instance.stop();
  });

  test('⏭ during the turn ends it: the next ayah plays at once', () async {
    final audio = AudioService.instance;
    final silence = await listenTo2620();
    finish(silence);
    await Future<void>.delayed(const Duration(milliseconds: 350)); // debounce
    audio.nextAyah();
    await until(() => loads.length == silence + 2, 'the next ayah');
    expect(loads[silence + 1].args, contains('026021.mp3'));
    expect(audio.talqeenTurn.value, isNull);
    // The cancelled silence runs out while 26:21 is still loading: that is
    // not 26:21 finishing, so nothing may move on.
    sendState(silence, 4);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(loads.length, silence + 2);
    finish(silence + 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(audio.currentAyah.value?.ayah, 21);
    audio.stop();
  });

  test('⏮ during the turn plays the same ayah again', () async {
    final audio = AudioService.instance;
    final silence = await listenTo2620();
    finish(silence);
    await Future<void>.delayed(const Duration(milliseconds: 350)); // debounce
    audio.previousAyah();
    await until(() => loads.length == silence + 2, 'the ayah again');
    expect(loads[silence + 1].args, contains('026020.mp3'));
    finish(silence + 1);
    audio.stop();
  });

  test('ayah repeat 2×: a turn after each of the two listens', () async {
    final audio = AudioService.instance;
    audio.repeatMode.value = AyahRepeatMode.count;
    audio.repeatCount.value = 2;
    final silence1 = await listenTo2620();
    expect(isSilence(silence1), isTrue);
    finish(silence1);
    sendState(silence1, 4);
    await until(() => loads.length == silence1 + 2, 'the second listen');
    expect(loads[silence1 + 1].args, contains('026020.mp3'));
    finish(silence1 + 1);
    sendState(silence1 + 1, 4);
    await until(() => loads.length == silence1 + 3, 'the second turn');
    expect(isSilence(silence1 + 2), isTrue);
    finish(silence1 + 2);
    sendState(silence1 + 2, 4);
    await until(() => loads.length == silence1 + 4, 'the next ayah');
    expect(loads[silence1 + 3].args, contains('026021.mp3'));
    finish(silence1 + 3);
    audio.stop();
  });

  test('the silence file is a valid mono 16-bit WAV header', () {
    final h = TalqeenSilence.wavHeader(16000, sampleRate: 8000);
    final b = ByteData.sublistView(h);
    expect(String.fromCharCodes(h.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(h.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(h.sublist(36, 40)), 'data');
    expect(b.getUint32(4, Endian.little), 36 + 16000);
    expect(b.getUint16(22, Endian.little), 1); // mono
    expect(b.getUint32(24, Endian.little), 8000);
    expect(b.getUint16(34, Endian.little), 16);
    expect(b.getUint32(40, Endian.little), 16000);
  });
}

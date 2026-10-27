import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Under [AudioScheme.timedSurah] the player holds the whole surah, and when
/// the next ayah begins exactly where the one playing ends, the boundary must
/// not pause the player: the recitation runs on and only the highlight moves
/// (no gap between ayat). Anything that is not a plain advance (here: ayah
/// repeat) keeps the pause-first path.
///
/// Same harness as audio_service_page_turn_timed_test.dart, plus a record of
/// every call made to the player.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final events = <String, MockStreamHandlerEventSink>{};
  final calls = <String>[];
  String? player;
  const surahLength = Duration(hours: 3);

  late Directory support;

  // 2:211-218 of أبوسنينة: contiguous spans, 2:218 read inside 2:217.
  const spans = <int, List<int>?>{
    211: [5390710, 5459900],
    212: [5459900, 5505040],
    213: [5505040, 5534930],
    214: [5534930, 5565390],
    215: [5565390, 5644590],
    216: [5644590, 5665180],
    217: [5665180, 5733070],
    218: null,
    219: [5733070, 5790600],
    220: [5790600, 5827540],
    221: [5827540, 5855140],
    222: [5855140, 5874400],
    223: [5874400, 5893540],
    224: [5893540, 5912705],
  };

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('flow_through_test');
    final cache = Directory('${support.path}/audio_cache_abusenainah_timed');
    Directory('${cache.path}/timings').createSync(recursive: true);
    File('${cache.path}/002.mp3').writeAsBytesSync(const [0]);
    File('${cache.path}/timings/002.json').writeAsStringSync(
      jsonEncode({
        'surah': 2,
        'file': '002.mp3',
        'duration_ms': surahLength.inMilliseconds,
        'ayat': {for (final e in spans.entries) '${e.key}': e.value},
      }),
    );
    SharedPreferences.setMockInitialValues({
      'selectedReciterId': 'abusenainah_qaloun',
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
              calls.add(c.method);
              if (c.method == 'load') {
                player = id;
                scheduleMicrotask(() => _send(events[id], Duration.zero));
                return {'duration': surahLength.inMicroseconds};
              }
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

  final audio = AudioService.instance;

  setUp(() {
    audio.stop();
    calls.clear();
    audio.onPageChangeRequired = (_) {};
  });

  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(done(), isTrue, reason: 'timed out waiting for $what');
  }

  /// The player reports [ms], a position in the whole surah file.
  Future<void> reach(int ms) async {
    _send(events[player], Duration(milliseconds: ms));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> startAt(int surah, int ayah) async {
    await audio.init();
    final page = audio.pageIndexForAyah(surah, ayah);
    expect(page, isNonNegative);
    final index = audio
        .getAyahsForPage(page)
        .indexWhere((a) => a.surah == surah && a.ayah == ayah);
    expect(index, isNonNegative);
    // The next ayah must be on the same page: a page end is a different path.
    expect(audio.getAyahsForPage(page).length, greaterThan(index + 1));
    await audio.playPage(page, startFromAyahIndex: index);
    await until(() => calls.contains('load'), 'the surah to load');
  }

  test('a contiguous next ayah is reached without pausing the player',
      () async {
    await startAt(2, 212);
    await reach(5459900 + 1000); // inside 2:212
    calls.clear();

    await reach(5505040 + 30); // 2:212's span ends
    await until(() => audio.currentAyah.value?.ayah == 213, '2:213');
    expect(calls, isNot(contains('pause')),
        reason: 'the sound runs straight on into 2:213');
    expect(calls, isNot(contains('seek')),
        reason: 'the player is already at 2:213\'s start');
    expect(calls, isNot(contains('load')));
    expect(audio.isPlaying.value, isTrue);

    // And the watch was re-armed for 2:213 (its end is a page end, which
    // takes the ordinary path; what matters here is that it is noticed).
    await reach(5505040 + 5000);
    await reach(5534930 + 30);
    await until(() => audio.currentAyah.value?.ayah == 214, '2:214');
  });

  test('a seek from outside (the notification bar) re-syncs the highlight',
      () async {
    final turns = <int>[];
    audio.onPageChangeRequired = turns.add;
    await startAt(2, 212);
    await reach(5459900 + 1000); // inside 2:212
    calls.clear();

    // Dragged forward into 2:215 (on the next page, p34): the highlight and
    // the page follow, the position stays.
    await reach(5565390 + 20000);
    await until(() => audio.currentAyah.value?.ayah == 215, '2:215');
    expect(calls, isNot(contains('seek')), reason: 'keeps the dragged position');
    expect(audio.isPlaying.value, isTrue);
    expect(turns, [33]);
    // ...and its own end is now the one being watched.
    await reach(5644590 + 30);
    await until(() => audio.currentAyah.value?.ayah == 216, '2:216');

    // Dragged back into 2:213, on p33 again.
    calls.clear();
    await reach(5505040 + 10000);
    await until(() => audio.currentAyah.value?.ayah == 213, '2:213');
    expect(calls, isNot(contains('seek')));
    expect(turns, [33, 32]);

    // Dragged two pages on (2:219 opens p35).
    await reach(5733070 + 20000);
    await until(() => audio.currentAyah.value?.ayah == 219, '2:219');
    expect(turns, [33, 32, 34]);
  });

  test('with ayah repeat on, the boundary still pauses and seeks back',
      () async {
    await startAt(2, 212);
    audio.cycleAyahRepeatMode(); // 2×, restarts 2:212
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await reach(5459900 + 1000);
    calls.clear();

    await reach(5505040 + 30);
    await until(() => calls.contains('seek'), 'the seek back to 2:212');
    expect(calls.indexOf('pause'), lessThan(calls.indexOf('seek')),
        reason: 'silence first, then jump back');
    expect(audio.currentAyah.value?.ayah, 212);
  });
}

void _send(MockStreamHandlerEventSink? sink, Duration position) {
  sink?.success({
    'processingState': 3, // ready
    'updateTime': DateTime.now().millisecondsSinceEpoch,
    'updatePosition': position.inMicroseconds,
    'bufferedPosition': const Duration(hours: 3).inMicroseconds,
    'duration': const Duration(hours: 3).inMicroseconds,
    'currentIndex': 0,
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/page_turn_cues.dart';
import 'package:islamic_dawah_mushaf/services/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The page turns inside an ayah printed across a page break — when the
/// sheikh finishes the last word on the earlier page, not when the ayah starts
/// or ends (lib/page_turn_cues.dart).
///
/// al-Hudaifi has both kinds: 4:44 (p85→86) is a clip of its own, so the turn
/// to p86 is held back inside it; 2:218 (p34→35) he reads inside 2:217's
/// breath, so the page turns mid-way through 2:217's clip, before the
/// recitation itself reaches p35. The platform player is faked: positions and
/// file ends are sent to the app as the real player's events.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final events = <String, MockStreamHandlerEventSink>{};
  final loaded = <String>[]; // file names, in load order
  String? player;
  const fileLength = Duration(seconds: 70);

  late Directory support;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('page_turn_test');
    final cache = Directory('${support.path}/audio_cache_hudaifi')
      ..createSync(recursive: true);
    for (final (surah, count) in const [(2, 286), (4, 176)]) {
      for (var ayah = 1; ayah <= count; ayah++) {
        File(
          '${cache.path}/${surah.toString().padLeft(3, '0')}'
          '${ayah.toString().padLeft(3, '0')}.mp3',
        ).writeAsBytesSync(const [0]);
      }
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
                player = id;
                // just_audio wraps the source in a playlist.
                var source = (c.arguments as Map)['audioSource'] as Map;
                while (source['uri'] == null) {
                  source = (source['children'] ?? [source['child']])[0] as Map;
                }
                loaded.add(Uri.parse(source['uri'] as String).pathSegments.last);
                scheduleMicrotask(() => _send(events[id], Duration.zero));
                return {'duration': fileLength.inMicroseconds};
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
  final turns = <int>[];

  setUp(() {
    audio.stop();
    turns.clear();
    loaded.clear();
    audio.onPageChangeRequired = turns.add;
  });

  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(done(), isTrue, reason: 'timed out waiting for $what');
  }

  /// The player reports [position] in the file now loaded.
  Future<void> reach(Duration position) async {
    _send(events[player], position);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  /// The file now loaded plays to its end.
  Future<void> finishFile() async {
    final before = loaded.length;
    _send(events[player], fileLength, completed: true);
    await until(() => loaded.length > before, 'the next file to load');
  }

  Future<void> startAt(int page, int surah, int ayah) async {
    await audio.init();
    final index = audio
        .getAyahsForPage(page - 1)
        .indexWhere((a) => a.surah == surah && a.ayah == ayah);
    expect(index, isNonNegative);
    await audio.playPage(page - 1, startFromAyahIndex: index);
    await until(() => loaded.isNotEmpty, 'the first file');
  }

  final p86 = pageTurnCues['hudaifi_qaloun']![86]!; // 004044.mp3
  final p35 = pageTurnCues['hudaifi_qaloun']![35]!; // inside 002217.mp3
  const early = Duration(seconds: 2);
  const late = Duration(milliseconds: 300);

  test('the turn to p86 waits inside 4:44 for «السبيل»', () async {
    await startAt(85, 4, 43);
    expect(loaded.last, '004043.mp3');
    await finishFile();

    // The recitation is on p86's first ayah, the reader still on p85.
    expect(loaded.last, '004044.mp3');
    expect(audio.currentAyah.value?.ayah, 44);
    expect(turns, isEmpty);
    expect(audio.isAudioOnPage(84), isTrue, reason: 'play button on p85');

    await reach(Duration(milliseconds: p86.atMs) - early);
    expect(turns, isEmpty);
    await reach(Duration(milliseconds: p86.atMs) + late);
    expect(turns, [85]);
    expect(audio.isAudioOnPage(84), isFalse);

    await finishFile(); // on to 4:45: no second turn
    expect(turns, [85]);
  });

  test('started on p86 itself, 4:44 never sends the reader back', () async {
    await startAt(86, 4, 44);
    await reach(Duration(milliseconds: p86.atMs) - early);
    await reach(Duration(milliseconds: p86.atMs) + late);
    await finishFile();
    expect(turns, isEmpty);
  });

  test('2:218, read inside 2:217, turns the page mid-way through 2:217', () async {
    expect(p35.ayah, 217);
    await startAt(34, 2, 217);
    expect(loaded.last, '002217.mp3');

    await reach(Duration(milliseconds: p35.atMs) - early);
    expect(turns, isEmpty);
    await reach(Duration(milliseconds: p35.atMs) + late);
    expect(turns, [34], reason: 'turned at «والآخرة», still inside 2:217');
    expect(audio.currentAyah.value?.ayah, 217);
    expect(audio.isAudioOnPage(34), isTrue, reason: 'play button on p35');

    // The clip ends; 2:218 has no audio of its own, so p35 plays 2:219 — and
    // the page is not turned a second time.
    await finishFile();
    expect(loaded.last, '002219.mp3');
    expect(turns, [34]);
  });

  test('repeating 2:217 keeps the reader on p34 until the last pass', () async {
    audio.repeatMode.value = AyahRepeatMode.count;
    audio.repeatCount.value = 2;
    addTearDown(() => audio.repeatMode.value = AyahRepeatMode.off);
    await startAt(34, 2, 217);

    await reach(Duration(milliseconds: p35.atMs) - early);
    await reach(Duration(milliseconds: p35.atMs) + late);
    expect(turns, isEmpty, reason: 'first of two passes');

    await finishFile(); // the second pass of 2:217
    expect(loaded.last, '002217.mp3');
    await reach(Duration(milliseconds: p35.atMs) - early);
    await reach(Duration(milliseconds: p35.atMs) + late);
    expect(turns, [34]);
  });

  test('repeating p34 never turns to p35', () async {
    audio.pageRepeatMode.value = AyahRepeatMode.infinite;
    addTearDown(() => audio.pageRepeatMode.value = AyahRepeatMode.off);
    await startAt(34, 2, 217);
    await reach(Duration(milliseconds: p35.atMs) - early);
    await reach(Duration(milliseconds: p35.atMs) + late);
    await finishFile(); // back to p34's first ayah
    expect(turns, isEmpty);
    expect(loaded.last, isNot('002219.mp3'));
  });
}

void _send(
  MockStreamHandlerEventSink? sink,
  Duration position, {
  bool completed = false,
}) {
  sink?.success({
    'processingState': completed ? 4 : 3, // completed : ready
    'updateTime': DateTime.now().millisecondsSinceEpoch,
    'updatePosition': position.inMicroseconds,
    'bufferedPosition': const Duration(seconds: 70).inMicroseconds,
    'duration': const Duration(seconds: 70).inMicroseconds,
    'currentIndex': 0,
  });
}

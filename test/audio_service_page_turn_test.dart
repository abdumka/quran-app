import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/page_turn_cues.dart';
import 'package:islamic_dawah_mushaf/services/audio_service.dart';
import 'package:islamic_dawah_mushaf/services/talqeen_setting.dart';
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

  // Owner, 2026-11-11: an ayah repeat follows the sheikh across the break on
  // every pass, and goes back to where the ayah begins for the next one.
  test('repeating 2:217 turns to p35 on every pass, back to p34 between', () async {
    audio.repeatMode.value = AyahRepeatMode.count;
    audio.repeatCount.value = 2;
    addTearDown(() => audio.repeatMode.value = AyahRepeatMode.off);
    await startAt(34, 2, 217);

    await reach(Duration(milliseconds: p35.atMs) - early);
    await reach(Duration(milliseconds: p35.atMs) + late);
    expect(turns, [34], reason: 'first of two passes reaches «والآخرة»');

    await finishFile(); // the second pass of 2:217
    expect(loaded.last, '002217.mp3');
    expect(turns, [34, 33], reason: 'back to p34 for the second pass');
    await reach(Duration(milliseconds: p35.atMs) - early);
    await reach(Duration(milliseconds: p35.atMs) + late);
    expect(turns, [34, 33, 34]);

    await finishFile(); // on to 2:219, already on p35
    expect(loaded.last, '002219.mp3');
    expect(turns, [34, 33, 34]);
  });

  test('repeating 4:44 goes back to p85 and turns again at «السبيل»', () async {
    addTearDown(() => audio.repeatMode.value = AyahRepeatMode.off);
    await startAt(85, 4, 43);
    await finishFile(); // into 4:44, the turn held
    // Repeat 4:44 only (switched on from the start it would repeat 4:43).
    audio.repeatCount.value = 2;
    audio.repeatMode.value = AyahRepeatMode.count;
    await reach(Duration(milliseconds: p86.atMs) - early);
    await reach(Duration(milliseconds: p86.atMs) + late);
    expect(turns, [85]);

    await finishFile(); // the second pass of 4:44
    expect(loaded.last, '004044.mp3');
    expect(turns, [85, 84]);
    expect(audio.isAudioOnPage(84), isTrue, reason: 'play button on p85');
    await reach(Duration(milliseconds: p86.atMs) - early);
    expect(turns, [85, 84]);
    await reach(Duration(milliseconds: p86.atMs) + late);
    expect(turns, [85, 84, 85]);
  });

  test('repeating 4:44 started on p86 itself still never sends it back', () async {
    audio.repeatMode.value = AyahRepeatMode.count;
    audio.repeatCount.value = 2;
    addTearDown(() => audio.repeatMode.value = AyahRepeatMode.off);
    await startAt(86, 4, 44);
    await reach(Duration(milliseconds: p86.atMs) + late);
    await finishFile(); // the second pass
    await reach(Duration(milliseconds: p86.atMs) - early);
    await reach(Duration(milliseconds: p86.atMs) + late);
    expect(turns, isEmpty);
  });

  group('تلقين', () {
    setUp(() {
      TalqeenSetting.enabled.value = true;
      TalqeenSetting.factor.value = 1.0;
    });
    tearDown(() => TalqeenSetting.enabled.value = false);

    // The turn is as long as the 70 s file; the page turns at the same share.
    test('the turn after 4:44 starts on p85 and turns at the same moment', () async {
      await startAt(85, 4, 43);
      await finishFile(); // the turn after 4:43
      expect(loaded.last, TalqeenSilence.fileName);
      expect(turns, isEmpty, reason: '4:43 crosses no break');
      await finishFile(); // into 4:44
      await reach(Duration(milliseconds: p86.atMs) + late);
      expect(turns, [85]);

      await finishFile(); // 4:44 done: the turn
      expect(loaded.last, TalqeenSilence.fileName);
      expect(turns, [85, 84], reason: 'back to where 4:44 begins');
      expect(audio.isAudioOnPage(84), isTrue);
      await reach(Duration(milliseconds: p86.atMs) - early);
      expect(turns, [85, 84]);
      await reach(Duration(milliseconds: p86.atMs) + late);
      expect(turns, [85, 84, 85], reason: 'turned at the same share');

      await finishFile(); // the turn ends: 4:45, on p86
      expect(loaded.last, '004045.mp3');
      expect(turns, [85, 84, 85]);
    });

    test('⏭ before the turn reached the break: straight to p86', () async {
      await startAt(86, 4, 44);
      // Started on p86 itself: the reader never saw p85, nor does the turn.
      await reach(Duration(milliseconds: p86.atMs) + late);
      await finishFile();
      expect(loaded.last, TalqeenSilence.fileName);
      expect(turns, isEmpty);
      audio.stop();

      turns.clear();
      await startAt(85, 4, 43);
      await finishFile(); // the turn after 4:43
      await finishFile(); // into 4:44
      await reach(Duration(milliseconds: p86.atMs) + late);
      await finishFile(); // the turn
      expect(turns, [85, 84]);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final before = loaded.length;
      audio.nextAyah();
      await until(() => loaded.length > before, '4:45');
      expect(loaded.last, '004045.mp3');
      expect(turns, [85, 84, 85]);
    });

    test('the turn after 2:217 (2:218 inside it) starts on p34', () async {
      await startAt(34, 2, 217);
      await reach(Duration(milliseconds: p35.atMs) + late);
      expect(turns, [34]);
      await finishFile(); // the turn
      expect(loaded.last, TalqeenSilence.fileName);
      expect(turns, [34, 33]);
      expect(audio.isAudioOnPage(33), isTrue);
      await reach(Duration(milliseconds: p35.atMs) + late);
      expect(turns, [34, 33, 34]);
      await finishFile(); // 2:219, on p35
      expect(loaded.last, '002219.mp3');
      expect(turns, [34, 33, 34]);
    });

    test('a page repeat that stays on p34 has a turn that stays too', () async {
      audio.pageRepeatMode.value = AyahRepeatMode.infinite;
      addTearDown(() => audio.pageRepeatMode.value = AyahRepeatMode.off);
      await startAt(34, 2, 217);
      await reach(Duration(milliseconds: p35.atMs) + late);
      await finishFile(); // the turn
      expect(loaded.last, TalqeenSilence.fileName);
      await reach(Duration(milliseconds: p35.atMs) + late);
      await finishFile(); // back to p34's first ayah
      expect(turns, isEmpty);
    });
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

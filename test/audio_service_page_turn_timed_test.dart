import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/page_turn_cues.dart';
import 'package:islamic_dawah_mushaf/services/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The same page turns as audio_service_page_turn_test.dart, for a reciter on
/// [AudioScheme.timedSurah]: the player holds the whole surah, so every
/// position is a position in the surah file — never an offset into the ayah.
/// (The turn used to be taken as a share of the player's duration, i.e. of
/// the whole surah, which put it at the ayah's start or after its end.)
///
/// أبوسنينة reads 2:218 inside 2:217's breath (its span is null) and 4:44 as a
/// span of its own. The spans below are his real ones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final events = <String, MockStreamHandlerEventSink>{};
  final loaded = <String>[];
  String? player;
  const surahLength = Duration(hours: 3);

  late Directory support;

  setUpAll(() async {
    support = await Directory.systemTemp.createTemp('page_turn_timed_test');
    final cache = Directory('${support.path}/audio_cache_abusenainah_timed');
    Directory('${cache.path}/timings').createSync(recursive: true);
    void surah(int number, Map<int, List<int>?> spans) {
      final name = number.toString().padLeft(3, '0');
      File('${cache.path}/$name.mp3').writeAsBytesSync(const [0]);
      File('${cache.path}/timings/$name.json').writeAsStringSync(
        jsonEncode({
          'surah': number,
          'file': '$name.mp3',
          'duration_ms': surahLength.inMilliseconds,
          'ayat': {for (final e in spans.entries) '${e.key}': e.value},
        }),
      );
    }

    surah(2, {
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
    });
    surah(4, {
      38: [1236960, 1262630],
      39: [1262630, 1279540],
      40: [1279540, 1295350],
      41: [1295350, 1311570],
      42: [1311570, 1326720],
      43: [1326720, 1408980],
      44: [1408980, 1437500],
      45: [1437500, 1488150],
      46: [1488150, 1527100],
      47: [1527100, 1548120],
      48: [1548120, 1563410],
      49: [1563410, 1574320],
      50: [1574320, 1601420],
      51: [1601420, 1616000],
    });
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
              if (c.method == 'load') {
                player = id;
                var source = (c.arguments as Map)['audioSource'] as Map;
                while (source['uri'] == null) {
                  source = (source['children'] ?? [source['child']])[0] as Map;
                }
                loaded.add(Uri.parse(source['uri'] as String).pathSegments.last);
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

  /// The player reports [ms] — a position in the whole surah file.
  Future<void> reach(int ms) async {
    _send(events[player], Duration(milliseconds: ms));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> startAt(int page, int surah, int ayah) async {
    await audio.init();
    final index = audio
        .getAyahsForPage(page - 1)
        .indexWhere((a) => a.surah == surah && a.ayah == ayah);
    expect(index, isNonNegative);
    await audio.playPage(page - 1, startFromAyahIndex: index);
    await until(() => loaded.isNotEmpty, 'the surah to load');
  }

  final p86 = pageTurnCues['abusenainah_qaloun']![86]!;
  final p35 = pageTurnCues['abusenainah_qaloun']![35]!;

  test('the turn to p86 waits inside 4:44\'s span for «السبيل»', () async {
    await startAt(85, 4, 43);
    expect(loaded.single, '004.mp3');
    await reach(1326720 + 1000); // inside 4:43
    await reach(1408980 + 30); // 4:43's span ends: on to p86's 4:44
    await until(() => audio.currentAyah.value?.ayah == 44, '4:44');
    expect(turns, isEmpty, reason: 'the reader stays on p85 for now');

    await reach(p86.atMs - 2000);
    expect(turns, isEmpty);
    await reach(p86.atMs + 300);
    expect(turns, [85]);
    expect(loaded.single, '004.mp3', reason: 'seeks within the surah');
  });

  test('2:218 (no span: read inside 2:217) turns p34 mid-way', () async {
    expect(p35.ayah, 217);
    await startAt(34, 2, 217);
    await reach(5665180 + 1000);
    await reach(p35.atMs - 2000);
    expect(turns, isEmpty);
    await reach(p35.atMs + 300);
    expect(turns, [34]);
    expect(audio.currentAyah.value?.ayah, 217);

    await reach(5733070 + 30); // 2:217's span ends; 2:219 opens p35
    await until(() => audio.currentAyah.value?.ayah == 219, '2:219');
    expect(turns, [34], reason: 'no second turn');
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

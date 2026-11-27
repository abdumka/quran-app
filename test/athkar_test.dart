import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:islamic_dawah_mushaf/models/athkar.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/services/athkar_audio.dart';
import 'package:islamic_dawah_mushaf/services/athkar_download_service.dart';
import 'package:islamic_dawah_mushaf/services/athkar_reminder_service.dart';
import 'package:islamic_dawah_mushaf/services/athkar_service.dart';
import 'package:islamic_dawah_mushaf/services/content_update_service.dart';
import 'package:islamic_dawah_mushaf/widgets/athkar/athkar_home_page.dart';
import 'package:islamic_dawah_mushaf/widgets/athkar/athkar_reader_page.dart';
import 'package:islamic_dawah_mushaf/widgets/athkar/athkar_widgets.dart';
import 'package:islamic_dawah_mushaf/widgets/settings/downloads_management_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Finishes each recording when the test says so.
class _FakePlayer implements AthkarPlayer {
  final List<String> played = [];
  final List<AthkarSource> sources = [];
  Completer<bool>? _current;

  /// The next plays that fail (no network).
  int failTimes = 0;
  int tries = 0;
  double speed = 1;

  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;

  @override
  Future<bool> play(List<AthkarSource> sources) {
    tries++;
    if (failTimes > 0) {
      failTimes--;
      return Future.error(StateError('no network'));
    }
    played.add(sources.map((s) => s.uri.toString()).join('+'));
    this.sources.addAll(sources);
    return (_current = Completer<bool>()).future;
  }

  /// The recording reached its end.
  Future<void> finish() async {
    _current?.complete(true);
    _current = null;
    await pumpEventQueue();
  }

  /// [finish] for widget tests (their clock does not run the event queue).
  void end() {
    _current?.complete(true);
    _current = null;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    final c = _current;
    _current = null;
    if (c != null && !c.isCompleted) c.complete(false);
  }
}

/// [_FakePlayer], but stopping takes until [hold] completes (a player
/// letting go of a recording still streaming in).
class _SlowStopPlayer implements AthkarPlayer {
  _SlowStopPlayer(this.inner);
  final _FakePlayer inner;
  Completer<void>? hold;

  @override
  Future<bool> play(List<AthkarSource> sources) => inner.play(sources);
  @override
  Future<void> pause() => inner.pause();
  @override
  Future<void> resume() => inner.resume();
  @override
  Future<void> stop() async {
    await inner.stop();
    await hold?.future;
  }

  @override
  Future<void> setSpeed(double speed) => inner.setSpeed(speed);
}

AthkarData _sample({bool withReciter = false}) =>
    AthkarData.parse(_sampleJson(withReciter: withReciter));

String _sampleJson({bool withReciter = false}) => json.encode({
  'ver': 1,
  'featured': [
    {'section': 10, 'label': 'أذكار الصباح', 'icon': 'sun'},
  ],
  'groups': [
    {
      'id': 'g',
      'name': 'اليوم والليلة',
      'sections': [10, 11],
    },
  ],
  'sections': [
    {
      'id': 10,
      'name': 'أذكار الصباح',
      'items': [
        {'id': 1, 't': 'الذكر الأول', 'n': 1, 's': 'رواه مسلم', 'a': 75},
        {'id': 2, 't': 'الذكر الثاني', 'n': 3, 's': 'رواه الترمذي', 'a': 76},
        {'id': 3, 't': 'الذكر الثالث', 'n': 1, 'a': 77},
      ],
    },
    {
      'id': 11,
      'name': 'أذكار النوم',
      'items': [
        {'id': 4, 't': 'باسمك اللهم أموت وأحيا', 'n': 1},
        {
          'id': 5,
          't': '﴿قُلْ هُوَ اَ۬للَّهُ أَحَدٌ﴾',
          'n': 3,
          'q': [
            [112, 1, 4],
          ],
        },
      ],
    },
  ],
  'reciters': [
    if (withReciter)
      {
        'id': 'one',
        'name': 'القارئ الأول',
        'url': 'https://example.com/one/{a}.mp3',
        'files': {'3': 'special.mp3'},
        'spans': {
          '2': [6.0, 9.5],
        },
      },
    if (withReciter)
      {
        'id': 'two',
        'name': 'القارئ الثاني',
        'url': 'https://example.com/two/{id}.mp3',
        'items': [4],
      },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = AthkarStore.instance;
  final audio = AthkarAudio.instance;

  setUp(() async {
    // the reminders' first-opening sheet has its own test
    SharedPreferences.setMockInitialValues({'athkarReminderIntroShown': true});
    AthkarReminderService.instance.debugReset();
    store.debugReset();
    await store.load();
    AthkarService.instance.debugSetData(_sample());
    audio.stopOtherAudio = () {};
    audio.cacheClips = false;
  });

  group('the bundled athkar', () {
    final text = File('assets/data/athkar.json').readAsStringSync();
    final data = AthkarData.parse(text);

    test('every section is in exactly one group, the tiles resolve', () {
      expect(data.sections.length, greaterThan(120));
      final grouped = [
        for (final g in data.groups)
          for (final s in g.sections) s.id,
      ];
      expect(grouped.toSet().length, grouped.length);
      expect(grouped.length, data.sections.length);
      expect(data.groups.any((g) => g.id == 'other'), isFalse);
      expect(data.featured.map((f) => f.label), [
        'أذكار الصباح',
        'أذكار المساء',
        'بعد الصلاة',
        'أذكار النوم',
        'الاستيقاظ',
      ]);
      for (final s in data.sections) {
        expect(s.items, isNotEmpty, reason: s.name);
      }
    });

    test('Western digits only, no em dash, the book is not named', () {
      expect(RegExp('[٠-٩۰-۹]').hasMatch(text), isFalse);
      expect(text.contains('—'), isFalse);
      expect(text.contains('حصن المسلم'), isFalse);
      expect(text.contains('QuranText'), isFalse);
    });

    test('its version matches the bundled version of the server item', () {
      expect(data.version, ContentUpdateService.bundledVersions['athkar']);
      expect(ContentUpdateService.items, contains('athkar'));
    });

    test('verses are in the app\'s Qalun text, ready for display', () {
      // 93 = آية الكرسي in أذكار الصباح
      final kursi = data.item(93)!;
      expect(kursi.text, startsWith('﴿'));
      // «وَهْوَ» is Qalun's reading; the open tanween is display-ready
      expect(kursi.text, contains('وَهْوَ'));
      expect(RegExp('[ٖٗٞے]').hasMatch(kursi.text), isFalse);
    });

    test('a broken file is refused', () {
      expect(() => AthkarData.parse('{"sections":[]}'), throwsFormatException);
      expect(
        () => ContentUpdateService.validate('athkar', '{"groups":[]}'),
        throwsFormatException,
      );
    });
  });

  group('counters and favourites', () {
    test('counts up to the dhikr\'s number and stops there', () {
      final item = _sample().item(2)!;
      expect(store.increment(item), isFalse);
      expect(store.increment(item), isFalse);
      expect(store.increment(item), isTrue);
      expect(store.increment(item), isFalse);
      expect(store.countOf(item), 3);
      expect(store.isDone(item), isTrue);
      store.reset(item);
      expect(store.countOf(item), 0);
    });

    test('a new day starts the counters again, favourites stay', () async {
      final item = _sample().item(1)!;
      store.now = () => DateTime(2026, 11, 17, 23, 50);
      store.increment(item);
      store.toggleFavourite(item);
      expect(store.isDone(item), isTrue);
      store.now = () => DateTime(2026, 11, 18, 0, 5);
      expect(store.isDone(item), isFalse);
      expect(store.isFavourite(item), isTrue);
    });

    test('counters, favourites and the view survive a restart', () async {
      final data = _sample();
      store.increment(data.item(2)!);
      store.toggleFavourite(data.item(4)!);
      store.toggleFavourite(data.item(1)!);
      store.view = AthkarView.single;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      store.debugReset();
      await store.load();
      expect(store.countOf(data.item(2)!), 1);
      expect(store.favourites, [1, 4]);
      expect(store.view, AthkarView.single);
    });

    test('the share line comes from the data (the server can change it)', () {
      final data = AthkarData.parse(
        json.encode({
          ...json.decode(_sampleJson()) as Map,
          'shareLine': 'سطر من الخادم',
        }),
      );
      expect(data.shareLine, 'سطر من الخادم');
      expect(
        athkarShareText(data.item(1)!, shareLine: data.shareLine),
        endsWith('سطر من الخادم'),
      );
      // older data without it keeps the app's line
      expect(_sample().shareLine, AthkarData.defaultShareLine);
      final bundled = AthkarData.parse(
        File('assets/data/athkar.json').readAsStringSync(),
      );
      expect(bundled.shareLine, 'من تطبيق المصحف الجامع');
    });

    test('share text: the dhikr, its count, its source, the app line', () {
      expect(
        athkarShareText(_sample().item(2)!),
        'الذكر الثاني\n(3 مرات)\nرواه الترمذي\n\nمن تطبيق المصحف الجامع',
      );
      expect(
        athkarShareText(_sample().item(4)!),
        'باسمك اللهم أموت وأحيا\n\nمن تطبيق المصحف الجامع',
      );
    });
  });

  group('listening', () {
    late _FakePlayer player;

    setUp(() {
      AthkarService.instance.debugSetData(_sample(withReciter: true));
      player = _FakePlayer();
      audio.player = player;
      audio.retryWaits = const [Duration.zero];
      audio.retryFor = const Duration(seconds: 60);
    });

    tearDown(() => audio.stop());

    test('a dhikr plays only its span: timings come from the data', () async {
      final data = AthkarService.instance.data;
      unawaited(audio.start([data.item(2)!, data.item(1)!], 0));
      await pumpEventQueue();
      expect(player.sources.single.start, const Duration(seconds: 6));
      expect(player.sources.single.end, const Duration(milliseconds: 9500));
      await audio.stop();
      // no span: the whole file
      unawaited(audio.start([data.item(1)!], 0));
      await pumpEventQueue();
      expect(player.sources.last.start, isNull);
    });

    test('«التالي» leaves a dhikr half counted and plays the next', () async {
      final data = AthkarService.instance.data;
      final items = data.section(10)!.items;
      unawaited(audio.start(items, 1)); // dhikr 2, said 3 times
      await pumpEventQueue();
      await player.finish(); // heard once
      expect(store.countOf(items[1]), 1);
      await audio.skip();
      await pumpEventQueue();
      expect(audio.current!.id, 3);
      expect(store.countOf(items[1]), 1);
      expect(store.isDone(items[1]), isFalse);
      await player.finish();
      expect(store.isDone(items[2]), isTrue);
    });

    test('a voice that lacks a dhikr is not used for it', () {
      final data = AthkarService.instance.data;
      store.chooseReciter(data.reciters[1]);
      // «two» has only dhikr 4: the others fall back to «one»
      expect(audio.voiceFor(data.item(4)!)!.id, 'two');
      expect(audio.voiceFor(data.item(1)!)!.id, 'one');
    });

    test(
      'recited Qur\'an plays from the Qur\'an reciter, النهي by default',
      () async {
        final data = AthkarService.instance.data;
        expect(data.item(5)!.isQuran, isTrue);
        expect(audio.quranReciter.id, 'naihi_qaloun');
        final asked = <String>[];
        final before = audio.quranSources;
        audio.quranSources = (r, item) async {
          asked.add('${r.id}:${item.verses.single.surah}');
          return [AthkarSource(Uri.parse('https://q.example/112.mp3'))];
        };
        addTearDown(() => audio.quranSources = before);
        unawaited(audio.start([data.item(5)!], 0));
        await pumpEventQueue();
        expect(asked, ['naihi_qaloun:112']);
        expect(audio.voiceNameFor(data.item(5)!), audio.quranReciter.name);
        await player.finish();
        await player.finish();
        await player.finish();
        expect(store.isDone(data.item(5)!), isTrue);
        expect(player.played, List.filled(3, 'https://q.example/112.mp3'));
      },
    );

    test('a voice\'s addresses', () {
      final data = AthkarService.instance.data;
      final r = data.reciters.first;
      expect(r.urlFor(data.item(1)!), 'https://example.com/one/0075.mp3');
      expect(r.urlFor(data.item(3)!), 'https://example.com/one/special.mp3');
      expect(r.urlFor(data.item(4)!), isNull);
      expect(audio.canPlay(data.item(4)!), isTrue); // «two» has it
    });

    test('no voice in the data: nothing to listen to', () {
      AthkarService.instance.debugSetData(_sample());
      expect(audio.hasReciters, isFalse);
      expect(audio.canPlay(_sample().item(1)!), isFalse);
    });

    test(
      'a dhikr said 3 times plays 3 times, counting, then goes on',
      () async {
        final data = AthkarService.instance.data;
        final items = data.section(10)!.items;
        unawaited(audio.start(items, 1));
        await pumpEventQueue();
        expect(audio.current!.id, 2);
        await player.finish();
        expect(store.countOf(items[1]), 1);
        await player.finish();
        await player.finish();
        expect(store.isDone(items[1]), isTrue);
        expect(audio.current!.id, 3);
        await player.finish();
        expect(audio.isActive, isFalse);
        expect(player.played, [
          'https://example.com/one/0076.mp3',
          'https://example.com/one/0076.mp3',
          'https://example.com/one/0076.mp3',
          'https://example.com/one/special.mp3',
        ]);
      },
    );

    test(
      '«تشغيل متواصل» off: the dhikr plays all its times, then stops',
      () async {
        final items = AthkarService.instance.data.section(10)!.items;
        store.continuous = false;
        unawaited(audio.start(items, 1)); // dhikr 2, said 3 times
        await pumpEventQueue();
        expect(audio.repeat, (1, 3));
        expect(audio.hasNext, isFalse);
        await player.finish();
        expect(audio.repeat, (2, 3));
        await player.finish();
        await player.finish();
        expect(store.isDone(items[1]), isTrue);
        expect(audio.isActive, isFalse);
        expect(player.played.length, 3);
      },
    );

    test(
      'turning it off while listening stops after the current dhikr',
      () async {
        final items = AthkarService.instance.data.section(10)!.items;
        unawaited(audio.start(items, 0));
        await pumpEventQueue();
        expect(audio.hasNext, isTrue);
        store.continuous = false;
        await player.finish();
        expect(audio.isActive, isFalse);
        expect(player.played.length, 1);
      },
    );

    test('x times: a completed dhikr is heard x times again; a half one '
        'plays the times left', () async {
      final items = AthkarService.instance.data.section(10)!.items;
      store.continuous = false;
      for (var k = 0; k < 3; k++) {
        store.increment(items[1]);
      }
      unawaited(audio.start(items, 1));
      await pumpEventQueue();
      for (var k = 0; k < 3; k++) {
        await player.finish();
      }
      expect(player.played.length, 3);
      expect(audio.isActive, isFalse);

      store.reset(items[1]);
      store.increment(items[1]); // said once by hand
      unawaited(audio.start(items, 1));
      await pumpEventQueue();
      expect(audio.repeat, (2, 3));
      await player.finish();
      await player.finish();
      expect(store.isDone(items[1]), isTrue);
      expect(audio.isActive, isFalse);
      expect(player.played.length, 5);
    });

    test(
      'the listening is shown on the media session, then handed back',
      () async {
        final seen = <String>[];
        final before = audio.session;
        audio.session = (a) => seen.add(
          a.current == null
              ? 'end'
              : '${a.current!.id} ${a.isPaused ? 'paused' : 'playing'}',
        );
        addTearDown(() => audio.session = before);
        final items = AthkarService.instance.data.section(10)!.items;
        unawaited(audio.start(items, 0));
        await pumpEventQueue();
        expect(seen.last, '1 playing');
        await audio.togglePause();
        expect(seen.last, '1 paused');
        await audio.togglePause();
        await audio.stop();
        expect(seen.last, 'end');
      },
    );

    test('the hidden speed reaches the player', () async {
      final items = AthkarService.instance.data.section(10)!.items;
      store.speed = 3;
      unawaited(audio.start(items, 0));
      await pumpEventQueue();
      expect(player.speed, 3);
    });

    test('▶ on a dhikr with no recording is answered, not silent', () async {
      AthkarService.instance.debugSetData(_sample(withReciter: true));
      final data = AthkarService.instance.data;
      final before = audio.unavailable.value;
      // dhikr 5 is Qur'an; its verse reciter gives nothing here
      final was = audio.quranSources;
      audio.quranSources = (r, item) async => null;
      addTearDown(() => audio.quranSources = was);
      await audio.start([data.item(5)!], 0);
      expect(audio.unavailable.value, before + 1);
      expect(audio.isActive, isFalse);
    });

    test('stop ends it; a failure is reported and ends it', () async {
      final items = AthkarService.instance.data.section(10)!.items;
      unawaited(audio.start(items, 0));
      await pumpEventQueue();
      expect(audio.isActive, isTrue);
      await audio.stop();
      expect(audio.isActive, isFalse);
      expect(store.countOf(items[0]), 0);

      // given up on only after [AthkarAudio.retryFor]
      audio.retryFor = Duration.zero;
      player.failTimes = 1;
      final before = audio.failures.value;
      await audio.start(items, 0);
      expect(audio.failures.value, before + 1);
      expect(audio.isActive, isFalse);
    });

    group('another voice while listening', () {
      // a third voice that has every dhikr
      setUp(() {
        final map = json.decode(_sampleJson(withReciter: true)) as Map;
        (map['reciters'] as List).add({
          'id': 'three',
          'name': 'القارئ الثالث',
          'url': 'https://example.com/three/{id}.mp3',
        });
        AthkarService.instance.debugSetData(AthkarData.parse(json.encode(map)));
      });

      test('the dhikr being heard starts again in the new voice, then the '
          'listening goes on in it', () async {
        final data = AthkarService.instance.data;
        final items = data.section(10)!.items;
        unawaited(audio.start(items, 1)); // dhikr 2, said 3 times
        await pumpEventQueue();
        await player.finish(); // heard once, in «one»
        expect(store.countOf(items[1]), 1);
        expect(audio.repeat, (2, 3));
        await audio.chooseReciter(data.reciters[2]);
        await pumpEventQueue();
        expect(audio.isActive, isTrue);
        expect(audio.current!.id, 2);
        expect(audio.repeat, (2, 3)); // the time cut short, again
        expect(store.countOf(items[1]), 1);
        expect(player.played.last, 'https://example.com/three/2.mp3');
        await player.finish();
        await player.finish();
        expect(store.isDone(items[1]), isTrue);
        expect(audio.current!.id, 3);
        expect(player.played.last, 'https://example.com/three/3.mp3');
      });

      test('paused: the new voice starts the dhikr again and plays', () async {
        final data = AthkarService.instance.data;
        final items = data.section(10)!.items;
        unawaited(audio.start(items, 0));
        await pumpEventQueue();
        await audio.togglePause();
        await audio.chooseReciter(data.reciters[2]);
        await pumpEventQueue();
        expect(audio.isPaused, isFalse);
        expect(audio.current!.id, 1);
        expect(player.played.last, 'https://example.com/three/1.mp3');
      });

      test('a change that does not touch the one being heard plays on; the '
          'verses\' reciter starts a verse again', () async {
        final data = AthkarService.instance.data;
        final asked = <String>[];
        final before = audio.quranSources;
        audio.quranSources = (r, item) async {
          asked.add(r.id);
          return [AthkarSource(Uri.parse('https://q.example/${r.id}.mp3'))];
        };
        addTearDown(() => audio.quranSources = before);
        final sleep = data.section(11)!.items; // 4 (voice «two»), 5 (Qur'an)
        unawaited(audio.start(sleep, 1));
        await pumpEventQueue();
        expect(player.tries, 1);
        // a verse is playing: a new athkar voice leaves it alone
        await audio.chooseReciter(data.reciters[2]);
        await pumpEventQueue();
        expect(player.tries, 1);
        expect(audio.current!.id, 5);
        // a new reciter for the verses starts it again in his voice
        await audio.chooseQuranReciter(Reciter.qaniwahQaloun);
        await pumpEventQueue();
        expect(player.tries, 2);
        expect(asked.last, 'qaniwah_qaloun');
        expect(player.played.last, 'https://q.example/qaniwah_qaloun.mp3');
        // the same reciter again: nothing restarts
        await audio.chooseQuranReciter(Reciter.qaniwahQaloun);
        await pumpEventQueue();
        expect(player.tries, 2);
      });

      test('a verse the chosen reciter has no file of is heard in the '
          'default one, and the bar says so', () async {
        final data = AthkarService.instance.data;
        final before = audio.quranSources;
        audio.quranSources = (r, item) async => r.id == 'qaniwah_qaloun'
            ? null // read inside the ayah before
            : [AthkarSource(Uri.parse('https://q.example/${r.id}.mp3'))];
        addTearDown(() => audio.quranSources = before);
        store.chooseQuranReciter('qaniwah_qaloun');
        final before2 = audio.unavailable.value;
        unawaited(audio.start([data.item(5)!], 0));
        await pumpEventQueue();
        expect(audio.unavailable.value, before2);
        expect(player.played.last, 'https://q.example/naihi_qaloun.mp3');
        expect(audio.voiceNameFor(data.item(5)!), Reciter.naihiQaloun.name);
        expect(audio.quranReciter.id, 'qaniwah_qaloun'); // still the choice
      });

      test('chosen while nothing plays: nothing starts', () async {
        final data = AthkarService.instance.data;
        await audio.chooseReciter(data.reciters[2]);
        await audio.chooseQuranReciter(Reciter.qaniwahQaloun);
        await pumpEventQueue();
        expect(audio.isActive, isFalse);
        expect(player.tries, 0);
        expect(store.reciterOf(data)!.id, 'three');
      });
    });

    test('↺ replays the recording being heard once, then goes on; full '
        'times stay counted', () async {
      final items = AthkarService.instance.data.section(10)!.items;
      unawaited(audio.start(items, 1)); // dhikr 2, said 3 times
      await pumpEventQueue();
      await player.finish(); // the 1st time, heard in full
      expect(audio.repeat, (2, 3));
      await audio.replay(); // the 2nd time from its start
      await pumpEventQueue();
      expect(audio.repeat, (2, 3));
      expect(store.countOf(items[1]), 1);
      expect(player.tries, 3);
      await player.finish();
      await player.finish();
      expect(store.isDone(items[1]), isTrue);
      expect(audio.current!.id, 3); // went on as usual
      await audio.stop();
      await audio.replay(); // nothing playing: nothing happens
      await pumpEventQueue();
      expect(audio.isActive, isFalse);
    });

    test('a recording that cannot be fetched is tried again on the same '
        'dhikr, never skipped', () async {
      final items = AthkarService.instance.data.section(10)!.items;
      final before = audio.failures.value;
      player.failTimes = 2;
      unawaited(audio.start(items, 0));
      await pumpEventQueue();
      expect(player.tries, 3);
      expect(audio.current!.id, 1);
      expect(player.played, ['https://example.com/one/0075.mp3']);
      expect(audio.isWaiting, isFalse);
      expect(audio.failures.value, before);
      await player.finish();
      expect(store.isDone(items[0]), isTrue);
      expect(audio.current!.id, 2);
    });

    test('while it waits: shown, «متابعة» tries now, stop ends it '
        'quietly', () async {
      final items = AthkarService.instance.data.section(10)!.items;
      final before = audio.failures.value;
      audio.retryWaits = const [Duration(hours: 1)];
      player.failTimes = 1000;
      unawaited(audio.start(items, 0));
      await pumpEventQueue();
      expect(player.tries, 1);
      expect(audio.isWaiting, isTrue);
      expect(audio.statusNote, 'ينتظر الاتصال…');
      expect(audio.current!.id, 1);
      await audio.togglePause(); // paused: not tried while paused
      expect(audio.statusNote, isNull);
      await audio.togglePause(); // «متابعة»
      await pumpEventQueue();
      expect(player.tries, 2);
      expect(audio.isWaiting, isTrue);
      await audio.skip(); // «التالي» goes on, as the reader asked
      await pumpEventQueue();
      expect(audio.current!.id, 2);
      await audio.stop();
      await pumpEventQueue();
      expect(audio.isActive, isFalse);
      expect(audio.isWaiting, isFalse);
      expect(audio.failures.value, before);
    });
  });

  group('kept on the phone', () {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory tmp;
    final fetched = <String>[];
    http.Client client() => MockClient((request) async {
      fetched.add(request.url.toString());
      return http.Response.bytes([1, 2, 3, 4], 200);
    });

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('athkar_keep');
      messenger.setMockMethodCallHandler(channel, (_) async => tmp.path);
      fetched.clear();
      AthkarService.instance.debugSetData(_sample(withReciter: true));
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      tmp.deleteSync(recursive: true);
      AthkarDownloadService.instance.state.value = const AthkarDownloadState();
    });

    test('a recording saved on the phone: the save finishes', () async {
      // it used to wait on itself forever (whenComplete returned its own
      // future), so every download hung, 2026-11-20
      const url = 'https://example.com/one/0075.mp3';
      final ok = await http
          .runWithClient(() => AthkarAudio.keepOnPhone(url), client)
          .timeout(const Duration(seconds: 5));
      expect(ok, isTrue);
      expect((await AthkarAudio.clipFile(url)).lengthSync(), 4);
      // there already: not fetched again
      expect(await AthkarAudio.keepOnPhone(url), isTrue);
      expect(fetched.length, 1);
    });

    test('«أصوات الأذكار»: every dhikr in the voice it plays in lands, '
        'and delete takes them off', () async {
      final service = AthkarDownloadService.instance;
      await http
          .runWithClient(service.download, client)
          .timeout(const Duration(seconds: 10));
      final st = service.state.value;
      // «one» has 1, 2 (span) and 3 (special.mp3); 4 only in «two»
      expect(fetched.toSet(), {
        'https://example.com/one/0075.mp3',
        'https://example.com/one/0076.mp3',
        'https://example.com/one/special.mp3',
        'https://example.com/two/4.mp3',
      });
      expect(st.total, 4);
      expect(st.done, 4);
      expect(st.complete, isTrue);
      expect(st.downloading, isFalse);
      expect(st.voices, ['القارئ الأول', 'القارئ الثاني']);
      expect(st.bytes, 16);
      await service.delete();
      expect(
        Directory('${tmp.path}/${AthkarAudio.clipFolder}').existsSync(),
        isFalse,
      );
      expect(service.state.value.done, 0);
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();
    }

    testWidgets('home: tiles on top, groups open to their sections', (
      tester,
    ) async {
      await pump(tester, const AthkarHomePage());
      expect(find.text('الأذكار'), findsOneWidget);
      expect(find.text('أذكار الصباح'), findsOneWidget);
      expect(find.text('المفضلة'), findsOneWidget);
      expect(find.text('أذكار النوم'), findsNothing);
      await tester.tap(find.text('اليوم والليلة'));
      await tester.pumpAndSettle();
      expect(find.text('أذكار النوم'), findsOneWidget);
      // no English anywhere on the page
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(RegExp('[A-Za-z]').hasMatch(t.data ?? ''), isFalse);
      }
    });

    testWidgets('home: search finds a dhikr by its words', (tester) async {
      await pump(tester, const AthkarHomePage());
      await tester.enterText(find.byType(TextField), 'أموت');
      await tester.pumpAndSettle();
      expect(find.text('باسمك اللهم أموت وأحيا'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ققق');
      await tester.pumpAndSettle();
      expect(find.text('لا توجد نتائج'), findsOneWidget);
    });

    testWidgets('list: the bar counts, completes, and can start again', (
      tester,
    ) async {
      final items = AthkarService.instance.data.section(10)!.items;
      await pump(tester, AthkarReaderPage(title: 'أذكار الصباح', items: items));
      expect(find.text('اضغط للعدّ: 3 مرات'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      await tester.tap(find.text('اضغط للعدّ: 3 مرات'));
      await tester.pump();
      expect(find.text('1 من 3'), findsOneWidget);
      await tester.tap(find.text('1 من 3'));
      await tester.pump();
      await tester.tap(find.text('2 من 3'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(store.isDone(items[1]), isTrue);
      expect(find.text('تمّ'), findsOneWidget);
      await tester.tap(find.text('إعادة'));
      // past the store's short save delay
      await tester.pump(const Duration(milliseconds: 500));
      expect(store.countOf(items[1]), 0);
    });

    testWidgets('list: «التالي» moves on without marking the dhikr done', (
      tester,
    ) async {
      final items = AthkarService.instance.data.section(10)!.items;
      await pump(tester, AthkarReaderPage(title: 'أذكار الصباح', items: items));
      // only the dhikr said several times has it
      expect(find.text('التالي'), findsOneWidget);
      await tester.tap(find.text('اضغط للعدّ: 3 مرات'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      expect(store.countOf(items[1]), 1);
      expect(store.isDone(items[1]), isFalse);
      expect(find.text('1 من 3'), findsOneWidget);
    });

    testWidgets('one a page: a tap on the card counts and the page turns', (
      tester,
    ) async {
      store.view = AthkarView.single;
      final items = AthkarService.instance.data.section(10)!.items;
      await pump(tester, AthkarReaderPage(title: 'أذكار الصباح', items: items));
      expect(find.text('الذكر الأول'), findsOneWidget);
      expect(find.text('الذكر الثاني'), findsNothing);
      await tester.tap(find.text('الذكر الأول'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(store.isDone(items[0]), isTrue);
      expect(find.text('الذكر الثاني'), findsOneWidget);
      // back to the list from the top bar
      await tester.tap(find.byTooltip('عرض الكل في قائمة'));
      await tester.pumpAndSettle();
      expect(store.view, AthkarView.list);
      expect(find.text('الذكر الثالث'), findsOneWidget);
    });

    testWidgets('the star adds to the favourites; the menu copies', (
      tester,
    ) async {
      final items = AthkarService.instance.data.section(10)!.items;
      await pump(tester, AthkarReaderPage(title: 'أذكار الصباح', items: items));
      await tester.tap(find.byTooltip('إضافة إلى المفضلة').first);
      await tester.pump();
      expect(store.favourites, [1]);
      await tester.tap(find.byTooltip('خيارات').first);
      await tester.pumpAndSettle();
      for (final label in ['إزالة من المفضلة', 'نسخ', 'مشاركة']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('استماع'), findsNothing);
    });

    testWidgets('with a voice: listen buttons and the player bar', (
      tester,
    ) async {
      AthkarService.instance.debugSetData(_sample(withReciter: true));
      final player = _FakePlayer();
      audio.player = player;
      final items = AthkarService.instance.data.section(10)!.items;
      await pump(tester, AthkarReaderPage(title: 'أذكار الصباح', items: items));
      expect(find.byType(AthkarPlayerBar), findsOneWidget);
      expect(find.text('القارئ الأول'), findsNothing);
      await tester.tap(find.byTooltip('استماع').first);
      await tester.pump();
      await tester.pump();
      expect(find.text('القارئ الأول'), findsOneWidget);
      expect(find.text('الذكر 1 من 3'), findsOneWidget);
      // ↺ plays the dhikr again from its beginning
      expect(player.tries, 1);
      await tester.tap(find.byTooltip('إعادة الذكر'));
      await tester.pump();
      await tester.pump();
      expect(player.tries, 2);
      expect(player.played, [
        'https://example.com/one/0075.mp3',
        'https://example.com/one/0075.mp3',
      ]);
      expect(find.text('الذكر 1 من 3'), findsOneWidget);
      await tester.tap(find.byTooltip('إيقاف'));
      await tester.pumpAndSettle();
      expect(find.text('القارئ الأول'), findsNothing);
    });

    testWidgets('the settings button opens the sheet: «تشغيل متواصل»', (
      tester,
    ) async {
      AthkarService.instance.debugSetData(_sample(withReciter: true));
      audio.player = _FakePlayer();
      final items = AthkarService.instance.data.section(10)!.items;
      await pump(tester, AthkarReaderPage(title: 'أذكار الصباح', items: items));
      await tester.tap(find.byTooltip('إعدادات الأذكار'));
      await tester.pumpAndSettle();
      expect(find.text('تشغيل متواصل'), findsOneWidget);
      expect(find.text('بعد انتهاء الذكر يبدأ الذي يليه'), findsOneWidget);
      // the first switch; the athkar reminders' two come after it
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(store.continuous, isFalse);
      expect(find.text('تذكير أذكار الصباح'), findsOneWidget);
      expect(find.text('تذكير أذكار المساء'), findsOneWidget);
      expect(find.text('يتوقف بعد الذكر الذي تستمع إليه'), findsOneWidget);
    });

    testWidgets('the first opening explains the reminders, once', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      AthkarReminderService.instance.debugReset();
      await pump(tester, const AthkarHomePage());
      expect(find.text('تذكير بأذكار الصباح والمساء'), findsOneWidget);
      expect(find.text('استخدم موقعي'), findsOneWidget);
      expect(find.text('اختر مدينتي من القائمة'), findsOneWidget);
      await tester.tap(find.text('ليس الآن'));
      await tester.pumpAndSettle();
      expect(find.text('تذكير بأذكار الصباح والمساء'), findsNothing);
      expect(AthkarReminderService.instance.introShown, isTrue);
      // the reminders stay on (at their defaults) after «ليس الآن»
      expect(AthkarReminderService.instance.morning.value.on, isTrue);
      await tester.pumpWidget(const SizedBox());
      await pump(tester, const AthkarHomePage());
      expect(find.text('تذكير بأذكار الصباح والمساء'), findsNothing);
    });

    testWidgets('a whole section in the favourites, from its star', (
      tester,
    ) async {
      final section = AthkarService.instance.data.section(10)!;
      await pump(
        tester,
        AthkarReaderPage(
          title: section.name,
          items: section.items,
          section: section,
        ),
      );
      await tester.tap(find.byTooltip('إضافة القسم إلى المفضلة'));
      await tester.pump();
      expect(store.isFavouriteSection(section), isTrue);
      expect(find.byTooltip('إزالة القسم من المفضلة'), findsOneWidget);
      // the favourites now list the section, which opens as itself
      await pump(tester, const AthkarHomePage());
      await tester.tap(find.text('المفضلة'));
      await tester.pumpAndSettle();
      expect(find.text('أقسام كاملة'), findsOneWidget);
      expect(find.text(section.name), findsOneWidget);
      expect(find.text('الأذكار المفضلة'), findsOneWidget);
      await tester.tap(find.text(section.name));
      await tester.pumpAndSettle();
      expect(find.byTooltip('إزالة القسم من المفضلة'), findsOneWidget);
    });

    test('favourite sections survive a restart', () async {
      final section = AthkarService.instance.data.section(10)!;
      store.toggleFavouriteSection(section);
      store.debugReset();
      await store.load();
      expect(store.favouriteSections, [10]);
    });

    testWidgets('every athkar voice shows without scrolling, the first too', (
      tester,
    ) async {
      AthkarService.instance.debugSetData(_sample(withReciter: true));
      store.chooseReciter(AthkarService.instance.data.reciters[1]);
      await pump(tester, const AthkarHomePage());
      await tester.tap(find.byTooltip('إعدادات الأذكار'));
      await tester.pumpAndSettle();
      final column = find.byType(AthkarVoiceColumn).first;
      final box = tester.getRect(column);
      for (final name in ['القارئ الأول', 'القارئ الثاني']) {
        final r = tester.getRect(
          find.descendant(of: column, matching: find.text(name)),
        );
        expect(box.contains(r.center), isTrue, reason: name);
      }
      // the voices come right under the title, above «تشغيل متواصل»
      expect(
        tester.getTopLeft(column).dy,
        lessThan(tester.getTopLeft(find.text('تشغيل متواصل')).dy),
      );
    });

    testWidgets('«أصوات الأذكار» in the downloads page: size before, a bar '
        'while it downloads, delete after', (tester) async {
      final service = AthkarDownloadService.instance;
      addTearDown(() => service.state.value = const AthkarDownloadState());
      service.state.value = const AthkarDownloadState(
        total: 300,
        estimate: 52 * 1024 * 1024,
        voices: ['سعد الغامدي', 'حمد الدريهم'],
      );
      await pump(tester, const Scaffold(body: AthkarDownloadsCard()));
      expect(find.text('أصوات الأذكار'), findsOneWidget);
      expect(
        find.text(
          'بصوت سعد الغامدي، وما لم يسجّله بصوت حمد الدريهم، لتسمعها دون إنترنت.',
        ),
        findsOneWidget,
      );
      expect(find.text('نحو \u206652 MB\u2069'), findsOneWidget);
      expect(find.text('تحميل'), findsOneWidget);
      expect(find.text('حذف'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      service.state.value = service.state.value.copyWith(
        downloading: true,
        done: 150,
        bytes: 20 * 1024 * 1024,
      );
      await tester.pump();
      expect(find.text('جارٍ التحميل 50%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('إيقاف'), findsOneWidget);
      expect(find.text('تحميل'), findsNothing);

      service.state.value = service.state.value.copyWith(
        downloading: false,
        done: 300,
        bytes: 51 * 1024 * 1024,
      );
      await tester.pump();
      expect(find.text('مكتملة · \u206651 MB\u2069'), findsOneWidget);
      expect(find.text('تحميل'), findsNothing);
      expect(find.text('حذف'), findsOneWidget);
    });

    testWidgets('the athkar home has the settings too', (tester) async {
      await pump(tester, const AthkarHomePage());
      await tester.tap(find.byTooltip('إعدادات الأذكار'));
      await tester.pumpAndSettle();
      expect(find.text('إعدادات الأذكار'), findsWidgets);
      expect(find.text('ذكر واحد في الصفحة'), findsOneWidget);
      await tester.tap(find.text('ذكر واحد في الصفحة'));
      await tester.pumpAndSettle();
      expect(store.view, AthkarView.single);
    });

    testWidgets('«التالي» on the dhikr being heard moves the listening on', (
      tester,
    ) async {
      AthkarService.instance.debugSetData(_sample(withReciter: true));
      final player = _FakePlayer();
      audio.player = player;
      final items = AthkarService.instance.data.section(10)!.items;
      await pump(tester, AthkarReaderPage(title: 'أذكار الصباح', items: items));
      unawaited(audio.start(items, 1)); // dhikr 2, said 3 times
      await tester.pump();
      await tester.pump();
      expect(audio.current!.id, 2);
      // the card's «التالي» (the bar has one too)
      await tester.tap(find.widgetWithText(OutlinedButton, 'التالي'));
      await tester.pump();
      await tester.pump();
      expect(audio.current!.id, 3);
      expect(store.isDone(items[1]), isFalse);
      await audio.stop();
      await tester.pumpAndSettle();
    });

    testWidgets('a voice that lacks a dhikr: its card says whose voice', (
      tester,
    ) async {
      AthkarService.instance.debugSetData(_sample(withReciter: true));
      audio.player = _FakePlayer();
      final data = AthkarService.instance.data;
      store.chooseReciter(data.reciters[1]); // «two» has only dhikr 4
      await pump(
        tester,
        AthkarReaderPage(title: 'أذكار الصباح', items: data.section(10)!.items),
      );
      expect(find.text('بصوت القارئ الأول'), findsNWidgets(3));
      await tester.tap(find.byTooltip('إعدادات الأذكار'));
      await tester.pumpAndSettle();
      // both voice lists side by side, and no per-page counts (owner,
      // 2026-11-19)
      expect(find.byType(AthkarVoiceColumn), findsNWidgets(2));
      expect(find.text('قارئ الأذكار'), findsOneWidget);
      expect(find.text('قارئ الآيات'), findsOneWidget);
      expect(find.textContaining('هذه الصفحة'), findsNothing);
      final columns = find.byType(AthkarVoiceColumn);
      expect(
        tester.getCenter(columns.first).dx,
        greaterThan(tester.getCenter(columns.last).dx),
        reason: 'the athkar voice is on the right',
      );
      // picking a voice keeps the sheet open, so the other can be changed too
      await tester.tap(
        find.descendant(of: columns.first, matching: find.text('القارئ الأول')),
      );
      await tester.pumpAndSettle();
      expect(store.reciterOf(data)!.id, 'one');
      expect(find.byType(AthkarVoiceColumn), findsNWidgets(2));
    });

    testWidgets('no recording at all: a muted speaker that says so', (
      tester,
    ) async {
      audio.player = _FakePlayer();
      final data = _sample(withReciter: true);
      // dhikr 4 is only in «two»; drop «two» from the voices
      final only = AthkarData.parse(
        json.encode({
          ...json.decode(_sampleJson(withReciter: true)) as Map,
          'reciters': [
            (json.decode(_sampleJson(withReciter: true)) as Map)['reciters'][0],
          ],
        }),
      );
      AthkarService.instance.debugSetData(only);
      expect(data.item(4), isNotNull);
      await pump(
        tester,
        AthkarReaderPage(title: 'أذكار النوم', items: only.section(11)!.items),
      );
      expect(find.byTooltip('لا يوجد تسجيل صوتي'), findsOneWidget);
    });

    testWidgets('switching to one a page opens on the dhikr scrolled to', (
      tester,
    ) async {
      final many = AthkarData.parse(
        json.encode({
          'ver': 1,
          'featured': [],
          'groups': [
            {
              'id': 'g',
              'name': 'g',
              'sections': [1],
            },
          ],
          'sections': [
            {
              'id': 1,
              'name': 'كثيرة',
              'items': [
                for (var i = 1; i <= 12; i++)
                  {'id': i, 't': 'ذكر رقم $i ${'كلمة ' * 30}', 'n': 1},
              ],
            },
          ],
          'reciters': [],
        }),
      );
      AthkarService.instance.debugSetData(many);
      final items = many.section(1)!.items;
      await pump(tester, AthkarReaderPage(title: 'كثيرة', items: items));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1500),
      );
      await tester.pumpAndSettle();
      // scrolled past dhikr 1
      expect(find.textContaining('ذكر رقم 1 ').hitTestable(), findsNothing);
      await tester.tap(find.byTooltip('ذكر واحد في الصفحة'));
      await tester.pumpAndSettle();
      expect(store.view, AthkarView.single);
      expect(find.textContaining('ذكر رقم 1 '), findsNothing);
    });
  });

  // owner, 2026-11-21: in the middle of a dhikr, «التالي» turned the page
  // but the old dhikr kept playing
  group('the listening follows the reader', () {
    late _FakePlayer player;
    late List<AthkarItem> items;

    Future<void> open(WidgetTester tester, {bool single = true}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      AthkarService.instance.debugSetData(_sample(withReciter: true));
      player = _FakePlayer();
      audio.player = player;
      store.view = single ? AthkarView.single : AthkarView.list;
      items = AthkarService.instance.data.section(10)!.items;
      await tester.pumpWidget(
        MaterialApp(
          home: AthkarReaderPage(title: 'أذكار الصباح', items: items),
        ),
      );
      await tester.pumpAndSettle();
    }

    // the page, not the player bar (it shows the text too)
    Finder onPage(String text) => find.descendant(
      of: find
          .byType(store.view == AthkarView.single ? PageView : Column)
          .first,
      matching: find.text(text),
    );

    Finder inBar(Finder f) =>
        find.descendant(of: find.byType(AthkarPlayerBar), matching: f);

    tearDown(() => audio.stop());

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }

    Future<void> done(WidgetTester tester) async {
      await audio.stop();
      await tester.pumpAndSettle();
    }

    // the page arrows, not the player bar's «التالي»
    Finder arrow(String tip) => find.descendant(
      of: find.byType(AthkarReaderPage),
      matching: find.widgetWithIcon(
        IconButton,
        tip == 'التالي'
            ? Icons.chevron_right_rounded
            : Icons.chevron_left_rounded,
      ),
    );

    testWidgets('the page arrows take the audio along, both ways', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('استماع').first);
      await settle(tester);
      expect(audio.current!.id, 1);
      await tester.tap(arrow('التالي'));
      await settle(tester);
      expect(onPage('الذكر الثاني'), findsOneWidget);
      expect(audio.current!.id, 2);
      expect(player.played.last, 'https://example.com/one/0076.mp3');
      expect(audio.isPaused, isFalse);
      await tester.tap(arrow('السابق'));
      await settle(tester);
      expect(onPage('الذكر الأول'), findsOneWidget);
      expect(audio.current!.id, 1);
      expect(player.played.last, 'https://example.com/one/0075.mp3');
      // skipped, not counted
      expect(store.countOf(items[0]), 0);
      expect(store.countOf(items[1]), 0);
      await done(tester);
    });

    testWidgets('a swipe takes the audio along; a quick run of swipes '
        'starts only the last one', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('استماع').first);
      await settle(tester);
      final before = player.tries;
      // right to left reading: the next page comes in from the left
      await tester.fling(find.byType(PageView), const Offset(500, 0), 2000);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.fling(find.byType(PageView), const Offset(500, 0), 2000);
      await tester.pumpAndSettle();
      expect(onPage('الذكر الثالث'), findsOneWidget);
      expect(audio.current!.id, 3);
      // dhikr 2 was passed over without being played
      expect(player.tries, before + 1);
      expect(player.played.last, 'https://example.com/one/special.mp3');
      await done(tester);
    });

    testWidgets('paused: it moves with the page and stays paused until '
        '«متابعة»', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('استماع').first);
      await settle(tester);
      await tester.tap(inBar(find.byTooltip('إيقاف مؤقت')));
      await settle(tester);
      final before = player.tries;
      await tester.tap(arrow('التالي'));
      await settle(tester);
      expect(audio.current!.id, 2);
      expect(audio.isPaused, isTrue);
      expect(player.tries, before);
      expect(find.text('المرة 1 من 3'), findsOneWidget);
      // the player bar's «التالي» while still paused: on again, paused
      await tester.tap(inBar(find.widgetWithText(TextButton, 'التالي')));
      await settle(tester);
      expect(audio.current!.id, 3);
      expect(audio.isPaused, isTrue);
      expect(onPage('الذكر الثالث'), findsOneWidget);
      await tester.tap(inBar(find.byTooltip('متابعة')));
      await settle(tester);
      expect(audio.isPaused, isFalse);
      expect(player.played.last, 'https://example.com/one/special.mp3');
      player.end();
      await settle(tester);
      expect(store.isDone(items[2]), isTrue);
      expect(audio.isActive, isFalse);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('completing the count of the one being heard moves it on', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('استماع').first);
      await settle(tester);
      await tester.tap(onPage('الذكر الأول'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(onPage('الذكر الثاني'), findsOneWidget);
      expect(audio.current!.id, 2);
      expect(player.played.last, 'https://example.com/one/0076.mp3');
      await done(tester);
    });

    testWidgets('list: «إتمام» on the one being heard moves the audio on '
        '(the owner\'s case)', (tester) async {
      await open(tester, single: false);
      await tester.tap(find.byTooltip('استماع').first);
      await settle(tester);
      expect(audio.current!.id, 1);
      await tester.tap(find.text('إتمام').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(store.isDone(items[0]), isTrue);
      expect(audio.current!.id, 2);
      expect(player.played.last, 'https://example.com/one/0076.mp3');
      // «إتمام» on another dhikr than the one heard leaves the audio alone
      // (after the guard against fast taps running on to the next card,
      // which goes by the real clock)
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 950)),
      );
      await tester.ensureVisible(find.text('إتمام').first); // dhikr 3's
      await tester.pumpAndSettle();
      await tester.tap(find.text('إتمام').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(store.isDone(items[2]), isTrue);
      expect(audio.current!.id, 2);
      await done(tester);
    });

    testWidgets('two quick arrows: the audio lands where the page does '
        '(emulator, 2026-11-21: it went back one)', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('استماع').first);
      await settle(tester);
      await tester.tap(arrow('التالي'));
      await tester.pump(const Duration(milliseconds: 120)); // mid-turn
      await tester.tap(arrow('التالي'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(onPage('الذكر الثالث'), findsOneWidget);
      expect(audio.current!.id, 3);
      expect(player.played.last, 'https://example.com/one/special.mp3');
      // and back the same way
      await tester.tap(arrow('السابق'));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(arrow('السابق'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(onPage('الذكر الأول'), findsOneWidget);
      expect(audio.current!.id, 1);
      await done(tester);
    });

    testWidgets('the old one slow to stop: the page does not fall back to '
        'it meanwhile', (tester) async {
      await open(tester);
      final slow = _SlowStopPlayer(player);
      audio.player = slow;
      await tester.tap(find.byTooltip('استماع').first);
      await settle(tester);
      slow.hold = Completer<void>();
      await tester.tap(arrow('التالي'));
      await tester.pump(const Duration(milliseconds: 50));
      // the player says it is loading, again and again
      for (var k = 0; k < 5; k++) {
        audio.notifyListeners();
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(onPage('الذكر الثاني'), findsOneWidget);
      expect(audio.current!.id, 2);
      slow.hold!.complete();
      slow.hold = null;
      await settle(tester);
      expect(onPage('الذكر الثاني'), findsOneWidget);
      expect(audio.current!.id, 2);
      expect(player.played.last, 'https://example.com/one/0076.mp3');
      await done(tester);
    });

    testWidgets('counting a dhikr said 3 times to its end while it plays: '
        'on to the next, page and audio (emulator, 2026-11-21)', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(arrow('التالي'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('استماع').first); // dhikr 2
      await settle(tester);
      player.end(); // heard once: counted
      await settle(tester);
      expect(store.countOf(items[1]), 1);
      expect(find.text('المرة 2 من 3'), findsOneWidget);
      final counter = find.byType(AthkarCounterBar);
      await tester.tap(counter);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(counter);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(counter); // one too many, as fingers do
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(store.isDone(items[1]), isTrue);
      expect(onPage('الذكر الثالث'), findsOneWidget);
      expect(audio.current!.id, 3);
      expect(store.countOf(items[2]), 0);
      await done(tester);
    });

    testWidgets('«تمّ» reached by taps and hearing together: no more repeats, '
        'on to the next (owner, 2026-11-21)', (tester) async {
      await open(tester);
      await tester.tap(arrow('التالي'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('استماع').first); // dhikr 2, 3 times
      await settle(tester);
      expect(find.text('المرة 1 من 3'), findsOneWidget);
      player.end(); // heard once
      await settle(tester);
      expect(find.text('المرة 2 من 3'), findsOneWidget);
      // the reader taps once while the second time plays
      await tester.tap(find.byType(AthkarCounterBar));
      await tester.pumpAndSettle();
      expect(store.countOf(items[1]), 2);
      player.end(); // the second time ends: 3 of 3, «تمّ»
      await settle(tester);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(store.isDone(items[1]), isTrue);
      // no third time: on to dhikr 3, the page with it
      expect(audio.current!.id, 3);
      expect(onPage('الذكر الثالث'), findsOneWidget);
      expect(player.played.where((u) => u.endsWith('0076.mp3')).length, 2);
      await done(tester);
    });

    testWidgets('going on by itself: the page follows, nothing restarts', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('استماع').first);
      await settle(tester);
      player.end();
      await settle(tester);
      expect(audio.current!.id, 2);
      expect(onPage('الذكر الثاني'), findsOneWidget);
      expect(player.played, [
        'https://example.com/one/0075.mp3',
        'https://example.com/one/0076.mp3',
      ]);
      await done(tester);
    });

    testWidgets('list: a card\'s «التالي» on another dhikr takes the audio '
        'there', (tester) async {
      await open(tester, single: false);
      unawaited(audio.start(items, 0));
      await settle(tester);
      expect(audio.current!.id, 1);
      // dhikr 2's card (said 3 times) has the only card «التالي»
      await tester.tap(find.widgetWithText(OutlinedButton, 'التالي'));
      await settle(tester);
      expect(audio.current!.id, 3);
      expect(player.played.last, 'https://example.com/one/special.mp3');
      await done(tester);
    });

    testWidgets('«تشغيل متواصل» off: the arrow plays that one dhikr, then '
        'stops', (tester) async {
      store.continuous = false;
      addTearDown(() => store.continuous = true);
      await open(tester);
      await tester.tap(find.byTooltip('استماع').first);
      await settle(tester);
      await tester.tap(arrow('التالي'));
      await settle(tester);
      expect(audio.current!.id, 2);
      for (var k = 0; k < 3; k++) {
        player.end();
        await settle(tester);
      }
      expect(store.isDone(items[1]), isTrue);
      expect(audio.isActive, isFalse);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  // phones held sideways, tablets, the largest text: nothing overflows
  group('every screen size', () {
    final data = AthkarData.parse(
      File('assets/data/athkar.json').readAsStringSync(),
    );
    // widths as on a phone: the test font draws every letter as a full
    // square, about twice as wide as Arabic letters really are
    setUpAll(() async {
      final naskh = File('test/fixtures/fonts/NotoNaskhArabic.ttf');
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(naskh.readAsBytesSync())),
          ))
          .load();
    });

    const sizes = <String, (Size, double)>{
      'small phone': (Size(720, 1280), 2.0),
      'phone sideways': (Size(2400, 1080), 2.75),
      'small phone sideways': (Size(1280, 720), 2.0),
      'tablet': (Size(1600, 2560), 2.0),
      'tablet sideways': (Size(2560, 1600), 2.0),
      'big tablet sideways': (Size(2732, 2048), 2.0),
    };

    for (final e in sizes.entries) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${e.key}, text x$scale', (tester) async {
          tester.view.physicalSize = e.value.$1;
          tester.view.devicePixelRatio = e.value.$2;
          addTearDown(tester.view.reset);
          AthkarService.instance.debugSetData(data);
          final player = _FakePlayer();
          audio.player = player;
          Future<void> show(Widget page) async {
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData.fromView(
                    tester.view,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: page,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$page');
          }

          await show(const AthkarHomePage());
          // the morning athkar: long ones, a verse, counts
          final morning = data.sections.firstWhere(
            (s) => s.name.contains('الصباح'),
          );
          for (final view in AthkarView.values) {
            store.view = view;
            await show(
              AthkarReaderPage(
                key: ValueKey(view),
                title: morning.name,
                items: morning.items,
                section: morning,
              ),
            );
            await tester.tap(find.byTooltip('استماع').first);
            await tester.pump();
            await tester.pump();
            await tester.pumpAndSettle();
            expect(audio.isActive, isTrue);
            expect(tester.takeException(), isNull, reason: '$view bar');
            if (view == AthkarView.single) {
              for (var k = 0; k < 4; k++) {
                await tester.tap(
                  find.descendant(
                    of: find.byType(AthkarReaderPage),
                    matching: find.widgetWithIcon(
                      IconButton,
                      Icons.chevron_right_rounded,
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull, reason: 'page $k');
              }
            }
            await tester.tap(find.byTooltip('إعدادات الأذكار'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$view sheet');
            // the voice lists leave room to drag the sheet to what is
            // under them (sideways, they took it all)
            final screen =
                tester.view.physicalSize.height / tester.view.devicePixelRatio;
            expect(
              tester.getSize(find.byType(AthkarVoiceColumn).first).height,
              lessThan(screen * 0.6),
              reason: 'voice lists',
            );
            await tester.ensureVisible(find.text('تشغيل متواصل'));
            await tester.pumpAndSettle();
            expect(find.text('تشغيل متواصل').hitTestable(), findsOneWidget);
            await tester.tapAt(const Offset(5, 5));
            await tester.pumpAndSettle();
            await audio.stop();
            await tester.pumpAndSettle();
          }
          store.view = AthkarView.list;
        });
      }
    }
  });
}

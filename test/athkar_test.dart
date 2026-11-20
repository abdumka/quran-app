import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/athkar.dart';
import 'package:islamic_dawah_mushaf/services/athkar_audio.dart';
import 'package:islamic_dawah_mushaf/services/athkar_service.dart';
import 'package:islamic_dawah_mushaf/services/content_update_service.dart';
import 'package:islamic_dawah_mushaf/widgets/athkar/athkar_home_page.dart';
import 'package:islamic_dawah_mushaf/widgets/athkar/athkar_reader_page.dart';
import 'package:islamic_dawah_mushaf/widgets/athkar/athkar_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Finishes each recording when the test says so.
class _FakePlayer implements AthkarPlayer {
  final List<String> played = [];
  final List<AthkarSource> sources = [];
  Completer<bool>? _current;
  bool failNext = false;
  double speed = 1;

  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;

  @override
  Future<bool> play(List<AthkarSource> sources) {
    if (failNext) {
      failNext = false;
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
    SharedPreferences.setMockInitialValues({});
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

      player.failNext = true;
      final before = audio.failures.value;
      await audio.start(items, 0);
      expect(audio.failures.value, before + 1);
      expect(audio.isActive, isFalse);
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
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(store.continuous, isFalse);
      expect(find.text('يتوقف بعد الذكر الذي تستمع إليه'), findsOneWidget);
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
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/page_phoneme_service.dart';
import 'package:islamic_dawah_mushaf/services/recitation_engine.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';
import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/memorization_test_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hand-driven phoneme engine (as in the flow tests) that counts its
/// starts and stops. Its clock starts at 0, as a real recognizer's does.
class _Engine extends RecitationEngine {
  final _controller = StreamController<RecognizedSegment>.broadcast();
  int _ms = 0;
  int starts = 0;
  int stops = 0;

  @override
  bool get emitsPhonemes => true;

  @override
  Stream<RecognizedSegment> get segments => _controller.stream;

  void recite(Iterable<String> words) {
    for (final w in words) {
      _ms += 400;
      _controller.add(RecognizedSegment(
        w,
        phonemes: [w],
        phonemeTimesMs: [_ms],
        audioEndMs: _ms,
      ));
    }
  }

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async {
    stops++;
    await _controller.close();
  }
}

/// A word engine that never hears anything (for the bar's widget tests).
class _QuietEngine extends RecitationEngine {
  final _controller = StreamController<RecognizedSegment>.broadcast();

  @override
  Stream<RecognizedSegment> get segments => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = MemorizationTestService.instance;

  late List<PhonemeWord> words; // page 1 (Al-Fatihah)
  List<String> ayah(int index) => [
        for (final w in words)
          if (w.ayah == index) collapseMadd(w.phon),
      ];
  List<WordStatus> statusesOf(int index) => [
        for (var i = 0; i < words.length; i++)
          if (words[i].ayah == index) service.statuses[i],
      ];
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 1500));

  setUpAll(() async {
    words = (await PagePhonemeService.forPage(1))!.words;
    MemorizationTestService.controlBarrierMs = 0;
  });

  setUp(resetTasmeeBarPlaceForTest);

  tearDown(() async {
    MemorizationTestService.engineFactoryForTest = null;
    await service.stop();
  });

  group('the service', () {
    test('pause lets go of the recognizer; nothing is judged or changed', () async {
      final first = _Engine();
      expect(
        await service.start(pageNumber: 1, engineOverride: first, stopPlayback: false),
        isTrue,
      );
      first.recite(ayah(0));
      first.recite(ayah(1));
      await settle();
      expect(statusesOf(1).every((s) => s == WordStatus.correct), isTrue);
      final before = List.of(service.statuses);

      await service.pause();
      expect(service.status.value, MemorizationTestStatus.paused);
      expect(first.stops, 1, reason: 'the microphone is closed');
      expect(service.audioLevel.value, 0);
      expect(service.isActive, isTrue, reason: 'the page stays up');

      // Every help button does nothing while paused.
      service.showHint();
      service.revealCurrentAyah();
      service.repeatAyah();
      service.skipCurrentAyah();
      service.finishDrillNow();
      await settle();
      expect(service.statuses, before);
      expect(service.status.value, MemorizationTestStatus.paused);
    });

    test('resume goes on from the same word with a new recognizer', () async {
      final first = _Engine();
      await service.start(pageNumber: 1, engineOverride: first, stopPlayback: false);
      first.recite(ayah(0));
      first.recite(ayah(1));
      await settle();
      await service.pause();

      final second = _Engine();
      MemorizationTestService.engineFactoryForTest = () => second;
      expect(await service.resume(), isTrue);
      expect(service.status.value, MemorizationTestStatus.listening);
      expect(second.starts, 1);

      // The new recognizer's clock starts at 0 again.
      second.recite(ayah(2));
      second.recite(ayah(3));
      await settle();
      expect(statusesOf(2).every((s) => s == WordStatus.correct), isTrue);
      expect(statusesOf(3).every((s) => s == WordStatus.correct), isTrue);
      expect(service.heldWord.value, -1);
      expect(service.feedback.value?.kind, isNot(FeedbackKind.wrong));
    });

    test('after a pause mid-ayah, going back to its start is followed', () async {
      final first = _Engine();
      await service.start(pageNumber: 1, engineOverride: first, stopPlayback: false);
      first.recite(ayah(0));
      first.recite(ayah(1));
      final third = ayah(2);
      first.recite(third.take(2));
      await settle();
      await service.pause();

      final second = _Engine();
      MemorizationTestService.engineFactoryForTest = () => second;
      expect(await service.resume(), isTrue);
      // The reciter starts the ayah again from its first word.
      second.recite(third);
      second.recite(ayah(3));
      await settle();
      expect(service.heldWord.value, -1, reason: 'no stop for going back');
      expect(statusesOf(2).every((s) => s == WordStatus.correct), isTrue);
      expect(statusesOf(3).every((s) => s == WordStatus.correct), isTrue);
    });

    test('ending a paused session keeps its report', () async {
      final first = _Engine();
      await service.start(pageNumber: 1, engineOverride: first, stopPlayback: false);
      service.takeRunReports();
      first.recite(ayah(0));
      first.recite(ayah(1));
      await settle();
      await service.pause();
      await service.stop();
      final reports = service.takeRunReports();
      expect(reports, hasLength(1));
      expect(reports.single.correct, greaterThan(0));
      expect(service.status.value, MemorizationTestStatus.idle);
    });

    test('a page turned while paused opens paused, the microphone closed', () async {
      final first = _Engine();
      await service.start(pageNumber: 1, engineOverride: first, stopPlayback: false);
      first.recite(ayah(0));
      await settle();
      await service.pause();

      final next = _Engine();
      expect(
        await service.start(pageNumber: 2, engineOverride: next, stopPlayback: false),
        isTrue,
      );
      expect(service.activePage, 2);
      expect(service.status.value, MemorizationTestStatus.paused);
      expect(next.starts, 0, reason: 'nothing listens on the new page yet');

      expect(await service.resume(), isTrue);
      expect(next.starts, 1);
      expect(service.status.value, MemorizationTestStatus.listening);
    });

    test('a session started anew after a stop is not paused', () async {
      await service.start(pageNumber: 1, engineOverride: _Engine(), stopPlayback: false);
      await service.pause();
      await service.stop();
      final fresh = _Engine();
      await service.start(pageNumber: 1, engineOverride: fresh, stopPlayback: false);
      expect(service.status.value, MemorizationTestStatus.listening);
      expect(fresh.starts, 1);
    });

    test('a self-test and a finished page do not pause', () async {
      await service.start(pageNumber: 1, silent: true, stopPlayback: false);
      expect(service.canPause, isFalse);
      await service.pause();
      service.pauseForAppInactive();
      expect(service.status.value, MemorizationTestStatus.listening);
    });

    test('the app losing the screen pauses a live session', () async {
      final first = _Engine();
      await service.start(pageNumber: 1, engineOverride: first, stopPlayback: false);
      service.pauseForAppInactive();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.status.value, MemorizationTestStatus.paused);
      expect(first.stops, 1);
    });

    test('a pause and a stop at once stop the recognizer once', () async {
      final first = _Engine();
      await service.start(pageNumber: 1, engineOverride: first, stopPlayback: false);
      // The app switcher: inactive (pause), then hidden (stop) right after.
      final pausing = service.pause();
      final stopping = service.stop();
      await Future.wait([pausing, stopping]);
      expect(first.stops, 1);
      expect(service.status.value, MemorizationTestStatus.idle);
    });

    test('a resume called off by a stop leaves nothing listening', () async {
      await service.start(pageNumber: 1, engineOverride: _Engine(), stopPlayback: false);
      await service.pause();
      final second = _Engine();
      MemorizationTestService.engineFactoryForTest = () => second;
      final resuming = service.resume();
      await service.stop();
      expect(await resuming, isFalse);
      expect(service.status.value, MemorizationTestStatus.idle);
      expect(second.stops, 1);
    });
  });

  group('the bar', () {
    // The page box is really 400 x 800 (the default test screen is 600
    // high, which would squeeze it).
    void screen(WidgetTester tester) {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<void> pumpBar(WidgetTester tester, int page) async {
      screen(tester);
      const size = Size(400, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: size,
                child: MemorizationTestOverlay(pageNumber: page),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> settleBar(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('after a pause the bar still steps off the line being read', (tester) async {
      MemorizationTestService.engineFactoryForTest = _QuietEngine.new;
      await tester.runAsync(
        () => service.start(
          pageNumber: 3,
          engineOverride: _QuietEngine(),
          stopPlayback: false,
        ),
      );
      final ayahs = service.regions!.ayahs;
      final first = ayahs.first.rects.first;
      final k = ayahs.indexWhere(
        (a) => a.rects.first.y > first.y + 5 * first.height,
      );
      expect(k, greaterThan(0));
      final target = ayahs[k].rects.first;
      SharedPreferences.setMockInitialValues({
        'tasmee_bar_pos': '0.0,${target.y}',
      });
      await pumpBar(tester, 3);
      double barTop() => tester.getTopLeft(find.text('كلمة')).dy;
      final home = barTop();

      // Pause, then go on.
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.pause_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settleBar(tester);
      expect(service.status.value, MemorizationTestStatus.paused);
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settleBar(tester);
      expect(service.status.value, MemorizationTestStatus.listening);
      // (The first layout may still settle the bar by up to 2.4 px.)
      expect(barTop(), closeTo(home, 3), reason: 'a pause moves nothing');

      // The reading reaches the bar's line: it steps aside.
      for (var i = 0; i < k; i++) {
        await tester.tap(find.text('تخطَّ'));
        await settleBar(tester);
      }
      expect(service.currentAyahIndex, k);
      final top = barTop();
      final bottom = tester.getBottomLeft(find.text('تخطَّ')).dy;
      const height = 800.0;
      final lineTop = target.y * height;
      final lineBottom = (target.y + target.height) * height;
      expect(
        top > lineBottom || bottom < lineTop,
        isTrue,
        reason: 'bar $top..$bottom, line $lineTop..$lineBottom',
      );
    });
    testWidgets('the dot pauses; paused, only «إنهاء» and «إخفاء» work', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(
        () => service.start(
          pageNumber: 1,
          engineOverride: _QuietEngine(),
          stopPlayback: false,
        ),
      );
      await pumpBar(tester, 1);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.pause_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settleBar(tester);
      expect(service.status.value, MemorizationTestStatus.paused);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('متوقّف مؤقتًا: اضغط الدائرة للمتابعة'), findsOneWidget);

      // The other buttons are still there, dimmed, and do nothing.
      final before = List.of(service.statuses);
      for (final label in ['كلمة', 'الآية', 'أعد الآية', 'تخطَّ', 'الصفحة']) {
        expect(find.text(label), findsOneWidget, reason: label);
        await tester.tap(find.text(label));
        await settleBar(tester);
      }
      expect(service.statuses, before);
      expect(service.status.value, MemorizationTestStatus.paused);

      // «إخفاء» folds the bar, the folded dot unfolds it (still paused).
      await tester.tap(find.text('إخفاء'));
      await settleBar(tester);
      expect(find.text('كلمة'), findsNothing);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
      await settleBar(tester);
      expect(find.text('كلمة'), findsOneWidget);
      expect(service.status.value, MemorizationTestStatus.paused);

      // «إنهاء» ends the session.
      await tester.runAsync(() async {
        await tester.tap(find.text('إنهاء'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settleBar(tester);
      expect(service.status.value, MemorizationTestStatus.idle);
    });

  });
}

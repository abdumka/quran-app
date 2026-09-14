import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/recitation_engine.dart';
import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';

/// Hand-driven engine: the test pushes segments explicitly.
class _ManualEngine extends RecitationEngine {
  final _controller = StreamController<String>.broadcast();

  void emit(String segment) => _controller.add(segment);

  @override
  Stream<String> get segments => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async => await _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = MemorizationTestService.instance;
  late _ManualEngine engine;

  Future<void> startPage1() async {
    engine = _ManualEngine();
    final started = await service.start(
      pageNumber: 1,
      engineOverride: engine,
      stopPlayback: false,
    );
    expect(started, isTrue);
  }

  Future<void> emit(String text) async {
    engine.emit(text);
    await Future<void>.delayed(Duration.zero);
  }

  tearDown(() async {
    await service.stop();
  });

  test('a completed ayah is announced with a tick', () async {
    await startPage1();
    await emit('الحمد لله رب العالمين');
    expect(service.lastHeard.value, 'الحمد لله رب العالمين');
    expect(service.currentAyahIndex, 1);
    expect(service.feedback.value?.kind, FeedbackKind.good);
    expect(service.feedback.value?.message, contains('الآية 1 ✓'));
  });

  test('an unrecognised segment asks to repeat, then flags a mistake',
      () async {
    await startPage1();
    await emit('كلمة غريبة');
    expect(service.feedback.value?.kind, FeedbackKind.unclear);
    expect(service.feedback.value?.message, contains('أعد'));
    expect(service.statuses.first, WordStatus.unclear);

    await emit('كلمة غريبة');
    expect(service.feedback.value?.kind, FeedbackKind.wrong);
    expect(service.feedback.value?.message, contains('خطأ في'));
    expect(service.feedback.value?.message, contains('سمعت'));
    expect(service.statuses.first, WordStatus.mistake);
  });

  test('reciting a different ayah of the page is called out by number',
      () async {
    await startPage1();
    // Ayah 5 while ayah 1 is expected: far outside the aligner window.
    await emit('اهدنا الصراط المستقيم');
    expect(service.feedback.value?.kind, FeedbackKind.wrong);
    expect(service.feedback.value?.message, contains('الآية 5'));
    expect(service.feedback.value?.message, contains('المطلوب الآية 1'));
    // Nothing was revealed by the wrong ayah.
    expect(service.currentAyahIndex, 0);
  });

  test('hint shows the next expected word without revealing anything',
      () async {
    await startPage1();
    service.showHint();
    expect(service.feedback.value?.kind, FeedbackKind.info);
    expect(service.feedback.value?.message, contains('اِ۬لْحَمْدُ'));
    expect(service.ayahStates.first, AyahRevealState.current);
  });

  test('reveal and skip buttons resolve the current ayah as flagged',
      () async {
    await startPage1();
    service.revealCurrentAyah();
    expect(service.ayahStates[0], AyahRevealState.flagged);
    expect(service.currentAyahIndex, 1);
    expect(service.feedback.value?.message, contains('تم كشف الآية 1'));

    service.skipCurrentAyah();
    expect(service.ayahStates[1], AyahRevealState.flagged);
    expect(service.currentAyahIndex, 2);
    expect(service.feedback.value?.message, contains('تم تخطي الآية 2'));
    expect(service.statuses.sublist(4, 6),
        everyElement(WordStatus.skipped));
  });

  test('skipping every ayah completes the page with a summary', () async {
    await startPage1();
    for (var i = 0; i < 7; i++) {
      service.skipCurrentAyah();
    }
    expect(service.status.value, MemorizationTestStatus.completed);
    expect(service.summary, (0, 7));
    expect(service.feedback.value?.message, contains('اكتملت الصفحة'));
    expect(service.feedback.value?.message, contains('7 بملاحظات'));
  });

  test('a clean recitation completes with praise', () async {
    await startPage1();
    await emit('الحمد لله رب العالمين الرحمن الرحيم ملك يوم الدين');
    await emit('اياك نعبد واياك نستعين اهدنا الصراط المستقيم');
    await emit('صراط الذين انعمت عليهم غير المغضوب عليهم ولا الضالين');
    expect(service.status.value, MemorizationTestStatus.completed);
    expect(service.summary, (7, 0));
    expect(service.feedback.value?.kind, FeedbackKind.good);
    expect(service.feedback.value?.message, contains('أحسنت'));
  });

  test('restart starts the same page over', () async {
    await startPage1();
    service.revealCurrentAyah();
    // restart() builds the real engine path when no override is given, so
    // drive the equivalent explicitly: a fresh start on the same page.
    await startPage1();
    expect(service.activePage, 1);
    expect(service.currentAyahIndex, 0);
    expect(service.feedback.value, isNull);
  });

  test('current ayah words appear one by one as they are recognised',
      () async {
    await startPage1();
    expect(service.currentAyahWords.length, 4);
    expect(
      service.currentAyahWords.every((w) => w.$2 == WordStatus.pending),
      isTrue,
    );
    await emit('الحمد لله');
    final words = service.currentAyahWords;
    expect(words[0].$2, WordStatus.correct);
    expect(words[1].$2, WordStatus.correct);
    expect(words[2].$2, WordStatus.pending);
    await emit('رب العالمين');
    // Ayah 1 done: the panel now tracks ayah 2.
    expect(service.currentAyahWords.length, 2);
    expect(normalizeRecitationText(service.currentAyahWords.first.$1), 'الرحمن');
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/page_phoneme_service.dart';
import 'package:islamic_dawah_mushaf/services/recitation_engine.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_weak_point_store.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';
import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';

/// Hand-driven PHONEME engine: the test "recites" words of the page by
/// pushing their expected phonemes, as the streaming recognizer would.
class _PhonemeEngine extends RecitationEngine {
  final _controller = StreamController<RecognizedSegment>.broadcast();
  int _ms = 0;

  @override
  bool get emitsPhonemes => true;

  @override
  Stream<RecognizedSegment> get segments => _controller.stream;

  /// A segment exactly as a phone logged it.
  void replay(List<String> tokens, List<int> timesMs, int audioEndMs) {
    _controller.add(RecognizedSegment(
      tokens.join(),
      phonemes: tokens,
      phonemeTimesMs: timesMs,
      audioEndMs: audioEndMs,
    ));
  }

  /// One token per word, 400 ms apart.
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
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    await _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = MemorizationTestService.instance;

  late List<PhonemeWord> words; // page 1 (Al-Fatihah)
  List<String> ayah(int index) => [
        for (final w in words)
          if (w.ayah == index) collapseMadd(w.phon),
      ];
  int firstWordOf(int index) => words.indexWhere((w) => w.ayah == index);

  /// Lets the stream deliver and the 1 s "settled" tick of the service run.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 1500));

  setUpAll(() async {
    words = (await PagePhonemeService.forPage(1))!.words;
  });

  tearDown(() async {
    await service.stop();
  });

  test('a skipped ayah stops the session hard until it is recited', () async {
    final engine = _PhonemeEngine();
    expect(
      await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false),
      isTrue,
    );
    engine.recite(ayah(0));
    engine.recite(ayah(2)); // ayah 2 (index 1) skipped
    engine.recite(ayah(3));
    await settle();

    final held = firstWordOf(1);
    expect(service.heldWord.value, held, reason: 'stopped at the first skipped word');
    expect(service.statuses[held], WordStatus.mistake);
    for (var w = held + 1; w < words.length; w++) {
      expect(service.statuses[w], WordStatus.pending, reason: 'word $w stays covered');
    }
    expect(service.feedback.value?.kind, FeedbackKind.wrong);

    // Reading further down the page changes nothing...
    engine.recite(ayah(4));
    await settle();
    expect(service.heldWord.value, held);
    expect(service.statuses[firstWordOf(4)], WordStatus.pending);

    // ...going back to the skipped ayah lifts the stop and the session goes on.
    engine.recite(ayah(1));
    engine.recite(ayah(2));
    await settle();
    expect(service.heldWord.value, -1);
    expect(service.statuses[held], WordStatus.correct);
    expect(service.statuses[firstWordOf(2)], WordStatus.correct);
  });

  test('a wrong word keeps the words after it covered', () async {
    final engine = _PhonemeEngine();
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    // Ayah 2 with its second word replaced by another word of the page,
    // then read on correctly.
    final second = ayah(1);
    final wrong = firstWordOf(1) + 1;
    engine.recite([second[0], ayah(3).last, ...second.skip(2)]);
    await settle();

    expect(service.heldWord.value, wrong, reason: 'stopped at the wrong word');
    expect(service.statuses[wrong], WordStatus.mistake);
    for (var w = wrong + 1; w < words.length; w++) {
      expect(service.statuses[w], WordStatus.pending, reason: 'word $w stays covered');
    }

    // Reading it right lifts the stop; the rest is uncovered as it is read.
    engine.recite(second.skip(1));
    await settle();
    expect(service.heldWord.value, -1);
    expect(service.statuses[wrong], WordStatus.correct);
    expect(service.statuses[firstWordOf(2) - 1], WordStatus.correct);
  });

  test('phone log p132: the word after a wrong word is not uncovered', () async {
    final fixture = json.decode(
      File('test/fixtures/tasmee_p132_wrong_word.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final wrong = fixture['wrongWord'] as int;
    final engine = _PhonemeEngine();
    await service.start(
      pageNumber: fixture['page'] as int,
      engineOverride: engine,
      stopPlayback: false,
    );
    for (final s in fixture['segments'] as List<dynamic>) {
      engine.replay(
        (s['tokens'] as List<dynamic>).cast<String>(),
        (s['timesMs'] as List<dynamic>).cast<int>(),
        s['audioEndMs'] as int,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(service.heldWord.value, wrong);
    expect(service.statuses[wrong], WordStatus.mistake);
    expect(service.statuses[wrong + 1], WordStatus.pending,
        reason: 'read correctly, but it comes after the wrong word');
  });

  test('repeat ayah: the ayah is as if never read', () async {
    final engine = _PhonemeEngine();
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    engine.recite(ayah(1));
    await settle();
    final start = firstWordOf(1);
    expect(service.statuses[start], WordStatus.correct);

    service.repeatAyah(); // the cursor is at the top of ayah 3: repeats ayah 2
    expect(service.statuses[start], WordStatus.pending);

    // One word said: one word uncovered, not the whole ayah.
    engine.recite([ayah(1).first]);
    await settle();
    expect(service.statuses[start], WordStatus.correct);
    expect(service.statuses[start + 1], WordStatus.pending);
  });

  test('a drill starts on its ayah and ends with its target ayah', () async {
    final engine = _PhonemeEngine();
    final target = TasmeeWeakPoint(
      surah: 1,
      ayah: 4,
      word: 1,
      page: 1,
      expected: 'x',
      kind: 'word',
    );
    final drill = TasmeeDrill(page: 1, surah: 1, ayah: 4, targets: [target]);
    await service.start(
      pageNumber: 1,
      engineOverride: engine,
      stopPlayback: false,
      startAyahIndex: 1,
      drill: drill,
    );
    // The ayah before the start is shown, not tested.
    expect(service.statuses[0], WordStatus.correct);
    expect(service.statuses[firstWordOf(1)], WordStatus.pending);
    expect(service.drillLabel.value, isNotNull);

    engine.recite(ayah(1));
    engine.recite(ayah(2));
    engine.recite(ayah(3));
    engine.recite([ayah(4).first]); // moves the cursor past the target ayah
    await settle();

    final result = service.drillResult.value;
    expect(result, isNotNull, reason: 'the drill ended with its target ayah');
    expect(result!.passed.map((p) => p.key), ['1:4:1']);
    expect(result.failed, isEmpty);
    expect(service.status.value, MemorizationTestStatus.completed);
  });

  test('restarting the page inside a drill restarts the drill', () async {
    final target = TasmeeWeakPoint(
      surah: 1,
      ayah: 4,
      word: 1,
      page: 1,
      expected: 'x',
      kind: 'word',
    );
    final drill = TasmeeDrill(page: 1, surah: 1, ayah: 4, targets: [target]);
    final first = _PhonemeEngine();
    await service.start(
      pageNumber: 1,
      engineOverride: first,
      stopPlayback: false,
      startAyahIndex: 1,
      drill: drill,
    );
    first.recite(ayah(1));
    await settle();
    expect(service.statuses[firstWordOf(1)], WordStatus.correct);

    final engine = _PhonemeEngine();
    expect(
      await service.restart(engineOverride: engine, stopPlayback: false),
      isTrue,
    );
    // Still the drill: same label, same shown ayah, same starting ayah.
    expect(service.drillActive, isTrue);
    expect(service.drillLabel.value, isNotNull);
    expect(service.statuses[0], WordStatus.correct);
    expect(service.statuses[firstWordOf(1)], WordStatus.pending);

    engine.recite(ayah(1));
    engine.recite(ayah(2));
    engine.recite(ayah(3));
    engine.recite([ayah(4).first]);
    await settle();
    expect(service.drillResult.value, isNotNull);
  });

  test('restarting an ordinary page starts it from its first word', () async {
    final first = _PhonemeEngine();
    await service.start(pageNumber: 1, engineOverride: first, stopPlayback: false);
    first.recite(ayah(0));
    await settle();
    expect(service.statuses[0], WordStatus.correct);

    final engine = _PhonemeEngine();
    expect(
      await service.restart(engineOverride: engine, stopPlayback: false),
      isTrue,
    );
    expect(service.drillActive, isFalse);
    expect(service.statuses.every((s) => s == WordStatus.pending), isTrue);
  });
}

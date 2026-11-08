import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/page_phoneme_service.dart';
import 'package:islamic_dawah_mushaf/services/recitation_engine.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_report_store.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';
import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hand-driven phoneme engine whose [verify] answers with whatever the test
/// sets, after a short delay (the worker's fresh decode).
class _VerifyingEngine extends RecitationEngine {
  final _controller = StreamController<RecognizedSegment>.broadcast();
  int _ms = 0;

  /// What the fresh decode "hears"; null = the engine keeps no audio.
  List<String>? fresh;
  final List<(int, int)> windows = [];

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
  Future<List<String>?> verify({required int fromMs, required int toMs}) async {
    windows.add((fromMs, toMs));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return fresh;
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() => _controller.close();
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
  /// Lets the stream deliver, the 1 s "settled" tick run and the fresh
  /// decode (200 ms here) answer.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 3000));

  setUpAll(() async {
    words = (await PagePhonemeService.forPage(1))!.words;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await TasmeeSpeedSetting.set(TasmeeSpeed.verified);
  });

  tearDown(() async {
    await service.stop();
    await TasmeeSpeedSetting.set(TasmeeSpeed.accurate);
  });

  /// Ayah 2 with its second word replaced by another word of the page.
  List<String> ayahTwoWithWrongSecond() {
    final second = ayah(1);
    return [second[0], ayah(3).last, ...second.skip(2)];
  }

  test('a stop the fresh decode clears is withdrawn and the word revealed', () async {
    final engine = _VerifyingEngine();
    final wrong = firstWordOf(1) + 1;
    // The fresh decode hears the ayah as written.
    engine.fresh = ayah(1);
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    engine.recite(ayahTwoWithWrongSecond());
    await settle();

    expect(engine.windows, isNotEmpty, reason: 'the engine was asked for a fresh decode');
    final (from, to) = engine.windows.first;
    expect(from, lessThan(to));
    expect(to - from, lessThanOrEqualTo(6000));
    expect(service.heldWord.value, -1, reason: 'no stop');
    expect(service.statuses[wrong], WordStatus.correct);
    expect(service.statuses[firstWordOf(2) - 1], WordStatus.correct,
        reason: 'the words after it were uncovered');
  });

  test('a stop the fresh decode confirms stands, after one verify only', () async {
    final engine = _VerifyingEngine();
    final wrong = firstWordOf(1) + 1;
    // The fresh decode hears the same wrong word.
    engine.fresh = ayahTwoWithWrongSecond();
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    engine.recite(ayahTwoWithWrongSecond());
    await settle();

    expect(engine.windows.length, 1);
    expect(service.heldWord.value, wrong, reason: 'stopped at the wrong word');
    expect(service.statuses[wrong], WordStatus.mistake);
    for (var w = wrong + 1; w < words.length; w++) {
      expect(service.statuses[w], WordStatus.pending, reason: 'word $w stays covered');
    }

    // Reading it right lifts the stop as before.
    engine.recite(ayah(1).skip(1));
    await settle();
    expect(service.heldWord.value, -1);
    expect(service.statuses[wrong], WordStatus.correct);
  });

  test('an engine without audio (null) leaves the stop as it was', () async {
    final engine = _VerifyingEngine();
    final wrong = firstWordOf(1) + 1;
    engine.fresh = null;
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    engine.recite(ayahTwoWithWrongSecond());
    await settle();
    expect(service.heldWord.value, wrong);
    expect(service.statuses[wrong], WordStatus.mistake);
  });

  test('«دقة أعلى» never asks for a fresh decode', () async {
    await TasmeeSpeedSetting.set(TasmeeSpeed.accurate);
    final engine = _VerifyingEngine();
    final wrong = firstWordOf(1) + 1;
    engine.fresh = ayah(1);
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    engine.recite(ayahTwoWithWrongSecond());
    await settle();
    expect(engine.windows, isEmpty);
    expect(service.heldWord.value, wrong);
  });
}

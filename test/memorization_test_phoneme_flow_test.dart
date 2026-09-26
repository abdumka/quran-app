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

  /// The microphone hearing voice (a held madd) or going quiet.
  Timer? _voice;
  void voice(bool on) {
    _voice?.cancel();
    _voice = null;
    audioLevel.value = 0;
    if (!on) return;
    var flip = false;
    _voice = Timer.periodic(const Duration(milliseconds: 100), (_) {
      audioLevel.value = (flip = !flip) ? 0.5 : 0.6;
    });
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    _voice?.cancel();
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

  test('half a word with the voice still sounding is not judged yet', () async {
    // A long madd: the recognizer sends the opening of the word, then
    // nothing for over a second while the reciter holds the sound.
    final word = firstWordOf(1) + 1;
    final whole = ayah(1)[1];
    final opening = String.fromCharCodes(whole.runes.take(3));
    final rest = String.fromCharCodes(whole.runes.skip(3));

    final engine = _PhonemeEngine();
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    engine.recite([ayah(1).first, opening]);
    engine.voice(true);
    await settle();
    expect(service.heldWord.value, -1, reason: 'the word is still being said');
    expect(service.statuses[word], WordStatus.pending);

    engine.recite([rest]);
    engine.voice(false);
    await settle();
    expect(service.heldWord.value, -1);
    expect(service.statuses[word], WordStatus.correct);
  });

  test('half a word followed by silence is a mistake, as before', () async {
    final word = firstWordOf(1) + 1;
    final opening = String.fromCharCodes(ayah(1)[1].runes.take(3));

    final engine = _PhonemeEngine();
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    engine.recite([ayah(1).first, opening]);
    await settle();
    expect(service.heldWord.value, word);
    expect(service.statuses[word], WordStatus.mistake);
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

  group('basmala before a surah', () {
    // One token per phoneme, as the sheikh audit hears it.
    const basmala = 'بِسمِللَااهِررَحمَاانِررَحِۦۦم';

    Future<List<PhonemeWord>> pageWords(int page) async =>
        (await PagePhonemeService.forPage(page))!.words;
    List<String> ayahOf(List<PhonemeWord> ws, int index) => [
          for (final w in ws)
            if (w.ayah == index) collapseMadd(w.phon),
        ];

    test('at the top of a page that opens a surah it is not a mistake', () async {
      final ws = await pageWords(151); // 7:1 at the top
      final engine = _PhonemeEngine();
      await service.start(pageNumber: 151, engineOverride: engine, stopPlayback: false);
      engine.recite([basmala.substring(0, 12), basmala.substring(12)]);
      engine.recite(ayahOf(ws, 0));
      await settle();
      expect(service.heldWord.value, -1, reason: 'the basmala was swallowed');
      expect(service.statuses[0], WordStatus.correct);
      expect(service.statuses[3], WordStatus.correct);
    });

    test('without one, the opening is judged as before', () async {
      final ws = await pageWords(151);
      final engine = _PhonemeEngine();
      await service.start(pageNumber: 151, engineOverride: engine, stopPlayback: false);
      engine.recite(ayahOf(ws, 0));
      await settle();
      expect(service.heldWord.value, -1);
      expect(service.statuses[0], WordStatus.correct);
    });

    test('the decision: a basmala, not yet, or something else', () {
      final table = PhonemeCostTable();
      int cut(String s) => MemorizationTestService.basmalaCut(s, table);
      expect(cut('بِس'), 0, reason: 'too little');
      expect(cut('بِسمِللَاا'), 0, reason: 'inside a basmala');
      expect(cut('بِسَبَبِ'), -1, reason: 'starts alike, is another word');
      expect(cut('ءَلَممممصَ'), -1, reason: 'the surah\'s own first word');
      expect(cut(basmala), basmala.length);
      // Slightly off (a dropped sound, a vowel at the end) still counts.
      expect(cut('بِسمِللَاهِررَحمَاانِررَحِۦۦمِ'), greaterThan(0));
      // With the next word glued on, the cut lands at the basmala's end.
      final glued = cut('$basmala' 'كِتَاابُن');
      expect(glued, inInclusiveRange(basmala.length - 1, basmala.length + 1));
    });

    test('in the middle of a page, between two surahs', () async {
      final ws = await pageWords(106); // 4:175 then 5:1
      final engine = _PhonemeEngine();
      await service.start(pageNumber: 106, engineOverride: engine, stopPlayback: false);
      engine.recite(ayahOf(ws, 0));
      await settle();
      engine.recite([basmala]);
      engine.recite(ayahOf(ws, 1).take(4));
      await settle();
      expect(service.heldWord.value, -1);
      final first51 = ws.indexWhere((w) => w.ayah == 1);
      expect(service.statuses[first51], WordStatus.correct);
      expect(service.statuses[first51 + 3], WordStatus.correct);
    });
  });

  test('an extra word between two words holds the word after it', () async {
    final engine = _PhonemeEngine();
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    final second = ayah(1); // الرحمن الرحيم
    final after = firstWordOf(1) + 1;
    engine.recite([second[0], 'قَدڇ', second[1]]); // «الرحمن قد الرحيم»
    engine.recite(ayah(2).take(2));
    await settle();

    expect(service.heldWord.value, after,
        reason: 'the word the extra was said before is held');
    expect(service.statuses[after], WordStatus.mistake);
    expect(service.feedback.value?.message, contains('زدت كلمة'));

    // A tick later the old reading of that word must not lift the hold...
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(service.heldWord.value, after);
    expect(service.statuses[after + 1], WordStatus.pending,
        reason: 'nothing after the held word is uncovered');

    // ...it is a notice: reading on a few words clears it, and the error
    // stays in the journal.
    engine.recite(ayah(2).skip(2).take(2));
    await settle();
    expect(service.heldWord.value, -1);
    expect(service.statuses[after], WordStatus.correct);
    expect(service.statuses[after + 1], WordStatus.correct);
  });

  test('nasal noise between two words is not an extra word', () async {
    final engine = _PhonemeEngine();
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    final second = ayah(1);
    engine.recite([second[0], 'ںںں', second[1]]);
    engine.recite(ayah(2).take(2));
    await settle();
    expect(service.heldWord.value, -1);
  });

  test('a mistake corrected after moving on is still accepted', () async {
    // The owner's 2026-09-26 session: «مالك» for «ملك», then on to «إياك
    // نعبد», then six clean repeats of «ملك يوم الدين» that were never
    // judged, because matching them forward with substitutions was cheaper
    // for the tracker than restarting at the held word.
    final engine = _PhonemeEngine();
    await service.start(pageNumber: 1, engineOverride: engine, stopPlayback: false);
    engine.recite(ayah(0));
    engine.recite(ayah(1));
    final third = ayah(2); // ملك يوم الدين
    final malik = firstWordOf(2);
    engine.recite(['مَاالِكِ', ...third.skip(1)]);
    engine.recite(ayah(3).take(2)); // إياك نعبد
    await settle();
    expect(service.heldWord.value, malik, reason: 'the Hafs reading is held');

    engine.recite(third); // the correction, three words after moving on
    await settle();
    expect(service.heldWord.value, -1, reason: 'the repeat repaired it');
    expect(service.statuses[malik], WordStatus.correct);
  });

  test('repeat ayah at the top of a continued page goes back a page', () async {
    final engine = _PhonemeEngine();
    await service.start(pageNumber: 2, engineOverride: engine, stopPlayback: false);
    service.continuedFromForTest = 1;
    final flips = <int>[];
    void onFlip() => flips.add(service.pageAdvanced.value);
    service.pageAdvanced.addListener(onFlip);
    MemorizationTestService.engineFactoryForTest = _PhonemeEngine.new;
    try {
      service.repeatAyah();
      await Future<void>.delayed(const Duration(milliseconds: 800));
    } finally {
      MemorizationTestService.engineFactoryForTest = null;
      service.pageAdvanced.removeListener(onFlip);
    }
    expect(flips, contains(1), reason: 'the view was told to go back');
    expect(service.activePage, 1);
    expect(service.status.value, MemorizationTestStatus.listening);
    // Only the last ayah of page 1 is under test; the rest is shown.
    final last = firstWordOf(6);
    expect(service.statuses[last - 1], WordStatus.correct);
    expect(service.statuses[last], WordStatus.pending);
  });
}

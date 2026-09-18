import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';

/// Parity test against the Python port (`tasmee_work/zipformer/
/// eval_session.py`) replayed on the first 80 s of the owner's p534
/// session with the Qalun asset: same tokens in, same verdicts and cursor out.
void main() {
  final fixture = json.decode(
    File('test/fixtures/phoneme_tracker_p534.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  PhonemeReference reference() {
    final words = <PhonemeWord>[];
    final raw = fixture['words'] as List<dynamic>;
    final counts = <int, int>{};
    for (final w in raw) {
      final m = w as Map<String, dynamic>;
      counts[m['ayah'] as int] = (counts[m['ayah'] as int] ?? 0) + 1;
    }
    final seen = <int, int>{};
    for (final w in raw) {
      final m = w as Map<String, dynamic>;
      final ayah = m['ayah'] as int;
      final idx = seen[ayah] ?? 0;
      seen[ayah] = idx + 1;
      words.add(PhonemeWord(
        phon: m['phon'] as String,
        text: m['qalun'] as String,
        ayah: ayah,
        wordInAyah: idx,
        ayahWords: counts[ayah]!,
        tanween: (m['tanween'] as String?) ?? '',
        taMarbuta: (m['taMarbuta'] as bool?) ?? false,
        hafsAlt: (m['hafsAlt'] as String?) ?? '',
        wasl: (m['wasl'] as bool?) ?? false,
      ));
    }
    return PhonemeReference(words, PhonemeCostTable());
  }

  test('cost table matches the reference costs', () {
    final t = PhonemeCostTable();
    expect(t.cost(t.id('ء'), t.id('ء')), 0);
    expect(t.cost(t.id('ۦ'), t.id('ي')), 0);
    expect(t.cost(t.id('ء'), t.id('ا')), closeTo(0.1, 1e-6));
    expect(t.cost(t.id('َ'), t.id('ُ')), closeTo(0.1, 1e-6));
    expect(t.cost(t.id('ذ'), t.id('د')), closeTo(0.25, 1e-6));
    expect(t.cost(t.id('ب'), t.id('ك')), 1);
    expect(t.cost(t.id('ب'), t.id('َ')), 1);
  });

  test('collapseMadd shortens runs of three or more to two', () {
    expect(collapseMadd('لعَاالَمِۦۦۦۦن'), 'لعَاالَمِۦۦن');
    expect(collapseMadd('ضضَااااااللِۦۦۦۦن'), 'ضضَااللِۦۦن');
    expect(collapseMadd('كَاانَ'), 'كَاانَ');
  });

  test('replaying the p534 token stream reproduces the Python verdicts', () {
    final ref = reference();
    final tracker = PhonemeTracker(ref);
    final tracer = VerdictTracer(tracker);
    final tokens = (fixture['tokens'] as List<dynamic>).cast<String>();
    final times = (fixture['timestamps'] as List<dynamic>).cast<num>();
    final chars = <HeardChar>[];
    for (var k = 0; k < tokens.length; k++) {
      final frame = (times[k] * 25).round();
      for (final r in collapseMadd(tokens[k]).runes) {
        chars.add(HeardChar(String.fromCharCode(r), frame));
      }
    }
    tracker.feed(chars);

    expect(tracker.cursorCell, fixture['cursorCell']);
    expect(tracker.cursorLocalWord, fixture['cursorWord']);
    expect(tracker.cursorCost, closeTo((fixture['cursorCost'] as num).toDouble(), 1e-2));
    final tail = (fixture['trailTail'] as List<dynamic>).cast<int>();
    expect(tracker.trail.sublist(tracker.trail.length - tail.length), tail);

    final verdicts = {
      for (final v in tracer.verdicts(settled: true)) v.word: v,
    };
    final expected = fixture['verdicts'] as Map<String, dynamic>;
    expect(verdicts.length, expected.length);
    for (final e in expected.entries) {
      final w = int.parse(e.key);
      final want = e.value as List<dynamic>;
      final got = verdicts[w];
      expect(got, isNotNull, reason: 'word $w missing');
      expect(got!.state.name, want[0], reason: 'word $w state');
      expect(got.distance, closeTo((want[1] as num).toDouble(), 2e-3), reason: 'word $w distance');
      expect(got.reason, (want.length > 2 ? want[2] as String : ''), reason: 'word $w reason');
    }
  });

  group('verdict rules', () {
    PhonemeReference fatihah3() => PhonemeReference(const [
          PhonemeWord(phon: 'مَلِكِ', text: 'مَلِكِ', ayah: 0, wordInAyah: 0, ayahWords: 3, hafsAlt: 'مَاالِكِ'),
          PhonemeWord(phon: 'يَومِ', text: 'يَوْمِ', ayah: 0, wordInAyah: 1, ayahWords: 3),
          PhonemeWord(phon: 'ددِۦۦن', text: 'ٱلدِّينِ', ayah: 0, wordInAyah: 2, ayahWords: 3, wasl: true),
          PhonemeWord(phon: 'ءِييَااكَ', text: 'إِيَّاكَ', ayah: 1, wordInAyah: 0, ayahWords: 2),
          PhonemeWord(phon: 'نَعبُدُ', text: 'نَعْبُدُ', ayah: 1, wordInAyah: 1, ayahWords: 2),
        ], PhonemeCostTable());

    List<HeardChar> say(String phonemes, {int startFrame = 0}) {
      var f = startFrame;
      return [
        for (final r in phonemes.runes) HeardChar(String.fromCharCode(r), f += 2),
      ];
    }

    test('the Hafs reading of a Qalun-specific word is wrong, not unsure', () {
      final tracker = PhonemeTracker(fatihah3());
      final tracer = VerdictTracer(tracker);
      tracker.feed(say('مَاالِكِيَومِددِۦۦن'));
      final v = {for (final x in tracer.verdicts(settled: true)) x.word: x};
      expect(v[0]!.state, VerdictState.wrong);
      expect(v[0]!.reason, 'hafs');
      expect(v[1]!.state, VerdictState.ok);
      expect(v[2]!.state, VerdictState.ok);
    });

    test('the Qalun reading of the same word is ok', () {
      final tracker = PhonemeTracker(fatihah3());
      final tracer = VerdictTracer(tracker);
      tracker.feed(say('مَلِكِيَومِددِۦۦن'));
      final v = {for (final x in tracer.verdicts(settled: true)) x.word: x};
      expect(v[0]!.state, VerdictState.ok);
      expect(v[0]!.reason, '');
    });

    test('a wasl-initial word connected to the previous one keeps its ok', () {
      final tracker = PhonemeTracker(PhonemeReference(const [
        PhonemeWord(phon: 'ررَحِۦۦم', text: 'ٱلرَّحِيمِ', ayah: 0, wordInAyah: 0, ayahWords: 1),
        PhonemeWord(phon: 'ءَررَحمَاانِ', text: 'ٱلرَّحْمَٰنِ', ayah: 1, wordInAyah: 0, ayahWords: 2, wasl: true),
        PhonemeWord(phon: 'ررَحِۦۦم', text: 'ٱلرَّحِيمِ', ayah: 1, wordInAyah: 1, ayahWords: 2),
      ], PhonemeCostTable()));
      final tracer = VerdictTracer(tracker);
      // Connected recitation: no hamza before الرحمن.
      tracker.feed(say('ررَحِۦۦمِررَحمَاانِررَحِۦۦم'));
      final v = {for (final x in tracer.verdicts(settled: true)) x.word: x};
      expect(v[1]!.state, VerdictState.ok, reason: 'distance ${v[1]!.distance}');
    });

    test('a restart re-judges the words the reciter went back to', () {
      final tracker = PhonemeTracker(fatihah3());
      final tracer = VerdictTracer(tracker);
      // ملك يوم + a wrong third word, then the ayah again from its start,
      // correctly, and on into the next ayah.
      tracker.feed(say('مَلِكِيَومِبَبَبَ'));
      var v = {for (final x in tracer.verdicts(settled: true)) x.word: x};
      expect(v[2]!.state, VerdictState.wrong, reason: 'setup: the slip');
      tracker.feed(say('مَلِكِيَومِددِۦۦنءِييَااكَنَعبُدُ', startFrame: 100));
      v = {for (final x in tracer.verdicts(settled: true)) x.word: x};
      // The restart costs its repeat penalty, so the DP only switches to
      // the restarted path a couple of words in; the verdicts must still
      // come from the restart's first phoneme, not from where it overtook.
      for (var w = 0; w < 5; w++) {
        expect(v[w]!.state, VerdictState.ok,
            reason: 'word $w ${v[w]!.state} heard ${v[w]!.heard}');
      }
      expect(v[2]!.heard, 'ددِۦۦن');
    });

    test('a Hafs final vowel past the span still flags the habit', () {
      PhonemeReference yaghfir() => PhonemeReference(const [
            PhonemeWord(phon: 'فَيَغفِر', text: 'فَيَغْفِرْ', ayah: 0, wordInAyah: 0, ayahWords: 3, hafsAlt: 'فَيَغفِرُ'),
            PhonemeWord(phon: 'لِمَيي', text: 'لِمَنْ', ayah: 0, wordInAyah: 1, ayahWords: 3),
            PhonemeWord(phon: 'يَشَااءُ', text: 'يَشَآءُ', ayah: 0, wordInAyah: 2, ayahWords: 3),
          ], PhonemeCostTable());
      // Hafs: فَيَغْفِرُ. The damma is an insertion the aligner leaves
      // between the words, outside this word's span.
      var tracker = PhonemeTracker(yaghfir());
      var tracer = VerdictTracer(tracker);
      tracker.feed(say('فَيَغفِرُلِمَيييَشَااءُ'));
      var v = {for (final x in tracer.verdicts(settled: true)) x.word: x};
      expect(v[0]!.state, VerdictState.wrong);
      expect(v[0]!.reason, 'hafs');
      expect(v[1]!.state, VerdictState.ok);
      // Qalun: فَيَغْفِرْ, no vowel.
      tracker = PhonemeTracker(yaghfir());
      tracer = VerdictTracer(tracker);
      tracker.feed(say('فَيَغفِرلِمَيييَشَااءُ'));
      v = {for (final x in tracer.verdicts(settled: true)) x.word: x};
      expect(v[0]!.state, VerdictState.ok);
      expect(v[0]!.reason, '');
    });
  });

  test('phonemesToArabic renders heard phonemes readably', () {
    expect(phonemesToArabic('مَاالِكِ'), 'مَالِكِ');
    expect(phonemesToArabic('يُخَاادِعُۥۥنَ'), 'يُخَادِعُونَ');
    expect(phonemesToArabic('لَقُرءَاانُںںں'), 'لَقُرءَانُن');
    expect(phonemesToArabic('ءِننننَهُۥۥ'), 'ءِنَهُو');
  });

  test('pausal form: tanween word stopped on', () {
    const s = PhonemeWord(
      phon: 'كَاانَ',
      text: 'كَانَ',
      ayah: 0,
      wordInAyah: 0,
      ayahWords: 3,
    );
    expect(pausalPhonemes(s.phon, s, false), 'كَاان');
    expect(pausalPhonemes(s.phon, s, true), isNull);
  });
}

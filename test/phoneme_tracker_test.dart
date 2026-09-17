import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';

/// Parity test against the Python port (`tasmee_work/zipformer/
/// eval_session.py`) replayed on the first 80 s of the owner's p534
/// session: same tokens in, same verdicts and cursor out.
void main() {
  final fixture = json.decode(
    File('test/fixtures/phoneme_tracker_p534.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  PhonemeReference reference() {
    final words = <PhonemeWord>[];
    final raw = fixture['words'] as List<dynamic>;
    // Reconstruct per-ayah positions from the ayah ids.
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
    }
  });

  test('pausal form: tanween word stopped on', () {
    const w = PhonemeWord(
      phon: 'كَرِۦۦم', // كريمٞ (tanween damm) written without the noon
      text: 'كَرِيمٞ',
      ayah: 0,
      wordInAyah: 0,
      ayahWords: 2,
      tanween: 'ٌ',
    );
    // Stem ends in the mim, not the tanween vowel: no distinct pausal form.
    expect(pausalPhonemes(w.phon, w, false), isNull);
    const v = PhonemeWord(
      phon: 'عَاادَنِ',
      text: 'عَادًا',
      ayah: 0,
      wordInAyah: 0,
      ayahWords: 3,
      tanween: 'ً',
    );
    expect(pausalPhonemes(v.phon, v, false), isNull);
    const u = PhonemeWord(
      phon: 'بَصِۦۦرَاا',
      text: 'بَصِيرًا',
      ayah: 0,
      wordInAyah: 1,
      ayahWords: 3,
    );
    expect(pausalPhonemes(u.phon, u, false), isNull);
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

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';

/// Parity with the Python port on a real phone log (p130, 2026-09-20 06:51,
/// cut at the minute mark), replayed from its logged phonemes against the
/// app's own asset words: look-alike alternatives, accepted forms and the
/// substitution rules included. Regenerate with
/// `tasmee_work/zipformer/make_fixture2.py --write`.
void main() {
  test('replaying the p130 phone log reproduces the Python verdicts', () {
    final fx = json.decode(
      File('test/fixtures/phoneme_tracker_p130.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final words = [
      for (final w in (fx['words'] as List<dynamic>).cast<Map<String, dynamic>>())
        PhonemeWord(
          phon: w['phon'] as String,
          text: w['text'] as String,
          ayah: w['ayah'] as int,
          wordInAyah: w['wordInAyah'] as int,
          ayahWords: w['ayahWords'] as int,
          tanween: w['tanween'] as String,
          taMarbuta: w['ta'] as bool,
          hafsAlt: w['hafsAlt'] as String,
          wasl: w['wasl'] as bool,
          alts: (w['alts'] as List<dynamic>).cast<String>(),
          accept: (w['accept'] as List<dynamic>).cast<String>(),
        ),
    ];
    final tracker = PhonemeTracker(PhonemeReference(words, PhonemeCostTable()));
    final lexicon = PhonemeLexicon(
      (json.decode(File('assets/data/phoneme_lexicon.json').readAsStringSync())
              as List<dynamic>)
          .cast<String>(),
    );
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    final tokens = (fx['tokens'] as List<dynamic>).cast<String>();
    final frames = (fx['frames'] as List<dynamic>).cast<int>();
    for (var k = 0; k < tokens.length; k++) {
      for (final r in collapseMadd(tokens[k]).runes) {
        tracker.feedOne(HeardChar(String.fromCharCode(r), frames[k]));
      }
    }
    expect(tracker.cursorCell, fx['cursorCell']);
    expect(tracker.cursorLocalWord, fx['cursorWord']);
    expect(tracker.cursorCost, closeTo((fx['cursorCost'] as num).toDouble(), 1e-2));

    final got = {for (final v in tracer.verdicts(settled: true)) v.word: v};
    final want = fx['verdicts'] as Map<String, dynamic>;
    expect(got.length, want.length);
    var substitutions = 0;
    for (final e in want.entries) {
      final w = int.parse(e.key);
      final exp = e.value as List<dynamic>;
      final v = got[w];
      expect(v, isNotNull, reason: 'word $w missing');
      expect(v!.state.name, exp[0], reason: 'word $w state (heard ${v.heard})');
      expect(v.distance, closeTo((exp[1] as num).toDouble(), 2e-3), reason: 'word $w distance');
      expect(v.reason, exp[2], reason: 'word $w reason');
      if (v.reason == 'word') substitutions++;
    }
    // نحشرهم read as يحشرهم: one letter of ten, inside the ok band.
    expect(substitutions, greaterThanOrEqualTo(1));
  });
}

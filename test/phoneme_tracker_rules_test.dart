import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';

/// Rules added after the 2026-09-20 sessions: a fixed start word, the barrier
/// of a hard stop, substitutions inside the ok band, look-alike (mutashabih)
/// alternatives, and accepted forms.
void main() {
  List<HeardChar> say(String phonemes, {int startFrame = 0}) {
    var f = startFrame;
    return [
      for (final r in phonemes.runes) HeardChar(String.fromCharCode(r), f += 2),
    ];
  }

  // Two ayahs: وَيَومَ نَحشُرُهُم جَمِيعَن | ثُمَّ نَقُولُ
  PhonemeReference hashr({
    List<String> alts = const [],
    List<String> accept = const [],
  }) =>
      PhonemeReference([
        const PhonemeWord(phon: 'وَيَومَ', text: 'وَيَوْمَ', ayah: 0, wordInAyah: 0, ayahWords: 3),
        PhonemeWord(
          phon: 'نَحشُرُهُم',
          text: 'نَحْشُرُهُمْ',
          ayah: 0,
          wordInAyah: 1,
          ayahWords: 3,
          alts: alts,
          accept: accept,
        ),
        const PhonemeWord(phon: 'جَمِۦۦعَن', text: 'جَمِيعاً', ayah: 0, wordInAyah: 2, ayahWords: 3),
        const PhonemeWord(phon: 'ثُممممَ', text: 'ثُمَّ', ayah: 1, wordInAyah: 0, ayahWords: 2),
        const PhonemeWord(phon: 'نَقُۥۥلُ', text: 'نَقُولُ', ayah: 1, wordInAyah: 1, ayahWords: 2),
      ], PhonemeCostTable());

  Map<int, WordVerdict> verdictsOf(VerdictTracer tracer) =>
      {for (final v in tracer.verdicts(settled: true)) v.word: v};

  test('exactly another Quran word inside the ok band is a substitution', () {
    final lexicon = PhonemeLexicon(['يَحشُرُهُم', 'نَحشُرُهُم', 'وَيَومَ']);
    final tracker = PhonemeTracker(hashr());
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    tracker.feed(say('وَيَومَيَحشُرُهُمجَمِۦۦعَن'));
    final v = verdictsOf(tracer);
    expect(v[1]!.distance, lessThanOrEqualTo(0.15), reason: 'one letter of ten');
    expect(v[1]!.state, VerdictState.wrong);
    expect(v[1]!.reason, 'word');
    expect(v[0]!.state, VerdictState.ok);
    expect(v[2]!.state, VerdictState.ok);
  });

  test('the expected word itself stays ok with the same lexicon', () {
    final lexicon = PhonemeLexicon(['يَحشُرُهُم', 'نَحشُرُهُم', 'وَيَومَ']);
    final tracker = PhonemeTracker(hashr());
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    tracker.feed(say('وَيَومَنَحشُرُهُمجَمِۦۦعَن'));
    expect(verdictsOf(tracer)[1]!.state, VerdictState.ok);
  });

  test('a look-alike alternative is flagged without any lexicon', () {
    final tracker = PhonemeTracker(hashr(alts: const ['يَحشُرُهُم']));
    final tracer = VerdictTracer(tracker);
    tracker.feed(say('وَيَومَيَحشُرُهُمجَمِۦۦعَن'));
    final v = verdictsOf(tracer);
    expect(v[1]!.state, VerdictState.wrong);
    expect(v[1]!.reason, 'word');
    expect(v[1]!.heard, 'يَحشُرُهُم');
  });

  test('an accepted form is ok and beats the substitution rules', () {
    final lexicon = PhonemeLexicon(['يَحشُرُهُم', 'نَحشُرُهُم']);
    final tracker = PhonemeTracker(hashr(accept: const ['يَحشُرُهُم']));
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    tracker.feed(say('وَيَومَيَحشُرُهُمجَمِۦۦعَن'));
    final v = verdictsOf(tracer);
    expect(v[1]!.state, VerdictState.ok);
    expect(v[1]!.reason, '');
  });

  test('startWord: the recitation can only begin on that word', () {
    final reference = hashr();
    final tracker = PhonemeTracker(reference, startAnywhere: false, startWord: 3);
    final tracer = VerdictTracer(tracker);
    tracker.feed(say('ثُممممَنَقُۥۥلُ'));
    final v = verdictsOf(tracer);
    expect(tracker.cursorWord, 4);
    expect(v[3]!.state, VerdictState.ok);
    expect(v[4]!.state, VerdictState.ok);
    expect(v.containsKey(0), isFalse, reason: 'nothing before the start word is judged');
  });

  test('maxCell bars the cursor from leaving the ayah of a hard stop', () {
    final reference = hashr();
    final tracker = PhonemeTracker(reference, startAnywhere: false, startWord: 0)
      ..maxCell = reference.wordStart[3]; // end of the first ayah
    // The reciter reads the SECOND ayah, again and again.
    tracker.feed(say('ثُممممَنَقُۥۥلُثُممممَنَقُۥۥلُثُممممَنَقُۥۥلُ'));
    expect(tracker.cursorCell, lessThanOrEqualTo(reference.wordStart[3]));
    // Going back to the held ayah is followed as usual, and once the barrier
    // is lifted the next ayah too.
    tracker.maxCell = null;
    tracker.feed(say('وَيَومَنَحشُرُهُمجَمِۦۦعَنثُممممَنَقُۥۥلُ', startFrame: 400));
    final v = verdictsOf(VerdictTracer(tracker));
    for (final w in [0, 1, 2, 3, 4]) {
      expect(v[w]!.state, VerdictState.ok, reason: 'word $w heard ${v[w]!.heard}');
    }
  });

  test('much more heard than the word holds is wrong, not unsure', () {
    // فَإِذَا expected, أَخَذْنَاهُم said over it.
    final reference = PhonemeReference(const [
      PhonemeWord(phon: 'بَغتَتَن', text: 'بَغْتَةً', ayah: 0, wordInAyah: 0, ayahWords: 3),
      PhonemeWord(phon: 'فَءِذَاا', text: 'فَإِذَا', ayah: 0, wordInAyah: 1, ayahWords: 3),
      PhonemeWord(phon: 'هُم', text: 'هُم', ayah: 0, wordInAyah: 2, ayahWords: 3),
    ], PhonemeCostTable());
    final tracker = PhonemeTracker(reference);
    final tracer = VerdictTracer(tracker);
    tracker.feed(say('بَغتَتَنفَءَخَذتنَااهُم'));
    final v = verdictsOf(tracer);
    expect(v[1]!.state, isNot(VerdictState.ok));
    expect(v[1]!.state, isNot(VerdictState.unsure), reason: 'd=${v[1]!.distance} heard=${v[1]!.heard}');
  });
}

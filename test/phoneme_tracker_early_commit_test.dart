import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';

/// `TrackerConfig.earlyCommit` (2026-10-06): a word heard exactly is committed
/// as soon as the next word has begun, instead of after `commitDwell` (6)
/// more phonemes, unless something could still extend it.
void main() {
  List<HeardChar> say(String phonemes, {int startFrame = 0}) {
    var f = startFrame;
    return [
      for (final r in phonemes.runes) HeardChar(String.fromCharCode(r), f += 2),
    ];
  }

  // وَيَومَ نَحشُرُهُم جَمِيعَن | ثُمَّ نَقُولُ
  PhonemeReference hashr({String hafsAlt = ''}) => PhonemeReference([
        PhonemeWord(
          phon: 'وَيَومَ',
          text: 'وَيَوْمَ',
          ayah: 0,
          wordInAyah: 0,
          ayahWords: 3,
          hafsAlt: hafsAlt,
        ),
        const PhonemeWord(phon: 'نَحشُرُهُم', text: 'نَحْشُرُهُمْ', ayah: 0, wordInAyah: 1, ayahWords: 3),
        const PhonemeWord(phon: 'جَمِۦۦعَن', text: 'جَمِيعاً', ayah: 0, wordInAyah: 2, ayahWords: 3),
        const PhonemeWord(phon: 'ثُممممَ', text: 'ثُمَّ', ayah: 1, wordInAyah: 0, ayahWords: 2),
        const PhonemeWord(phon: 'نَقُۥۥلُ', text: 'نَقُولُ', ayah: 1, wordInAyah: 1, ayahWords: 2),
      ], PhonemeCostTable());

  Map<int, WordVerdict> live(VerdictTracer tracer) =>
      {for (final v in tracer.verdicts(settled: false)) v.word: v};

  final lexicon = PhonemeLexicon(['وَيَومَ', 'وَيَومَهُم', 'نَحشُرُهُم', 'جَمِۦۦعَن', 'ثُممممَ', 'نَقُۥۥلُ']);

  test('an exact word is committed once the next word has begun', () {
    final tracker = PhonemeTracker(hashr());
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    // Two words exactly, then only the first syllable of the third: the
    // second word's span ends 2 phonemes before the end, well inside the
    // dwell of 6.
    tracker.feed(say('وَيَومَنَحشُرُهُمجَ'));
    final v = live(tracer);
    expect(v[1]!.state, VerdictState.ok, reason: 'exact, nothing extends it');
    expect(v[0]!.state, VerdictState.ok);
    expect(v[2]?.state ?? VerdictState.pending, VerdictState.pending, reason: 'the cursor word waits');
  });

  test('the same stream without earlyCommit still waits for the dwell', () {
    final tracker = PhonemeTracker(hashr());
    final tracer = VerdictTracer(
      tracker,
      cfg: const TrackerConfig(earlyCommit: false),
      lexicon: lexicon,
    );
    tracker.feed(say('وَيَومَنَحشُرُهُمجَ'));
    expect(live(tracer)[1]!.state, VerdictState.pending);
  });

  test('a word that a longer lexicon word could continue keeps waiting', () {
    final tracker = PhonemeTracker(hashr());
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    // وَيَومَ heard exactly, but what follows (هُ) is how وَيَومَهُم goes on:
    // the reciter may be saying the longer word.
    tracker.feed(say('وَيَومَهُ'));
    final v0 = live(tracer)[0];
    expect(v0?.state ?? VerdictState.pending, VerdictState.pending);
    // Once the following sounds clearly belong to the next word it commits.
    tracker.feed(say('نَحشُرُهُمجَ', startFrame: 40));
    expect(live(tracer)[0]!.state, VerdictState.ok);
  });

  test('a word whose Hafs form extends it keeps the full dwell', () {
    // Qalun فَيَغْفِر-style: the Hafs alternative is the Qalun form plus a
    // final vowel, so the exact Qalun form is not yet proof of a Qalun reading.
    final tracker = PhonemeTracker(hashr(hafsAlt: 'وَيَومَُ'));
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    tracker.feed(say('وَيَومَنَحشُ'));
    final v0 = live(tracer)[0];
    expect(v0?.state ?? VerdictState.pending, VerdictState.pending);
  });

  test('without a lexicon the local checks alone decide', () {
    final tracker = PhonemeTracker(hashr());
    final tracer = VerdictTracer(tracker);
    tracker.feed(say('وَيَومَنَحشُرُهُمجَ'));
    expect(live(tracer)[1]!.state, VerdictState.ok);
  });

  test('PhonemeLexicon.extendsEntry', () {
    expect(lexicon.extendsEntry('وَيَومَ'), isTrue, reason: 'وَيَومَهُم begins with it');
    expect(lexicon.extendsEntry('وَيَومَهُ'), isTrue);
    expect(lexicon.extendsEntry('وَيَومَهُم'), isFalse, reason: 'a whole entry, nothing longer');
    expect(lexicon.extendsEntry('نَحشُرُهُم'), isFalse);
    expect(lexicon.extendsEntry('وَيَومَنَ'), isFalse);
  });
}

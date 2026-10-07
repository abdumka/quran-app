import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';

/// Second half of `TrackerConfig.earlyCommit` (2026-10-06): the cursor word
/// itself commits the moment it is heard exactly and complete, when no word
/// in the lexicon begins with it, so the reveal does not wait for the next
/// word to start. Replay of 256 sessions: commit lag median 0.64 -> 0.52 s,
/// words revealed then called wrong +2.
void main() {
  List<HeardChar> say(String phonemes, {int startFrame = 0}) {
    var f = startFrame;
    return [
      for (final r in phonemes.runes) HeardChar(String.fromCharCode(r), f += 2),
    ];
  }

  // وَيَومَ نَحشُرُهُم جَمِيعَن | ثُمَّ نَقُولُ
  final reference = PhonemeReference([
    const PhonemeWord(phon: 'وَيَومَ', text: 'وَيَوْمَ', ayah: 0, wordInAyah: 0, ayahWords: 3),
    const PhonemeWord(phon: 'نَحشُرُهُم', text: 'نَحْشُرُهُمْ', ayah: 0, wordInAyah: 1, ayahWords: 3),
    const PhonemeWord(phon: 'جَمِۦۦعَن', text: 'جَمِيعاً', ayah: 0, wordInAyah: 2, ayahWords: 3),
    const PhonemeWord(phon: 'ثُممممَ', text: 'ثُمَّ', ayah: 1, wordInAyah: 0, ayahWords: 2),
    const PhonemeWord(phon: 'نَقُۥۥلُ', text: 'نَقُولُ', ayah: 1, wordInAyah: 1, ayahWords: 2),
  ], PhonemeCostTable());
  final lexicon = PhonemeLexicon(['وَيَومَ', 'وَيَومَهُم', 'نَحشُرُهُم', 'جَمِۦۦعَن', 'ثُممممَ', 'نَقُۥۥلُ']);

  Map<int, WordVerdict> live(VerdictTracer tracer) =>
      {for (final v in tracer.verdicts(settled: false)) v.word: v};

  test('the cursor word commits as soon as it is complete when nothing extends it', () {
    final tracker = PhonemeTracker(reference);
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    tracker.feed(say('وَيَومَنَحشُرُهُم'));
    expect(tracker.cursorWord, 1, reason: 'the DP is still on the second word');
    expect(live(tracer)[1]!.state, VerdictState.ok);
  });

  test('a cursor word that a longer word begins with keeps waiting', () {
    final tracker = PhonemeTracker(reference);
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    tracker.feed(say('وَيَومَ'));
    expect(live(tracer)[0]?.state ?? VerdictState.pending, VerdictState.pending);
  });

  test('without a lexicon the cursor word waits for the next word', () {
    final tracker = PhonemeTracker(reference);
    final tracer = VerdictTracer(tracker);
    tracker.feed(say('وَيَومَنَحشُرُهُم'));
    expect(live(tracer)[1]?.state ?? VerdictState.pending, VerdictState.pending);
  });
}

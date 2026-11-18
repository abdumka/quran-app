import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';

/// `TrackerConfig.finalMadd` (2026-11-10): on p206 the owner read «يتخلّفوا»
/// right and the model ended the word on its short vowel, «يَتَخَللَفُ». That
/// is 0.154 from the word, just past the ok band, and the dictionary check
/// then named the nearest Quran word: "you read «يتكلّم»". Same on p78 with
/// «اليتامى» heard «اليتامَ».
void main() {
  List<HeardChar> say(String phonemes) {
    var f = 0;
    return [for (final r in phonemes.runes) HeardChar(String.fromCharCode(r), f += 2)];
  }

  // فَمَا يَتَخَلَّفُوا عَن رَسُولِهِ
  final reference = PhonemeReference([
    const PhonemeWord(phon: 'فَمَاا', text: 'فَمَا', ayah: 0, wordInAyah: 0, ayahWords: 4),
    const PhonemeWord(phon: 'يَتَخَللَفُۥۥ', text: 'يَتَخَلَّفُواْ', ayah: 0, wordInAyah: 1, ayahWords: 4),
    const PhonemeWord(phon: 'عَن', text: 'عَن', ayah: 0, wordInAyah: 2, ayahWords: 4),
    const PhonemeWord(phon: 'رَسُۥۥلِهِۦۦ', text: 'رَسُولِهِۦ', ayah: 0, wordInAyah: 3, ayahWords: 4),
  ], PhonemeCostTable());
  final lexicon = PhonemeLexicon(['فَمَاا', 'يَتَخَللَفُۥۥ', 'يَتَكَللَمُ', 'عَن', 'رَسُۥۥلِهِۦۦ']);

  WordVerdict judge(String word1, {TrackerConfig cfg = const TrackerConfig()}) {
    final tracker = PhonemeTracker(reference);
    final tracer = VerdictTracer(tracker, cfg: cfg, lexicon: lexicon);
    tracker.feed(say('فَمَاا$word1' 'عَن' 'رَسُۥۥلِهِۦۦ'));
    return tracer.verdicts(settled: true).firstWhere((v) => v.word == 1);
  }

  test('the word without its final long vowel is not named as another word', () {
    final v = judge('يَتَخَللَفُ');
    expect(v.state, VerdictState.unsure);
    expect(v.reason, '');
  });

  test('without the rule the nearest dictionary word was named', () {
    final v = judge('يَتَخَللَفُ', cfg: const TrackerConfig(finalMadd: false));
    expect(v.state, VerdictState.wrong);
    expect(v.heard, 'يَتَكَللَمُ');
  });

  test('another word said in its place is still caught', () {
    final v = judge('يَتَكَللَمُ');
    expect(v.state, VerdictState.wrong);
    expect(v.reason, 'word');
  });

  test('droppedFinalMadd covers only the final ا، و، ي', () {
    expect(droppedFinalMadd('يَتَخَللَفُ', 'يَتَخَللَفُۥۥ', false), isTrue);
    expect(droppedFinalMadd('ليَتَاامَ', 'ليَتَاامَاا', true), isTrue);
    expect(droppedFinalMadd('فِ', 'فِۦۦ', false), isTrue);
    // a letter missing, not a long vowel
    expect(droppedFinalMadd('قَاا', 'قَاالَ', false), isFalse);
    // a long vowel missing inside the word
    expect(droppedFinalMadd('قَلَ', 'قَاالَ', false), isFalse);
  });
}

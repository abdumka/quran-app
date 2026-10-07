import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';

/// `TrackerConfig.orphanVowel` (2026-10-06): the owner read «إنك من المرسلين»
/// for «إنك لمن المرسلين» on p440 and the app let it pass. The model wrote the
/// dropped lam's vowel, «َمِنَ», which is 0.167 from «لَمِنَ» (unsure) and too
/// far from the lexicon word «مِنَ» for the substitution check to find it.
void main() {
  List<HeardChar> say(String phonemes, {int startFrame = 0}) {
    var f = startFrame;
    return [
      for (final r in phonemes.runes) HeardChar(String.fromCharCode(r), f += 2),
    ];
  }

  // إِنَّكَ لَمِنَ ٱلْمُرْسَلِينَ | عَلَىٰ صِرَٰطٍ
  final reference = PhonemeReference([
    const PhonemeWord(phon: 'ءِننننَكَ', text: 'إِنَّكَ', ayah: 0, wordInAyah: 0, ayahWords: 3),
    const PhonemeWord(phon: 'لَمِنَ', text: 'لَمِنَ', ayah: 0, wordInAyah: 1, ayahWords: 3),
    const PhonemeWord(phon: 'لمُرسَلِۦۦن', text: 'ٱلْمُرْسَلِينَ', ayah: 0, wordInAyah: 2, ayahWords: 3, wasl: true),
    const PhonemeWord(phon: 'عَلَاا', text: 'عَلَىٰ', ayah: 1, wordInAyah: 0, ayahWords: 2),
    const PhonemeWord(phon: 'صِرَااطِن', text: 'صِرَٰطٍ', ayah: 1, wordInAyah: 1, ayahWords: 2),
  ], PhonemeCostTable());
  final lexicon = PhonemeLexicon(['ءِننننَكَ', 'لَمِنَ', 'مِنَ', 'مِن', 'لمُرسَلِۦۦن', 'عَلَاا', 'صِرَااطِن']);

  Map<int, WordVerdict> settled(VerdictTracer tracer) =>
      {for (final v in tracer.verdicts(settled: true)) v.word: v};

  test('«من» heard with a stray leading vowel for «لمن» is a substitution', () {
    final tracker = PhonemeTracker(reference);
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    tracker.feed(say('ءِننننَكَ' 'َمِنَ' 'لمُرسَلِۦۦن' 'عَلَاا' 'صِرَااطِن'));
    final v = settled(tracer)[1]!;
    expect(v.state, VerdictState.wrong);
    expect(v.reason, 'word');
    expect(v.heard, 'مِنَ');
  });

  test('without the rule the same reading passes as unsure', () {
    final tracker = PhonemeTracker(reference);
    final tracer = VerdictTracer(
      tracker,
      cfg: const TrackerConfig(orphanVowel: false),
      lexicon: lexicon,
    );
    tracker.feed(say('ءِننننَكَ' 'َمِنَ' 'لمُرسَلِۦۦن' 'عَلَاا' 'صِرَااطِن'));
    expect(settled(tracer)[1]!.state, VerdictState.unsure);
  });

  test('the word itself read correctly stays ok', () {
    final tracker = PhonemeTracker(reference);
    final tracer = VerdictTracer(tracker, lexicon: lexicon);
    tracker.feed(say('ءِننننَكَ' 'لَمِنَ' 'لمُرسَلِۦۦن' 'عَلَاا' 'صِرَااطِن'));
    expect(settled(tracer)[1]!.state, VerdictState.ok);
  });
}

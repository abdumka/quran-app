// Regression test tying QuranWordAligner to real data: the exact Al-Fatihah
// expected words from assets/data/output.json, fed the *actual* recognized
// output (verbatim, including its own spelling conventions) that
// tarteel-ai/whisper-base-ar-quran produced for real Qaloon reciter audio
// (Al-Naihi) during this feature's go/no-go feasibility spike. This is the
// same evidence that justified building the feature without a
// Qaloon-specific acoustic model -- captured here as a lasting regression
// test rather than a one-off script result.
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';

void main() {
  test('a real Quran-tuned Whisper model\'s output for real Qaloon Al-Fatihah audio resolves every word to correct, with no mistakes/skips', () {
    final expectedWords = [
        'اِ۬لْحَمْدُ',
        'لِلهِ',
        'رَبِّ',
        'اِ۬لْعَٰلَمِينَ',
        'اَ۬لرَّحْمَٰنِ',
        'اِ۬لرَّحِيمِ',
        'مَلِكِ',
        'يَوْمِ',
        'اِ۬لدِّينِۖ',
        'إِيَّاكَ',
        'نَعْبُدُ',
        'وَإِيَّاكَ',
        'نَسْتَعِينُۖ',
        'اُ۪هْدِنَا',
        'اَ۬لصِّرَٰطَ',
        'اَ۬لْمُسْتَقِيمَ',
        'صِرَٰطَ',
        'اَ۬لذِينَ',
        'أَنْعَمْتَ',
        'عَلَيْهِمْ',
        'غَيْرِ',
        'اِ۬لْمَغْضُوبِ',
        'عَلَيْهِمْ',
        'وَلَا',
        'اَ۬لضَّآلِّينَۖ',
      ];

    // One recognized segment per ayah, verbatim from the ASR spike.
    final recognizedSegments = [
        'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
        'الرَّحْمَنِ الرَّحِيمِ',
        'مَلِكِ يَوْمِ الدِّينِ',
        'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
        'اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ',
        'صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ',
        'غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ',
      ];

    final aligner = QuranWordAligner(expectedWords);
    for (final segment in recognizedSegments) {
      aligner.submitRecognizedSegment(segment);
    }

    expect(aligner.isComplete, isTrue, reason: 'statuses: ${aligner.statuses}');
    expect(
      aligner.statuses.every((s) => s == WordStatus.correct),
      isTrue,
      reason: 'expected every word correct, got: ${aligner.statuses}',
    );
  });
}

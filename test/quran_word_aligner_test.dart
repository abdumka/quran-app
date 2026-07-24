import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';

void main() {
  group('QuranWordAligner', () {
    test('reciting every word correctly reveals them all in order', () {
      final aligner = QuranWordAligner(['alhamdu', 'lillahi', 'rabbi', 'alameen']);

      aligner.submitRecognizedSegment('alhamdu lillahi');
      expect(aligner.statuses, [
        WordStatus.correct,
        WordStatus.correct,
        WordStatus.pending,
        WordStatus.pending,
      ]);

      aligner.submitRecognizedSegment('rabbi alameen');
      expect(aligner.statuses, [
        WordStatus.correct,
        WordStatus.correct,
        WordStatus.correct,
        WordStatus.correct,
      ]);
      expect(aligner.isComplete, isTrue);
    });

    test('a single mispronounced/garbled segment is only "unclear", never an immediate mistake', () {
      final aligner = QuranWordAligner(['alhamdu', 'lillahi', 'rabbi']);

      aligner.submitRecognizedSegment('xyzzy nonsense');
      expect(aligner.statuses[0], WordStatus.unclear);
      expect(aligner.isComplete, isFalse);
    });

    test('two consecutive unrecognizable segments promote the stuck word to mistake', () {
      final aligner = QuranWordAligner(['alhamdu', 'lillahi', 'rabbi']);

      aligner.submitRecognizedSegment('xyzzy');
      expect(aligner.statuses[0], WordStatus.unclear);

      aligner.submitRecognizedSegment('qwerty');
      expect(aligner.statuses[0], WordStatus.mistake);
      // The aligner advances past a promoted mistake so the session isn't
      // stuck forever on one word.
      expect(aligner.cursor, 1);
    });

    test('recovering after an unclear segment clears the miss streak', () {
      final aligner = QuranWordAligner(['alhamdu', 'lillahi', 'rabbi']);

      aligner.submitRecognizedSegment('xyzzy'); // unclear, miss streak = 1
      aligner.submitRecognizedSegment('alhamdu'); // recognized correctly
      expect(aligner.statuses[0], WordStatus.correct);

      // A later unrelated segment should need two fresh strikes again, not
      // pick up where the earlier streak left off.
      aligner.submitRecognizedSegment('xyzzy');
      expect(aligner.statuses[1], WordStatus.unclear);
    });

    test('a genuinely dropped word gets marked skipped when a later word matches', () {
      final aligner = QuranWordAligner(['alhamdu', 'lillahi', 'rabbi', 'alameen']);

      // User skips "lillahi" entirely and continues with "rabbi alameen".
      aligner.submitRecognizedSegment('alhamdu rabbi alameen');

      expect(aligner.statuses, [
        WordStatus.correct,
        WordStatus.skipped,
        WordStatus.correct,
        WordStatus.correct,
      ]);
      expect(aligner.isComplete, isTrue);
    });

    test('repeating an already-confirmed word/phrase does not double-advance or corrupt state', () {
      final aligner = QuranWordAligner(['alhamdu', 'lillahi', 'rabbi', 'alameen']);

      aligner.submitRecognizedSegment('alhamdu lillahi');
      // User stutters and repeats the phrase they just said.
      aligner.submitRecognizedSegment('alhamdu lillahi');

      expect(aligner.statuses, [
        WordStatus.correct,
        WordStatus.correct,
        WordStatus.pending,
        WordStatus.pending,
      ]);
      expect(aligner.cursor, 2);

      aligner.submitRecognizedSegment('rabbi alameen');
      expect(aligner.isComplete, isTrue);
    });

    test('minor spelling/diacritic noise still counts as correct (near-match tolerance)', () {
      final aligner = QuranWordAligner(['alrrahman']);
      // One-character difference (missing a doubled letter), well within
      // the near-match threshold for a 9-letter word.
      aligner.submitRecognizedSegment('alrahman');
      expect(aligner.statuses[0], WordStatus.correct);
    });

    test('a genuinely different word beyond the near-match threshold does not match', () {
      final aligner = QuranWordAligner(['alrrahman', 'alraheem']);
      aligner.submitRecognizedSegment('banana');
      expect(aligner.statuses[0], isNot(WordStatus.correct));
    });

    test('a far-ahead coincidental match is bounded by windowSize, not skipping everything', () {
      final aligner = QuranWordAligner(
        ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
        windowSize: 3,
      );
      // "h" is 7 positions ahead of the cursor -- outside the window of 3 --
      // so it must not be reachable from a single segment.
      aligner.submitRecognizedSegment('h');
      expect(aligner.statuses.any((s) => s == WordStatus.correct), isFalse);
    });

    test('empty/whitespace-only segments are a no-op', () {
      final aligner = QuranWordAligner(['alhamdu', 'lillahi']);
      aligner.submitRecognizedSegment('   ');
      expect(aligner.statuses, [WordStatus.pending, WordStatus.pending]);
      expect(aligner.cursor, 0);
    });

    test('reset restores the initial pending state', () {
      final aligner = QuranWordAligner(['alhamdu', 'lillahi']);
      aligner.submitRecognizedSegment('alhamdu lillahi');
      expect(aligner.isComplete, isTrue);

      aligner.reset();
      expect(aligner.isComplete, isFalse);
      expect(aligner.cursor, 0);
      expect(aligner.statuses, [WordStatus.pending, WordStatus.pending]);
    });

    test('onWordResolved fires with the resolved word index', () {
      final resolved = <int>[];
      final aligner = QuranWordAligner(['alhamdu', 'lillahi'])
        ..onWordResolved = resolved.add;

      aligner.submitRecognizedSegment('alhamdu lillahi');
      expect(resolved, [0, 1]);
    });

    test('a word the passage repeats still matches at its second occurrence '
        '(Al-Fatihah has عليهم in both ayah 6 and ayah 7)', () {
      // Mirror of the real Fatihah tail: ... alayhim (ayah 6) ghayri
      // almaghdubi alayhim (ayah 7) ...
      final aligner = QuranWordAligner(
        ['anamta', 'alayhim', 'ghayri', 'almaghdubi', 'alayhim', 'wala'],
      );

      aligner.submitRecognizedSegment('anamta alayhim');
      aligner.submitRecognizedSegment('ghayri almaghdubi');
      expect(aligner.cursor, 4);

      // The second occurrence arrives alone in its own segment. The
      // repeat-of-history guard must NOT swallow it just because the same
      // word already appears in the confirmed history.
      aligner.submitRecognizedSegment('alayhim');
      expect(aligner.statuses[4], WordStatus.correct);
      expect(aligner.cursor, 5);
    });

    test('submitting after completion is a no-op', () {
      final aligner = QuranWordAligner(['alhamdu']);
      aligner.submitRecognizedSegment('alhamdu');
      expect(aligner.isComplete, isTrue);

      // Should not throw or change state.
      aligner.submitRecognizedSegment('anything');
      expect(aligner.statuses, [WordStatus.correct]);
    });
  });
}

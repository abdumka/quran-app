import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/word_position_data.dart';
import 'package:islamic_dawah_mushaf/services/word_position_service.dart';

void main() {
  group('WordPositionPageData', () {
    test('round-trips through JSON', () {
      const original = WordPositionPageData(
        page: 1,
        ayahs: [
          AyahWordPositionData(
            surah: 1,
            ayah: 1,
            words: [
              WordPositionRect(
                index: 0,
                text: 'كلمة',
                x: 0.1,
                y: 0.2,
                width: 0.05,
                height: 0.04,
              ),
            ],
          ),
        ],
      );

      final decoded = WordPositionPageData.fromJson(
        json.decode(json.encode(original.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.page, 1);
      expect(decoded.ayahs.single.ayah, 1);
      final word = decoded.ayahs.single.words.single;
      expect(word.index, 0);
      expect(word.text, 'كلمة');
      expect(word.x, 0.1);
      expect(word.toPixelRect(1000, 2000).left, closeTo(100, 0.001));
      expect(word.toPixelRect(1000, 2000).height, closeTo(80, 0.001));
    });
  });

  group('bundled word_positions.json asset', () {
    // Reads the real asset file directly from disk (tests run from the
    // project root) so the shipped data itself is validated, not a copy.
    late final List<dynamic> rawPages;
    late final List<dynamic> rawOutputPages;

    setUpAll(() {
      rawPages = json.decode(
        File('assets/data/word_positions.json').readAsStringSync(),
      ) as List<dynamic>;
      rawOutputPages = json.decode(
        File('assets/data/output.json').readAsStringSync(),
      ) as List<dynamic>;
    });

    test('parses via the models and covers all 7 Fatihah ayahs / 25 words', () {
      final page1 = WordPositionPageData.fromJson(
        rawPages.single as Map<String, dynamic>,
      );
      expect(page1.page, 1);
      expect(page1.ayahs.map((a) => a.ayah).toList(), [1, 2, 3, 4, 5, 6, 7]);
      expect(page1.wordsInRecitationOrder.length, 25);

      // Every box must be a sane on-page ratio rect.
      for (final word in page1.wordsInRecitationOrder) {
        expect(word.x, inInclusiveRange(0, 1));
        expect(word.y, inInclusiveRange(0, 1));
        expect(word.width, greaterThan(0));
        expect(word.height, greaterThan(0));
        expect(word.x + word.width, lessThanOrEqualTo(1));
        expect(word.y + word.height, lessThanOrEqualTo(1));
      }
    });

    test('word boxes agree with output.json text (no drift)', () {
      final page1 = WordPositionPageData.fromJson(
        rawPages.single as Map<String, dynamic>,
      );
      final outputPage1 = rawOutputPages.firstWhere(
        (p) => (p as Map<String, dynamic>)['page'] == 1,
      ) as Map<String, dynamic>;
      final expectedWordsByAyah = {
        for (final ayah in outputPage1['ayahs'] as List<dynamic>)
          (ayah as Map<String, dynamic>)['ayah'] as int:
              (ayah['text'] as String).split(RegExp(r'\s+')),
      };

      final problems = WordPositionService.validateAgainstExpectedWords(
        page1,
        expectedWordsByAyah,
      );
      expect(problems, isEmpty);
    });
  });
}

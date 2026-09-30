import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/quran_display_text.dart';

void main() {
  group('quranDisplayText', () {
    test('maps the KFGQPC open tanween to standard tanween', () {
      // لَسِحْرٞ (open dammatan) and ضِئَآءٗ (open fathatan), as in output.json.
      expect(
        quranDisplayText('لَسِحْر\u065E'),
        'لَسِحْر\u064C',
      );
      expect(
        quranDisplayText('ضِئَآء\u0657'),
        'ضِئَآء\u064B',
      );
      expect(
        quranDisplayText('مُّبِين\u0656'),
        'مُّبِين\u064D',
      );
    });

    test('keeps length, so search highlight offsets stay valid', () {
      const s = 'نَارا\u0657 وَهُوَ حَكِيم\u065E عَلِيم\u0656';
      expect(quranDisplayText(s).length, s.length);
    });

    test('leaves the whole of output.json free of open-tanween marks', () {
      final pages = json.decode(
        File('assets/data/output.json').readAsStringSync(),
      ) as List;
      final open = RegExp('[\u0656\u0657\u065E]');
      var converted = 0;
      for (final page in pages.expand((p) => p is List ? p : [p])) {
        for (final a in (page as Map)['ayahs'] as List) {
          final text = (a as Map)['text'] as String;
          if (open.hasMatch(text)) converted++;
          expect(open.hasMatch(quranDisplayText(text)), isFalse);
        }
      }
      expect(converted, greaterThan(0));
    });
  });
}

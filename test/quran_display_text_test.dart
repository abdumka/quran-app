import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/quran_display_text.dart';

void main() {
  group('quranDisplayText', () {
    test('maps the KFGQPC open tanween to standard tanween', () {
      // لَسِحْرٞ (open dammatan) and ضِئَآءٗ (open fathatan), as in output.json.
      expect(quranDisplayText('لَسِحْر\u065E'), 'لَسِحْر\u064C');
      expect(quranDisplayText('ضِئَآء\u0657'), 'ضِئَآء\u064B');
      expect(quranDisplayText('مُّبِين\u0656'), 'مُّبِين\u064D');
    });

    test('shows alef maqsura as ى, not a dotted ya', () {
      expect(quranDisplayText('عِيسَ\u064A'), 'عِيسَ\u0649');
      expect(quranDisplayText('عَلَ\u064A\u0670'), 'عَلَ\u0649\u0670');
      expect(quranDisplayText('مُوسَ\u064A\u0670\u06D6'),
          'مُوسَ\u0649\u0670\u06D6');
      // Fathatan on the maqsura: هُدًى.
      expect(quranDisplayText('هُد\u064A\u0657'), 'هُد\u0649\u064B');
      // Mid-word, carrying a dagger alef: سَوَّىٰهُنَّ.
      expect(quranDisplayText('سَوَّ\u064A\u0670هُنَّ'),
          'سَوَّ\u0649\u0670هُنَّ');
    });

    test('leaves a real ya alone', () {
      for (final w in ['عَلَيَّ', 'إِنِّيَ', 'هُدِيَ', 'وَلِيّٞ', 'أَحْيَٰكُمْ']) {
        expect(quranDisplayText(w), fixOpenTanween(w), reason: w);
      }
      // App prose inside Tasmee messages has no fatha before its final ya.
      expect(quranDisplayText('في الذي عليه'), 'في الذي عليه');
    });

    test('shows the yeh barree as an ordinary ya', () {
      expect(quranDisplayText('فِ\u06D2'), 'فِ\u064A');
      expect(quranDisplayText('شَ\u06D2ْءٍ'), 'شَ\u064Aْءٍ');
      // اِمْرِئٍ: the hamza below the barree becomes the usual ئ.
      expect(quranDisplayText('اِمْرِ\u06D2\u0655\u0656'),
          'اِمْرِ\u064A\u0654\u064D');
    });

    test('keeps length, so search highlight offsets stay valid', () {
      const s = 'نَارا\u0657 عَلَ\u064A\u0670 فِ\u06D2 حَكِيم\u065E';
      expect(quranDisplayText(s).length, s.length);
    });

    test('cleans the whole of output.json', () {
      final pages = json.decode(
        File('assets/data/output.json').readAsStringSync(),
      ) as List;
      final leftovers = RegExp('[\u0656\u0657\u065E\u06D2]');
      // A vowel-less dotted ya right after a fatha, at a word end: a maqsura
      // the rule missed.
      final missedMaqsura = RegExp(
        '\u064E\u064A[\u0670\u0653\u06D6-\u06ED]*(?:\u0020|\u000A|\$)',
      );
      var maqsura = 0;
      for (final page in pages.expand((p) => p is List ? p : [p])) {
        for (final a in (page as Map)['ayahs'] as List) {
          final shown = quranDisplayText((a as Map)['text'] as String);
          expect(leftovers.hasMatch(shown), isFalse, reason: shown);
          expect(missedMaqsura.hasMatch(shown), isFalse, reason: shown);
          maqsura += '\u0649'.allMatches(shown).length;
        }
      }
      expect(maqsura, greaterThanOrEqualTo(2910));
    });
  });

  group('tafsirDisplayText', () {
    test('fixes the maqsura typos in the sources', () {
      expect(tafsirDisplayText('قال موسي بن عقبة'), 'قال موسى بن عقبة');
      expect(tafsirDisplayText('يونس بن متي، ألا'), 'يونس بن متى، ألا');
      expect(tafsirDisplayText('قوله تعالي: وقال'), 'قوله تعالى: وقال');
      expect(tafsirDisplayText('ربه حتي يتكبر'), 'ربه حتى يتكبر');
    });

    test('leaves prose and real words alone', () {
      for (final s in [
        'الذي في عليه',
        'وَلِلْمَرْأَةِ تَعَالَيْ',
        'تعالي يا فلانة',
        'يحيي الموتى',
        'موسيقى',
      ]) {
        expect(tafsirDisplayText(s), s, reason: s);
      }
    });

    test('does not apply the mushaf maqsura rule to prose', () {
      expect(tafsirDisplayText('رَأَي'), 'رَأَي');
    });
  });
}

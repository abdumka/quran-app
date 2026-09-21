import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/arabic_text_normalizer.dart';

void main() {
  group('normalizeArabicText', () {
    test('strips tashkeel and unifies alef/ya/waw/ta-marbuta variants', () {
      expect(normalizeArabicText('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ'),
          'بسم الله الرحمان الرحيم');
    });

    test('expands the Qaloon dagger-alif (U+0670) to a full alef rather than dropping it', () {
      // Ayah 1:1 exactly as stored in assets/data/output.json.
      expect(normalizeArabicText('اِ۬لْحَمْدُ لِلهِ رَبِّ اِ۬لْعَٰلَمِينَ'), 'الحمد لله رب العالمين');
    });

    test('is idempotent and collapses whitespace', () {
      final once = normalizeArabicText('اَ۬لرَّحْمَٰنِ اِ۬لرَّحِيمِ');
      final twice = normalizeArabicText(once);
      expect(once, twice);
      expect(normalizeArabicText('  a    b  '), 'a b');
    });
  });

  group('normalizeArabicChar', () {
    test('drops diacritics and returns null', () {
      expect(normalizeArabicChar(String.fromCharCode(0x064E)), isNull); // fatha
      expect(normalizeArabicChar(String.fromCharCode(0x0652)), isNull); // sukun
    });

    test('maps dagger alef (U+0670) to a full alef', () {
      expect(normalizeArabicChar(String.fromCharCode(0x0670)), 'ا');
    });

    test('unifies letter variants the same way normalizeArabicText does', () {
      expect(normalizeArabicChar(String.fromCharCode(0x0623)), 'ا'); // hamza above
      expect(normalizeArabicChar(String.fromCharCode(0x0625)), 'ا'); // hamza below
      expect(normalizeArabicChar(String.fromCharCode(0x0622)), 'ا'); // madda above
      expect(normalizeArabicChar(String.fromCharCode(0x0649)), 'ي'); // alef maksura
      expect(normalizeArabicChar(String.fromCharCode(0x0626)), 'ي'); // yeh hamza
      expect(normalizeArabicChar(String.fromCharCode(0x0624)), 'و'); // waw hamza
      expect(normalizeArabicChar(String.fromCharCode(0x0629)), 'ه'); // ta marbuta
    });

    test('drops tatweel, standalone hamza, and Arabic comma', () {
      expect(normalizeArabicChar(String.fromCharCode(0x0640)), isNull); // tatweel
      expect(normalizeArabicChar(String.fromCharCode(0x0621)), isNull); // hamza
      expect(normalizeArabicChar(String.fromCharCode(0x060C)), isNull); // arabic comma
    });

    test('passes whitespace through as a single space marker', () {
      expect(normalizeArabicChar(' '), ' ');
    });
  });

  group('normalizedArabicWords', () {
    test('splits normalized text on whitespace, dropping empties', () {
      expect(normalizedArabicWords('اِ۬لْحَمْدُ لِلهِ رَبِّ اِ۬لْعَٰلَمِينَ'), ['الحمد', 'لله', 'رب', 'العالمين']);
    });
  });
}

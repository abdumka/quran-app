// Server corrections to الفهرس labels: the `thumnTexts` and `hizbTitles`
// sections of the `quran_data` item, laid over the bundle by IndexText.

import 'package:flutter_test/flutter_test.dart';

import 'package:islamic_dawah_mushaf/services/index_text.dart';
import 'package:islamic_dawah_mushaf/services/quran_data_patch.dart';
import 'package:islamic_dawah_mushaf/thumn_data.dart';

void main() {
  tearDown(IndexText.debugReset);

  test('without corrections the bundle shows', () {
    expect(IndexText.thumn(thumnEntries[470]), 'فلا أقسم بالشفق');
    expect(IndexText.hizbTitle(60), 'الأعلى');
    expect(IndexText.hizbTitle(61), '');
  });

  test('parsed sections replace only the labels they name', () {
    final patch = QuranDataPatch.parse(
      '{"ver": 1, "thumnTexts": {"471": " فلا أقسم بالشفق والليل "},'
      ' "hizbTitles": {"60": "سبح"}}',
    );
    expect(patch.thumnTexts, {471: 'فلا أقسم بالشفق والليل'});
    expect(patch.hizbTitles, {60: 'سبح'});

    IndexText.apply(thumn: patch.thumnTexts, hizb: patch.hizbTitles);
    expect(IndexText.thumn(thumnEntries[470]), 'فلا أقسم بالشفق والليل');
    expect(IndexText.thumn(thumnEntries[471]), 'إن بطش ربك لشديد');
    expect(IndexText.hizbTitle(60), 'سبح');
    expect(IndexText.hizbTitle(59), 'النبأ');
  });

  test('a file without the sections still parses, with none', () {
    final patch = QuranDataPatch.parse('{"ver": 3}');
    expect(patch.thumnTexts, isEmpty);
    expect(patch.hizbTitles, isEmpty);
  });

  test('bad labels refuse the whole file', () {
    for (final bad in [
      '{"ver": 1, "thumnTexts": {"481": "x"}}',
      '{"ver": 1, "thumnTexts": {"0": "x"}}',
      '{"ver": 1, "thumnTexts": {"5": ""}}',
      '{"ver": 1, "thumnTexts": {"5": 7}}',
      '{"ver": 1, "thumnTexts": {"5": "a\\nb"}}',
      '{"ver": 1, "thumnTexts": ["x"]}',
      '{"ver": 1, "hizbTitles": {"61": "x"}}',
      '{"ver": 1, "hizbTitles": {"6": "${'x' * 61}"}}',
    ]) {
      expect(() => QuranDataPatch.parse(bad), throwsFormatException, reason: bad);
    }
  });
}

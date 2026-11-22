// Surah names that come from a page number, and the athman index labels.
//
// A user reported that الفهرس named «فلا أقسم بالشفق» under البروج and «إن بطش
// ربك لشديد» under الطارق (2026-11-21). The thumn data was right; the label
// came from the last surah to begin on the thumn's page, which names the next
// surah whenever one begins after the thumn on that page (18 athman). The top
// bar and the daily page reminder named pages the same way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islamic_dawah_mushaf/quran_constants.dart';
import 'package:islamic_dawah_mushaf/quran_index_page.dart';
import 'package:islamic_dawah_mushaf/services/daily_page_service.dart';
import 'package:islamic_dawah_mushaf/surah_data.dart';
import 'package:islamic_dawah_mushaf/thumn_data.dart';

void main() {
  group('surahNamesForPage', () {
    test('a page shared by the end of one surah and the start of the next', () {
      expect(surahNamesForPage(587), 'الانشقاق - البروج');
      expect(surahNamesForPage(588), 'البروج - الطارق');
    });

    test('a page inside one surah', () {
      expect(surahNamesForPage(3), 'البقرة');
      expect(surahNamesForPage(100), 'النساء');
    });

    test('a surah that starts at the top of its page stands alone', () {
      expect(surahNamesForPage(1), 'الفاتحة');
      expect(surahNamesForPage(2), 'البقرة');
      expect(surahNamesForPage(77), 'النساء');
    });

    test('the daily page reminder names the page the same way', () {
      expect(DailyPageService.surahNameForPage(587), 'الانشقاق - البروج');
    });
  });

  test('every hizb has a title', () {
    expect(hizbTitles, hasLength(60));
    expect(hizbTitles.last, 'الأعلى');
  });

  testWidgets('an athman row names the surah its first ayah is in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuranIndexPage(
          surahs: surahList,
          onGoToPage: (_, {double yOffsetRatio = 0.0}) {},
          currentSurahNumber: 1,
          currentPage: 0,
          onSelectSurah: (_) {},
          initialTab: QuranIndexTab.hizbs,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'بالشفق');
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('فلا أقسم بالشفق').hitTestable(),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: row.first, matching: find.text('الانشقاق')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row.first, matching: find.text('البروج')),
      findsNothing,
    );
  });

  test('every thumn starts inside a surah that exists', () {
    for (final e in thumnEntries) {
      expect(e.startSurah, inInclusiveRange(1, 114), reason: '${e.number}');
    }
  });
}

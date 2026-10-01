// The السور tab of الفهرس: the grid (default) / one-per-line list switch
// beside the search field, what a list row says, and that the choice is
// remembered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:islamic_dawah_mushaf/quran_index_page.dart';
import 'package:islamic_dawah_mushaf/services/surah_index_view_service.dart';
import 'package:islamic_dawah_mushaf/surah_data.dart';

Future<void> pumpIndex(WidgetTester tester, {bool portrait = true}) async {
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = portrait
      ? const Size(1080, 2400)
      : const Size(2400, 1080);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: QuranIndexPage(
        surahs: surahList,
        onGoToPage: (_, {double yOffsetRatio = 0.0}) {},
        currentSurahNumber: 1,
        currentPage: 0,
        onSelectSurah: (_) {},
        initialTab: QuranIndexTab.surahs,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final Finder toggle = find.byIcon(Icons.apps_rounded);

/// Only list rows carry the ayah count; al-Fatihah's is unique to it.
const String fatihaDetails = '7 آيات';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SurahIndexViewService.instance.setGrid(true);
  });

  testWidgets('the grid is the default, with the switch beside the search', (
    tester,
  ) async {
    await pumpIndex(tester);
    expect(toggle, findsOneWidget);
    expect(find.text('الفاتحة'), findsOneWidget);
    expect(find.text(fatihaDetails), findsNothing);
    // The switch shares the search field's row.
    expect(
      tester.getCenter(toggle).dy,
      moreOrLessEquals(tester.getCenter(find.byType(TextField)).dy, epsilon: 1),
    );
  });

  testWidgets('turning it off lists one surah per line and remembers it', (
    tester,
  ) async {
    await pumpIndex(tester);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text(fatihaDetails), findsOneWidget);
    // al-Baqarah: مدنية, 285 ayat in the Qaloon count, page 2.
    expect(find.text('285 آية'), findsOneWidget);
    expect(find.text('صفحة 2'), findsOneWidget);
    // The columns line up: every page cell has the same width.
    expect(
      tester.getSize(find.text('صفحة 1')).width,
      tester.getSize(find.text('صفحة 2')).width,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('surahIndexGridView'), isFalse);

    // A fresh open of the index keeps the list.
    await tester.pumpWidget(const SizedBox());
    await pumpIndex(tester);
    expect(find.text(fatihaDetails), findsOneWidget);

    // And back.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text(fatihaDetails), findsNothing);
    expect(prefs.getBool('surahIndexGridView'), isTrue);
  });

  testWidgets('landscape has no search row, so the switch is in the app bar', (
    tester,
  ) async {
    await pumpIndex(tester, portrait: false);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: toggle),
      findsOneWidget,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text(fatihaDetails), findsOneWidget);
  });

  test('ayah counts are the Qaloon (Madani) ones', () {
    int count(int surah) => surahList[surah - 1]['ayahs'] as int;
    expect(count(2), 285);
    expect(count(18), 105);
    expect(surahList.fold<int>(0, (sum, s) => sum + (s['ayahs'] as int)), 6214);
  });
}

// Pins the الأحزاب والأثمان filtering rules of الفهرس.
//
// That logic used to live inline inside _buildThumnsByHizb and _buildHizbCard.
// Adding Android TV remote navigation pulled it out into a shared view model
// (_hizbViewModel / _athmanFor) so the D-pad could walk exactly the rows that
// are on screen. The extraction is supposed to be behaviour-preserving for
// phones and tablets, and nothing in the suite covered الفهرس at all, so these
// tests exist to say so.
//
// The subtle rule, and the one worth protecting: when a search matches a hizb
// by its TITLE or NUMBER rather than by the text of a thumn, that hizb shows
// ALL of its athman. Only a hizb matched through thumn text is narrowed to the
// matching ones. Get that backwards and searching a hizb by name silently
// empties it.
//
// Note the assertions hold whether or not a card is expanded: AnimatedCrossFade
// keeps the collapsed thumn rows in the widget tree, so what is being checked
// is which thumns were BUILT, which is precisely what _athmanFor decides.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islamic_dawah_mushaf/quran_index_page.dart';

/// Thumn 1 of hizb 1. Present only when hizb 1 is shown unfiltered.
const String kFirstThumnOfHizb1 = 'الحمد لله رب العالمين';

/// Thumn 2 of hizb 1, and a phrase that appears in no hizb TITLE, so a search
/// for it can only match through thumn text.
const String kSecondThumnOfHizb1 =
    'وإذا لقوا الذين آمنوا قالوا آمنا وإذا خلوا إلى شياطينهم قالوا إنا معكم';

Future<void> pumpIndex(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: QuranIndexPage(
        surahs: const [
          {'number': 1, 'name': 'الفاتحة', 'english': 'Al-Fatihah', 'page': 1},
        ],
        onGoToPage: (_, {double yOffsetRatio = 0.0}) {},
        currentSurahNumber: 1,
        currentPage: 0,
        onSelectSurah: (_) {},
        initialTab: QuranIndexTab.hizbs,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no query the list starts at hizb 1 and shows its athman', (
    tester,
  ) async {
    await pumpIndex(tester);

    expect(find.text('الحزب 1'), findsOneWidget);
    // currentPage 0 puts the reader in hizb 1, which opens expanded.
    expect(find.text(kFirstThumnOfHizb1), findsOneWidget);
    expect(find.text(kSecondThumnOfHizb1), findsOneWidget);
  });

  testWidgets('a number query narrows to that hizb alone', (tester) async {
    await pumpIndex(tester);
    await search(tester, 'حزب 14');

    expect(find.text('الحزب 14'), findsOneWidget);
    expect(find.text('الحزب 13'), findsNothing);
    expect(find.text('الحزب 15'), findsNothing);
    // Matched by number, not by thumn text, so nothing inside it is hidden.
    expect(find.text('الحزب 1'), findsNothing);
  });

  testWidgets('a thumn-text query keeps only the matching athman', (
    tester,
  ) async {
    await pumpIndex(tester);
    await search(tester, 'وإذا لقوا الذين آمنوا');

    expect(find.text('الحزب 1'), findsOneWidget);
    expect(find.text(kSecondThumnOfHizb1), findsOneWidget);
    // Hizb 1 matched through thumn text, so its other seven are dropped.
    expect(find.text(kFirstThumnOfHizb1), findsNothing);
  });

  testWidgets('a title query keeps every thumn of the matched hizb', (
    tester,
  ) async {
    await pumpIndex(tester);
    // 'الفاتحة' is the title of hizb 1 and appears in none of its thumns.
    await search(tester, 'الفاتحة');

    expect(find.text('الحزب 1'), findsOneWidget);
    // The fallback: matched by title, so it is NOT narrowed to nothing.
    expect(find.text(kFirstThumnOfHizb1), findsOneWidget);
    expect(find.text(kSecondThumnOfHizb1), findsOneWidget);
  });

  testWidgets('a query matching nothing says so', (tester) async {
    await pumpIndex(tester);
    await search(tester, 'قنقنقن');

    expect(find.text('لا توجد نتيجة'), findsOneWidget);
  });

  testWidgets('clearing the query restores the full list', (tester) async {
    await pumpIndex(tester);
    await search(tester, 'حزب 14');
    expect(find.text('الحزب 1'), findsNothing);

    await search(tester, '');

    expect(find.text('الحزب 1'), findsOneWidget);
    expect(find.text(kFirstThumnOfHizb1), findsOneWidget);
  });
}

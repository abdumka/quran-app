import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/quran_page_data.dart';
import 'package:islamic_dawah_mushaf/quran_pages.dart';
import 'package:islamic_dawah_mushaf/search_page.dart';
import 'package:islamic_dawah_mushaf/services/audio_service.dart';
import 'package:islamic_dawah_mushaf/services/ayah_position_service.dart';
import 'package:islamic_dawah_mushaf/services/ayah_region_service.dart';
import 'package:islamic_dawah_mushaf/services/quran_json_service.dart';
import 'package:islamic_dawah_mushaf/services/word_region_service.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/playing_ayah_highlight.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/selected_ayah_highlight.dart';

/// Tapping a search result opens the result's page and tints the ayah there,
/// through the long-press highlight (`SelectedAyahHighlight`), which draws the
/// line rects `ayah_regions.json` holds for that page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The tint painters on screen -- at most one, ever.
  List<PlayingAyahHighlightPainter> tints(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<PlayingAyahHighlightPainter>()
      .toList();

  void recite(int surah, int ayah) {
    AudioService.instance.currentAyah.value = QuranAyahData(
      surah: surah,
      surahName: '',
      ayah: ayah,
      text: '',
    );
    AudioService.instance.isRecitationBarVisible.value = true;
  }

  void silence() {
    AudioService.instance.currentAyah.value = null;
    AudioService.instance.currentAyahGroup.value = const [];
    AudioService.instance.isRecitationBarVisible.value = false;
  }

  tearDown(() {
    SelectedAyahHighlight.selected.value = null;
    silence();
  });

  /// The page a result carries, resolved exactly as the search page does: the
  /// visual positions first, the page JSON where they are silent.
  ///
  /// The tint only shows when that page and the page the regions were cut
  /// from agree. Both are derived from `output.json`, and this guards that
  /// they stay in step: regenerate `ayah_regions.json` whenever a page
  /// assignment moves, or search results stop being highlighted.
  test('every search result has line rects on the page it opens', () async {
    final positions = await AyahPositionService.loadAyahPositions();
    final visualPage = <String, int>{
      for (final entry in positions.entries)
        for (final position in entry.value)
          '${position.surah}_${position.ayah}': entry.key,
    };

    final regions = await AyahRegionService.loadAll();
    final tinted = <int, Set<String>>{
      for (final page in regions.values)
        page.page: {
          for (final ayah in page.ayahs)
            if (ayah.rects.isNotEmpty) '${ayah.surah}_${ayah.ayah}',
        },
    };

    final untinted = <String>[];
    var results = 0;
    for (final page in await QuranJsonService.loadQuranPages()) {
      for (final ayah in page.ayahs) {
        final key = '${ayah.surah}_${ayah.ayah}';
        final resultPage = visualPage[key] ?? page.page;
        results++;
        if (!(tinted[resultPage]?.contains(key) ?? false)) {
          untinted.add('$key on page $resultPage');
        }
      }
    }

    expect(results, 6214);
    expect(
      untinted,
      isEmpty,
      reason: '${untinted.length} results would open their page with nothing '
          'tinted: ${untinted.take(10).join(', ')}',
    );
  });

  group('the tint on the page', () {
    // Al-Baqarah 1 (Alif Lam Mim), page 2 of the mushaf.
    setUp(() async {
      await AyahRegionService.loadAll();
      SelectedAyahHighlight.selected.value = const SelectedAyah(
        pageNumber: 2,
        surah: 2,
        ayah: 1,
      );
    });

    Future<void> showPage(WidgetTester tester, int page) async {
      await tester.pumpWidget(
        MaterialApp(home: SelectedAyahHighlight(pageNumber: page, dark: false)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is drawn on the page the result opened', (tester) async {
      await showPage(tester, 2);
      expect(tints(tester), hasLength(1));
      expect(tints(tester).single.rects, isNotEmpty);
    });

    testWidgets('is not drawn on the next page', (tester) async {
      await showPage(tester, 3);
      expect(tints(tester), isEmpty);
    });

    testWidgets('comes off the moment a recitation tints the same page', (
      tester,
    ) async {
      await showPage(tester, 2);
      expect(tints(tester), hasLength(1), reason: 'the result is tinted');

      // The reader taps Tilawah: the recitation starts on this very page
      // (page 2 carries al-Baqarah 1-4).
      recite(2, 3);
      await tester.pumpAndSettle();
      expect(
        tints(tester),
        isEmpty,
        reason: 'the recitation has the page; two tinted ayat is the bug',
      );

      // ...and the page is given back when the recitation lets go of it.
      silence();
      await tester.pumpAndSettle();
      expect(tints(tester), hasLength(1));
    });

    testWidgets('stands down for a recitation on another page too', (
      tester,
    ) async {
      // Not a per-page rule: the landscape spread shows two pages at once, so
      // the recited page and the result's page can share a screen.
      recite(20, 1); // Ta-Ha, hundreds of pages away.
      await showPage(tester, 2);
      expect(tints(tester), isEmpty);
    });

    testWidgets('does not double-tint the ayah being recited', (tester) async {
      recite(2, 1); // The recitation is on the tinted ayah itself.
      await showPage(tester, 2);
      expect(
        tints(tester),
        isEmpty,
        reason: 'the recitation paints it; a second band would darken it',
      );
    });

    testWidgets('lands on the page inside the margin-view image', (
      tester,
    ) async {
      // With the margin scans on, the page sits inside a wider image; the
      // tint has to be placed into it rather than over the whole box.
      await tester.runAsync(() => WordRegionService.loadAll());
      await tester.pumpWidget(
        const MaterialApp(
          home: SelectedAyahHighlight(
            pageNumber: 2,
            dark: false,
            marginView: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boxes = tints(tester).single.boxes(const Size(1000, 1000));
      expect(boxes, isNotEmpty);
      expect(
        boxes.first.width,
        lessThan(1000),
        reason: 'the tint is inside the page, not across the whole image',
      );
    });

    testWidgets('stands down with the recitation bar up but the tint off', (
      tester,
    ) async {
      // With the reader's "highlight the recited ayah" setting off there is
      // no recitation tint to collide with, so the result keeps its own.
      recite(2, 3);
      PlayingAyahHighlightSetting.enabled.value = false;
      addTearDown(() => PlayingAyahHighlightSetting.enabled.value = true);
      await showPage(tester, 2);
      expect(tints(tester), hasLength(1));
    });
  });

  group('leaving the page', () {
    test('the tint survives the page it was set on', () {
      expect(searchTintSurvivesPage(240, 239), isTrue);
    });

    test('it survives the other half of a landscape spread', () {
      // A result on page 241 shows in the spread [240, 241], which reports
      // 240 (0-based 239) as the current page.
      expect(searchTintSurvivesPage(241, 239), isTrue);
      expect(searchTintSurvivesPage(240, 240), isTrue);
    });

    test('it goes once the reader has turned past it', () {
      expect(searchTintSurvivesPage(240, 241), isFalse);
      expect(searchTintSurvivesPage(240, 237), isFalse);
      expect(searchTintSurvivesPage(1, 603), isFalse);
    });
  });

  testWidgets('tapping a result hands over the ayah, not just its page', (
    tester,
  ) async {
    // The whole point of the change: the search page used to report only a
    // page number, which is not enough to tint anything.
    final pages = await QuranJsonService.loadQuranPages();
    final target = pages
        .expand((p) => p.ayahs)
        .firstWhere((a) => a.surah == 1 && a.text.contains('نَعْبُدُ'));

    int? gotPage;
    int? gotSurah;
    int? gotAyah;
    final navigator = GlobalKey<NavigatorState>();

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => SearchPage(
            onGoToPage: (page, {int? surah, int? ayah}) {
              gotPage = page;
              gotSurah = surah;
              gotAyah = ayah;
            },
          ),
        ),
      );

      Future<bool> settleUntil(Finder finder) async {
        for (var i = 0; i < 80; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return true;
        }
        return false;
      }

      expect(await settleUntil(find.byType(TextField)), isTrue);
      await tester.enterText(find.byType(TextField), target.text);

      // The card shows the ayah verbatim, in one RichText.
      final card = find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == target.text,
        ),
        matching: find.byType(InkWell),
      );
      expect(
        await settleUntil(card),
        isTrue,
        reason: 'the ayah searched for is among the results',
      );
      await tester.tap(card.first);
      await tester.pump();
    });

    expect(gotSurah, target.surah);
    expect(gotAyah, target.ayah);
    expect(gotPage, 1, reason: 'al-Fatihah is on page 1');
  });
}

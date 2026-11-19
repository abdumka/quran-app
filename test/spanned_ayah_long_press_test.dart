import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/ayah_region_service.dart';
import 'package:islamic_dawah_mushaf/services/quran_json_service.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/playing_ayah_highlight.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/selected_ayah_highlight.dart';

/// The five ayat printed across a page break (2:218, 4:44, 14:27, 24:36,
/// 24:42) begin at the foot of one page and end on the next. `output.json`
/// lists each under the page it ends on, so on the earlier page its head is
/// the page's `continuing` region. A long press on that head used to find
/// nothing (owner, 2026-11-19: 24:42 on page 355).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const spanned = {
    34: (2, 218),
    85: (4, 44),
    258: (14, 27),
    354: (24, 36),
    355: (24, 42),
  };

  tearDown(() => SelectedAyahHighlight.selected.value = null);

  test('the five heads are the whole set, each listed on the next page',
      () async {
    final regions = await AyahRegionService.loadAll();
    final heads = {
      for (final p in regions.values)
        if (p.continuing != null)
          p.page: (p.continuing!.surah, p.continuing!.ayah),
    };
    expect(heads, spanned);
    final pages = await QuranJsonService.loadQuranPages();
    for (final e in spanned.entries) {
      bool lists(int page) => pages
          .firstWhere((p) => p.page == page)
          .ayahs
          .any((a) => a.surah == e.value.$1 && a.ayah == e.value.$2);
      expect(lists(e.key), isFalse, reason: 'page ${e.key}');
      expect(lists(e.key + 1), isTrue, reason: 'page ${e.key + 1}');
    }
  });

  test('a long press on every line of a head finds that ayah', () async {
    final regions = await AyahRegionService.loadAll();
    for (final e in spanned.entries) {
      final head = regions[e.key]!.continuing!;
      for (final r in head.rects) {
        final hit = await SelectedAyahHighlight.hitTest(
          e.key,
          Offset(r.x + r.width / 2, r.y + r.height / 2),
        );
        expect(hit, e.value, reason: 'page ${e.key}');
      }
    }
  });

  test('the tail on the next page still answers as before', () async {
    final regions = await AyahRegionService.loadAll();
    for (final e in spanned.entries) {
      final tail = regions[e.key + 1]!.ayahs.first;
      expect((tail.surah, tail.ayah), e.value);
      final r = tail.rects.first;
      final hit = await SelectedAyahHighlight.hitTest(
        e.key + 1,
        Offset(r.x + r.width / 2, r.y + r.height / 2),
      );
      expect(hit, e.value, reason: 'page ${e.key + 1}');
    }
  });

  test('the ayah before the head still answers for itself', () async {
    // 24:41 ends on page 355 on the line where 24:42 begins.
    final regions = await AyahRegionService.loadAll();
    final before = regions[355]!.ayahs.last;
    expect((before.surah, before.ayah), (24, 41));
    final m = before.marker!;
    final hit = await SelectedAyahHighlight.hitTest(
      355,
      Offset(m.x + m.width / 2, m.y + m.height / 2),
    );
    expect(hit, (24, 41));
  });

  List<PlayingAyahHighlightPainter> tints(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<PlayingAyahHighlightPainter>()
      .toList();

  Future<void> showPage(WidgetTester tester, int page) async {
    await tester.pumpWidget(
      MaterialApp(home: SelectedAyahHighlight(pageNumber: page, dark: false)),
    );
    await tester.pumpAndSettle();
  }

  group('the tint of a pressed head', () {
    setUp(() async {
      await AyahRegionService.loadAll();
      SelectedAyahHighlight.selected.value = const SelectedAyah(
        pageNumber: 355,
        surah: 24,
        ayah: 42,
      );
    });

    testWidgets('is drawn over the head on the pressed page', (tester) async {
      await showPage(tester, 355);
      expect(tints(tester).single.rects, hasLength(4));
    });

    testWidgets('is drawn over the tail on the next page', (tester) async {
      await showPage(tester, 356);
      expect(tints(tester), hasLength(1));
      expect(tints(tester).single.rects, isNotEmpty);
    });

    testWidgets('is not drawn on the page before', (tester) async {
      await showPage(tester, 354);
      expect(tints(tester), isEmpty);
    });
  });

  testWidgets('a tail selected on its page tints the head on the page before',
      (tester) async {
    // A search result or a tanzilat place opens the page that lists the ayah.
    await AyahRegionService.loadAll();
    SelectedAyahHighlight.selected.value = const SelectedAyah(
      pageNumber: 355,
      surah: 24,
      ayah: 36,
    );
    await showPage(tester, 354);
    expect(tints(tester).single.rects, hasLength(2));
  });

  testWidgets('an ordinary ayah is still tinted on its own page only',
      (tester) async {
    await AyahRegionService.loadAll();
    SelectedAyahHighlight.selected.value = const SelectedAyah(
      pageNumber: 355,
      surah: 24,
      ayah: 41,
    );
    await showPage(tester, 356);
    expect(tints(tester), isEmpty);
    await showPage(tester, 354);
    expect(tints(tester), isEmpty);
    await showPage(tester, 355);
    expect(tints(tester), hasLength(1));
  });
}

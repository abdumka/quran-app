import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/page_span_data.dart';
import 'package:islamic_dawah_mushaf/services/ayah_region_service.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/playing_ayah_highlight.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('an ayah printed across a page break', () {
    final pages = <int, List<(int, int)>>{};

    setUpAll(() {
      void add(Object? item) {
        if (item is List) {
          for (final sub in item) {
            add(sub);
          }
        } else if (item is Map<String, dynamic>) {
          pages[item['page'] as int] = [
            for (final a in item['ayahs'] as List)
              ((a as Map)['surah'] as int, a['ayah'] as int),
          ];
        }
      }

      add(json.decode(File('assets/data/output.json').readAsStringSync()));
    });

    test('is tinted on both pages from its first word', () async {
      for (final page in spannedAyahHead.keys) {
        final spanning = pages[page]!.first;
        final before = (await AyahRegionService.forPage(page - 1))!;
        final after = (await AyahRegionService.forPage(page))!;
        expect(
          highlightRects(before, {spanning}),
          isNotEmpty,
          reason: '$spanning starts at the foot of p${page - 1}',
        );
        expect(highlightRects(after, {spanning}), isNotEmpty);
        // The earlier page's own last ayah is still its own.
        final last = pages[page - 1]!.last;
        expect(highlightRects(before, {last}), isNotEmpty);
        expect(
          highlightRects(before, {spanning}),
          isNot(contains(anyOf(highlightRects(before, {last})))),
        );
      }
    });

    test('only those pages carry a head, and their ayat still match the '
        'text one for one (التسميع relies on it)', () async {
      final all = await AyahRegionService.loadAll();
      for (final MapEntry(key: page, value: regions) in all.entries) {
        final head = regions.continuing;
        if (spannedAyahHead.containsKey(page + 1)) {
          expect(head, isNotNull, reason: 'p$page');
          expect((head!.surah, head.ayah), pages[page + 1]!.first);
          expect(head.marker, isNull);
        } else {
          expect(head, isNull, reason: 'p$page');
        }
        expect(
          [for (final a in regions.ayahs) (a.surah, a.ayah)],
          pages[page],
          reason: 'p$page',
        );
      }
    });
  });

  test('boxes map page ratios onto the page box, trimmed top and bottom', () {
    const painter = PlayingAyahHighlightPainter(
      [Rect.fromLTWH(0.25, 0.5, 0.5, 0.1)],
      null,
      false,
    );
    final box = painter.boxes(const Size(720, 1640)).single;
    expect(box.left, closeTo(180, 0.01));
    expect(box.right, closeTo(540, 0.01));
    // 164 px tall line: 8% trimmed above, 4% below.
    expect(box.top, closeTo(820 + 164 * 0.08, 0.01));
    expect(box.bottom, closeTo(984 - 164 * 0.04, 0.01));
  });

  test('in the margin view the page sits inside the shown image', () {
    const painter = PlayingAyahHighlightPainter(
      [Rect.fromLTWH(0, 0, 1, 1)],
      Rect.fromLTWH(0.1, 0.2, 0.5, 0.5),
      true,
    );
    final box = painter.boxes(const Size(1000, 1000)).single;
    expect(box.left, closeTo(100, 0.01));
    expect(box.right, closeTo(600, 0.01));
    expect(box.top, closeTo(200 + 500 * 0.08, 0.01));
    expect(box.bottom, closeTo(700 - 500 * 0.04, 0.01));
  });
}

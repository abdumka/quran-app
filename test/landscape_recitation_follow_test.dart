import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/continuous_quran_view.dart';
import 'package:islamic_dawah_mushaf/models/quran_page_data.dart';
import 'package:islamic_dawah_mushaf/services/audio_service.dart';
import 'package:islamic_dawah_mushaf/services/ayah_region_service.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/ayah_follow.dart';

/// The landscape reader shows the page at the screen's width, so only about
/// a fifth of it at a time. It has to keep the ayah being recited on screen
/// (owner's recording, 2026-11-19: page 356, the tint went on down the page
/// while the view stayed on its first lines).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A phone held sideways.
  const screen = Size(800, 360);
  const aspect = 720 / 1640; // the reader's page aspect (cropped view)
  const pageHeight = 800 / aspect; // ~1822: the page is 5 screens tall

  setUpAll(() async {
    await AyahRegionService.loadAll();
  });

  void recite(int surah, int ayah) {
    AudioService.instance.currentAyah.value = QuranAyahData(
      surah: surah,
      surahName: '',
      ayah: ayah,
      text: '',
    );
    AudioService.instance.isRecitationBarVisible.value = true;
  }

  tearDown(() {
    AudioService.instance.currentAyah.value = null;
    AudioService.instance.currentAyahGroup.value = const [];
    AudioService.instance.isRecitationBarVisible.value = false;
  });

  /// [page]'s line rects of ([surah], [ayah]), as ratios of the page.
  Future<(double, double)> span(int page, int surah, int ayah) async {
    final regions = (await AyahRegionService.forPage(page))!;
    final a = regions.ayahs.firstWhere(
      (a) => a.surah == surah && a.ayah == ayah,
    );
    final top = a.rects.map((r) => r.y).reduce((x, y) => x < y ? x : y);
    final bottom = a.rects
        .map((r) => r.y + r.height)
        .reduce((x, y) => x > y ? x : y);
    return (top, bottom);
  }

  final key = GlobalKey<ContinuousQuranViewState>();

  Future<void> showReader(
    WidgetTester tester, {
    int initialPage = 355, // page 356, 0-based
    bool autoScroll = false,
    double obscuredBottom = 0,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContinuousQuranView(
            key: key,
            pages: List.generate(602, (i) => 'p$i'),
            pageImageProviderBuilder: (_) => const _BlankPage(),
            initialPage: initialPage,
            viewportWidth: screen.width,
            pageAspectRatio: aspect,
            autoScrollEnabled: autoScroll,
            autoScrollPixelsPerSecond: 0,
            bookmarks: const [],
            onPageChanged: (_) {},
            onSaveBookmark: (_, _, _, _, _) {},
            onMoveBookmark: (_, _, _, _, _, _) {},
            onMoveBookmarkEnd: () async {},
            onAutoScrollInterrupted: () {},
            obscuredBottom: obscuredBottom,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double offsetOf(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

  /// Whether page [page]'s ayah ([surah], [ayah]) is wholly on screen,
  /// above [obscuredBottom].
  Future<bool> onScreen(
    WidgetTester tester,
    int page,
    int surah,
    int ayah, {
    double obscuredBottom = 0,
  }) async {
    final (top, bottom) = await span(page, surah, ayah);
    final offset = offsetOf(tester);
    final pageTop = (page - 1) * pageHeight;
    return pageTop + top * pageHeight >= offset - 1 &&
        pageTop + bottom * pageHeight <=
            offset + screen.height - obscuredBottom + 1;
  }

  testWidgets('an ayah further down the page is brought on screen', (
    tester,
  ) async {
    recite(24, 42); // the first line of page 356
    await showReader(tester);
    await tester.pumpAndSettle();
    expect(offsetOf(tester), closeTo(355 * pageHeight, 0.5));
    expect(await onScreen(tester, 356, 24, 42), isTrue);

    // The recording: 24:44 starts at the end of the fourth line and goes
    // under the bottom of the screen.
    recite(24, 44);
    await tester.pumpAndSettle();
    expect(await onScreen(tester, 356, 24, 44), isTrue);

    // ...and on down to the page's last ayah.
    for (final ayah in [45, 46, 47, 48, 49, 50, 51]) {
      recite(24, ayah);
      await tester.pumpAndSettle();
      expect(
        await onScreen(tester, 356, 24, ayah),
        isTrue,
        reason: '24:$ayah is recited off screen',
      );
    }
  });

  testWidgets('the view moves only when the ayah is not on screen', (
    tester,
  ) async {
    recite(24, 42);
    await showReader(tester);
    await tester.pumpAndSettle();
    final before = offsetOf(tester);
    recite(24, 43); // lines 2-4: on screen already
    await tester.pumpAndSettle();
    expect(offsetOf(tester), before);
  });

  testWidgets('turned sideways mid-recitation, it opens on the ayah', (
    tester,
  ) async {
    // The recitation is on 24:49, two thirds down the page, when the phone
    // is turned: the landscape reader is built at the page's top.
    recite(24, 49);
    await showReader(tester);
    await tester.pumpAndSettle();
    expect(await onScreen(tester, 356, 24, 49), isTrue);
  });

  testWidgets('the ayah is kept above the recitation bar', (tester) async {
    const bar = 80.0;
    recite(24, 42);
    await showReader(tester, obscuredBottom: bar);
    await tester.pumpAndSettle();
    for (final ayah in [44, 45, 46, 47]) {
      recite(24, ayah);
      await tester.pumpAndSettle();
      expect(
        await onScreen(tester, 356, 24, ayah, obscuredBottom: bar),
        isTrue,
        reason: '24:$ayah is under the bar',
      );
    }
  });

  testWidgets('the page turn shows the new page and its first ayah', (
    tester,
  ) async {
    recite(24, 51); // the last ayah of page 356
    await showReader(tester);
    await tester.pumpAndSettle();
    expect(await onScreen(tester, 356, 24, 51), isTrue);

    // The recitation reaches page 357.
    final regions357 = (await AyahRegionService.forPage(357))!;
    final first = regions357.ayahs.first;
    key.currentState!.followRecitationToPage(356);
    recite(first.surah, first.ayah);
    await tester.pumpAndSettle();
    expect(await onScreen(tester, 357, first.surah, first.ayah), isTrue);
    expect(
      offsetOf(tester),
      greaterThanOrEqualTo(356 * pageHeight - 1),
      reason: 'the top of the view is on the new page',
    );
  });

  testWidgets('a reader who went to another page is left there', (
    tester,
  ) async {
    recite(24, 42);
    await showReader(tester);
    await tester.pumpAndSettle();

    // From the index, while the recitation goes on: page 101.
    key.currentState!.scrollToPage(100);
    await tester.pumpAndSettle();
    recite(24, 45);
    await tester.pumpAndSettle();
    expect(offsetOf(tester), closeTo(100 * pageHeight, 0.5));
  });

  testWidgets('a drag of the reader is not fought', (tester) async {
    recite(24, 42);
    await showReader(tester);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    final dragged = offsetOf(tester);
    recite(24, 49); // far below, while the finger is still down
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(offsetOf(tester), dragged);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('auto-scroll keeps its own pace inside the page', (
    tester,
  ) async {
    recite(24, 42);
    await showReader(tester, autoScroll: true);
    await tester.pump(const Duration(milliseconds: 100));
    final before = offsetOf(tester);
    recite(24, 49);
    await tester.pump(const Duration(milliseconds: 500));
    // Speed 0: nothing else moves it.
    expect(offsetOf(tester), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a search result further down the page is shown', (
    tester,
  ) async {
    await showReader(tester);
    await tester.pumpAndSettle();
    expect(await onScreen(tester, 356, 24, 50), isFalse);
    unawaited(key.currentState!.revealAyah(355, 24, 50));
    await tester.pumpAndSettle();
    expect(await onScreen(tester, 356, 24, 50), isTrue);
  });

  group('the scroll rule', () {
    test('in view: stays', () {
      expect(
        revealScrollOffset(
          offset: 100,
          viewport: 300,
          maxScroll: 5000,
          targetTop: 150,
          targetBottom: 350,
        ),
        isNull,
      );
    });

    test('below: its top goes near the top of the view', () {
      expect(
        revealScrollOffset(
          offset: 100,
          viewport: 300,
          maxScroll: 5000,
          targetTop: 380,
          targetBottom: 450,
          lead: 12,
        ),
        368,
      );
    });

    test('half under the bar counts as off screen', () {
      expect(
        revealScrollOffset(
          offset: 0,
          viewport: 300,
          maxScroll: 5000,
          targetTop: 200,
          targetBottom: 260,
          bottomInset: 80,
          lead: 12,
        ),
        188,
      );
    });

    test('above: brought back down', () {
      expect(
        revealScrollOffset(
          offset: 1000,
          viewport: 300,
          maxScroll: 5000,
          targetTop: 900,
          targetBottom: 950,
          lead: 12,
        ),
        888,
      );
    });

    test('the first lines of a page: the page top, not the page before', () {
      expect(
        revealScrollOffset(
          offset: 500,
          viewport: 300,
          maxScroll: 5000,
          targetTop: 1005,
          targetBottom: 1060,
          minOffset: 1000,
          lead: 12,
        ),
        1000,
      );
    });

    test('never past the end', () {
      expect(
        revealScrollOffset(
          offset: 0,
          viewport: 300,
          maxScroll: 400,
          targetTop: 600,
          targetBottom: 650,
        ),
        400,
      );
    });
  });

  group('an ayah taller than the screen', () {
    // Five full lines, 60 px each.
    final lines = [
      for (var i = 0; i < 5; i++) Rect.fromLTWH(0, i * 60.0, 700, 58),
    ];

    test('a short ayah is shown whole', () {
      expect(followSpan(lines.take(2).toList(), 300, 0.9), (0, 118));
    });

    test('the line being recited and the one before it', () {
      expect(followSpan(lines, 200, 0), (0, 58));
      expect(followSpan(lines, 200, 0.5), (60, 178));
      expect(followSpan(lines, 200, 1), (180, 298));
    });

    test('a short last line takes a short time', () {
      final withShortEnd = [...lines.take(4), const Rect.fromLTWH(500, 240, 200, 58)];
      // 4 x 700 + 200 = 3000: the last line starts at 93 %.
      expect(readingLineIndex(withShortEnd, 0.9), 3);
      expect(readingLineIndex(withShortEnd, 0.95), 4);
    });

    test('lines are read top to bottom, right to left', () {
      final shuffled = [
        const Rect.fromLTWH(0, 60, 300, 58),
        const Rect.fromLTWH(0, 0, 700, 58),
        const Rect.fromLTWH(400, 60, 300, 58),
      ];
      expect(orderedLines(shuffled), [
        const Rect.fromLTWH(0, 0, 700, 58),
        const Rect.fromLTWH(400, 60, 300, 58),
        const Rect.fromLTWH(0, 60, 300, 58),
      ]);
    });
  });
}

/// A page image that never arrives: the test is about where the view is.
class _BlankPage extends ImageProvider<_BlankPage> {
  const _BlankPage();

  @override
  Future<_BlankPage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_BlankPage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);

  @override
  bool operator ==(Object other) => other is _BlankPage;

  @override
  int get hashCode => 0;
}

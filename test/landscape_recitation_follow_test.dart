import 'dart:async';
import 'dart:math' as math;

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

  final key = GlobalKey<ContinuousQuranViewState>();

  Future<void> showReader(
    WidgetTester tester, {
    int initialPage = 355, // page 356, 0-based
    bool autoScroll = false,
    double obscuredBottom = 0,
    double height = 360,
  }) async {
    tester.view.physicalSize = Size(screen.width, height);
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

  /// Whether page [page]'s ayah ([surah], [ayah]) is on screen above
  /// [obscuredBottom], judged on its tint (the boxes the highlight paints):
  /// all of it, or for an ayah taller than the screen its first line, the
  /// one being recited when it starts.
  Future<bool> onScreen(
    WidgetTester tester,
    int page,
    int surah,
    int ayah, {
    double obscuredBottom = 0,
    double height = 360,
  }) async {
    final lines = (await ayahLineBoxes(
      pageNumber: page,
      keys: {(surah, ayah)},
      box: Size(screen.width, pageHeight),
      marginView: false,
    ))!;
    expect(lines, isNotEmpty, reason: '$surah:$ayah is not on page $page');
    final pageTop = (page - 1) * pageHeight;
    final top = pageTop + lines.map((r) => r.top).reduce(math.min);
    final bottom = pageTop + lines.map((r) => r.bottom).reduce(math.max);
    final offset = offsetOf(tester);
    final visibleBottom = offset + height - obscuredBottom;
    final room = height - obscuredBottom - 12;
    final mustShowBottom = bottom - top <= room
        ? bottom
        : pageTop + lines.first.bottom;
    return top >= offset - 0.5 && mustShowBottom <= visibleBottom + 0.5;
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
    // A taller screen, where 24:42 and 24:43 (lines 1-4) both show.
    recite(24, 42);
    await showReader(tester, height: 700);
    await tester.pumpAndSettle();
    final before = offsetOf(tester);
    expect(await onScreen(tester, 356, 24, 43, height: 700), isTrue);
    recite(24, 43);
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

  group('a pinch-zoomed page (upright reader)', () {
    // A phone held upright, page 356 filling the reader, zoomed in 2x at
    // its top: the top half of the page shows.
    const viewer = Size(400, 800);

    (TransformationController, ZoomedPageFollower) follower({
      double bar = 0,
      bool zoomed = true,
    }) {
      final controller = TransformationController(
        zoomed ? (Matrix4.identity()..scaleByDouble(2, 2, 1, 1)) : null,
      );
      final f = ZoomedPageFollower(
        controller: controller,
        active: () => zoomed,
        pageNumber: () => 356,
        pageBox: () => Offset.zero & viewer,
        viewportHeight: () => viewer.height,
        obscuredBottom: () => bar,
        marginView: () => false,
      );
      controller.addListener(f.transformChanged);
      addTearDown(() {
        f.dispose();
        controller.dispose();
      });
      return (controller, f);
    }

    /// Whether ([surah], [ayah])'s tint (or its first line, for an ayah
    /// taller than the view) is inside the zoomed view above [bar].
    Future<bool> inView(
      TransformationController c,
      int surah,
      int ayah, {
      double bar = 0,
    }) async {
      final lines = (await ayahLineBoxes(
        pageNumber: 356,
        keys: {(surah, ayah)},
        box: viewer,
        marginView: false,
      ))!;
      final s = c.value.getMaxScaleOnAxis();
      final ty = c.value.getTranslation().y;
      final top = lines.map((r) => r.top).reduce(math.min) * s + ty;
      var bottom = lines.map((r) => r.bottom).reduce(math.max) * s + ty;
      if (bottom - top > viewer.height - bar - 12) {
        bottom = lines.first.bottom * s + ty;
      }
      return top >= -0.5 && bottom <= viewer.height - bar + 0.5;
    }

    testWidgets('the view pans down to the ayah being recited', (
      tester,
    ) async {
      final (c, f) = follower();
      for (final ayah in [42, 45, 47, 49, 51]) {
        recite(24, ayah);
        f.recitationChanged();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(await inView(c, 24, ayah), isTrue, reason: '24:$ayah');
      }
      expect(c.value.getMaxScaleOnAxis(), 2, reason: 'the zoom is kept');
      expect(c.value.getTranslation().x, 0, reason: 'and the sideways spot');
    });

    testWidgets('and keeps it above the recitation bar', (tester) async {
      final (c, f) = follower(bar: 90);
      for (final ayah in [44, 46, 48]) {
        recite(24, ayah);
        f.recitationChanged();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(await inView(c, 24, ayah, bar: 90), isTrue, reason: '24:$ayah');
      }
    });

    testWidgets('an ayah already in view does not move it', (tester) async {
      final (c, f) = follower();
      recite(24, 43);
      f.recitationChanged();
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.value.getTranslation().y, 0);
    });

    testWidgets('a pinch or pan of the reader wins for a while', (
      tester,
    ) async {
      final (c, f) = follower();
      // The reader pans a little.
      c.value = c.value.clone()..setTranslationRaw(0, -10, 0);
      recite(24, 51);
      f.recitationChanged();
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.value.getTranslation().y, -10);
    });

    testWidgets('not zoomed: nothing to do', (tester) async {
      final (c, f) = follower(zoomed: false);
      recite(24, 51);
      f.recitationChanged();
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.value, Matrix4.identity());
    });
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

  group('the upright scroll mode (a page per screen)', () {
    // Pages 800 tall; the reader stopped half way down page 10 (0-based).
    const extent = 800.0;
    const pageTop = 10 * extent;

    test('the ayah shows: stays', () {
      expect(
        pageScrollRevealOffset(
          offset: pageTop + 400,
          viewport: extent,
          maxScroll: 600 * extent,
          pageTop: pageTop,
          ayahTop: pageTop + 500,
          ayahBottom: pageTop + 600,
        ),
        isNull,
      );
    });

    test('in the half above the screen: the whole page', () {
      expect(
        pageScrollRevealOffset(
          offset: pageTop + 400,
          viewport: extent,
          maxScroll: 600 * extent,
          pageTop: pageTop,
          ayahTop: pageTop + 100,
          ayahBottom: pageTop + 200,
        ),
        pageTop,
      );
    });

    test('under the bar at the page foot: the ayah at the top', () {
      expect(
        pageScrollRevealOffset(
          offset: pageTop,
          viewport: extent,
          maxScroll: 600 * extent,
          pageTop: pageTop,
          ayahTop: pageTop + 720,
          ayahBottom: pageTop + 780,
          bottomInset: 100,
          lead: 12,
        ),
        pageTop + 708,
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

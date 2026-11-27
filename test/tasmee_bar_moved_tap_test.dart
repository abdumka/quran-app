import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/recitation_engine.dart';
import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/memorization_test_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QuietEngine extends RecitationEngine {
  final _controller = StreamController<RecognizedSegment>.broadcast();

  @override
  Stream<RecognizedSegment> get segments => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async => _controller.close();
}

/// Owner 2026-11-03: once the bar had stepped out of the way of the line
/// being read, none of its buttons worked (it was only painted elsewhere).
void main() {
  final service = MemorizationTestService.instance;
  setUp(resetTasmeeBarPlaceForTest);
  tearDown(() async => service.stop());

  testWidgets('the bar moves off the line being read and its buttons still work',
      (tester) async {
    await tester.runAsync(
      () => service.start(
        pageNumber: 1,
        engineOverride: _QuietEngine(),
        stopPlayback: false,
      ),
    );
    // The bar's saved place: right on the first line of the page.
    final first = service.regions!.ayahs.first.rects.first;
    SharedPreferences.setMockInitialValues({
      'tasmee_bar_pos': '0.0,${first.y}',
    });

    // The page box is really 400 x 800 (the default test screen is 600
    // high, which would squeeze it).
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const size = Size(400, 800);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: size,
              child: const MemorizationTestOverlay(pageNumber: 1),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Moved clear of the first line (whose top is at first.y of the box).
    final ayahButton = find.text('الآية');
    expect(ayahButton, findsOneWidget);
    final barTop = tester.getTopLeft(find.text('كلمة')).dy;
    final lineTop = first.y * size.height;
    final lineBottom = (first.y + first.height) * size.height;
    expect(
      barTop > lineBottom || tester.getBottomLeft(ayahButton).dy < lineTop,
      isTrue,
      reason: 'bar text at $barTop, line $lineTop..$lineBottom',
    );

    // And a tap on the moved bar reaches its button.
    expect(service.wordStatusesOf(0).every((s) => s == WordStatus.correct), isFalse);
    await tester.tap(ayahButton);
    await tester.pump();
    expect(
      service.wordStatusesOf(0).every((s) => s != WordStatus.pending),
      isTrue,
      reason: '«الآية» uncovered the first ayah',
    );
  });

  // Owner 2026-11-27: after one «تخطَّ» the bar never stepped aside again
  // on that page: a skipped ayah's words stay marked skipped, and the bar
  // took the first of them as the line being read.
  testWidgets('after «تخطَّ» the bar still steps off the line being read',
      (tester) async {
    await tester.runAsync(
      () => service.start(
        pageNumber: 3,
        engineOverride: _QuietEngine(),
        stopPlayback: false,
      ),
    );
    final ayahs = service.regions!.ayahs;
    // The bar's saved place: on the first line of the first ayah that
    // starts at least 5 lines below the first one, far from the line
    // being read at the start.
    final first = ayahs.first.rects.first;
    final k = ayahs.indexWhere(
      (a) => a.rects.first.y > first.y + 5 * first.height,
    );
    expect(k, greaterThan(0));
    final target = ayahs[k].rects.first;
    SharedPreferences.setMockInitialValues({
      'tasmee_bar_pos': '0.0,${target.y}',
    });

    // The page box is really 400 x 800 (the default test screen is 600
    // high, which would squeeze it).
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const size = Size(400, 800);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: size,
              child: const MemorizationTestOverlay(pageNumber: 3),
            ),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    double barTop() => tester.getTopLeft(find.text('كلمة')).dy;
    await settle();
    final home = barTop();

    // Skip every ayah before it: the reading reaches the bar's line.
    for (var i = 0; i < k; i++) {
      await tester.tap(find.text('تخطَّ'));
      await settle();
    }
    expect(service.currentAyahIndex, k);
    expect(service.wordStatusesOf(0).first, WordStatus.skipped);
    final top = barTop();
    final bottom = tester.getBottomLeft(find.text('تخطَّ')).dy;
    final lineTop = target.y * size.height;
    final lineBottom = (target.y + target.height) * size.height;
    expect(
      top > lineBottom || bottom < lineTop,
      isTrue,
      reason: 'bar $top..$bottom, line $lineTop..$lineBottom',
    );
    expect(top, isNot(closeTo(home, 1)), reason: 'the bar moved');
  });
}

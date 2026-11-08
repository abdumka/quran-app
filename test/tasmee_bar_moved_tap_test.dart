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
}

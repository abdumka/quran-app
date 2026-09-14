import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/recitation_engine.dart';
import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/memorization_test_overlay.dart';

/// Hand-driven engine so the test controls exactly when segments arrive.
class _ManualEngine extends RecitationEngine {
  final _controller = StreamController<RecognizedSegment>.broadcast();

  void emit(String segment, {bool isFinal = true}) =>
      _controller.add(RecognizedSegment(segment, isFinal: isFinal));

  @override
  Stream<RecognizedSegment> get segments => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async => _controller.close();
}

/// Counts the mask/wash boxes the overlay currently draws. Each rendered
/// region rect is exactly one `Positioned.fromRect` whose direct child is a
/// DecoratedBox -- revealed ayahs draw nothing. The predicate deliberately
/// excludes the floating listening chip (its Positioned stretches with
/// left+right and wraps a Center, not a DecoratedBox).
int _boxCount(WidgetTester tester) => tester
    .widgetList(
      find.descendant(
        of: find.byType(MemorizationTestOverlay),
        matching: find.byWidgetPredicate(
          (w) => w is Positioned && w.width != null && w.child is DecoratedBox,
        ),
      ),
    )
    .length;

void main() {
  final service = MemorizationTestService.instance;

  /// `start()` does real async work (rootBundle + `compute()` isolates),
  /// which never completes inside testWidgets' fake-async zone -- so it has
  /// to run through `runAsync`.
  Future<void> startSession(WidgetTester tester, RecitationEngine engine) async {
    await tester.runAsync(
      () => service.start(
        pageNumber: 1,
        engineOverride: engine,
        stopPlayback: false,
      ),
    );
  }

  /// Emits a segment and pumps until the resulting repaint has landed. The
  /// stream delivers on a microtask that runs *after* the frame a single
  /// `pump()` builds, so one pump would leave the overlay a segment behind.
  Future<void> reciteAndSettle(
    WidgetTester tester,
    _ManualEngine engine,
    String segment,
  ) async {
    engine.emit(segment);
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpOverlay(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: MemorizationTestOverlay(),
          ),
        ),
      ),
    );
  }

  int rectsOf(int ayahIndex) => service.regions!.ayahs[ayahIndex].rects.length;
  int totalRects() =>
      service.regions!.ayahs.fold(0, (sum, a) => sum + a.rects.length);

  /// Mask boxes an ayah draws: one per word not yet heard correctly.
  int pendingWordsOf(int ayahIndex) => service
      .wordStatusesOf(ayahIndex)
      .where((s) => s != WordStatus.correct)
      .length;

  /// Every ayah of page 1 has word boxes, so the page is masked word by
  /// word from the start: total pending words across all ayahs.
  int pendingWords() {
    var n = 0;
    for (var i = 0; i < service.regions!.ayahs.length; i++) {
      expect(service.wordBoxesFor(i), isNotNull);
      n += pendingWordsOf(i);
    }
    return n;
  }

  tearDown(() async => service.stop());

  testWidgets('masks every ayah up-front, then unmasks each as it is recited',
      (tester) async {
    final engine = _ManualEngine();
    await startSession(tester, engine);

    await pumpOverlay(tester);
    // Nothing recited yet: ayah 1 is masked word by word (4 words), the
    // other 6 Al-Fatihah ayahs by their line rects.
    expect(pendingWordsOf(0), 4);
    expect(pendingWords(), 25);
    expect(_boxCount(tester), 25);

    await reciteAndSettle(tester, engine, 'الحمد لله');
    // Two words of ayah 1 heard: two masks fewer, nothing else changes.
    expect(pendingWordsOf(0), 2);
    expect(_boxCount(tester), 23);

    await reciteAndSettle(tester, engine, 'رب العالمين');
    // Ayah 1 revealed entirely.
    expect(_boxCount(tester), 21);

    await reciteAndSettle(tester, engine, 'الرحمن الرحيم');
    expect(_boxCount(tester), 19);
    expect(totalRects() - rectsOf(0), greaterThan(0)); // rects still exist
  });

  testWidgets('draws nothing at all once every ayah is revealed',
      (tester) async {
    final engine = _ManualEngine();
    await startSession(tester, engine);
    await pumpOverlay(tester);

    for (final segment in [
      'الحمد لله رب العالمين',
      'الرحمن الرحيم',
      'ملك يوم الدين',
      'اياك نعبد واياك نستعين',
      'اهدنا الصراط المستقيم',
      'صراط الذين انعمت عليهم',
      'غير المغضوب عليهم ولا الضالين',
    ]) {
      await reciteAndSettle(tester, engine, segment);
    }

    expect(service.status.value, MemorizationTestStatus.completed);
    // A fully-correct recitation leaves the page completely unobscured.
    expect(_boxCount(tester), 0);
  });

  testWidgets('renders nothing when no session is active', (tester) async {
    await pumpOverlay(tester);
    expect(_boxCount(tester), 0);
  });
}

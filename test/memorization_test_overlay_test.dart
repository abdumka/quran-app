import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/recitation_engine.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/memorization_test_overlay.dart';

/// Hand-driven engine so the test controls exactly when segments arrive.
class _ManualEngine implements RecitationEngine {
  final _controller = StreamController<String>.broadcast();

  void emit(String segment) => _controller.add(segment);

  @override
  Stream<String> get segments => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async => _controller.close();
}

/// Counts the mask/wash boxes the overlay currently draws. Each rendered
/// word layer is exactly one DecoratedBox, so this is the number of words
/// still hidden or flagged -- revealed (`correct`) words draw nothing.
/// Scoped to the overlay's own subtree so Material's internal DecoratedBoxes
/// (Scaffold background etc.) can't inflate the count.
int _boxCount(WidgetTester tester) => tester
    .widgetList(
      find.descendant(
        of: find.byType(MemorizationTestOverlay),
        matching: find.byType(DecoratedBox),
      ),
    )
    .length;

void main() {
  final service = MemorizationTestService.instance;

  /// `start()` does real async work (rootBundle + a `compute()` isolate to
  /// parse output.json), which never completes inside testWidgets' fake-async
  /// zone -- so it has to run through `runAsync`.
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

  tearDown(() async => service.stop());

  testWidgets('masks every word up-front, then unmasks each as it is recited',
      (tester) async {
    final engine = _ManualEngine();
    await startSession(tester, engine);

    await pumpOverlay(tester);
    // Nothing recited yet: all 25 Al-Fatihah words are hidden.
    expect(_boxCount(tester), 25);

    await reciteAndSettle(tester, engine, 'الحمد لله رب العالمين');
    // Ayah 1's four words are now revealed, so four fewer boxes.
    expect(_boxCount(tester), 21);

    await reciteAndSettle(tester, engine, 'الرحمن الرحيم');
    expect(_boxCount(tester), 19);
  });

  testWidgets('draws nothing at all once every word is revealed',
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/widgets/sheet_pull_to_close.dart';

/// A sheet taller than the screen, like the ayah video sheet on a phone.
Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showPullToCloseSheet<void>(
                context: context,
                builder: (_) => SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 60,
                        child: ListView(
                          key: const Key('chips'),
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (var i = 0; i < 30; i++)
                              SizedBox(width: 80, child: Text('chip $i')),
                          ],
                        ),
                      ),
                      for (var i = 0; i < 40; i++)
                        SizedBox(height: 50, child: Text('row $i')),
                    ],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(_sheet, findsOneWidget);
}

final _sheet = find.byType(SheetPullToClose);

void main() {
  testWidgets('a swipe down on the content closes the sheet', (tester) async {
    await _open(tester);
    await tester.drag(find.text('row 3'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
  });

  testWidgets('a quick flick down closes it too', (tester) async {
    await _open(tester);
    await tester.fling(find.text('row 3'), const Offset(0, 120), 1500);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
  });

  testWidgets('a small slow pull springs back', (tester) async {
    await _open(tester);
    final top = tester.getTopLeft(find.text('row 3')).dy;
    final g = await tester.startGesture(tester.getCenter(find.text('row 3')));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 100));
    }
    // it follows the finger while pulled (60 px less the touch slop)
    expect(tester.getTopLeft(find.text('row 3')).dy - top, closeTo(42, 3));
    await g.up();
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
    expect(tester.getTopLeft(find.text('row 3')).dy, closeTo(top, 0.5));
  });

  testWidgets('scrolled down, a swipe down scrolls back first', (
    tester,
  ) async {
    await _open(tester);
    final scroll = find.byType(SingleChildScrollView);
    double offset() =>
        tester.widget<SingleChildScrollView>(scroll).controller?.offset ??
        Scrollable.of(tester.element(find.text('row 0'))).position.pixels;
    await tester.drag(find.text('row 3'), const Offset(0, -600));
    await tester.pumpAndSettle();
    final down = offset();
    expect(down, greaterThan(400));
    await tester.drag(find.text('row 12'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget); // still open
    expect(offset(), lessThan(down - 200));
  });

  testWidgets('sideways swipes on a row of chips leave the sheet alone', (
    tester,
  ) async {
    await _open(tester);
    await tester.drag(find.byKey(const Key('chips')), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
  });
}

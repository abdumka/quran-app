import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/widgets/repeat_count_wheel.dart';

/// The number wheel in تكرار مقطع (owner, 2026-11-11): swipe up for more,
/// down for less, arrows for one, tap the chosen wheel to type; it must win
/// the swipe even inside the dialog's scroll view, and sit on one line with
/// the chips beside it.
void main() {
  late int value;
  late bool selected;

  Widget host({double width = 300, int start = 7, bool isSelected = true}) {
    value = start;
    selected = isSelected;
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 200),
                SizedBox(
                  width: width,
                  child: StatefulBuilder(
                    builder: (context, setState) => Row(
                      children: [
                        for (final n in const [2, 3, 5]) ...[
                          Expanded(
                            child: Container(
                              height: 38,
                              alignment: Alignment.center,
                              child: Text('$n×'),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: RepeatCountWheel(
                            key: const Key('wheel'),
                            value: value,
                            selected: selected,
                            accentColor: Colors.brown,
                            borderColor: Colors.grey,
                            textColor: Colors.black54,
                            onChanged: (v) => setState(() {
                              value = v;
                              selected = true;
                            }),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Expanded(child: Center(child: Text('∞'))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Finder chip() => find.byKey(RepeatCountWheel.chipKey);

  testWidgets('swiping up makes the number bigger, even in a scroll view', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final before = tester.getTopLeft(find.byKey(const Key('wheel'))).dy;
    await tester.timedDrag(
      chip().first,
      const Offset(0, -60),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(value, 11, reason: '60 px at 14 px a number');
    expect(
      tester.getTopLeft(find.byKey(const Key('wheel'))).dy,
      before,
      reason: 'the dialog must not scroll instead',
    );
  });

  testWidgets('swiping down makes it smaller, and stops at 2', (tester) async {
    await tester.pumpWidget(host(start: 4));
    await tester.timedDrag(
      chip().first,
      const Offset(0, 120),
      const Duration(milliseconds: 800),
    );
    await tester.pumpAndSettle();
    expect(value, 2);
  });

  testWidgets('a flick runs on past the finger', (tester) async {
    await tester.pumpWidget(host(start: 7));
    // 60 px alone is 4 numbers (to 11); the flick carries it further.
    await tester.fling(chip().first, const Offset(0, -60), 1500);
    await tester.pump(const Duration(seconds: 1)); // the flick's own steps
    await tester.pumpAndSettle();
    expect(value, greaterThan(11));
  });

  testWidgets('the arrows add and take one, up to 99', (tester) async {
    await tester.pumpWidget(host(start: 98));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pump();
    expect(value, 99);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pump();
    expect(value, 99);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    expect(value, 98);
  });

  testWidgets('a tap chooses it; a tap on the chosen wheel types a number, '
      'Arabic-Indic digits included', (tester) async {
    await tester.pumpWidget(host(start: 7, isSelected: false));
    await tester.tap(chip().first);
    await tester.pump();
    expect(selected, isTrue);
    expect(find.byType(TextField), findsNothing, reason: 'no keypad yet');

    await tester.tap(chip().first);
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '١٢');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(value, 12);
    expect(find.text('12×'), findsOneWidget);
  });

  testWidgets('two digits are set smaller and fit a narrow phone on one line', (
    tester,
  ) async {
    await tester.pumpWidget(host(width: 230, start: 99));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow');
    final two = tester.widget<Text>(find.text('99×'));
    await tester.pumpWidget(host(width: 230, start: 7));
    await tester.pumpAndSettle();
    final one = tester.widget<Text>(find.text('7×'));
    expect(two.style!.fontSize, lessThan(one.style!.fontSize!));
  });
}

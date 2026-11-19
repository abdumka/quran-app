// The reciter menus show six and a half rows. The cue that more follows
// (owner's pick, «شريط واضح», 2026-11-18): a wide gold bar that stays on
// screen, and a fade over the row the list's bottom edge cuts, for as long as
// there is more to scroll to.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islamic_dawah_mushaf/widgets/menu_scroll_cue.dart';

void main() {
  const rowHeight = 48.0;
  const rows = 11;

  Future<ScrollController> pumpList(WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MenuScrollCue(
              child: Builder(
                builder: (context) => SizedBox(
                  width: 300,
                  height: 6.5 * rowHeight,
                  child: ScrollbarTheme(
                    data: menuScrollbarTheme(context),
                    child: Scrollbar(
                      controller: controller,
                      child: ListView(
                        controller: controller,
                        padding: EdgeInsets.zero,
                        children: [
                          for (int i = 0; i < rows; i++)
                            SizedBox(
                              height: rowHeight,
                              child: MenuRowEdgeFade(child: Text('row $i')),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return controller;
  }

  (double, double)? fadeOf(WidgetTester tester, int row) => tester
      .state<MenuRowEdgeFadeState>(
        find.ancestor(
          of: find.text('row $row'),
          matching: find.byType(MenuRowEdgeFade),
        ),
      )
      .fade;

  testWidgets('the row cut by the bottom edge fades, rows above do not', (
    tester,
  ) async {
    await pumpList(tester);
    expect(fadeOf(tester, 0), isNull);
    expect(fadeOf(tester, 3), isNull);
    // Row 6 starts at 288 and the list ends at 312: half of it shows.
    final cut = fadeOf(tester, 6);
    expect(cut, isNotNull);
    expect(cut!.$2, 24, reason: 'the fade ends where the edge cuts the row');
    expect(cut.$1, 24 - MenuRowEdgeFade.fadeLength);
  });

  testWidgets('nothing fades once the list is at its end', (tester) async {
    final controller = await pumpList(tester);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    for (int i = 4; i < rows; i++) {
      expect(fadeOf(tester, i), isNull, reason: 'row $i');
    }
  });

  testWidgets('the fade follows the list as it scrolls', (tester) async {
    final controller = await pumpList(tester);
    controller.jumpTo(2 * rowHeight);
    await tester.pump();
    await tester.pump();
    // Row 8 is now the one the edge cuts in half.
    expect(fadeOf(tester, 8), isNotNull);
    expect(fadeOf(tester, 6), isNull);
  });

  testWidgets('the bar is wide, gold and always shown', (tester) async {
    await pumpList(tester);
    final theme = ScrollbarTheme.of(tester.element(find.text('row 0')));
    expect(theme.thickness?.resolve({}), 7);
    expect(theme.thumbVisibility?.resolve({}), isTrue);
    expect(theme.trackVisibility?.resolve({}), isTrue);
    expect(theme.thumbColor?.resolve({}), const Color(0xFFD2B97E));
  });
}

// A vertical D-pad step must not escape the list it is in while that list
// still has somewhere to scroll.
//
// Reported from a real television: in إعدادات, going all the way down and then
// back up did not return to the top of the list -- the highlight jumped to the
// app bar's back arrow instead, leaving every row above the fold unreachable
// by remote.
//
// The cause is that TvFocusScope walks the SEMANTICS tree, and a lazy list
// only builds the rows on screen. From the topmost built row, the previous
// entry in reading order genuinely was the back arrow. The fix scrolls the
// list first so those rows exist, then steps.
//
// The assertion is black box: drive the remote, then press Select and see
// which callback ran. That is exactly what the user experiences, and it does
// not reach into TvFocusScope's private highlight state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:islamic_dawah_mushaf/services/tv_service.dart';
import 'package:islamic_dawah_mushaf/widgets/tv/tv_focus_scope.dart';

const int kRowCount = 40;

/// An app bar with a back arrow above a long lazy list, which is the shape of
/// the settings screen the bug was reported on.
Widget harness({
  required void Function(String) onActivate,
  required ScrollController controller,
}) {
  return MaterialApp(
    home: TvFocusScope(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => onActivate('back'),
          ),
          title: const Text('الإعدادات'),
        ),
        body: ListView.builder(
          controller: controller,
          itemCount: kRowCount,
          itemBuilder: (context, i) => InkWell(
            onTap: () => onActivate('row$i'),
            child: SizedBox(height: 96, child: Center(child: Text('row $i'))),
          ),
        ),
      ),
    ),
  );
}

Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, [
  int n = 1,
]) async {
  for (int i = 0; i < n; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump(const Duration(milliseconds: 50));
  }
  // Select schedules retries out to 800 ms (menus animate closed before their
  // semantics settle), so let those run or the test ends with timers pending.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => TvService.instance.debugIsTv = true);
  tearDown(() => TvService.instance.debugIsTv = false);

  testWidgets('every Up step moves exactly one row, never skipping out', (
    tester,
  ) async {
    final activated = <String>[];
    final controller = ScrollController();
    await tester.pumpWidget(
      harness(onActivate: activated.add, controller: controller),
    );
    await tester.pumpAndSettle();

    // The highlight starts on the first target in reading order, which is the
    // app bar's back arrow. So N downs land on row N-1.
    await press(tester, LogicalKeyboardKey.arrowDown, 20);
    expect(
      controller.position.pixels,
      greaterThan(0),
      reason: 'Down should have scrolled the list',
    );

    // One fewer Up than Down leaves us on row 0 -- but only if every Up moved
    // exactly one row. Before the fix, the first Up taken from the topmost
    // BUILT row jumped straight to the back arrow, so these steps overshot
    // and the remaining ones went nowhere.
    await press(tester, LogicalKeyboardKey.arrowUp, 19);
    await press(tester, LogicalKeyboardKey.select);

    expect(activated, ['row0']);
  });

  testWidgets('going down then back up returns near the top of the list', (
    tester,
  ) async {
    final activated = <String>[];
    final controller = ScrollController();
    await tester.pumpWidget(
      harness(onActivate: activated.add, controller: controller),
    );
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowDown, 20);
    await press(tester, LogicalKeyboardKey.arrowUp, 25);

    expect(
      controller.position.pixels,
      lessThan(96.0),
      reason: 'the list should have scrolled back to the top',
    );
  });

  testWidgets('the app bar is still reachable once the list is at its top', (
    tester,
  ) async {
    final activated = <String>[];
    final controller = ScrollController();
    await tester.pumpWidget(
      harness(onActivate: activated.add, controller: controller),
    );
    await tester.pumpAndSettle();

    // Never scrolled: from the first row, Up has nowhere to scroll, so the
    // highlight must be allowed to leave for the back arrow.
    await press(tester, LogicalKeyboardKey.arrowUp, 3);
    await press(tester, LogicalKeyboardKey.select);

    expect(activated, ['back']);
  });
}

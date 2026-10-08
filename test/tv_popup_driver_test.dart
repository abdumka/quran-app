// A dialog or modal sheet on TV must be operable by remote.
//
// Reported from a real television: opening the bookmarks and pressing إغلاق
// did nothing, and only the Back button got out. That was not one broken
// button. Select is blocked app-wide on TV (so a single DPAD_CENTER cannot
// both run a screen's handler and "click" whatever holds Flutter focus), and
// nothing drove popups, so EVERY dialog and sheet opened from a screen that
// handles its own D-pad had dead buttons -- about twenty of them.
//
// The fix is one driver above the navigator that engages only while a
// PopupRoute is on top. These tests pin the behaviour that makes it safe:
// it operates popups, and it keeps out of the way otherwise.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islamic_dawah_mushaf/services/tv_popup_observer.dart';
import 'package:islamic_dawah_mushaf/services/tv_service.dart';
import 'package:islamic_dawah_mushaf/widgets/tv/tv_focus_scope.dart';

/// Mirrors how main() wires the driver up, so the test exercises the real
/// arrangement rather than a convenient one.
Widget app({required Widget home}) {
  return MaterialApp(
    navigatorKey: kAppNavigatorKey,
    navigatorObservers: [TvPopupObserver.instance],
    // main() blocks these app-wide on TV so one DPAD_CENTER cannot both run a
    // handler and activate whatever holds Flutter focus. Without it here the
    // harness would be a kinder environment than the real app, and would hide
    // exactly the double-activation that block exists to prevent.
    shortcuts: <ShortcutActivator, Intent>{
      ...WidgetsApp.defaultShortcuts,
      const SingleActivator(LogicalKeyboardKey.select):
          const DoNothingAndStopPropagationIntent(),
      const SingleActivator(LogicalKeyboardKey.enter):
          const DoNothingAndStopPropagationIntent(),
      const SingleActivator(LogicalKeyboardKey.gameButtonA):
          const DoNothingAndStopPropagationIntent(),
    },
    builder: (context, child) =>
        TvFocusScope.popupDriver(child: child ?? const SizedBox.shrink()),
    home: home,
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
  // Select schedules retries out to 800 ms; let them run or the test ends
  // with timers pending.
  // Long enough to outlive the ring's delayed rect corrections (up to
  // 600 ms) and Select's retries (up to 800 ms), or the test ends with
  // timers pending.
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TvService.instance.debugIsTv = true;
    // The observer is a singleton and the previous test's routes are never
    // popped, so without this popupOnTop is still true when the next test
    // starts.
    TvPopupObserver.instance.reset();
  });
  tearDown(() => TvService.instance.debugIsTv = false);

  testWidgets('a dialog button can be activated by remote', (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      app(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    content: const Text('العلامات'),
                    actions: [
                      TextButton(
                        onPressed: () => pressed.add('إغلاق'),
                        child: const Text('إغلاق'),
                      ),
                    ],
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
    expect(find.text('إغلاق'), findsOneWidget);
    expect(TvPopupObserver.instance.popupOnTop.value, isTrue);

    await press(tester, LogicalKeyboardKey.select);

    expect(pressed, [
      'إغلاق',
    ], reason: 'the remote could not work the dialog button');
  });

  testWidgets('arrows reach a second button in the dialog', (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      app(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    content: const Text('تأكيد'),
                    actions: [
                      TextButton(
                        onPressed: () => pressed.add('cancel'),
                        child: const Text('إلغاء'),
                      ),
                      TextButton(
                        onPressed: () => pressed.add('ok'),
                        child: const Text('موافق'),
                      ),
                    ],
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

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);

    expect(pressed, isNotEmpty, reason: 'Select did nothing after a step');
    expect(pressed.single, anyOf('cancel', 'ok'));
  });

  testWidgets('a modal bottom sheet is driven too', (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      app(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => SizedBox(
                    height: 200,
                    child: Center(
                      child: TextButton(
                        onPressed: () => pressed.add('sheet'),
                        child: const Text('تشغيل'),
                      ),
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

    await press(tester, LogicalKeyboardKey.select);

    expect(pressed, ['sheet']);
  });

  testWidgets('the driver stays out of the way when no popup is open', (
    tester,
  ) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      app(
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => pressed.add('page'),
              child: const Text('زر في الصفحة'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(TvPopupObserver.instance.popupOnTop.value, isFalse);
    await press(tester, LogicalKeyboardKey.select);

    expect(
      pressed,
      isEmpty,
      reason:
          'the driver activated a page button; it must leave pages to the '
          'screens that drive their own D-pad',
    );
  });

  testWidgets('a page pushed from a wrapped page is driven by that scope', (
    tester,
  ) async {
    // The audit leans on this: PageColorPreviewPage, DownloadsManagementPage
    // and FullscreenMenuPage are all pushed from إعدادات, which is wrapped,
    // so they need no wrapper of their own. TvFocusScope collects from the
    // global semantics root and narrows to the innermost route scope, which
    // is the newly pushed page. If that ever stops being true, those three
    // go dead and this test is the warning.
    final pressed = <String>[];
    await tester.pumpWidget(
      app(
        home: TvFocusScope(
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed: () => pressed.add('inner'),
                            child: const Text('زر في الصفحة الداخلية'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      TvPopupObserver.instance.popupOnTop.value,
      isFalse,
      reason:
          'a pushed page is not a popup, so the root driver is not what '
          'is being tested here',
    );

    await press(tester, LogicalKeyboardKey.select);

    expect(pressed, ['inner']);
  });

  testWidgets('arrows do not move Flutter focus while a popup is open', (
    tester,
  ) async {
    // Two cursors was the bug. A Material dropdown menu opens in its OWN
    // route, which no scope's ExcludeFocus covers, so the menu moved its grey
    // highlight on every arrow press while the scope moved the gold ring.
    // They drifted apart -- grey on 15. الحجر, ring on 19. مريم -- and Select
    // fired on the ring, which read as the تكرار مقطع picker skipping surahs.
    //
    // Two stacked focusable buttons, so directional traversal has somewhere
    // to go: without the barrier the arrow moves focus from one to the other.
    final first = FocusNode(debugLabel: 'first');
    final second = FocusNode(debugLabel: 'second');
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      app(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    content: SizedBox(
                      height: 200,
                      child: Column(
                        children: [
                          TextButton(
                            focusNode: first,
                            onPressed: () {},
                            child: const Text('أ'),
                          ),
                          const Spacer(),
                          TextButton(
                            focusNode: second,
                            onPressed: () {},
                            child: const Text('ب'),
                          ),
                        ],
                      ),
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

    first.requestFocus();
    await tester.pumpAndSettle();
    expect(first.hasFocus, isTrue, reason: 'could not seed focus');

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(
      second.hasFocus,
      isFalse,
      reason: 'directional traversal ran alongside the scope: two cursors',
    );
    expect(first.hasFocus, isTrue);
  });

  testWidgets('a text field inside a popup can still take focus', (
    tester,
  ) async {
    // The driver must not exclude focus app-wide: a dialog that asks for a
    // bookmark name has to be typeable on TV.
    await tester.pumpWidget(
      app(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: TextField()),
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

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final node = FocusScope.of(
      tester.element(find.byType(TextField)),
    ).focusedChild;
    expect(node?.hasFocus, isTrue, reason: 'the text field could not focus');
  });
}

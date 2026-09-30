import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/search_page.dart';

/// The app draws edge to edge, so the results list runs under the system
/// navigation bar. Scrolled to the end, the last result has to come to rest
/// above the bar, or it is only ever seen half covered (and screenshots of the
/// results always look cropped).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dpr = 2.625; // Pixel 7
  const screen = Size(1080 / dpr, 2400 / dpr);

  /// A result card: the one box on the page painted in the card colour.
  final cards = find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).color == const Color(0xFFF7F3EA),
  );

  /// Opens the search page, searches for [query] and scrolls the results to
  /// the very end. Returns where the last card's bottom edge comes to rest.
  Future<double> lastCardBottom(
    WidgetTester tester, {
    required Size size,
    required double navBar,
    double keyboard = 0,
    String query = 'موسى',
  }) async {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = size * dpr;
    tester.view.viewPadding = FakeViewPadding(bottom: navBar * dpr);
    // As on a phone: the keyboard takes over the navigation bar's space, so
    // the bar stops counting as padding while the keyboard is up.
    tester.view.padding = FakeViewPadding(
      bottom: (navBar - keyboard).clamp(0, navBar) * dpr,
    );
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
    addTearDown(tester.view.reset);

    late double bottom;
    await tester.runAsync(() async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => SearchPage(onGoToPage: (_, {surah, ayah}) {}),
        ),
      );

      Future<bool> settleUntil(Finder finder) async {
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return true;
        }
        return false;
      }

      expect(await settleUntil(find.byType(TextField)), isTrue);
      await tester.enterText(find.byType(TextField), query);
      expect(await settleUntil(cards), isTrue, reason: 'results show');

      final list = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(list).position;
      expect(position.maxScrollExtent, greaterThan(0), reason: 'must scroll');
      // A lazy list only estimates its length until the end is laid out, so
      // keep jumping until the end stops moving.
      for (var i = 0; i < 20; i++) {
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        if (position.pixels == position.maxScrollExtent) break;
      }
      expect(position.pixels, position.maxScrollExtent);

      bottom = cards
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)).bottom)
          .reduce((a, b) => a > b ? a : b);
    });
    return bottom;
  }

  group('the last search result, scrolled to the end', () {
    testWidgets('clears a 3-button navigation bar', (tester) async {
      const navBar = 48.0;
      final bottom = await lastCardBottom(
        tester,
        size: screen,
        navBar: navBar,
      );
      expect(bottom, lessThanOrEqualTo(screen.height - navBar));
    });

    testWidgets('clears the gesture handle', (tester) async {
      const navBar = 24.0;
      final bottom = await lastCardBottom(
        tester,
        size: screen,
        navBar: navBar,
      );
      expect(bottom, lessThanOrEqualTo(screen.height - navBar));
    });

    testWidgets('clears the bar in landscape', (tester) async {
      const navBar = 24.0;
      final landscape = screen.flipped;
      final bottom = await lastCardBottom(
        tester,
        size: landscape,
        navBar: navBar,
      );
      expect(bottom, lessThanOrEqualTo(landscape.height - navBar));
    });

    testWidgets('sits just above the keyboard, without the bar\'s gap too', (
      tester,
    ) async {
      // The keyboard already covers the navigation bar; padding for the bar
      // on top of that would leave a blank strip above the keyboard.
      const navBar = 48.0;
      const keyboard = 300.0;
      final bottom = await lastCardBottom(
        tester,
        size: screen,
        navBar: navBar,
        keyboard: keyboard,
      );
      final keyboardTop = screen.height - keyboard;
      expect(bottom, lessThanOrEqualTo(keyboardTop));
      expect(bottom, greaterThan(keyboardTop - navBar));
    });

    testWidgets('keeps its small margin with no navigation bar at all', (
      tester,
    ) async {
      final bottom = await lastCardBottom(tester, size: screen, navBar: 0);
      expect(bottom, lessThan(screen.height));
      expect(bottom, greaterThan(screen.height - 24));
    });
  });
}

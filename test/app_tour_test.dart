import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/app_tour_service.dart';
import 'package:islamic_dawah_mushaf/services/whats_new_service.dart';
import 'package:islamic_dawah_mushaf/widgets/tour/tour_scenes.dart';
import 'package:islamic_dawah_mushaf/widgets/tour/welcome_tour_page.dart';
import 'package:islamic_dawah_mushaf/widgets/tour/whats_new_deck.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('who sees the welcome tour', () {
    test('a fresh install does', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(AppTourService.instance.shouldShowWelcome(prefs), isTrue);
    });

    test('someone updating with a reading position does not, ever', () async {
      SharedPreferences.setMockInitialValues({'lastPage': 40});
      final prefs = await SharedPreferences.getInstance();
      expect(AppTourService.instance.shouldShowWelcome(prefs), isFalse);
      expect(prefs.getBool('welcomeTourSeen'), isTrue);
    });

    test('someone who saw a What\'s New popup does not', () async {
      SharedPreferences.setMockInitialValues({
        WhatsNewService.lastSeenBuildPrefKey: 140,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(AppTourService.instance.shouldShowWelcome(prefs), isFalse);
    });

    test(
      'after the tour: not again, and the bookmark hint is retired',
      () async {
        SharedPreferences.setMockInitialValues({});
        await AppTourService.instance.markWelcomeSeen();
        final prefs = await SharedPreferences.getInstance();
        expect(AppTourService.instance.shouldShowWelcome(prefs), isFalse);
        expect(prefs.getBool('bookmarkGuideDismissed'), isTrue);
      },
    );
  });

  test('every story and card has its words', () {
    for (final scene in TourScene.values) {
      expect(kTourText[scene], isNotNull, reason: '$scene');
    }
    for (final id in WhatsNewService.tourCards) {
      expect(WhatsNewDeck.sceneFor(id), isNotNull, reason: id);
    }
  });

  test('no Eastern digits or em dashes in the tour words', () {
    final bad = RegExp('[٠-٩۰-۹—]');
    for (final t in kTourText.values) {
      expect(bad.hasMatch(t.title + t.body), isFalse, reason: t.title);
    }
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  testWidgets('welcome tour: «تخطّ» ends it in one tap', (tester) async {
    phone(tester);
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: WelcomeTourPage(onFinish: () => finished++)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('تخطّ'));
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('welcome tour: every story plays, the last one finishes', (
    tester,
  ) async {
    phone(tester);
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: WelcomeTourPage(onFinish: () => finished++)),
    );
    final n = WelcomeTourPage.stories.length;
    for (var i = 1; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('التالي'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('${i + 1} / $n'), findsOneWidget);
    }
    expect(finished, 0);
    await tester.tap(find.text('ابدأ القراءة'));
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('welcome tour moves on by itself', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(home: WelcomeTourPage(onFinish: () {})),
    );
    expect(find.text('1 / ${WelcomeTourPage.stories.length}'), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('2 / ${WelcomeTourPage.stories.length}'), findsOneWidget);
  });

  testWidgets('every scene draws on a small landscape screen too', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    for (final scene in TourScene.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: TourSceneView(key: ValueKey(scene), scene: scene),
            ),
          ),
        ),
      );
      for (var t = 0; t < 12; t++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(tester.takeException(), isNull, reason: '$scene');
    }
  });

  testWidgets('deck: «التالي» through the cards, then it closes', (
    tester,
  ) async {
    phone(tester);
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await WhatsNewDeck.show(
                  context,
                  WhatsNewService.tourCards,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 1; i < WhatsNewService.tourCards.length; i++) {
      await tester.tap(find.text('التالي'));
      await tester.pump(const Duration(milliseconds: 700));
    }
    await tester.tap(find.text('حسنًا'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(result, isNull);
    expect(find.text('حسنًا'), findsNothing);
  });

  testWidgets('deck: no «جرّبها الآن»; «كل التغييرات» returns all', (
    tester,
  ) async {
    phone(tester);
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await WhatsNewDeck.show(
                  context,
                  WhatsNewService.tourCards,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < WhatsNewService.tourCards.length; i++) {
      expect(find.textContaining('جرّبها'), findsNothing);
      if (i < WhatsNewService.tourCards.length - 1) {
        await tester.tap(find.text('التالي'));
        await tester.pump(const Duration(milliseconds: 700));
      }
    }
    await tester.tap(find.text('كل التغييرات في هذا الإصدار'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(result, WhatsNewDeck.allChangesId);
  });

  group('the replay from the side menu closes', () {
    Future<void> openReplay(WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => WelcomeTourPage.replay(context),
                  child: const Text('menu'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(WelcomeTourPage), findsOneWidget);
    }

    Future<void> expectClosed(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(WelcomeTourPage), findsNothing);
      expect(find.text('menu'), findsOneWidget);
    }

    testWidgets('after all 12 stories, «ابدأ القراءة»', (tester) async {
      await openReplay(tester);
      for (var i = 1; i < WelcomeTourPage.stories.length; i++) {
        await tester.tap(find.text('التالي'));
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.tap(find.text('ابدأ القراءة'));
      await expectClosed(tester);
    });

    testWidgets('«تخطّ»', (tester) async {
      await openReplay(tester);
      await tester.tap(find.text('تخطّ'));
      await expectClosed(tester);
    });

    testWidgets('Back', (tester) async {
      await openReplay(tester);
      await tester.binding.handlePopRoute();
      await expectClosed(tester);
    });
  });
}

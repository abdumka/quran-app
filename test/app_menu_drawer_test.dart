import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/app_update_service.dart';
import 'package:islamic_dawah_mushaf/services/chat_service.dart';
import 'package:islamic_dawah_mushaf/widgets/menu/app_menu_drawer.dart';
import 'package:islamic_dawah_mushaf/widgets/top_overlay_bar.dart';

void main() {
  group('side drawer', () {
    late List<String> called;

    AppMenuActions actions() => AppMenuActions(
      openSettings: () => called.add('settings'),
      openTafsir: () => called.add('tafsir'),
      openReciter: () => called.add('reciter'),
      openDownloads: () => called.add('downloads'),
      openReminders: () => called.add('reminders'),
      openReports: () => called.add('reports'),
      openWhatsNew: () => called.add('whatsNew'),
    );

    Future<void> openDrawer(
      WidgetTester tester, {
      Size screen = const Size(1080, 2400),
    }) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      AppMenuDrawer.show(context, actions: actions()),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    setUp(() {
      called = [];
      ChatService.instance.unread.value = 0;
      AppUpdateService.instance.currentVersion = '1.5.6';
    });

    testWidgets(
      'shows today\'s rows, grouped, with the version at the bottom',
      (tester) async {
        await openDrawer(tester);
        for (final label in [
          'المصحف الجامع',
          'الإعدادات',
          'الأذكار',
          'التفسير',
          'القارئ',
          'التحميلات',
          'الإحصاءات والتقارير',
          'صفحة اليوم وسورة الكهف',
          'ما الجديد',
          'تواصل معنا',
          'شارك التطبيق',
          'قيّم التطبيق',
          'حول التطبيق',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        // the version, kept left-to-right inside the Arabic line
        expect(find.text('الإصدار \u20661.5.6\u2069'), findsOneWidget);
        // 10 rows besides الإعدادات, so the group labels show
        for (final group in ['القراءة', 'الحفظ', 'التذكير', 'التطبيق']) {
          expect(find.text(group), findsOneWidget, reason: group);
        }
        // nothing hints at features that are not there yet
        expect(find.textContaining('قريب'), findsNothing);
        // the hide bar and full screen are not in the drawer
        expect(find.text('شريط الإخفاء'), findsNothing);
        expect(find.text('ملء الشاشة'), findsNothing);
      },
    );

    testWidgets('each reader row closes the drawer and runs its action', (
      tester,
    ) async {
      const rows = {
        'الإعدادات': 'settings',
        'التفسير': 'tafsir',
        'القارئ': 'reciter',
        'التحميلات': 'downloads',
        'الإحصاءات والتقارير': 'reports',
        'صفحة اليوم وسورة الكهف': 'reminders',
        'ما الجديد': 'whatsNew',
      };
      for (final entry in rows.entries) {
        await openDrawer(tester);
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(called.last, entry.value, reason: entry.key);
        expect(find.byType(AppMenuDrawer), findsNothing, reason: entry.key);
      }
    });

    testWidgets('tapping outside closes it', (tester) async {
      await openDrawer(tester);
      await tester.tapAt(const Offset(20, 400));
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuDrawer), findsNothing);
      expect(called, isEmpty);
    });

    // Owner, 2026-11-13: on a short screen a quick swipe to «حول التطبيق»
    // threw the list back to the top (the fade wrapper came and went, and
    // the list was rebuilt with it).
    testWidgets('a short screen scrolls to the last row and stays there', (
      tester,
    ) async {
      await openDrawer(tester, screen: const Size(1080, 1700));
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position;
      expect(position.maxScrollExtent, greaterThan(0));
      await tester.fling(find.text('التفسير'), const Offset(0, -400), 3000);
      await tester.pumpAndSettle();
      final after = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position;
      expect(after.pixels, after.maxScrollExtent);
      expect(find.text('حول التطبيق').hitTestable(), findsOneWidget);
    });
  });

  group('reader top bar', () {
    Widget bar({VoidCallback? onMenu, required VoidCallback onSettings}) =>
        MaterialApp(
          home: Scaffold(
            body: TopOverlayBar(
              show: true,
              isSearching: false,
              currentPage: 528,
              isTwoPageView: false,
              getHizbNumber: (_) => 54,
              getSurahName: (_) => 'الرحمن',
              onSettingsPressed: onSettings,
              isHideBarEnabled: false,
              onToggleHideBar: (_) {},
              isFullScreenMode: false,
              onToggleFullScreenMode: (_) {},
              onMenuPressed: onMenu,
            ),
          ),
        );

    testWidgets('phones: menu button and full screen, eye, no gear', (
      tester,
    ) async {
      var menuTaps = 0;
      await tester.pumpWidget(bar(onMenu: () => menuTaps++, onSettings: () {}));
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_rounded), findsNothing);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('القائمة'));
      expect(menuTaps, 1);
    });

    testWidgets('TV (no menu callback): the old gear and eye stay', (
      tester,
    ) async {
      var settingsTaps = 0;
      await tester.pumpWidget(bar(onSettings: () => settingsTaps++));
      expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.settings_outlined));
      expect(settingsTaps, 1);
    });
  });
}

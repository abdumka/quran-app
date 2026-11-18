import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/app_look_service.dart';
import 'package:islamic_dawah_mushaf/theme/app_surfaces.dart';
import 'package:islamic_dawah_mushaf/widgets/app_switch_theme.dart';
import 'package:islamic_dawah_mushaf/widgets/settings/app_look_tile.dart';
import 'package:islamic_dawah_mushaf/widgets/settings/settings_components.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final look = AppLookService.instance;
    look.look.value = AppLook.current;
    look.palette.value = MenuPalette.paper;
    look.darkChrome.value = true;
    look.barOpacity.value = BarOpacity.p94;
  });

  Widget settings() => AppLookScope(
    notifier: AppLookService.instance.changes,
    child: const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            AppLookTile(),
            SettingsGroupCard(
              icon: Icons.chrome_reader_mode_rounded,
              title: 'إعدادات العرض',
              children: [Text('a'), Text('b')],
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('«السابق» brings back the count badge, «الجديد» removes it', (
    tester,
  ) async {
    await tester.pumpWidget(settings());
    // the new look: no count on the group card
    expect(find.text('2'), findsNothing);

    await tester.tap(find.byKey(AppLookTile.previousKey));
    await tester.pumpAndSettle();
    expect(AppLookService.instance.look.value, AppLook.previous);
    expect(find.text('2'), findsOneWidget);
    // the row is still there in the previous look, so the way back is too
    expect(find.text('شكل التطبيق'), findsOneWidget);

    await tester.tap(find.byKey(AppLookTile.currentKey));
    await tester.pumpAndSettle();
    expect(AppLookService.instance.look.value, AppLook.current);
    expect(find.text('2'), findsNothing);
  });

  test('the choice is saved and read back', () async {
    await AppLookService.instance.set(AppLook.previous);
    AppLookService.instance.look.value = AppLook.current;
    await AppLookService.instance.load();
    expect(AppLookService.instance.look.value, AppLook.previous);
  });

  test('switch thumbs: ✓ / ✕ only in the previous look', () {
    expect(appSwitchThemeFor(previousLook: false).thumbIcon, isNull);
    final icons = appSwitchThemeFor(previousLook: true).thumbIcon!;
    expect(icons.resolve({WidgetState.selected})!.icon, Icons.check_rounded);
    expect(icons.resolve(<WidgetState>{})!.icon, Icons.close_rounded);
  });

  test('build 144 choices move over: «فاتح بالكامل» and «ضبابي»', () async {
    SharedPreferences.setMockInitialValues({
      'app_look_palette': 'light',
      'app_look_bar_opacity': 'frosted',
    });
    final look = AppLookService.instance;
    await look.load();
    expect(look.palette.value, MenuPalette.paper);
    expect(look.darkChrome.value, isFalse);
    expect(look.barOpacity.value, BarOpacity.p80);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_look_palette'), 'paper');
    expect(prefs.getBool('app_look_dark_chrome'), isFalse);
    expect(prefs.getString('app_look_bar_opacity'), 'p80');
  });

  testWidgets('seven colours: a swatch sets the menus and the bars', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    late AppSurfaces? surfaces;
    late AppChrome chrome;
    await tester.pumpWidget(
      AppLookScope(
        notifier: AppLookService.instance.changes,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const AppLookChoicesTile(),
                  Builder(
                    builder: (context) {
                      surfaces = AppSurfaces.maybeOf(context);
                      chrome = AppChrome.of(context);
                      return const SizedBox();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (final name in [
      'ورقي',
      'كريمي وذهبي',
      'زيتوني',
      'كحلي',
      'عنّابي',
      'بنّي',
      'رمادي هادئ',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('ضبابي'), findsNothing);
    expect(find.text('فاتح بالكامل'), findsNothing);

    await tester.tap(find.text('كحلي'));
    await tester.pumpAndSettle();
    expect(AppLookService.instance.palette.value, MenuPalette.navy);
    expect(surfaces, same(AppSurfaces.navy));
    expect(chrome.dark, isTrue);
    expect(chrome.bar, const Color(0xFF1A2436));

    // the switch off: light bars in the same colour
    await tester.tap(
      find.descendant(
        of: find.byKey(AppLookChoicesTile.darkChromeKey),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(AppLookService.instance.darkChrome.value, isFalse);
    expect(chrome.dark, isFalse);
    expect(chrome.bar, AppSurfaces.navy.sheet);
  });

  test('every colour has its own bar colour and menu colours', () {
    final bars = MenuPalette.values.map(AppChrome.swatchInk).toSet();
    // ورقي and كريمي وذهبي share the charcoal bars
    expect(bars.length, MenuPalette.values.length - 1);
    final sheets = MenuPalette.values.map((p) => AppSurfaces.of(p).sheet);
    expect(sheets.toSet().length, MenuPalette.values.length);
  });
}

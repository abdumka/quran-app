import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/services/ayah_play_setting.dart';
import 'package:islamic_dawah_mushaf/services/reciter_service.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/ayah_recite_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The «تلاوة» line in an ayah's options (owner, 2026-10-25): one line on a
/// phone, a reciter list that scrolls, and a remembered «آية فقط».
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AyahPlaySetting.onlyThisAyah.value = false;
  });

  Future<void> pumpRow(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AyahReciteRow(isDarkMode: false, onPlay: () {}),
            ),
          ),
        ),
      ),
    );
  }

  for (final width in [320.0, 360.0, 390.0, 412.0]) {
    testWidgets('fits on one line at $width dp', (tester) async {
      await pumpRow(tester, width);
      expect(tester.takeException(), isNull);
      final play = tester.getRect(find.byIcon(Icons.play_arrow_rounded));
      final toggle = tester.getRect(find.text('آية فقط'));
      expect((play.center.dy - toggle.center.dy).abs(), lessThan(4));
      // The reciter's button keeps room for a name.
      final picker = tester.getRect(find.byIcon(Icons.expand_more_rounded));
      expect(picker.right - play.right, lessThan(0));
    });
  }

  testWidgets('the play button says «تلاوة» when there is room', (
    tester,
  ) async {
    await pumpRow(tester, 700);
    expect(find.text('تلاوة'), findsOneWidget);
  });

  testWidgets('«آية فقط» is remembered', (tester) async {
    await pumpRow(tester, 390);
    await tester.tap(find.text('آية فقط'));
    await tester.pump();
    expect(AyahPlaySetting.onlyThisAyah.value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ayahPlayOnlyThis'), isTrue);
  });

  testWidgets('the reciter list is capped, scrolls, and picks', (tester) async {
    final service = ReciterService.instance;
    await service.select(Reciter.all.last);
    await pumpRow(tester, 390);
    expect(find.text(Reciter.all.last.shortName), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();
    final menu = find.byType(SingleChildScrollView).last;
    expect(
      tester.getSize(menu).height,
      lessThanOrEqualTo(ReciterService.pickerMenuMaxHeight(48)),
    );
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: menu, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    // Opens on the reciter in use, the last one here.
    expect(position.pixels, greaterThan(0));

    final other = Reciter.all[Reciter.all.length - 2];
    await tester.tap(find.text(other.shortName).last);
    await tester.pumpAndSettle();
    expect(service.selected.value.id, other.id);
  });
}

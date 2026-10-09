import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/widgets/settings/settings_components.dart';

/// The way into the developer tools: holding the ℹ️ on «إعدادات متقدمة».
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  );

  Widget card({VoidCallback? onInfoTap, VoidCallback? onInfoHold}) =>
      SettingsGroupCard(
        icon: Icons.tune_rounded,
        title: 'إعدادات متقدمة',
        onInfoTap: onInfoTap ?? () {},
        onInfoHold: onInfoHold,
        children: const [Text('nested setting')],
      );

  group('info button', () {
    testWidgets('a tap explains the group without expanding it', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(wrap(card(onInfoTap: () => taps++)));

      expect(find.text('nested setting'), findsNothing);
      await tester.tap(find.byType(InfoHintButton));
      await tester.pumpAndSettle();

      expect(taps, 1);
      expect(
        find.text('nested setting'),
        findsNothing,
        reason: 'the ℹ️ explains the group, it does not open it',
      );
    });

    testWidgets('a near miss still lands on the button, not the group', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(wrap(card(onInfoTap: () => taps++)));

      // 13px off centre: inside the button's padding, but on a bare 16px icon
      // it would have hit the ExpansionTile and expanded the group.
      final centre = tester.getCenter(find.byType(InfoHintButton));
      await tester.tapAt(centre + const Offset(13, 0));
      await tester.pumpAndSettle();

      expect(taps, 1);
      expect(find.text('nested setting'), findsNothing);
    });

    testWidgets('has no info button unless one is given', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SettingsGroupCard(
            icon: Icons.tune_rounded,
            title: 'إعدادات متقدمة',
            children: [Text('nested setting')],
          ),
        ),
      );
      expect(find.byType(InfoHintButton), findsNothing);
    });
  });

  group('holding the info button', () {
    testWidgets('fires after the full seven seconds', (tester) async {
      var holds = 0;
      var taps = 0;
      await tester.pumpWidget(
        wrap(card(onInfoTap: () => taps++, onInfoHold: () => holds++)),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InfoHintButton)),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(holds, 0, reason: 'six seconds is not enough');

      // The hold starts when the tap is recognised, a fraction after touch
      // down, so the seventh second lands just past the seven-second mark.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(holds, 1);

      // Letting go afterwards must not also run the ordinary tap, which would
      // drop a notice over the page the hold just opened.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('letting go early does nothing but explain', (tester) async {
      var holds = 0;
      var taps = 0;
      await tester.pumpWidget(
        wrap(card(onInfoTap: () => taps++, onInfoHold: () => holds++)),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InfoHintButton)),
      );
      await tester.pump(const Duration(seconds: 3));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(holds, 0);
      expect(taps, 1);
    });

    testWidgets('sliding off the button cancels the hold', (tester) async {
      var holds = 0;
      await tester.pumpWidget(wrap(card(onInfoHold: () => holds++)));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InfoHintButton)),
      );
      await tester.pump(const Duration(seconds: 2));
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump(const Duration(seconds: 6));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(holds, 0);
    });

    testWidgets('a tile with no hold action is unaffected', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(card(onInfoTap: () => taps++)));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InfoHintButton)),
      );
      await tester.pump(const Duration(seconds: 9));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(taps, 1, reason: 'still just a tap, however long it is held');
    });
  });
}

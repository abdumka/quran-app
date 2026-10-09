import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/multi_tap_detector.dart';
import 'package:islamic_dawah_mushaf/widgets/settings/settings_components.dart';

void main() {
  group('MultiTapDetector', () {
    final start = DateTime(2026, 10, 8, 12, 0);

    test('fires on the seventh tap, not before', () {
      final detector = MultiTapDetector(taps: 7);
      for (var i = 0; i < 6; i++) {
        expect(
          detector.register(start.add(Duration(milliseconds: 200 * i))),
          isFalse,
          reason: 'tap ${i + 1} must not trigger',
        );
      }
      expect(
        detector.register(start.add(const Duration(milliseconds: 1200))),
        isTrue,
      );
    });

    test('a pause longer than the gap starts the run over', () {
      final detector = MultiTapDetector(taps: 7);
      for (var i = 0; i < 6; i++) {
        detector.register(start.add(Duration(milliseconds: 200 * i)));
      }
      // Six taps in, then the user walks away and comes back.
      expect(
        detector.register(start.add(const Duration(seconds: 30))),
        isFalse,
      );
      // That late tap counts as the first of a new run, so six more are needed.
      for (var i = 1; i < 6; i++) {
        expect(
          detector.register(
            start.add(Duration(seconds: 30, milliseconds: 200 * i)),
          ),
          isFalse,
        );
      }
      expect(
        detector.register(
          start.add(const Duration(seconds: 31, milliseconds: 500)),
        ),
        isTrue,
      );
    });

    test('a tap exactly on the limit still continues the run', () {
      final detector = MultiTapDetector(taps: 2);
      expect(detector.register(start), isFalse);
      expect(detector.register(start.add(const Duration(seconds: 1))), isTrue);
    });

    test('resets after firing, so a held run cannot fire twice', () {
      final detector = MultiTapDetector(taps: 2);
      detector.register(start);
      expect(
        detector.register(start.add(const Duration(milliseconds: 100))),
        isTrue,
      );
      expect(
        detector.register(start.add(const Duration(milliseconds: 200))),
        isFalse,
      );
    });
  });

  group('SettingsGroupCard info button', () {
    Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: ListView(children: [child])),
    );

    testWidgets('calls onInfoTap without expanding the group', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          SettingsGroupCard(
            icon: Icons.tune_rounded,
            title: 'إعدادات متقدمة',
            onInfoTap: () => taps++,
            children: const [Text('nested setting')],
          ),
        ),
      );

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
      await tester.pumpWidget(
        wrap(
          SettingsGroupCard(
            icon: Icons.tune_rounded,
            title: 'إعدادات متقدمة',
            onInfoTap: () => taps++,
            children: const [Text('nested setting')],
          ),
        ),
      );

      // 13px off centre: inside the button's padding, but on the bare 16px
      // icon it would have hit the ExpansionTile and expanded the group.
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
}

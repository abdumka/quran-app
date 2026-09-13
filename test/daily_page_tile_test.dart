import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/daily_page_service.dart';
import 'package:islamic_dawah_mushaf/widgets/settings/daily_page_tile.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFFF6F1E5),
      body: SingleChildScrollView(child: child),
    ),
  );

  DailyPageTile tile({
    bool enabled = true,
    DailyPageReminderMode mode = DailyPageReminderMode.fixed,
    DateTime? nextReminderAt,
    ValueChanged<bool>? onToggle,
    ValueChanged<DailyPageReminderMode>? onModeChanged,
    ValueChanged<int>? onFixedMinutesChanged,
  }) => DailyPageTile(
    enabled: enabled,
    mode: mode,
    fixedMinutes: 20 * 60,
    windowStartMinutes: 8 * 60,
    windowEndMinutes: 22 * 60,
    nextReminderAt: nextReminderAt,
    onToggle: onToggle ?? (_) {},
    onModeChanged: onModeChanged ?? (_) {},
    onFixedMinutesChanged: onFixedMinutesChanged ?? (_) {},
    onWindowChanged: (_, _) {},
  );

  group('formatDailyPageTime', () {
    test('renders a 12-hour Arabic clock', () {
      expect(formatDailyPageTime(0), '12:00 ص');
      expect(formatDailyPageTime(8 * 60 + 5), '8:05 ص');
      expect(formatDailyPageTime(12 * 60), '12:00 م');
      expect(formatDailyPageTime(20 * 60 + 30), '8:30 م');
      expect(formatDailyPageTime(23 * 60 + 59), '11:59 م');
    });
  });

  group('formatNextReminder', () {
    test('names today, tomorrow and further-out days', () {
      final now = DateTime.now();
      expect(
        formatNextReminder(DateTime(now.year, now.month, now.day, 20)),
        'اليوم 8:00 م',
      );
      final tomorrow = DateTime(now.year, now.month, now.day + 1, 7, 15);
      expect(formatNextReminder(tomorrow), 'غدًا 7:15 ص');
      final later = DateTime(now.year, now.month, now.day + 3, 20);
      expect(formatNextReminder(later), endsWith('8:00 م'));
      expect(formatNextReminder(later), isNot(contains('غدًا')));
    });
  });

  testWidgets('collapsed when off: no schedule controls', (tester) async {
    await tester.pumpWidget(host(tile(enabled: false)));
    await tester.pumpAndSettle();

    expect(find.text('صفحة اليوم'), findsOneWidget);
    // AnimatedCrossFade keeps both children in the tree; the schedule half must
    // be fully faded out when the feature is off.
    final crossFade = tester.widget<AnimatedCrossFade>(
      find.byType(AnimatedCrossFade),
    );
    expect(crossFade.crossFadeState, CrossFadeState.showFirst);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fixed mode shows one time field, random mode shows two', (
    tester,
  ) async {
    await tester.pumpWidget(host(tile()));
    await tester.pumpAndSettle();
    expect(find.text('وقت التذكير'), findsOneWidget);
    expect(find.text('8:00 م'), findsOneWidget);

    await tester.pumpWidget(host(tile(mode: DailyPageReminderMode.random)));
    await tester.pumpAndSettle();
    expect(find.text('من'), findsOneWidget);
    expect(find.text('إلى'), findsOneWidget);
    expect(find.text('8:00 ص'), findsOneWidget);
    expect(find.text('10:00 م'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode chips report the mode they were tapped for', (
    tester,
  ) async {
    final tapped = <DailyPageReminderMode>[];
    await tester.pumpWidget(host(tile(onModeChanged: tapped.add)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('وقت عشوائي'));
    await tester.tap(find.text('وقت محدد'));
    expect(tapped, [
      DailyPageReminderMode.random,
      DailyPageReminderMode.fixed,
    ]);
  });

  testWidgets('the switch reports the value it is being moved to', (
    tester,
  ) async {
    final toggles = <bool>[];
    await tester.pumpWidget(
      host(tile(enabled: false, onToggle: toggles.add)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    expect(toggles, [true]);
  });

  testWidgets('next reminder line appears only when one is queued', (
    tester,
  ) async {
    await tester.pumpWidget(host(tile()));
    await tester.pumpAndSettle();
    expect(find.textContaining('التذكير القادم'), findsNothing);

    final now = DateTime.now();
    await tester.pumpWidget(
      host(
        tile(
          nextReminderAt: DateTime(now.year, now.month, now.day + 1, 20),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('التذكير القادم: غدًا 8:00 م'), findsOneWidget);
  });

  testWidgets('the time sheet returns the minute-of-day it was left on', (
    tester,
  ) async {
    int? picked;
    await tester.pumpWidget(
      host(tile(onFixedMinutesChanged: (value) => picked = value)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('وقت التذكير'));
    await tester.pumpAndSettle();
    expect(find.byType(DailyPageTimeSheet), findsOneWidget);
    // Each wheel is captioned, so three columns of bare numbers can't be
    // mistaken for one another.
    expect(find.text('ساعة'), findsOneWidget);
    expect(find.text('دقيقة'), findsOneWidget);
    expect(find.text('ص / م'), findsOneWidget);
    // Opens on the current value and hands it straight back on save.
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(picked, 20 * 60);
  });

  testWidgets('renders on a narrow phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(tile(mode: DailyPageReminderMode.random)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

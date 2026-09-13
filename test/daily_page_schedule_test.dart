import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/daily_page_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets the chained prefs writes behind `pendingOpenPage` drain. Each link
/// awaits `SharedPreferences.getInstance()` plus the write itself, so a single
/// microtask turn isn't enough.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  List<DateTime> fixed({required DateTime now, required int minutes, int count = 3}) =>
      DailyPageService.upcomingOccurrences(
        now: now,
        mode: DailyPageReminderMode.fixed,
        fixedMinutes: minutes,
        windowStartMinutes: DailyPageService.defaultWindowStartMinutes,
        windowEndMinutes: DailyPageService.defaultWindowEndMinutes,
        random: Random(7),
        count: count,
      );

  List<DateTime> random({
    required DateTime now,
    int start = 8 * 60,
    int end = 22 * 60,
    int count = 3,
  }) => DailyPageService.upcomingOccurrences(
    now: now,
    mode: DailyPageReminderMode.random,
    fixedMinutes: DailyPageService.defaultFixedMinutes,
    windowStartMinutes: start,
    windowEndMinutes: end,
    random: Random(7),
    count: count,
  );

  group('fixed mode', () {
    test('starts today when the time is still ahead', () {
      final result = fixed(now: DateTime(2026, 9, 8, 9), minutes: 20 * 60);
      expect(result.first, DateTime(2026, 9, 8, 20));
      expect(result[1], DateTime(2026, 9, 9, 20));
      expect(result[2], DateTime(2026, 9, 10, 20));
    });

    test('skips today once the time has passed', () {
      final result = fixed(now: DateTime(2026, 9, 8, 21), minutes: 20 * 60);
      expect(result.first, DateTime(2026, 9, 9, 20));
      expect(result.length, 3);
    });

    test('a time inside the one-minute slack is pushed to tomorrow', () {
      // Exactly on the slot: the one minute of slack puts it out of reach, so
      // it goes to tomorrow rather than being scheduled a second in the past.
      final result = fixed(now: DateTime(2026, 9, 8, 20), minutes: 20 * 60);
      expect(result.first, DateTime(2026, 9, 9, 20));
    });

    test('rolls over a month end', () {
      final result = fixed(now: DateTime(2026, 9, 29, 21), minutes: 20 * 60);
      expect(result.first, DateTime(2026, 9, 30, 20));
      expect(result[1], DateTime(2026, 10, 1, 20));
    });

    test('returns a full horizon of distinct days by default', () {
      final result = DailyPageService.upcomingOccurrences(
        now: DateTime(2026, 9, 8, 9),
        mode: DailyPageReminderMode.fixed,
        fixedMinutes: 20 * 60,
        windowStartMinutes: 8 * 60,
        windowEndMinutes: 22 * 60,
        random: Random(7),
      );
      expect(result.length, 30);
      expect(result.map((d) => DateTime(d.year, d.month, d.day)).toSet().length, 30);
      // Well under the 64 pending-notification cap iOS enforces.
      expect(result.length, lessThan(64));
    });
  });

  group('random mode', () {
    test('every time lands inside the window', () {
      final result = random(now: DateTime(2026, 9, 8, 6), count: 10);
      expect(result.length, 10);
      for (final when in result) {
        final minutes = when.hour * 60 + when.minute;
        expect(minutes, greaterThanOrEqualTo(8 * 60));
        expect(minutes, lessThanOrEqualTo(22 * 60));
      }
    });

    test('today is drawn from the remainder of the window, not its start', () {
      final result = random(now: DateTime(2026, 9, 8, 19));
      expect(result.first.day, 8);
      final minutes = result.first.hour * 60 + result.first.minute;
      expect(minutes, greaterThanOrEqualTo(19 * 60 + 1));
    });

    test('skips today when the window has already closed', () {
      final result = random(now: DateTime(2026, 9, 8, 23));
      expect(result.first.day, 9);
      expect(result.length, 3);
    });

    test('produces different times on different days', () {
      final result = random(now: DateTime(2026, 9, 8, 6), count: 14);
      final distinct = result
          .map((when) => when.hour * 60 + when.minute)
          .toSet();
      // A 14-hour window makes an all-identical draw vanishingly unlikely; this
      // guards against accidentally reusing one draw for the whole batch.
      expect(distinct.length, greaterThan(1));
    });
  });

  group('pending page from a tapped reminder', () {
    test('is restored from prefs on load, then cleared once taken', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'flutter.dailyPagePendingOpen': 291,
      });

      final service = DailyPageService.instance;
      await service.load();
      expect(service.pendingOpenPage.value, 291);

      expect(service.takePendingOpenPage(), 291);
      expect(service.pendingOpenPage.value, isNull);
      // A second reader must not be handed the same page again.
      expect(service.takePendingOpenPage(), isNull);

      await _settle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('dailyPagePendingOpen'), isNull);
    });

    test('a tap consumed in the same turn leaves nothing behind', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final service = DailyPageService.instance;
      await service.load();

      // Exactly what happens on a warm tap: setting the value fires the
      // reader's listener, which takes it straight back. The two prefs writes
      // must land in that order — unchained, the tap's write would settle after
      // the removal and strand a page that gets re-opened on the next launch.
      int? seen;
      void listener() {
        seen ??= service.takePendingOpenPage();
      }

      service.pendingOpenPage.addListener(listener);
      addTearDown(() => service.pendingOpenPage.removeListener(listener));
      service.handleReminderTapped('123');

      expect(seen, 123);
      expect(service.pendingOpenPage.value, isNull);
      await _settle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('dailyPagePendingOpen'), isNull);
    });

    test('ignores a payload that is not a real page', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final service = DailyPageService.instance;
      for (final payload in ['', 'abc', '0', '-3', '603']) {
        service.handleReminderTapped(payload);
        expect(service.pendingOpenPage.value, isNull, reason: payload);
      }
    });
  });

  group('surahNameForPage', () {
    test('maps page boundaries to the surah that owns them', () {
      expect(DailyPageService.surahNameForPage(1), 'الفاتحة');
      expect(DailyPageService.surahNameForPage(2), 'البقرة');
      expect(DailyPageService.surahNameForPage(49), 'البقرة');
      expect(DailyPageService.surahNameForPage(50), 'آل عمران');
      expect(DailyPageService.surahNameForPage(602), 'الناس');
    });
  });
}

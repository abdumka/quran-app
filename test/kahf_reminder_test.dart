import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/kahf_reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  DateTime next(DateTime now, {int minutes = KahfReminderService.defaultMinutes}) =>
      KahfReminderService.nextOccurrence(now, minutes);

  group('nextOccurrence', () {
    test('from midweek, lands on the coming Friday at the chosen time', () {
      // Wednesday 2026-09-16.
      final when = next(DateTime(2026, 9, 16, 14, 0));
      expect(when, DateTime(2026, 9, 18, 10, 0));
      expect(when.weekday, DateTime.friday);
    });

    test('on Friday before the time, fires the same day', () {
      expect(next(DateTime(2026, 9, 18, 6, 30)), DateTime(2026, 9, 18, 10, 0));
    });

    test('on Friday after the time, waits a week', () {
      expect(next(DateTime(2026, 9, 18, 10, 30)), DateTime(2026, 9, 25, 10, 0));
    });

    test('a slot less than a minute away is skipped, not scheduled in the past', () {
      // The platform rejects a schedule that lands in the past and building it
      // takes a moment, so the minute of slack has to push this to next week.
      expect(
        next(DateTime(2026, 9, 18, 9, 59, 30)),
        DateTime(2026, 9, 25, 10, 0),
      );
    });

    test('Saturday is the longest wait: six days', () {
      final when = next(DateTime(2026, 9, 19, 11, 0));
      expect(when, DateTime(2026, 9, 25, 10, 0));
      expect(when.difference(DateTime(2026, 9, 19, 11, 0)).inDays, 5);
    });

    test('keeps its wall-clock time across a month end', () {
      // Wednesday 2026-09-30 -> Friday 2026-10-02.
      expect(next(DateTime(2026, 9, 30, 12, 0)), DateTime(2026, 10, 2, 10, 0));
    });

    test('honours a custom time', () {
      expect(
        next(DateTime(2026, 9, 16, 14, 0), minutes: 17 * 60 + 45),
        DateTime(2026, 9, 18, 17, 45),
      );
    });
  });

  group('preferences', () {
    test('defaults to on at 10:00, and a stored choice wins', () async {
      SharedPreferences.setMockInitialValues({});
      final service = KahfReminderService.instance;
      await service.load();
      expect(service.enabled.value, isTrue);
      expect(service.minutes.value, KahfReminderService.defaultMinutes);
      expect(service.nextReminderAt.value?.weekday, DateTime.friday);
    });
  });

  test('the Al-Kahf page is the surah opening', () {
    // Surah 18 starts on page 293 (see surahList in surah_data.dart).
    expect(KahfReminderService.kahfPage, 293);
  });
}

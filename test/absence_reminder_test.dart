import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/data/absence_reminder_messages.dart';
import 'package:islamic_dawah_mushaf/services/absence_reminder_service.dart';

void main() {
  test('fires d days later at the same clock time, across a month end', () {
    final now = DateTime(2026, 11, 28, 21, 15);
    expect(AbsenceReminderService.fireTime(now, 5), DateTime(2026, 12, 3, 21, 15));
    expect(AbsenceReminderService.fireTime(now, 20), DateTime(2026, 12, 18, 21, 15));
  });

  test('picks only the chosen messages, two different ones first', () {
    final picks = AbsenceReminderService.pickMessages(Random(1), 3);
    expect(picks, hasLength(3));
    for (final m in picks) {
      expect(absenceMessageIds, contains(m.id));
    }
    expect(picks[0].id, isNot(picks[1].id));
  });

  test('every chosen id exists among the candidates', () {
    final ids = absenceMessageCandidates.map((m) => m.id).toSet();
    for (final id in absenceMessageIds) {
      expect(ids, contains(id));
    }
  });

  test('ayah text: ornate brackets, display marks, surah and number', () {
    final q1 = absenceMessageCandidates.firstWhere((m) => m.id == 'Q1');
    final body = AbsenceReminderService.bodyFor(q1, days: 5, page: 362);
    expect(body, startsWith('﴿'));
    expect(body, contains('قَوْمِيَ'));
    // open fathatan (U+0657) is shown as a plain fathatan
    expect(body.contains('ٗ'), isFalse);
    expect(body, endsWith('الفرقان 30'));
  });

  test('hadith and app lines', () {
    final h1 = absenceMessageCandidates.firstWhere((m) => m.id == 'H1');
    expect(
      AbsenceReminderService.bodyFor(h1, days: 5, page: 1),
      'قال رسول الله صلى الله عليه وسلم: «${h1.text}»\nرواه مسلم',
    );
    final g5 = absenceMessageCandidates.firstWhere((m) => m.id == 'G5');
    expect(
      AbsenceReminderService.bodyFor(g5, days: 5, page: 156),
      'تابع وردك من حيث توقفت: صفحة 156',
    );
  });

  test('no Eastern digits or em dashes in any message', () {
    for (final m in absenceMessageCandidates) {
      expect(RegExp('[٠-٩۰-۹—]').hasMatch(m.text + m.source), isFalse, reason: m.id);
    }
  });
}

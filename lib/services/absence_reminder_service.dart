import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/absence_reminder_messages.dart';
import '../utils/quran_display_text.dart';
import 'daily_page_service.dart';
import 'notification_center.dart';

/// «لا تهجر القرآن» (owner, 2026-11-12): when the app has not been opened for
/// [days] days in a row, the device itself shows one gentle reminder: an
/// ayah, a hadith or a short line, picked at random from
/// [absenceMessageIds]. If the reader still stays away, it comes again after
/// twice and four times as long (5, 10 and 20 days by default) and then
/// stops, so it never nags.
///
/// Every open of the app re-arms the three, from that moment and at that
/// clock time (a time the reader tends to read), so they only ever fire after
/// a real absence. All on the device: no server, works offline. Tapping
/// opens the page the reader stopped at.
class AbsenceReminderService {
  AbsenceReminderService._();
  static final AbsenceReminderService instance = AbsenceReminderService._();

  static const String payloadPrefix = 'absence';
  static const String title = 'لا تهجر القرآن';

  static const String _enabledPrefKey = 'absenceReminderEnabled';
  static const String _daysPrefKey = 'absenceReminderDays';

  /// Clear of 4801/4802 (updates, push test), 4890 (Kahf) and 4900-4929
  /// (صفحة اليوم).
  static const int _firstNotificationId = 4880;

  /// After d, 2d and 4d days.
  static const List<int> _multiples = [1, 2, 4];

  static const String _channelId = 'absence_reminder';
  static const String _channelName = 'لا تهجر القرآن';

  static const List<int> dayChoices = [3, 5, 7];
  static const int defaultDays = 5;

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  final ValueNotifier<int> days = ValueNotifier<int>(defaultDays);

  bool _loaded = false;
  DateTime? _lastArmed;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    // On by default, like the Kahf reminder: it only shows where the reader
    // has allowed notifications, and the switch turns it off for good.
    enabled.value = prefs.getBool(_enabledPrefKey) ?? true;
    final d = prefs.getInt(_daysPrefKey) ?? defaultDays;
    days.value = dayChoices.contains(d) ? d : defaultDays;
    NotificationCenter.instance.registerTapHandler(
      payloadPrefix,
      (value) => DailyPageService.instance.handleReminderTapped(value),
    );
  }

  Future<DailyPageEnableResult> setEnabled(bool value) async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    if (!value) {
      enabled.value = false;
      await prefs.setBool(_enabledPrefKey, false);
      await _cancel();
      return DailyPageEnableResult.ok;
    }
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return DailyPageEnableResult.unsupported;
    }
    final granted = await NotificationCenter.instance.requestPermission();
    if (!granted) return DailyPageEnableResult.permissionDenied;
    enabled.value = true;
    await prefs.setBool(_enabledPrefKey, true);
    await rearm(force: true);
    return DailyPageEnableResult.ok;
  }

  Future<void> setDays(int value) async {
    if (!dayChoices.contains(value) || days.value == value) return;
    days.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_daysPrefKey, value);
    if (enabled.value) await rearm(force: true);
  }

  /// Called when the app opens and on every resume. Re-arming more than
  /// every few hours buys nothing for a reminder counted in days, so a resume
  /// soon after the last one returns at once.
  Future<void> rearm({bool force = false}) async {
    if (kIsWeb) return;
    await load();
    final now = DateTime.now();
    if (!force &&
        _lastArmed != null &&
        now.difference(_lastArmed!) < const Duration(hours: 6)) {
      return;
    }
    _lastArmed = now;
    try {
      final center = NotificationCenter.instance;
      await center.ensureInitialized();
      await center.ensureTimeZoneReady();
      await _cancel();
      if (!enabled.value) return;
      if (!await center.areNotificationsEnabled()) return;

      final prefs = await SharedPreferences.getInstance();
      // the reader's page, 1-based (the reader stores the 0-based index)
      final page = (prefs.getInt('lastPage') ?? 0) + 1;
      final picks = pickMessages(Random(), _multiples.length);
      final mode = await center.canScheduleExactAlarms()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      for (var i = 0; i < _multiples.length; i++) {
        final after = days.value * _multiples[i];
        final when = fireTime(now, after);
        final body = bodyFor(picks[i], days: after, page: page);
        await center.plugin.zonedSchedule(
          _firstNotificationId + i,
          title,
          body,
          tz.TZDateTime.from(when, tz.local),
          _details(body),
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: '$payloadPrefix:$page',
        );
      }
    } catch (error, stack) {
      debugPrint('AbsenceReminderService rearm failed: $error\n$stack');
    }
  }

  Future<void> _cancel() async {
    if (kIsWeb) return;
    try {
      await NotificationCenter.instance.ensureInitialized();
      for (var i = 0; i < _multiples.length; i++) {
        await NotificationCenter.instance.plugin.cancel(
          _firstNotificationId + i,
        );
      }
    } catch (error, stack) {
      debugPrint('AbsenceReminderService cancel failed: $error\n$stack');
    }
  }

  /// [days] calendar days after [now], at the same clock time. Built from
  /// calendar fields so a month end or a DST change keeps the hour.
  @visibleForTesting
  static DateTime fireTime(DateTime now, int days) =>
      DateTime(now.year, now.month, now.day + days, now.hour, now.minute);

  /// [count] messages from the chosen ones, no two alike while there are
  /// enough of them.
  @visibleForTesting
  static List<AbsenceMessage> pickMessages(Random random, int count) {
    final pool = [
      for (final m in absenceMessageCandidates)
        if (absenceMessageIds.contains(m.id)) m,
    ]..shuffle(random);
    return [for (var i = 0; i < count; i++) pool[i % pool.length]];
  }

  /// The notification text: an ayah in ornate brackets with its surah and
  /// number, a hadith with its source, or one of the app's own lines.
  @visibleForTesting
  static String bodyFor(
    AbsenceMessage m, {
    required int days,
    required int page,
  }) {
    switch (m.kind) {
      case AbsenceKind.ayah:
        return '﴿${quranDisplayText(m.text)}﴾\n${m.source}';
      case AbsenceKind.hadith:
        return 'قال رسول الله صلى الله عليه وسلم: «${m.text}»\n${m.source}';
      case AbsenceKind.line:
        return m.text
            .replaceAll('{N}', '$days')
            .replaceAll('{P}', '$page');
    }
  }

  NotificationDetails _details(String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'تنبيه إذا لم تفتح المصحف عدة أيام',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }
}

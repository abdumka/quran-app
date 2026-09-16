import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'daily_page_service.dart';
import 'notification_center.dart';

/// "سورة الكهف": an opt-in weekly reminder to read Surah Al-Kahf on Friday,
/// fired by the device itself at the chosen hour in its own local time — so a
/// reader in Tripoli and a reader in New York are each reminded at their own
/// 10 a.m., with no server involved. Tapping it opens the surah.
///
/// Unlike «صفحة اليوم» this is a single repeating notification
/// ([DateTimeComponents.dayOfWeekAndTime]): the text never changes, so the one
/// entry the OS repeats every week is enough and it costs one slot against the
/// 64 iOS allows an app. That also means the reminder keeps working for a user
/// who doesn't open the app for months.
///
/// Like the daily reminder, this deliberately asks for no exact-alarm
/// permission (see [NotificationCenter.canScheduleExactAlarms]), so on Android
/// 12+ it can drift — acceptable for "read Al-Kahf today".
class KahfReminderService {
  KahfReminderService._();
  static final KahfReminderService instance = KahfReminderService._();

  /// Payload prefix used to route notification taps back here.
  static const String payloadPrefix = 'kahf';

  static const String _enabledPrefKey = 'kahfReminderEnabled';
  static const String _minutesPrefKey = 'kahfReminderMinutes';

  /// Kept clear of UpdateNotificationService's 4801 and the daily-page block
  /// (4900 … 4929).
  static const int _notificationId = 4890;

  static const String _channelId = 'kahf_reminder';
  static const String _channelName = 'تذكير سورة الكهف';

  /// Friday, as [DateTime.friday].
  static const int _weekday = DateTime.friday;

  /// Default reminder time: 10:00.
  static const int defaultMinutes = 10 * 60;

  /// First page of سورة الكهف in the mushaf.
  static const int kahfPage = 293;

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<int> minutes = ValueNotifier<int>(defaultMinutes);

  /// When the next reminder is due, so Settings can show it.
  final ValueNotifier<DateTime?> nextReminderAt = ValueNotifier<DateTime?>(null);

  bool _loaded = false;

  /// Reads the stored preferences. Prefs only — it deliberately leaves the
  /// notification plugin and the timezone database alone, so it is safe on the
  /// startup path; [refreshSchedule] does that work after the first frame.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    // On by default — the Friday reminder is the kind of thing a reader of this
    // app wants without having to discover it. Turning the switch off writes
    // `false`, so the default only ever applies until the user has an opinion.
    // It still needs the OS notification permission to actually show: until
    // that is granted the schedule is accepted and silently dropped, and
    // [verifyPermissionStillGranted] turns the switch off honestly rather than
    // leaving it on and doing nothing.
    enabled.value = prefs.getBool(_enabledPrefKey) ?? true;
    minutes.value = _clampMinutes(
      prefs.getInt(_minutesPrefKey) ?? defaultMinutes,
    );
    if (enabled.value) {
      nextReminderAt.value = nextOccurrence(DateTime.now(), minutes.value);
    }
    // Registered here rather than on first use so a tap that cold-started the
    // app is delivered as soon as the plugin finishes initialising.
    NotificationCenter.instance.registerTapHandler(
      payloadPrefix,
      (value) => DailyPageService.instance.handleReminderTapped(value),
    );
  }

  /// Turns the reminder on or off. Turning it on asks for the OS notification
  /// permission first and refuses if it is denied, so the switch never sits in
  /// an "on but silently doing nothing" state.
  Future<DailyPageEnableResult> setEnabled(bool value) async {
    await load();
    if (!value) {
      enabled.value = false;
      nextReminderAt.value = null;
      final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPrefKey, true);
    await reschedule();
    return DailyPageEnableResult.ok;
  }

  Future<void> setMinutes(int value) async {
    final clamped = _clampMinutes(value);
    if (minutes.value == clamped) return;
    minutes.value = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_minutesPrefKey, clamped);
    if (enabled.value) await reschedule();
  }

  /// Re-arms the reminder if it is on. Cheap enough to call on resume: the
  /// weekly notification is one platform call, and re-scheduling the same id
  /// replaces it rather than stacking.
  Future<void> refreshSchedule() async {
    await load();
    if (!enabled.value || kIsWeb) return;
    await reschedule();
  }

  /// Checks the OS notification permission and turns the reminder off if it has
  /// been revoked from system settings. Returns whether it is still on.
  Future<bool> verifyPermissionStillGranted() async {
    await load();
    if (!enabled.value || kIsWeb) return false;
    if (await NotificationCenter.instance.areNotificationsEnabled()) return true;
    enabled.value = false;
    nextReminderAt.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPrefKey, false);
    await _cancel();
    return false;
  }

  /// Schedules (or replaces) the weekly Friday notification.
  Future<void> reschedule() async {
    if (kIsWeb) return;
    try {
      final center = NotificationCenter.instance;
      await center.ensureInitialized();
      await center.ensureTimeZoneReady();
      await _cancel();
      if (!enabled.value) return;

      final scheduleMode = await center.canScheduleExactAlarms()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final when = nextOccurrence(DateTime.now(), minutes.value);

      await center.plugin.zonedSchedule(
        _notificationId,
        _channelName,
        _body,
        tz.TZDateTime.from(when, tz.local),
        _notificationDetails(),
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // Repeats weekly at the same weekday and time — in whatever timezone
        // the device is in when it fires, which is the point of doing this on
        // the device instead of from a server.
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: '$payloadPrefix:$kahfPage',
      );
      nextReminderAt.value = when;
    } catch (error, stack) {
      debugPrint('KahfReminderService schedule failed: $error\n$stack');
    }
  }

  Future<void> _cancel() async {
    if (kIsWeb) return;
    try {
      await NotificationCenter.instance.ensureInitialized();
      await NotificationCenter.instance.plugin.cancel(_notificationId);
    } catch (error, stack) {
      debugPrint('KahfReminderService cancel failed: $error\n$stack');
    }
  }

  /// The next Friday at [minutesOfDay], from [now]. Today counts only while its
  /// time is still ahead; a minute of slack keeps the platform from rejecting a
  /// schedule that lands in the past.
  ///
  /// Pure, so the day arithmetic can be tested without a device.
  @visibleForTesting
  static DateTime nextOccurrence(DateTime now, int minutesOfDay) {
    final earliest = now.add(const Duration(minutes: 1));
    final daysAhead = (_weekday - now.weekday + 7) % 7;
    for (var day = daysAhead; day <= daysAhead + 7; day += 7) {
      // Built from calendar fields rather than by adding a Duration so the
      // reminder keeps its wall-clock time across a month end or a DST shift.
      final when = DateTime(
        now.year,
        now.month,
        now.day + day,
        minutesOfDay ~/ 60,
        minutesOfDay % 60,
      );
      if (when.isAfter(earliest)) return when;
    }
    return DateTime(
      now.year,
      now.month,
      now.day + daysAhead + 7,
      minutesOfDay ~/ 60,
      minutesOfDay % 60,
    );
  }

  static const String _body = 'يوم الجمعة: اقرأ سورة الكهف';

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'تذكير أسبوعي بقراءة سورة الكهف يوم الجمعة',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(_body),
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  static int _clampMinutes(int value) => value.clamp(0, 24 * 60 - 1);
}

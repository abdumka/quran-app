import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../surah_data.dart';
import 'notification_center.dart';

/// When the daily "صفحة اليوم" reminder fires.
enum DailyPageReminderMode {
  /// Every day at one time the user picked.
  fixed,

  /// A different time each day, drawn from a window the user picked.
  random,
}

/// Why [DailyPageService.setEnabled] could not turn the feature on.
enum DailyPageEnableResult {
  ok,

  /// The user denied (or has previously denied) the OS notification permission.
  permissionDenied,

  /// Notifications aren't a thing on this platform (web/desktop).
  unsupported,
}

/// "صفحة اليوم": a daily nudge to read at least one page of the mushaf, with a
/// randomly chosen page attached to each reminder.
///
/// ## How the schedule works
///
/// The OS only fires notifications the app has handed it in advance, and there
/// is no "fire at a random time each day" primitive — so instead of one
/// repeating notification this schedules [_horizonDays] individually dated ones
/// (ids [_firstNotificationId] … +[_horizonDays]-1), each with its own time and
/// its own pre-drawn page. The queue is topped back up to a full horizon every
/// time the app is opened or resumed, so in practice it never runs dry; a user
/// who doesn't open the app for a month straight stops being reminded, which is
/// the deliberate trade for showing the page number in the notification itself.
///
/// iOS caps an app at 64 pending notifications, so the horizon has to stay well
/// under that — it shares the budget with anything else the app schedules.
class DailyPageService {
  DailyPageService._();
  static final DailyPageService instance = DailyPageService._();

  /// Payload prefix used to route notification taps back here.
  static const String payloadPrefix = 'dailyPage';

  static const String _enabledPrefKey = 'dailyPageEnabled';
  static const String _modePrefKey = 'dailyPageMode';
  static const String _fixedMinutesPrefKey = 'dailyPageFixedMinutes';
  static const String _windowStartPrefKey = 'dailyPageWindowStartMinutes';
  static const String _windowEndPrefKey = 'dailyPageWindowEndMinutes';
  static const String _scheduledOnPrefKey = 'dailyPageScheduledOn';
  static const String _occurrencesPrefKey = 'dailyPageOccurrences';
  static const String _pendingPagePrefKey = 'dailyPagePendingOpen';

  /// Notification id block reserved for the reminders. Kept clear of
  /// `UpdateNotificationService`'s 4801.
  static const int _firstNotificationId = 4900;
  static const int _horizonDays = 30;

  static const String _channelId = 'daily_page';
  static const String _channelName = 'صفحة اليوم';

  /// Total pages in the mushaf, matching the bundled page images.
  static const int pageCount = 602;

  /// Default reminder time in fixed mode: 20:00.
  static const int defaultFixedMinutes = 20 * 60;

  /// Default random window: 08:00 – 22:00.
  static const int defaultWindowStartMinutes = 8 * 60;
  static const int defaultWindowEndMinutes = 22 * 60;

  /// The random window must stay at least this wide so there is something to
  /// draw from.
  static const int minWindowSpanMinutes = 30;

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<DailyPageReminderMode> mode =
      ValueNotifier<DailyPageReminderMode>(DailyPageReminderMode.fixed);
  final ValueNotifier<int> fixedMinutes = ValueNotifier<int>(
    defaultFixedMinutes,
  );
  final ValueNotifier<int> windowStartMinutes = ValueNotifier<int>(
    defaultWindowStartMinutes,
  );
  final ValueNotifier<int> windowEndMinutes = ValueNotifier<int>(
    defaultWindowEndMinutes,
  );

  /// When the next reminder is due, so Settings can show it. Null while the
  /// feature is off or before the first schedule has been built.
  final ValueNotifier<DateTime?> nextReminderAt = ValueNotifier<DateTime?>(null);

  /// Set to the page a tapped reminder pointed at, for the reader to open.
  /// Consumers clear it with [takePendingOpenPage].
  final ValueNotifier<int?> pendingOpenPage = ValueNotifier<int?>(null);

  final Random _random = Random();

  bool _loaded = false;
  bool _rescheduling = false;

  /// Tail of the chained prefs writes for [pendingOpenPage]; see
  /// [_setPendingOpenPage].
  Future<void>? _pendingPageWrite;

  /// Reads the stored preferences. Cheap (prefs only) and safe on the startup
  /// path — it deliberately does not touch the notification plugin or the
  /// timezone database, which [refreshSchedule] handles later off the critical
  /// path.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledPrefKey) ?? false;
    mode.value = prefs.getString(_modePrefKey) == 'random'
        ? DailyPageReminderMode.random
        : DailyPageReminderMode.fixed;
    fixedMinutes.value = _clampMinutes(
      prefs.getInt(_fixedMinutesPrefKey) ?? defaultFixedMinutes,
    );
    windowStartMinutes.value = _clampMinutes(
      prefs.getInt(_windowStartPrefKey) ?? defaultWindowStartMinutes,
    );
    windowEndMinutes.value = _clampMinutes(
      prefs.getInt(_windowEndPrefKey) ?? defaultWindowEndMinutes,
    );
    if (windowEndMinutes.value - windowStartMinutes.value <
        minWindowSpanMinutes) {
      windowStartMinutes.value = defaultWindowStartMinutes;
      windowEndMinutes.value = defaultWindowEndMinutes;
    }
    final pending = prefs.getInt(_pendingPagePrefKey);
    if (pending != null) {
      pendingOpenPage.value = pending;
    }
    _publishNextReminder(prefs);

    // Registering here (rather than on first use) means a tap that cold-started
    // the app is picked up as soon as the plugin finishes initialising, even
    // though initialisation itself is deferred.
    NotificationCenter.instance.registerTapHandler(
      payloadPrefix,
      handleReminderTapped,
    );
  }

  /// Turns the feature on or off. Turning it on asks for the OS notification
  /// permission first and refuses if it is denied, so the switch never sits in
  /// an "on but silently doing nothing" state.
  Future<DailyPageEnableResult> setEnabled(bool value) async {
    await load();
    if (!value) {
      enabled.value = false;
      nextReminderAt.value = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledPrefKey, false);
      await prefs.remove(_scheduledOnPrefKey);
      await prefs.remove(_occurrencesPrefKey);
      await _cancelAll();
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

  Future<void> setMode(DailyPageReminderMode value) async {
    if (mode.value == value) return;
    mode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _modePrefKey,
      value == DailyPageReminderMode.random ? 'random' : 'fixed',
    );
    if (enabled.value) await reschedule();
  }

  Future<void> setFixedMinutes(int minutes) async {
    final value = _clampMinutes(minutes);
    if (fixedMinutes.value == value) return;
    fixedMinutes.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_fixedMinutesPrefKey, value);
    if (enabled.value && mode.value == DailyPageReminderMode.fixed) {
      await reschedule();
    }
  }

  /// Sets the window random reminders are drawn from. The end is pushed out (or
  /// the start pulled in) as needed to keep at least [minWindowSpanMinutes]
  /// between them.
  Future<void> setRandomWindow({required int start, required int end}) async {
    var newStart = _clampMinutes(start);
    var newEnd = _clampMinutes(end);
    if (newEnd - newStart < minWindowSpanMinutes) {
      if (newEnd + minWindowSpanMinutes <= _maxMinutes) {
        newEnd = newStart + minWindowSpanMinutes;
      } else {
        newEnd = _maxMinutes;
        newStart = newEnd - minWindowSpanMinutes;
      }
    }
    if (windowStartMinutes.value == newStart &&
        windowEndMinutes.value == newEnd) {
      return;
    }
    windowStartMinutes.value = newStart;
    windowEndMinutes.value = newEnd;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_windowStartPrefKey, newStart);
    await prefs.setInt(_windowEndPrefKey, newEnd);
    if (enabled.value && mode.value == DailyPageReminderMode.random) {
      await reschedule();
    }
  }

  /// Tops the queue back up if it hasn't been rebuilt today. Called on startup
  /// and on every resume; cheap to call repeatedly because the date check —
  /// a plain prefs read, before anything touches the notification plugin —
  /// short-circuits it after the first run of the day.
  ///
  /// Pass [verifyQueue] on a cold start to also confirm the OS still holds the
  /// reminders. Android drops an app's alarms when it is force-stopped, and
  /// aggressive OEM battery managers do the same — the date guard alone would
  /// then skip rescheduling for the rest of the day and silently lose the
  /// reminder. Costs one extra platform call, so it is not worth doing on every
  /// resume.
  Future<void> refreshSchedule({bool verifyQueue = false}) async {
    await load();
    if (!enabled.value || kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_scheduledOnPrefKey) == _dateKey(DateTime.now())) {
      if (!verifyQueue || await _queueLooksIntact()) return;
    }
    if (!await verifyPermissionStillGranted()) return;
    await reschedule();
  }

  /// Whether the OS still holds any of this feature's scheduled reminders.
  /// Checks for *any* rather than a full count: the queue legitimately drains
  /// as reminders fire during the day.
  Future<bool> _queueLooksIntact() async {
    try {
      await NotificationCenter.instance.ensureInitialized();
      final pending = await NotificationCenter.instance.plugin
          .pendingNotificationRequests();
      return pending.any(
        (request) =>
            request.id >= _firstNotificationId &&
            request.id < _firstNotificationId + _horizonDays,
      );
    } catch (error, stack) {
      // Can't tell — assume intact rather than churning the whole schedule on
      // a transient platform error.
      debugPrint('DailyPageService queue check failed: $error\n$stack');
      return true;
    }
  }

  /// Checks the OS notification permission and turns the feature off if it has
  /// been revoked from system settings, so the switch in Settings never claims
  /// reminders are running when the OS will drop them. Returns whether the
  /// feature is still on afterwards.
  Future<bool> verifyPermissionStillGranted() async {
    await load();
    if (!enabled.value || kIsWeb) return false;
    if (await NotificationCenter.instance.areNotificationsEnabled()) {
      return true;
    }
    enabled.value = false;
    nextReminderAt.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPrefKey, false);
    await prefs.remove(_scheduledOnPrefKey);
    await prefs.remove(_occurrencesPrefKey);
    await _cancelAll();
    return false;
  }

  /// Rebuilds the whole queue: cancels the reserved id block and schedules a
  /// fresh horizon of reminders, each with its own random page.
  Future<void> reschedule() async {
    if (kIsWeb || _rescheduling) return;
    _rescheduling = true;
    try {
      final center = NotificationCenter.instance;
      await center.ensureInitialized();
      await center.ensureTimeZoneReady();
      await _cancelAll();
      if (!enabled.value) return;

      final scheduleMode = await center.canScheduleExactAlarms()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      final occurrences = _upcomingOccurrences(DateTime.now());
      // Draw without replacement across the batch so the same page can't come
      // up twice in the same month of reminders.
      final drawn = <int>{};
      final scheduled = <DateTime>[];

      for (var i = 0; i < occurrences.length; i++) {
        final when = occurrences[i];
        final page = _drawPage(drawn);
        drawn.add(page);
        final body = _notificationBody(page);
        try {
          await center.plugin.zonedSchedule(
            _firstNotificationId + i,
            _channelName,
            body,
            tz.TZDateTime.from(when, tz.local),
            _notificationDetails(body),
            androidScheduleMode: scheduleMode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: '$payloadPrefix:$page',
          );
          scheduled.add(when);
        } catch (error, stack) {
          debugPrint('DailyPageService schedule failed: $error\n$stack');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_scheduledOnPrefKey, _dateKey(DateTime.now()));
      // Kept so Settings can still say when the next reminder is due after a
      // restart that finds the queue already built for today.
      await prefs.setStringList(
        _occurrencesPrefKey,
        scheduled
            .map((when) => when.millisecondsSinceEpoch.toString())
            .toList(),
      );
      _publishNextReminder(prefs);
    } finally {
      _rescheduling = false;
    }
  }

  /// Points [nextReminderAt] at the first queued reminder still in the future.
  void _publishNextReminder(SharedPreferences prefs) {
    if (!enabled.value) {
      nextReminderAt.value = null;
      return;
    }
    final now = DateTime.now();
    for (final raw in prefs.getStringList(_occurrencesPrefKey) ?? const []) {
      final millis = int.tryParse(raw);
      if (millis == null) continue;
      final when = DateTime.fromMillisecondsSinceEpoch(millis);
      if (when.isAfter(now)) {
        nextReminderAt.value = when;
        return;
      }
    }
    nextReminderAt.value = null;
  }

  /// Initialises the notification plugin far enough to learn whether a tapped
  /// reminder is what launched the app, populating [pendingOpenPage] before the
  /// splash screen decides which page to open.
  ///
  /// Only pays that cost when the feature is on, and is capped so a stalled
  /// platform channel can never hold the splash screen open.
  Future<void> resolveLaunchTap() async {
    await load();
    if (!enabled.value || kIsWeb) return;
    try {
      await NotificationCenter.instance.ensureInitialized().timeout(
        const Duration(seconds: 2),
      );
    } catch (error, stack) {
      debugPrint('DailyPageService launch tap lookup failed: $error\n$stack');
    }
  }

  /// Returns the page a tapped reminder pointed at and clears it, so the reader
  /// opens it once and a later restart doesn't jump there again.
  int? takePendingOpenPage() {
    final page = pendingOpenPage.value;
    if (page == null) return null;
    _setPendingOpenPage(null);
    return page;
  }

  /// Records the page a tapped reminder pointed at. Public only so a test can
  /// drive the tap without a platform channel.
  @visibleForTesting
  void handleReminderTapped(String value) {
    final page = int.tryParse(value);
    if (page == null || page < 1 || page > pageCount) return;
    _setPendingOpenPage(page);
  }

  /// Updates the pending page in memory *and* on disk. The notifier is set
  /// synchronously so a listening reader reacts on this turn of the loop, while
  /// the prefs writes are chained: setting the value fires the listener, which
  /// calls [takePendingOpenPage] to clear it, so an unchained pair would let
  /// the tap's write land after the removal and strand a page that would then
  /// be re-opened on the next cold start.
  void _setPendingOpenPage(int? page) {
    // Extend the chain *before* touching the notifier. Setting it runs the
    // reader's listener synchronously, which calls takePendingOpenPage and
    // re-enters here to queue the removal — and that re-entry has to see this
    // write as the tail, or the removal chains behind the stale tail and the
    // write that set the page settles last, stranding a page that would be
    // re-opened on the next cold start.
    _pendingPageWrite = (_pendingPageWrite ?? Future<void>.value()).then((
      _,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      if (page == null) {
        await prefs.remove(_pendingPagePrefKey);
      } else {
        // Persisted because on a cold start the tap is delivered before the
        // reader exists, and the splash screen reads it back from prefs.
        await prefs.setInt(_pendingPagePrefKey, page);
      }
    });
    pendingOpenPage.value = page;
  }

  Future<void> _cancelAll() async {
    if (kIsWeb) return;
    try {
      await NotificationCenter.instance.ensureInitialized();
      for (var i = 0; i < _horizonDays; i++) {
        await NotificationCenter.instance.plugin.cancel(
          _firstNotificationId + i,
        );
      }
    } catch (error, stack) {
      debugPrint('DailyPageService cancel failed: $error\n$stack');
    }
  }

  List<DateTime> _upcomingOccurrences(DateTime now) => upcomingOccurrences(
    now: now,
    mode: mode.value,
    fixedMinutes: fixedMinutes.value,
    windowStartMinutes: windowStartMinutes.value,
    windowEndMinutes: windowEndMinutes.value,
    random: _random,
  );

  /// The next [count] reminder times, starting from the first one still in the
  /// future — today is skipped when its slot (or its whole window) has already
  /// passed.
  ///
  /// Pure, so the day-boundary arithmetic can be tested without a device: pass
  /// a seeded [Random] for a repeatable random-mode schedule.
  @visibleForTesting
  static List<DateTime> upcomingOccurrences({
    required DateTime now,
    required DailyPageReminderMode mode,
    required int fixedMinutes,
    required int windowStartMinutes,
    required int windowEndMinutes,
    required Random random,
    int count = _horizonDays,
  }) {
    // A minute of slack: the platform rejects a schedule that lands in the
    // past, and building the batch itself takes a moment.
    final earliest = now.add(const Duration(minutes: 1));
    final today = DateTime(now.year, now.month, now.day);
    final result = <DateTime>[];

    for (var day = 0; result.length < count; day++) {
      // Bounded so a pathological config can't spin: at most one skipped day
      // (today) is ever expected.
      if (day > count + 1) break;
      final int? minutes;
      if (mode == DailyPageReminderMode.fixed) {
        minutes = fixedMinutes;
      } else {
        // Only today can be partly in the past; on later days the whole window
        // is available.
        final from = day == 0
            ? max(windowStartMinutes, _minutesOfDay(earliest))
            : windowStartMinutes;
        minutes = from > windowEndMinutes
            ? null
            : from + random.nextInt(windowEndMinutes - from + 1);
      }
      if (minutes == null) continue;
      // Built from calendar fields rather than by adding a Duration so the
      // reminder keeps its wall-clock time across a month end or a DST shift.
      final when = DateTime(
        today.year,
        today.month,
        today.day + day,
        minutes ~/ 60,
        minutes % 60,
      );
      if (!when.isAfter(earliest)) continue;
      result.add(when);
    }
    return result;
  }

  int _drawPage(Set<int> alreadyDrawn) {
    // The batch is far smaller than the mushaf, so a couple of retries always
    // lands on a free page; the fallback scan is just belt and braces.
    for (var attempt = 0; attempt < 12; attempt++) {
      final page = _random.nextInt(pageCount) + 1;
      if (!alreadyDrawn.contains(page)) return page;
    }
    for (var page = 1; page <= pageCount; page++) {
      if (!alreadyDrawn.contains(page)) return page;
    }
    return _random.nextInt(pageCount) + 1;
  }

  NotificationDetails _notificationDetails(String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'تذكير يومي بقراءة صفحة من المصحف',
        importance: Importance.high,
        priority: Priority.high,
        // The body carries a surah name and can wrap; expand it so the page is
        // readable without opening the app.
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  String _notificationBody(int page) =>
      'اقرأ صفحة اليوم: صفحة $page — ${surahNameForPage(page)}';

  /// Name of the surah a page belongs to, for the reminder text.
  static String surahNameForPage(int page) {
    var name = surahList.first['name'] as String;
    for (final surah in surahList) {
      if ((surah['page'] as int) > page) break;
      name = surah['name'] as String;
    }
    return name;
  }

  static const int _maxMinutes = 23 * 60 + 59;

  static int _clampMinutes(int minutes) => minutes.clamp(0, _maxMinutes);

  static int _minutesOfDay(DateTime time) => time.hour * 60 + time.minute;

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month}-${date.day}';
}

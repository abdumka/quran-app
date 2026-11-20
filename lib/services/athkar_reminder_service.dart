import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'city_search_service.dart';
import 'daily_page_service.dart' show DailyPageEnableResult;
import 'notification_center.dart';
import 'sun_times.dart';
import 'tv_service.dart';

enum AthkarReminderKind { morning, evening }

enum AthkarReminderMode { sun, fixed }

extension AthkarReminderKindText on AthkarReminderKind {
  String get id => this == AthkarReminderKind.morning ? 'morning' : 'evening';

  /// «أذكار الصباح» / «أذكار المساء».
  String get label =>
      this == AthkarReminderKind.morning ? 'أذكار الصباح' : 'أذكار المساء';

  /// «الشروق» / «الغروب».
  String get sunWord =>
      this == AthkarReminderKind.morning ? 'الشروق' : 'الغروب';

  /// The minutes from the sun the reminder starts at (owner, 2026-11-19:
  /// morning 50 before sunrise, about 30 after al-Fajr in Libya; evening 30
  /// before sunset).
  int get defaultOffset => this == AthkarReminderKind.morning ? -50 : -30;
  int get minOffset => -90;
  int get maxOffset => this == AthkarReminderKind.morning ? 30 : 60;

  /// The clock time used with no place, or where the sun does not rise or
  /// set that day: 6:30 ص and 4:30 م.
  int get fallbackMinutes =>
      this == AthkarReminderKind.morning ? 6 * 60 + 30 : 16 * 60 + 30;
}

/// One reminder's settings.
@immutable
class AthkarReminderConfig {
  const AthkarReminderConfig({
    required this.on,
    required this.mode,
    required this.offset,
    required this.fixedMinutes,
  });

  final bool on;
  final AthkarReminderMode mode;

  /// Minutes from sunrise/sunset, in steps of 10 (negative = before).
  final int offset;

  /// The clock time of «وقت محدد», minutes after midnight.
  final int fixedMinutes;

  AthkarReminderConfig copyWith({
    bool? on,
    AthkarReminderMode? mode,
    int? offset,
    int? fixedMinutes,
  }) => AthkarReminderConfig(
    on: on ?? this.on,
    mode: mode ?? this.mode,
    offset: offset ?? this.offset,
    fixedMinutes: fixedMinutes ?? this.fixedMinutes,
  );
}

/// «أذكار الصباح» and «أذكار المساء» reminders, timed to the sun (owner,
/// 2026-11-19): by default 50 minutes before sunrise and 30 minutes before
/// sunset where the reader is, or at a clock time of their choosing.
///
/// * On for everyone by default, existing readers included. Like «صفحة
///   اليوم», a reminder only shows where notifications are allowed; until
///   they are, a reminder the reader never touched simply waits (it is not
///   switched off for good), and the first opening of الأذكار asks.
/// * The place: the phone's location or a city from the list, set when الأذكار
///   is first opened; until then the main city of the phone's time zone.
///   The times are worked out on the phone; the location never leaves it.
/// * The sun moves every day, so instead of one repeating notification each
///   day gets its own: [horizonDays] days ahead, topped up whenever the app
///   opens. 12 days x 2 = 24 of the 64 notifications iOS allows an app
///   (صفحة اليوم 30, لا تهجر القرآن 3, الكهف 1, updates 1-2).
/// * Inexact alarms, like the other reminders: the owner accepts "whenever
///   the phone wakes up" over asking for the exact-alarm permission.
/// * Each notification has «إيقاف»: it opens the app and turns that
///   reminder off, with an undo.
class AthkarReminderService {
  AthkarReminderService._();
  static final AthkarReminderService instance = AthkarReminderService._();

  static const String payloadPrefix = 'athkar';
  static const String stopAction = 'stop';
  static const String iosCategory = 'athkar_reminder';
  static const int horizonDays = 12;

  /// After صفحة اليوم's 4900-4929: morning 4930-4941, evening 4942-4953.
  static const int _firstId = 4930;

  static const String _channelId = 'athkar_reminder';
  static const String _channelName = 'تذكير الأذكار';

  static const String _placeKey = 'athkarReminderPlace';
  static const String _introKey = 'athkarReminderIntroShown';
  static const String _scheduledKey = 'athkarReminderScheduled';

  final ValueNotifier<AthkarReminderConfig> morning = ValueNotifier(
    _defaults(AthkarReminderKind.morning),
  );
  final ValueNotifier<AthkarReminderConfig> evening = ValueNotifier(
    _defaults(AthkarReminderKind.evening),
  );

  /// The place the reader set (location or a city); null until then.
  final ValueNotifier<AthkarPlace?> place = ValueNotifier(null);

  /// The main city of the phone's time zone, used while [place] is null.
  final ValueNotifier<AthkarPlace?> zonePlace = ValueNotifier(null);

  /// A tapped reminder: which athkar to open. The reader page clears it.
  final ValueNotifier<AthkarReminderKind?> pendingOpen = ValueNotifier(null);

  /// A reminder turned off from its notification's «إيقاف»: the app says so
  /// and offers to undo. Cleared once shown.
  final ValueNotifier<AthkarReminderKind?> stoppedFromNotification =
      ValueNotifier(null);

  final Map<AthkarReminderKind, bool?> _stored = {};
  bool _allowed = true;
  bool _introShown = false;
  bool _loaded = false;
  Future<void>? _loading;
  String? _zoneId;

  ValueNotifier<AthkarReminderConfig> config(AthkarReminderKind kind) =>
      kind == AthkarReminderKind.morning ? morning : evening;

  AthkarPlace? get effectivePlace => place.value ?? zonePlace.value;

  bool get introShown => _introShown;

  /// Phones only: not the web build, and not a TV (no notifications there
  /// to speak of, and no place to ask for).
  static bool get supported =>
      !kIsWeb &&
      !TvService.instance.isTv &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static AthkarReminderConfig _defaults(AthkarReminderKind kind) =>
      AthkarReminderConfig(
        on: true,
        mode: AthkarReminderMode.sun,
        offset: kind.defaultOffset,
        fixedMinutes: kind.fallbackMinutes,
      );

  static String _key(AthkarReminderKind kind, String what) =>
      'athkarReminder.${kind.id}.$what';

  /// Prefs only (safe on the startup path), and claims the tap prefix so a
  /// tap that cold-started the app is delivered.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final kind in AthkarReminderKind.values) {
      final stored = prefs.getBool(_key(kind, 'on'));
      _stored[kind] = stored;
      final mode = prefs.getString(_key(kind, 'mode')) == 'fixed'
          ? AthkarReminderMode.fixed
          : AthkarReminderMode.sun;
      final offset = _clampOffset(
        kind,
        prefs.getInt(_key(kind, 'offset')) ?? kind.defaultOffset,
      );
      final fixed = (prefs.getInt(_key(kind, 'fixed')) ?? kind.fallbackMinutes)
          .clamp(0, 24 * 60 - 1);
      config(kind).value = AthkarReminderConfig(
        on: stored ?? true,
        mode: mode,
        offset: offset,
        fixedMinutes: fixed,
      );
    }
    try {
      final raw = prefs.getString(_placeKey);
      if (raw != null) place.value = AthkarPlace.fromJson(json.decode(raw));
    } catch (_) {}
    _introShown = prefs.getBool(_introKey) ?? false;
    _loaded = true;
    NotificationCenter.instance.registerTapHandler(payloadPrefix, handleTap);
  }

  static int _clampOffset(AthkarReminderKind kind, int v) {
    final stepped = (v / 10).round() * 10;
    return stepped.clamp(kind.minOffset, kind.maxOffset);
  }

  Future<void> markIntroShown() async {
    _introShown = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introKey, true);
  }

  // ---------------------------------------------------------------- times

  /// When [kind] fires on the local day of [day], in the phone's own time.
  DateTime fireTime(AthkarReminderKind kind, DateTime day) {
    final c = config(kind).value;
    DateTime clock(int minutes) =>
        DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
    if (c.mode == AthkarReminderMode.fixed) return clock(c.fixedMinutes);
    final sun = sunEvent(kind, day);
    if (sun == null) return clock(kind.fallbackMinutes);
    return sun.add(Duration(minutes: c.offset));
  }

  /// Sunrise (morning) or sunset (evening) at the place on [day], local time;
  /// null with no place or where the sun does not rise or set that day.
  DateTime? sunEvent(AthkarReminderKind kind, DateTime day) {
    final p = effectivePlace;
    if (p == null) return null;
    final t = SunTimes.of(day.year, day.month, day.day, p.lat, p.lon);
    final e = kind == AthkarReminderKind.morning ? t.sunrise : t.sunset;
    return e?.toLocal();
  }

  /// The next time [kind] fires after [now], or null when it is off.
  DateTime? nextFire(AthkarReminderKind kind, [DateTime? now]) {
    final at = now ?? DateTime.now();
    if (!config(kind).value.on) return null;
    for (var d = 0; d < 3; d++) {
      final t = fireTime(kind, DateTime(at.year, at.month, at.day + d));
      if (t.isAfter(at)) return t;
    }
    return null;
  }

  // ---------------------------------------------------------------- changes

  /// Turns [kind] on or off. On asks for notifications first and refuses
  /// when they are denied, so the switch never says on while nothing shows.
  Future<DailyPageEnableResult> setEnabled(
    AthkarReminderKind kind,
    bool value,
  ) async {
    await load();
    if (value) {
      if (!supported) return DailyPageEnableResult.unsupported;
      final granted = await NotificationCenter.instance.requestPermission();
      if (!granted) return DailyPageEnableResult.permissionDenied;
      _allowed = true;
      // the other one, if never touched, comes on with the permission too
      for (final other in AthkarReminderKind.values) {
        final c = config(other).value;
        if (_stored[other] == null && !c.on) {
          config(other).value = c.copyWith(on: true);
        }
      }
    }
    _stored[kind] = value;
    config(kind).value = config(kind).value.copyWith(on: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(kind, 'on'), value);
    await reschedule();
    return DailyPageEnableResult.ok;
  }

  Future<void> setMode(AthkarReminderKind kind, AthkarReminderMode mode) async {
    await load();
    final c = config(kind).value;
    if (c.mode == mode) return;
    var fixed = c.fixedMinutes;
    final prefs = await SharedPreferences.getInstance();
    if (mode == AthkarReminderMode.fixed &&
        prefs.getInt(_key(kind, 'fixed')) == null) {
      // starts at today's sun time, rounded to 10 minutes
      final now = DateTime.now();
      final t = fireTime(kind, DateTime(now.year, now.month, now.day));
      fixed = ((t.hour * 60 + t.minute) / 10).round() * 10 % (24 * 60);
      await prefs.setInt(_key(kind, 'fixed'), fixed);
    }
    config(kind).value = c.copyWith(mode: mode, fixedMinutes: fixed);
    await prefs.setString(_key(kind, 'mode'), mode.name);
    await reschedule();
  }

  /// Moves the sun-based time by [delta] minutes (a 10-minute step).
  Future<void> moveOffset(AthkarReminderKind kind, int delta) async {
    await load();
    final c = config(kind).value;
    final v = _clampOffset(kind, c.offset + delta);
    if (v == c.offset) return;
    config(kind).value = c.copyWith(offset: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(kind, 'offset'), v);
    await reschedule();
  }

  Future<void> setFixedMinutes(AthkarReminderKind kind, int minutes) async {
    await load();
    final v = minutes.clamp(0, 24 * 60 - 1);
    config(kind).value = config(kind).value.copyWith(fixedMinutes: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(kind, 'fixed'), v);
    await reschedule();
  }

  Future<void> setPlace(AthkarPlace value) async {
    await load();
    place.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_placeKey, json.encode(value.toJson()));
    await reschedule();
  }

  // ---------------------------------------------------------------- schedule

  /// Tops the queue up: on the first frame and on every resume. Cheap once
  /// it has run that day, unless the time zone or the settings changed.
  Future<void> refreshSchedule({bool force = false}) async {
    if (!supported) return;
    await load();
    await _updateZone();
    final bool allowed;
    try {
      allowed = await NotificationCenter.instance.areNotificationsEnabled();
    } catch (error) {
      debugPrint('AthkarReminderService permission check failed: $error');
      return;
    }
    final changed = allowed != _allowed;
    _allowed = allowed;
    for (final kind in AthkarReminderKind.values) {
      final stored = _stored[kind];
      final c = config(kind).value;
      if (stored == null) {
        // never touched: on as soon as notifications are allowed
        if (c.on != allowed) config(kind).value = c.copyWith(on: allowed);
      } else if (stored && !allowed) {
        // allowed once and taken back in the phone's settings: off, honestly
        _stored[kind] = false;
        config(kind).value = c.copyWith(on: false);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_key(kind, 'on'), false);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final stamp = _stamp(DateTime.now());
    if (!force && !changed && prefs.getString(_scheduledKey) == stamp) return;
    await reschedule();
  }

  /// Today + the place + the zone: what the queue was built for.
  String _stamp(DateTime now) {
    final p = effectivePlace;
    return '${now.year}-${now.month}-${now.day}|${p?.lat},${p?.lon}|$_zoneId';
  }

  Future<void> _updateZone() async {
    try {
      final id = (await FlutterTimezone.getLocalTimezone()).identifier;
      if (id == _zoneId && zonePlace.value != null) return;
      _zoneId = id;
      zonePlace.value = await CitySearchService.instance.zonePlace(id);
    } catch (error) {
      debugPrint('AthkarReminderService zone lookup failed: $error');
    }
  }

  /// Rebuilds the whole queue: [horizonDays] days of each reminder that is on.
  Future<void> reschedule() async {
    if (!supported) return;
    await load();
    try {
      final center = NotificationCenter.instance;
      await center.ensureInitialized();
      await center.ensureTimeZoneReady();
      if (_zoneId == null) await _updateZone();
      for (var i = 0; i < horizonDays * 2; i++) {
        await center.plugin.cancel(_firstId + i);
      }
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setString(_scheduledKey, _stamp(now));
      if (!_allowed) return;
      final mode = await center.canScheduleExactAlarms()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final soonest = now.add(const Duration(minutes: 1));
      for (final kind in AthkarReminderKind.values) {
        if (!config(kind).value.on) continue;
        final base = kind == AthkarReminderKind.morning
            ? _firstId
            : _firstId + horizonDays;
        var slot = 0;
        for (var d = 0; d <= horizonDays && slot < horizonDays; d++) {
          final when = fireTime(kind, DateTime(now.year, now.month, now.day + d));
          if (!when.isAfter(soonest)) continue;
          await center.plugin.zonedSchedule(
            base + slot,
            kind.label,
            'اضغط لتبدأ ${kind.label}.',
            tz.TZDateTime.from(when, tz.local),
            _details(kind),
            androidScheduleMode: mode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: '$payloadPrefix:${kind.id}',
          );
          slot++;
        }
      }
    } catch (error, stack) {
      debugPrint('AthkarReminderService schedule failed: $error\n$stack');
    }
  }

  NotificationDetails _details(AthkarReminderKind kind) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'تذكير بأذكار الصباح والمساء',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation('اضغط لتبدأ ${kind.label}.'),
      actions: const [
        AndroidNotificationAction(
          stopAction,
          'إيقاف',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    ),
    iOS: const DarwinNotificationDetails(categoryIdentifier: iosCategory),
  );

  /// `athkar:morning`, or `athkar:morning#stop` for «إيقاف».
  void handleTap(String value) {
    final parts = value.split('#');
    final kind = parts.first == 'evening'
        ? AthkarReminderKind.evening
        : AthkarReminderKind.morning;
    if (parts.length > 1 && parts[1] == stopAction) {
      setEnabled(kind, false).then((_) {
        stoppedFromNotification.value = kind;
      });
      return;
    }
    pendingOpen.value = kind;
  }

  /// Tests only.
  @visibleForTesting
  void debugReset() {
    _loading = null;
    _loaded = false;
    _stored.clear();
    _allowed = true;
    _introShown = false;
    _zoneId = null;
    place.value = null;
    zonePlace.value = null;
    pendingOpen.value = null;
    stoppedFromNotification.value = null;
    morning.value = _defaults(AthkarReminderKind.morning);
    evening.value = _defaults(AthkarReminderKind.evening);
  }

  @visibleForTesting
  bool get isLoaded => _loaded;
}

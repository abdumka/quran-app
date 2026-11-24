import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_service.dart';
import 'content_update_service.dart';
import 'debug_log_service.dart';

/// What «التحقق من وجود تحديث» found: a newer store release, newer server
/// data, both, nothing, or no connection.
@immutable
class UpdateCheckOutcome {
  const UpdateCheckOutcome({
    this.appUpdate,
    this.dataMessage,
    this.failed = false,
  });

  static const String upToDateText =
      'أنت تستخدم أحدث إصدار من التطبيق وبياناته.';
  static const String failedText =
      'تعذر التحقق من التحديثات. تحقق من اتصالك بالإنترنت.';

  /// A newer store release, shown with the update dialog.
  final AppUpdateInfo? appUpdate;

  /// What the data check installed ([ContentCheckResult.message]).
  final String? dataMessage;

  /// The data check could not reach the server.
  final bool failed;

  /// The line to show the reader, or null when the update dialog alone says
  /// it all.
  String? get notice {
    if (dataMessage != null) return dataMessage;
    if (appUpdate != null) return null;
    return failed ? failedText : upToDateText;
  }

  /// One line for the record in «أدوات الاختبار».
  String get summary {
    final app = appUpdate;
    final parts = [
      if (app != null) 'يوجد إصدار جديد ${app.latestVersion}.',
      ?notice,
    ];
    return parts.join(' ');
  }
}

/// «التحقق من وجود تحديث»: the store release and the server-updated data
/// (tanzilat, reciters, athkar...), checked together. Run from the settings
/// button and from a tapped notification whose payload is `check:`
/// ([PushUpdateCheck]).
class UpdateCheck {
  UpdateCheck._();

  /// Never throws. Whatever newer data the server has is installed on the
  /// way (by [ContentUpdateService]); the store release is only reported.
  static Future<UpdateCheckOutcome> run() async {
    final content = _checkContent();
    AppUpdateInfo? info;
    try {
      info = await AppUpdateService.instance.fetchIfUpdateAvailable();
    } catch (_) {
      info = null;
    }
    final data = await content;
    return UpdateCheckOutcome(
      appUpdate: info,
      dataMessage: data.message,
      failed: data.failed,
    );
  }

  static Future<ContentCheckResult> _checkContent() async {
    try {
      final service = ContentUpdateService.instance;
      var result = await service.check(manual: true);
      // Joined the launch's silent check, which skips when the last one was
      // recent: ask again, this time for real.
      if (result.skipped) result = await service.check(manual: true);
      return result;
    } catch (_) {
      return const ContentCheckResult.failed();
    }
  }
}

/// Lets a tapped notification with the payload `check:` run
/// «التحقق من وجود تحديث», on Android and iOS, whether the app was open, in
/// the background or closed.
///
/// The reader attaches the code that runs it ([attachRunner]), because the
/// result is shown over the mushaf. A tap that cold-started the app arrives
/// before that and waits here. The last run is kept, with its time and
/// result, so «أدوات الاختبار» can show that a test message worked.
class PushUpdateCheck {
  PushUpdateCheck._();
  static final PushUpdateCheck instance = PushUpdateCheck._();

  /// The payload prefix: `check:` from a Firebase message,
  /// `check:local` from the test button in «أدوات الاختبار».
  static const String prefix = 'check';
  static const String localTestValue = 'local';

  static const String _lastRunPrefKey = 'pushUpdateCheckLastRun';

  Future<void> Function(String value)? _runner;
  String? _pendingValue;
  bool _running = false;

  /// The last run: `null` until one has happened on this install.
  final ValueNotifier<PushUpdateCheckRecord?> lastRun =
      ValueNotifier<PushUpdateCheckRecord?>(null);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    lastRun.value = PushUpdateCheckRecord.decode(
      prefs.getString(_lastRunPrefKey),
    );
  }

  /// From the reader once it is on screen.
  void attachRunner(Future<void> Function(String value) runner) {
    _runner = runner;
    final pending = _pendingValue;
    if (pending != null) {
      _pendingValue = null;
      unawaited(_run(pending));
    }
  }

  /// The notification tap handler ([NotificationCenter] prefix [prefix]).
  void request(String value) {
    if (_runner == null) {
      _pendingValue = value;
      return;
    }
    unawaited(_run(value));
  }

  Future<void> _run(String value) async {
    final runner = _runner;
    // A second tap while the first check is still out changes nothing.
    if (runner == null || _running) return;
    _running = true;
    _log('tapped (${value.isEmpty ? 'push' : value})');
    try {
      await runner(value);
    } catch (error) {
      _log('run failed: $error');
    } finally {
      _running = false;
    }
  }

  /// Called by the runner with what the reader was shown.
  Future<void> record({required String value, required String result}) async {
    final entry = PushUpdateCheckRecord(
      at: DateTime.now(),
      fromLocalTest: value == localTestValue,
      result: result,
    );
    lastRun.value = entry;
    _log('result: $result');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRunPrefKey, entry.encode());
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest() {
    _runner = null;
    _pendingValue = null;
    _running = false;
    _loaded = false;
    lastRun.value = null;
  }

  void _log(String message) {
    debugPrint('[PushUpdateCheck] $message');
    try {
      DebugLogService.instance.log('[PushUpdateCheck] $message');
    } catch (_) {}
  }
}

/// When a `check:` notification last ran, what started it and what it found.
@immutable
class PushUpdateCheckRecord {
  const PushUpdateCheckRecord({
    required this.at,
    required this.fromLocalTest,
    required this.result,
  });

  final DateTime at;
  final bool fromLocalTest;
  final String result;

  String encode() =>
      '${at.toIso8601String()}|${fromLocalTest ? 'local' : 'push'}|$result';

  static PushUpdateCheckRecord? decode(String? raw) {
    if (raw == null) return null;
    final first = raw.indexOf('|');
    final second = first < 0 ? -1 : raw.indexOf('|', first + 1);
    if (second < 0) return null;
    final at = DateTime.tryParse(raw.substring(0, first));
    if (at == null) return null;
    return PushUpdateCheckRecord(
      at: at,
      fromLocalTest: raw.substring(first + 1, second) == 'local',
      result: raw.substring(second + 1),
    );
  }

  /// `2026-11-23 18:40`, in Western digits.
  String get timeLabel {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }
}

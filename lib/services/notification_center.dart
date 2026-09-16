import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Owns the app's single [FlutterLocalNotificationsPlugin] instance.
///
/// The plugin routes every tap through one method-channel handler, so the last
/// `initialize()` call wins: two services each creating their own instance
/// would silently steal each other's taps (an "update available" tap running
/// the daily-page handler, or vice versa). Everything that posts a notification
/// therefore goes through here and identifies itself with a payload prefix —
/// `<prefix>:<value>` — which this class dispatches back to the handler
/// registered for that prefix.
///
/// Nothing here runs at app startup: the plugin, the permission prompt and the
/// timezone database are all initialised lazily, the first time a feature
/// actually needs them.
class NotificationCenter {
  NotificationCenter._();
  static final NotificationCenter instance = NotificationCenter._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  final Map<String, void Function(String value)> _tapHandlers = {};

  bool _initialized = false;
  bool _timeZoneReady = false;

  /// Payload of the notification that cold-started the app, if any. Held until
  /// a handler is registered for its prefix (which happens after
  /// [ensureInitialized] returns), then delivered once and cleared.
  String? _pendingLaunchPayload;

  /// Registers the tap handler for notifications whose payload starts with
  /// `prefix:`. If the app was cold-started by such a notification, the handler
  /// is invoked immediately with that payload.
  void registerTapHandler(String prefix, void Function(String value) handler) {
    _tapHandlers[prefix] = handler;
    final pending = _pendingLaunchPayload;
    if (pending != null && pending.startsWith('$prefix:')) {
      _pendingLaunchPayload = null;
      handler(pending.substring(prefix.length + 1));
    }
  }

  /// Routes a `<prefix>:<value>` payload that arrived by some other path than
  /// this plugin — a tapped push notification, which the OS displayed itself —
  /// to the same handlers local notifications use.
  void handlePayload(String? payload) => _dispatch(payload);

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      // Don't request permission at init; each feature asks explicitly at the
      // moment the user opts into it, so the prompt has clear context.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) =>
          _dispatch(response.payload),
    );
    _initialized = true;

    // A tap that launched the app from cold doesn't arrive through the callback
    // above — it has to be read from the launch details. _dispatch delivers it
    // straight away if its feature has already claimed the prefix, and parks it
    // for registerTapHandler otherwise.
    try {
      final details = await plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        _dispatch(details?.notificationResponse?.payload);
      }
    } catch (error, stack) {
      debugPrint('NotificationCenter launch details failed: $error\n$stack');
    }
  }

  void _dispatch(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final separator = payload.indexOf(':');
    if (separator <= 0) return;
    final handler = _tapHandlers[payload.substring(0, separator)];
    if (handler == null) {
      // Arrived before its feature registered (an early cold-start tap); hold
      // it so registerTapHandler can deliver it.
      _pendingLaunchPayload = payload;
      return;
    }
    handler(payload.substring(separator + 1));
  }

  /// Requests notification permission where the OS requires it (Android 13+,
  /// iOS). Returns whether notifications are allowed. Safe to call repeatedly —
  /// once the user has answered, the OS returns the standing answer instead of
  /// prompting again.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await ensureInitialized();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final granted = await plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      // Below Android 13 there is no runtime permission, so a null answer means
      // "nothing to grant" rather than "denied".
      return granted ?? true;
    }
    return false;
  }

  /// Whether the OS currently lets the app post notifications. Unlike
  /// [requestPermission] this never shows a first-time prompt, so it
  /// is safe to poll on resume to notice a permission revoked in system
  /// settings.
  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    await ensureInitialized();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.areNotificationsEnabled() ?? true;
    }
    // checkPermissions only reads the current status. requestPermissions would
    // pop the one-time system prompt for a user who hasn't answered yet.
    final options = await plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    return options?.isEnabled ?? false;
  }

  /// Whether the OS grants this app exact alarms. Android 12+ withholds them
  /// unless the app declares SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM — both of
  /// which need a Play Store justification a reading reminder doesn't qualify
  /// for — so this is false there and callers fall back to an inexact schedule.
  Future<bool> canScheduleExactAlarms() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    await ensureInitialized();
    try {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Loads the timezone database and points `tz.local` at the device's zone.
  ///
  /// `zonedSchedule` passes the location *name* down to the platform, which
  /// resolves it with `ZoneId.of` / `NSTimeZone(name:)` — so it has to be a
  /// real IANA name, not a synthetic fixed-offset zone. Uses the 10-year
  /// dataset (a quarter the size of the full one) since reminders are only ever
  /// scheduled weeks ahead.
  Future<void> ensureTimeZoneReady() async {
    if (_timeZoneReady) return;
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (error, stack) {
      // Unknown/unsupported zone name: fall back to UTC rather than leaving
      // tz.local unset, which would throw on the first TZDateTime.
      debugPrint('NotificationCenter timezone lookup failed: $error\n$stack');
      tz.setLocalLocation(tz.UTC);
    }
    _timeZoneReady = true;
  }
}

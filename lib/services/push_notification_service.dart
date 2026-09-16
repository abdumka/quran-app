import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../firebase_options.dart';
import 'app_update_service.dart';
import 'daily_page_service.dart';
import 'debug_log_service.dart';
import 'notification_center.dart';

/// Receives push notifications sent through Firebase Cloud Messaging.
///
/// Every install subscribes to topics instead of registering its device token
/// anywhere, so sending needs no backend — the Firebase console targets a
/// topic directly:
///
///  * `all` — every install.
///  * `android` / `ios` — one platform (e.g. a store-specific update).
///  * `test` — debug and profile builds only, so a message can be tried on a
///    development device before it goes to `all`.
///
/// A message may carry a custom data key `payload` holding a
/// `<prefix>:<value>` string, routed through [NotificationCenter] when the
/// notification is tapped:
///
///  * `store:` — opens this platform's own store page ("go update the app"),
///    so one message can be sent to `all` rather than one per platform.
///  * `update:<store url>` — opens that exact store page.
///  * `url:<https link>` — opens the link in the browser.
///  * `page:<1-602>` — opens that mushaf page.
///
/// While the app is closed or in the background the OS displays the
/// notification itself, so no Dart background handler is registered (that
/// would spin up an isolate per message). Nothing here runs during `main()`:
/// [start] is called after the reader's first frame.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// Data key carrying the tap payload.
  static const String payloadKey = 'payload';

  static const String _channelId = 'announcements';
  static const String _channelName = 'إعلانات';
  static const String _channelDescription = 'أخبار وإعلانات من المصحف الجامع';

  /// The token and topic set the current subscriptions were made for.
  /// Subscriptions belong to a token, so a new token (app data restored onto a
  /// new device, or FCM rotating it) needs them made again.
  static const String _subscriptionPrefKey = 'pushTopicSubscription';

  bool _started = false;

  static bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static List<String> get _topics => [
    'all',
    defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    if (!kReleaseMode) 'test',
  ];

  Future<void> start() async {
    if (_started || !_isSupported) return;
    _started = true;
    try {
      _registerTapHandlers();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final messaging = FirebaseMessaging.instance;

      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleOpened(initial);

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS can show the banner itself while the app is open.
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } else {
        // Android never shows a push while the app is in the foreground, so
        // it is posted as a local notification instead.
        await _createAndroidChannel();
        FirebaseMessaging.onMessage.listen(_showWhileInForeground);
      }

      messaging.onTokenRefresh.listen(_subscribe);
      final token = await _getToken(messaging);
      if (token != null) await _subscribe(token);
    } catch (error, stack) {
      _log('start failed: $error\n$stack');
    }
  }

  void _registerTapHandlers() {
    final center = NotificationCenter.instance;
    center.registerTapHandler('url', (value) {
      final uri = Uri.tryParse(value);
      if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
        return;
      }
      launchUrl(uri, mode: LaunchMode.externalApplication);
    });
    center.registerTapHandler(
      'page',
      DailyPageService.instance.handleReminderTapped,
    );
    center.registerTapHandler('store', (_) {
      final url = defaultTargetPlatform == TargetPlatform.iOS
          ? AppUpdateService.appStoreUrl
          : AppUpdateService.playStoreUrl;
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    });
  }

  void _handleOpened(RemoteMessage message) {
    NotificationCenter.instance.handlePayload(message.data[payloadKey]);
  }

  /// On iOS the FCM token only exists once APNs has handed the app its own
  /// token, which can lag launch by a moment; asking earlier throws.
  Future<String?> _getToken(FirebaseMessaging messaging) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      for (var attempt = 0; attempt < 5; attempt++) {
        if (await messaging.getAPNSToken() != null) break;
        await Future.delayed(const Duration(seconds: 2));
      }
      if (await messaging.getAPNSToken() == null) {
        _log('no APNs token; topics will be subscribed on token refresh');
        return null;
      }
    }
    final token = await messaging.getToken();
    debugPrint('[Push] FCM token: $token');
    return token;
  }

  Future<void> _subscribe(String token) async {
    try {
      final topics = _topics;
      final signature = '$token|${topics.join(',')}';
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_subscriptionPrefKey) == signature) return;
      final messaging = FirebaseMessaging.instance;
      for (final topic in topics) {
        await messaging.subscribeToTopic(topic);
      }
      await prefs.setString(_subscriptionPrefKey, signature);
      _log('subscribed to ${topics.join(', ')}');
    } catch (error) {
      // Offline, most likely. The signature isn't saved, so the next launch
      // tries again.
      _log('topic subscription failed: $error');
    }
  }

  Future<void> _createAndroidChannel() async {
    final center = NotificationCenter.instance;
    await center.ensureInitialized();
    await center.plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
  }

  Future<void> _showWhileInForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    try {
      final center = NotificationCenter.instance;
      if (!await center.areNotificationsEnabled()) return;
      await center.plugin.show(
        (message.messageId ?? '${DateTime.now()}').hashCode & 0x7fffffff,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: message.data[payloadKey],
      );
    } catch (error) {
      _log('foreground display failed: $error');
    }
  }

  void _log(String message) {
    debugPrint('[Push] $message');
    try {
      DebugLogService.instance.log('[Push] $message');
    } catch (_) {}
  }
}

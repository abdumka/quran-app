import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

/// Presents an update as a system notification. Tapping it opens the store page.
///
/// Only used when the user opts into notification delivery in Settings; the
/// default is in-app only, which never touches this class (so no notification
/// permission is requested unless the user asks for it).
class UpdateNotificationService {
  UpdateNotificationService._();
  static final UpdateNotificationService instance =
      UpdateNotificationService._();

  static const int _updateNotificationId = 4801;
  static const String _channelId = 'app_updates';
  static const String _channelName = 'تحديثات التطبيق';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// The store URL to open when the notification is tapped, set each time a
  /// notification is shown.
  String? _pendingStoreUrl;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      // Don't request permission at init; we ask explicitly right before
      // showing a notification so the prompt has clear context.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final url = response.payload;
        if (url != null && url.isNotEmpty) {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } else if (_pendingStoreUrl != null) {
          launchUrl(
            Uri.parse(_pendingStoreUrl!),
            mode: LaunchMode.externalApplication,
          );
        }
      },
    );
    _initialized = true;
  }

  /// Requests notification permission where the OS requires it (Android 13+,
  /// iOS). Returns whether notifications are allowed. Safe to call repeatedly.
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    }
    return false;
  }

  /// Shows the "update available" notification. Does nothing if permission is
  /// denied. [storeUrl] is opened when the notification is tapped.
  Future<void> showUpdateNotification({
    required String title,
    required String body,
    required String storeUrl,
  }) async {
    final allowed = await requestPermission();
    if (!allowed) return;

    _pendingStoreUrl = storeUrl;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'إشعارات توفر تحديث جديد للتطبيق',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();

    await _plugin.show(
      _updateNotificationId,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: storeUrl,
    );
  }
}

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_center.dart';

/// Presents an update as a system notification. Tapping it opens the store page.
///
/// Only used when the user opts into notification delivery in Settings; the
/// default is in-app only, which never touches this class (so no notification
/// permission is requested unless the user asks for it).
class UpdateNotificationService {
  UpdateNotificationService._();
  static final UpdateNotificationService instance =
      UpdateNotificationService._();

  /// Payload prefix used to route notification taps back here. See
  /// [NotificationCenter] for why every feature needs its own.
  static const String payloadPrefix = 'update';

  static const int _updateNotificationId = 4801;
  static const String _channelId = 'app_updates';
  static const String _channelName = 'تحديثات التطبيق';

  bool _handlerRegistered = false;

  /// Claims the `update:` payload prefix so a tap opens the store page. Just a
  /// map insert — it does not initialise the notification plugin — so it is
  /// safe to call on the startup path, which is where it belongs: a tap that
  /// cold-started the app is only delivered once a handler exists for it.
  void registerTapHandler() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    NotificationCenter.instance.registerTapHandler(payloadPrefix, (url) {
      if (url.isEmpty) return;
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    });
  }

  /// Requests notification permission where the OS requires it (Android 13+,
  /// iOS). Returns whether notifications are allowed. Safe to call repeatedly.
  Future<bool> requestPermission() =>
      NotificationCenter.instance.requestPermission();

  /// Shows the "update available" notification. Does nothing if permission is
  /// denied. [storeUrl] is opened when the notification is tapped.
  Future<void> showUpdateNotification({
    required String title,
    required String body,
    required String storeUrl,
  }) async {
    final allowed = await NotificationCenter.instance.requestPermission();
    if (!allowed) return;
    registerTapHandler();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'إشعارات توفر تحديث جديد للتطبيق',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();

    await NotificationCenter.instance.plugin.show(
      _updateNotificationId,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: '$payloadPrefix:$storeUrl',
    );
  }
}

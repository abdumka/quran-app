import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_update_service.dart';
import 'notification_center.dart';

/// Presents an update as a system notification. Tapping it opens the store page.
///
/// Notification delivery is on by default, but Android 13+ and iOS only allow
/// it after the user taps "Allow" on the OS permission prompt, and no app can
/// grant that itself. The prompt is shown once, right after the "what's new"
/// popup ([shouldAskForPermission] / [askForPermissionOnce]) — never while the
/// update check runs at launch.
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

  static const String _permissionAskedPrefKey = 'updateNotifyPermissionAsked';

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

  /// Whether to show the one-time OS permission prompt: delivery is set to
  /// notification (the default), the prompt hasn't been shown for this yet, and
  /// the OS doesn't already allow notifications (Android 12 and older, or
  /// granted earlier for «صفحة اليوم» — then there's nothing to ask).
  Future<bool> shouldAskForPermission() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    if (AppUpdateService.instance.notifyMode.value !=
        UpdateNotifyMode.notification) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_permissionAskedPrefKey) ?? false) return false;
    if (await NotificationCenter.instance.areNotificationsEnabled()) {
      await prefs.setBool(_permissionAskedPrefKey, true);
      return false;
    }
    return true;
  }

  /// Shows the OS permission prompt and remembers it was shown. Denying it
  /// switches delivery to in-app only, so the Settings switch reflects what
  /// will actually happen; turning the switch back on asks again.
  Future<void> askForPermissionOnce() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionAskedPrefKey, true);
    if (!await requestPermission()) {
      await AppUpdateService.instance.setNotifyMode(UpdateNotifyMode.inApp);
    }
  }

  /// Shows the "update available" notification. Does nothing if the OS doesn't
  /// allow notifications — it never prompts, since this runs at launch.
  /// [storeUrl] is opened when the notification is tapped.
  Future<void> showUpdateNotification({
    required String title,
    required String body,
    required String storeUrl,
  }) async {
    if (!await NotificationCenter.instance.areNotificationsEnabled()) return;
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

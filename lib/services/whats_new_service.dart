import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_service.dart';

/// A one-time "what's new" popup for changes bundled in the app that's already
/// installed — as opposed to [AppUpdateService], which checks a remote
/// manifest for a *newer* release the user hasn't installed yet.
///
/// Shown once per build via [AppUpdateInfo.mandatory]-free semantics: it never
/// blocks and is skipped entirely once the current build has been marked seen.
class WhatsNewService {
  WhatsNewService._();
  static final WhatsNewService instance = WhatsNewService._();

  static const String _lastSeenBuildPrefKey = 'whatsNewLastSeenBuild';

  /// Changes shipped in the current installed build. Update this list (and
  /// nothing else) on each release that should show a "what's new" popup;
  /// leave it empty to skip the popup entirely for a release.
  static const List<String> currentReleaseChanges = [
    'إضافة تذكير «سورة الكهف»: تنبيه كل يوم جمعة الساعة العاشرة صباحًا بتوقيت جهازك، وبالضغط عليه تُفتح السورة مباشرة. مفعّل تلقائيًا، ويمكنك تغيير وقته أو إيقافه من الإعدادات.',
    'إمكانية وصول إشعارات من التطبيق بالتحديثات والإضافات الجديدة مثل التلاوات والتفاسير، ويمكنك إيقافها من إعدادات الإشعارات في جهازك.',
    'أصبح التنبيه بتوفّر تحديث جديد يصلك كإشعار افتراضيًا، ويمكنك تغيير ذلك من الإعدادات.',
  ];

  /// Whether the popup should be shown for the currently installed build:
  /// there are changes to show, and this exact build hasn't been seen yet.
  Future<bool> shouldShow() async {
    if (currentReleaseChanges.isEmpty) return false;
    final build = AppUpdateService.instance.currentBuild;
    if (build <= 0) return false;
    final prefs = await SharedPreferences.getInstance();
    final lastSeenBuild = prefs.getInt(_lastSeenBuildPrefKey) ?? 0;
    return lastSeenBuild < build;
  }

  /// Records the current build as seen, so the popup isn't repeated.
  Future<void> markSeen() async {
    final build = AppUpdateService.instance.currentBuild;
    if (build <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSeenBuildPrefKey, build);
  }
}

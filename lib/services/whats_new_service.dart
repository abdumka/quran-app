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

  static const String lastSeenBuildPrefKey = 'whatsNewLastSeenBuild';

  /// Whether the popup ends in «أرني أين», the walkthrough of Settings. Off
  /// since the list was started fresh with تلقين (owner, 2026-11-11): the
  /// popup just says «حسنًا». The tour itself is kept for a release that
  /// wants it again.
  static const bool offerSettingsTour = false;

  /// The cards of the What's New deck, in order (owner, 2026-11-19: تلقين,
  /// فيديو الآية, الأذكار, أحكام وأصول الرواية, Android Auto for everyone).
  /// Empty falls back to the plain list popup. [currentReleaseChanges]
  /// stays the full list, behind the deck's «كل التغييرات».
  static const List<String> tourCards = [
    'talqeen',
    'video',
    'athkar',
    'usul',
    'auto',
  ];

  /// Changes shipped in the current installed build. Update this list (and
  /// nothing else) on each release that should show a "what's new" popup;
  /// leave it empty to skip the popup entirely for a release.
  static const List<String> currentReleaseChanges = [
    'جديد «أحكام وأصول الرواية» في القائمة الجانبية: شرح ميسّر لأحكام التلاوة وأصول رواية قالون.',
    'جديد «مشاركة الآية فيديو قصيرًا بخلفية»: تلاوة القارئ الذي تختاره، والآيات واسم السورة بخط المصحف نفسه، على خلفية متحركة من المساجد والمعالم أو من الطبيعة.',
    'جديد «الأذكار» في القائمة الجانبية: أذكار الصباح والمساء وبعد الصلاة والنوم والاستيقاظ وغيرها.',
    'جديد «تلقين - استمع ثم ردّد»: يتلو القارئ الآية ثم يسكت لتردّدها بعده.',
    'جديد «لا تهجر القرآن»: تنبيه لطيف إذا لم تفتح المصحف 5 أيام.',
    'جديد «المصحف الجامع في السيارة»: يعمل التطبيق مباشرة على السيارات التي تدعم Android Auto.',
    'شكل جديد للتطبيق: قائمة جانبية، و7 ألوان تختار منها في «إعدادات العرض».',
  ];

  /// Whether the popup should be shown for the currently installed build:
  /// there are changes to show, and this exact build hasn't been seen yet.
  Future<bool> shouldShow() async {
    if (currentReleaseChanges.isEmpty) return false;
    final build = AppUpdateService.instance.currentBuild;
    if (build <= 0) return false;
    final prefs = await SharedPreferences.getInstance();
    final lastSeenBuild = prefs.getInt(lastSeenBuildPrefKey) ?? 0;
    return lastSeenBuild < build;
  }

  /// Records the current build as seen, so the popup isn't repeated.
  Future<void> markSeen() async {
    final build = AppUpdateService.instance.currentBuild;
    if (build <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(lastSeenBuildPrefKey, build);
  }
}

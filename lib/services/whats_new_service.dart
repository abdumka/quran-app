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
    'جديد: «تنزيلات ومتشابهات». تُلوَّن كلماتها على الصفحة (من «أدوات الحفظ والمراجعة» في الإعدادات)، وبالضغط المطوّل على أي آية واختيار «تنزيلات ومتشابهات» ترى كل مواضعها وعددها وبيت الدنفاسي فيها، وتنتقل إلى أي موضع بلمسة ثم تعود.',
    'تلاوة من أي آية: اضغط مطوّلًا على الآية واختر «تلاوة». تختار القارئ من السطر نفسه، و«متابعة» لتستمر التلاوة بعدها أو «آية فقط» لتسمعها وحدها، ويتذكّر التطبيق اختيارك. والآيات التي يصلها القارئ في نفَس واحد تُتلى معًا.',
    'ثلاثة قرّاء جدد: نورالدين المسلاتي، وأحمد خضر الطرابلسي، ومحمد خليل الزروق. وقوائم اختيار القارئ صارت قصيرة تمرّرها مهما كثر القرّاء.',
    'التسميع: خيار جديد في إعدادات التسميع بين «دقة أعلى» و«استجابة أسرع»، تظهر فيه الكلمات أسرع قليلًا مع تنبيهات خاطئة أكثر قليلًا.',
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

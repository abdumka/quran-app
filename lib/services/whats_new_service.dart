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
    'طريقة جديدة للتفسير: اضغط مطوّلًا على أي آية لفتح التفسير).',
    'شرح «التسميع» يظهر عند أول استخدام، ويمكنك فتحه في أي وقت من «أدوات الحفظ» ← «شرح التسميع»: كيف يعمل، وما يفعله كل زر في شريط التسميع.',
    'شريط التسميع أصبح متحركًا: اضغط عليه مطوّلًا واسحبه إلى حيث لا يحجب النص، ويحفظ التطبيق مكانه.',
    'تنبيهات التسميع صارت اثنين: تنبيه عند الخطأ، وتنبيه خفيف عند تصويبه، ليمكنك التسميع دون النظر إلى الشاشة. لكلٍّ منهما: اهتزاز، أو صوت، أو كلاهما، أو لا شيء، من «أدوات الحفظ» ← «تنبيهات».',
    'التسميع لا يعدّ البسملة في أول السورة خطأ، ويلتقط الكلمة الزائدة بين كلمتين، وزر «أعد الآية» في أول صفحة جديدة يعيدك إلى آخر آية في الصفحة السابقة.',
    'تقارير التسميع أوضح: لا تُعرض إلا الكلمات الحقيقية التي سُمعت مكان الكلمة الصحيحة، ولا تظهر رموز غير مقروءة.',
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

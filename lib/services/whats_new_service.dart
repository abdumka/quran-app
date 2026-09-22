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
    'إضافة «التسميع» في قائمة «أدوات الحفظ»: تُغطّى آيات الصفحة وتقرأ من حفظك، فتنكشف كل آية عند إتمامها مع تنبيه عند الخطأ أو التجاوز، ويُحفظ لكل صفحة تقرير بأخطائها. يُنزَّل نموذج التعرّف على التلاوة (نحو 70 ميغابايت) مرة واحدة عند أول استخدام، ثم يعمل التسميع على جهازك دون إنترنت.',
    'تظليل الآية التي تُتلى على الصفحة أثناء التلاوة، ومع القرّاء الذين يصلون عدة آيات في نَفَس واحد تُظلَّل الآيات الموصولة معًا. يمكنك إيقافه من «خيارات التلاوة» ← «تظليل الآية المتلوّة».',
    'خيارات جديدة في تكرار المقطع: «تكرار كل آية داخل المقطع» عدة مرات قبل الانتقال إلى التي تليها، واختيار ما يحدث «بعد انتهاء المقطع»: متابعة التلاوة أو التوقف عند أوله.',
    'إضافة تذكير «سورة الكهف»: تنبيه كل يوم جمعة، وبالضغط عليه تُفتح السورة مباشرة. يمكنك تغيير الوقت من الإعدادات.',
    'إمكانية وصول إشعارات من التطبيق بالتحديثات والإضافات الجديدة مثل التلاوات والتفاسير، ويمكنك إيقافها.',
    'شريط التلاوة يختفي تلقائيًا بعد 15 ثانية من عدم الاستخدام كي لا يغطي الصفحة، وأي لمسة تُظهره من جديد. يمكنك تغيير المدة أو إيقاف الخاصية من الإعدادات ← إعدادات متقدمة.',
    'في عرض الصفحتين أصبح بإمكانك تشغيل التلاوة واختيار الآيات من الصفحة اليسرى أيضًا.',
    'إصلاح انقطاع الصوت بين الآيات في تلاوتَي الشيخ عبدالحميد القريو والشيخ محمد أبوسنينة: كان الصوت ينقطع نحو نصف ثانية قبل كل آية، وأصبح الانتقال متصلًا.',
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

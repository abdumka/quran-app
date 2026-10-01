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
    'جديد في أدوات الحفظ: «اختبار الحفظ» يسألك من أخطائك في التسميع أو عشوائيًا، في نطاق تختاره (المصحف كله، سور، أحزاب، أثمان، صفحات)، ويبيّن لك على الصفحة من أين تبدأ. و«اختبار ذاتي» يخفي آيات الصفحة لتقرأ في نفسك وتكشف كلمةً أو آية وتحكم على نفسك، دون ميكروفون. وإعدادات التنبيه صارت خلف زر الترس.',
    'التسميع: تنتقل الصفحة حين تتابع القراءة، ولا تُحسب البسملة بين السورتين خطأً، ويمكن البدء من أي آية في الصفحة. وعلى الآيفون تعمل تنبيهات الخطأ أثناء التسجيل.',
    'الهوامش صارت ضمن التطبيق، فلا حاجة إلى تنزيلها، والتبديل بينها وبين العرض العادي فوري. وتُحذف الملفات التي نُزّلت سابقًا تلقائيًا لتوفير المساحة.',
    'جديد: «ظلّ الكعب»، ظلّ خفيف على طرف الصفحة المجاور للكعب، يبيّن الصفحة اليمنى من اليسرى كما في المصحف المفتوح.',
    'البحث: عند فتح نتيجة تُظلَّل الآية في الصفحة لتجدها مباشرة.',
    'الفهرس: كل حزب في «الأحزاب والأثمان» يذكر السورة والصفحة التي يبدأ منها.',
    'إصلاح شكل التنوين والألف المقصورة (مثل «عيسى» و«على») في نص الآيات في البحث والتفسير والتسميع.',
    'التلاوة دون إنترنت: تتوقف مع تنبيه بدل التنقل السريع بين الآيات والصفحات، وزر التشغيل بعدها يعيد الآية نفسها.',
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

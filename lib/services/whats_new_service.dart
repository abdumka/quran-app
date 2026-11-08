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
    'بشرى لأهل القرآن، ولأول مرة في المصحف الجامع: «تنزيلات ومتشابهات». تُلوَّن كلمات التنزيلات على صفحات المصحف بحسب عدد مواضعها، فيتميّز المتشابه ويثبت الحفظ بإذن الله. وهي مفعّلة، ويمكنك إيقافها من «تلوين التنزيلات والمتشابهات» في «أدوات الحفظ والمراجعة» بالإعدادات. واضغط مرتين على أي آية واختر «تنزيلات ومتشابهات» لترى كل مواضعها وعددها وبيت الدنفاسي فيها، وتنسخ ما شئت منها، وتكتب ملاحظاتك عليها، وتنتقل إلى أي موضع بلمسة ثم تعود.',
    'تلاوة متصلة: عند قرّاء الملف الواحد (الزروق والطرابلسي والمسلاتي ورجب والقريو وأبوسنينة والنايحي) تمضي التلاوة من الآية إلى التي بعدها دون توقّف ولا صمت بينهما.',
    'ما تسمعه يبقى على هاتفك: كل جزء من السورة يصل إليك يُحفظ، فلا يُحمَّل مرة أخرى، ويُتلى بلا إنترنت لاحقًا. وإذا اكتملت السورة ظهرت ضمن «تحميل الصوتيات».',
    'انقطاع الإنترنت أثناء التلاوة يوقفها عند آيتها مع تنبيه، وتستأنف من موضعها بالضغط على تشغيل.',
    'الاختبار الذاتي: إذا كشفت آخر كلمة أو آية في الصفحة بقيت الصفحة أمامك لتقرأها. اقلبها لتتابع، أو اضغط «كلمة» أو «الآية» مرة أخرى فتنقلب وينكشف أول الصفحة التالية.',
    'التسميع أدقّ وأقل توقّفًا: قبل أن ينبّهك إلى خطأ يعيد المصحف الاستماع إلى آخر ثوانٍ من قراءتك مرة ثانية بأذن جديدة، فإن سمع الكلمة في موضعها تركك تواصل. على نحو 70 صفحة من التسميع الحقيقي قلّت التوقفات الخاطئة بنحو 11 إلى 14 بالمائة دون أن يفوته خطأ حقيقي، وتظهر الكلمات بالسرعة نفسها (نصف ثانية تقريبًا). وصار للتسميع سلوك واحد مضبوط على الأفضل، فأُزيلت خيارات «دقة أعلى» و«استجابة أسرع».',
    'إصلاحات في التسميع: لم يعد يُحسب ما قرأته قبل الضغط على «كلمة» أو «أعد الآية» على الكلمة التالية، وصُحّحت 7 كلمات كان تنوينها مكتوبًا على رواية حفص فتوقف عندها القارئ بقالون (منها «كافرةٌ ترونهم» و«مصيبةٍ بما»).',
    'التسميع أعدل في الحساب: الكلمة الوردية التي يتوقف عندها الميكروفون صارت تنبيهًا لا يُحسب خطأً، فالنموذج قد لا يلتقط كلمة قرأتها صحيحة. الخطأ هو ما كشفته بزر «كلمة» أو «الآية» أو تخطّيته، أو ما حكمت عليه بنفسك في الاختبار الذاتي، وتُحسب الإحصاءات السابقة بهذا من جديد.',
    'مسح الإحصاءات: في «الإحصاءات» اضغط زر الحذف ثم «مسح» لتمسح آخر 7 أيام أو 30 يومًا أو أي عدد من الأيام أو الكل، ولك أن تتراجع بعدها مباشرة. وفي «تقارير التسميع والأخطاء» احذف الأخطاء القديمة دفعة واحدة، أو اسحب كلمة جانبًا لحذفها وحدها.',
    'شريط التسميع لا يغطي سطرك: إذا وصلت قراءتك إليه ارتفع مرة واحدة فوق السطر الذي تقرؤه، وبقي هناك حتى آخر الصفحة، ثم يعود إلى مكانه.',
    'إصلاحات: إنهاء التسميع بعد قلب الصفحة لم يعد يُبقي الآيات مخفية، وقلب الصفحات بسرعة في الاختبار الذاتي لم يعد يُعلّق رسالة «جارٍ تجهيز التسميع»، والرجوع أثناء تحميل التفسير لا يغلق المصحف، وإيقاف «صفحة اليوم» يلغي تذكيراتها كلها.',
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

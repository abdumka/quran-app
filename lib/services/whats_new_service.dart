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

  /// Whether the popup ends in «أرني أين», the walkthrough of Settings. Off
  /// since the list was started fresh with تلقين (owner, 2026-11-11): the
  /// popup just says «حسنًا». The tour itself is kept for a release that
  /// wants it again.
  static const bool offerSettingsTour = false;

  /// Changes shipped in the current installed build. Update this list (and
  /// nothing else) on each release that should show a "what's new" popup;
  /// leave it empty to skip the popup entirely for a release.
  static const List<String> currentReleaseChanges = [
    'جديد «مشاركة الآية»: اضغط مطوّلًا على أي آية ثم زر المشاركة بجانب اسمها، وشارك نصها، أو أنشئ «فيديو الآية»: تلاوة القارئ الذي تختاره، والآيات واسم السورة بخط المصحف نفسه، على خلفية متحركة من المساجد والمعالم أو من الطبيعة، طوليًا أو بشكل المنشور أو مربعًا أو عرضيًا، واسم القارئ تحت اسم السورة بخط وحجم تختارهما، مع صدى أو قاعة إن شئت. يُنشأ الفيديو على هاتفك، أندرويد كان أو آيفون، ويُعرض فور اكتماله ويُحفظ في معرض الصور، ولا تُنزَّل إلا الخلفية التي تختارها.',
    'جديد «الأذكار» في القائمة الجانبية: أذكار الصباح والمساء وبعد الصلاة والنوم والاستيقاظ وغيرها، مع عدّاد لكل ذكر ومفضّلة تجمع ما تحب. استمع إليها بصوت القارئ الذي تختاره، فيتكرر الذكر بعدد مرات قوله، والآيات فيها برواية قالون.',
    'جديد «أحكام وأصول الرواية» في القائمة الجانبية: شرح ميسّر لأحكام التلاوة وأصول رواية قالون والكلمات المتكررة، مع ذكر المصادر. لكل حكم أمثلة من المصحف، اضغط المثال لترى موضعه في صفحته.',
    'جديد «خلافات القراء»: اضغط مطوّلًا على أي آية واختر «خلافات القراء» لترى كيف قرأ القراء العشرة ورواتهم كلماتها، وقراءة قالون أولًا في كل كلمة.',
    'جديد «تلقين - استمع ثم ردّد»: يتلو القارئ الآية ثم يسكت لتردّدها بعده، ثم ينتقل إلى ما بعدها. تختار مدة دورك: أقصر من القارئ أو مثله أو أطول. يعمل مع تكرار الآية والصفحة والثمن والمقطع. فعّله من «خيارات التلاوة» في شريط التلاوة، ويبقى مفعّلًا حتى تلغيه.',
    'جديد «المصحف الجامع في السيارة» (Android Auto): اختر السورة أو الجزء أو القارئ من شاشة السيارة وابدأ من أي آية، مع رجوع وتقديم 10 ثوانٍ، وتكرار الآية أو السورة كلها، ومؤقت للإيقاف بعد السورة أو بعد 15 أو 30 أو 60 دقيقة، وتغيير السرعة. ويمكنك أن تقول لمساعد Google: «شغّل سورة الكهف».',
    'تكرار المقطع بأي عدد: في «تكرار مقطع» اسحب الرقم إلى أعلى أو إلى أسفل، أو اضغطه لتكتب العدد، من 2 إلى 99، لتكرار المقطع كله ولتكرار كل آية داخله.',
    'الآية الممتدة بين صفحتين: عند تكرارها أو في دورك في التلقين تعود الصفحة إلى أول الآية، ثم تُقلب عند الكلمة نفسها التي يقلب عندها القارئ.',
    'الآية المتلوّة تبقى أمامك: إذا أدرت الهاتف أفقيًا أو كبّرت الصفحة تتحرك الصفحة مع التلاوة حتى لا تغيب الآية عن الشاشة.',
    'جديد «قيّم التطبيق» في القائمة الجانبية: ضغطة واحدة تفتح صفحة التطبيق في المتجر لتضع تقييمك.',
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

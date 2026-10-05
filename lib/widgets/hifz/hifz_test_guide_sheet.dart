import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hifz_palette.dart';

const String _micSeenPref = 'hifz_test_guide_seen';
const String _silentSeenPref = 'hifz_silent_test_guide_seen';

/// Shows the guide of a test the first time that test is opened. Returns
/// once the sheet is closed (at once when it was seen before).
Future<void> showHifzTestGuideOnce(BuildContext context, {required bool silent}) async {
  final pref = silent ? _silentSeenPref : _micSeenPref;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(pref) ?? false) return;
    await prefs.setBool(pref, true);
  } catch (_) {}
  if (!context.mounted) return;
  await showHifzTestGuide(context, silent: silent);
}

/// The guide of a test: what it is, then its steps, each with a picture
/// drawn from the same shapes the real screens use.
Future<void> showHifzTestGuide(BuildContext context, {required bool silent}) {
  final p = HifzPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _Guide(silent: silent),
  );
}

class _Guide extends StatelessWidget {
  const _Guide({required this.silent});
  final bool silent;

  static const Color _gold = Color(0xFF8A6D2F);
  static const Color _paper = Color(0xFFFCFCD8);
  static const Color _ink = Color(0xFF2B2B2B);
  static const Color _good = Color(0xFF2E7D32);
  static const Color _bad = Color(0xFFB3261E);

  /// A numbered step: its picture on top, the words under it.
  Widget _step(HifzPalette p, int n, String title, String what, Widget picture) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: p.title, shape: BoxShape.circle),
                  child: Text(
                    '$n',
                    style: TextStyle(color: p.onTitle, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: p.title,
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.raised,
                  border: Border.all(color: p.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: picture,
              ),
            ),
            const SizedBox(height: 6),
            Text(what, style: TextStyle(color: p.text, fontSize: 14, height: 1.6)),
          ],
        ),
      );

  // ---- pictures -------------------------------------------------------

  Widget _chip(String label, {bool on = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: on ? _gold : const Color(0xFFF8F1DE),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2D2A5)),
        ),
        child: Text(
          label,
          style: TextStyle(color: on ? Colors.white : _ink, fontSize: 11),
        ),
      );

  /// The setup page in miniature: the range chips and a stepper.
  Widget _setupPicture() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('النطاق', style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _chip('المصحف كله'),
              _chip('الصفحة الحالية', on: true),
              _chip('سور'),
              _chip('أحزاب'),
              _chip('أثمان'),
              _chip('صفحات'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text('عدد الأسئلة', style: TextStyle(color: _ink, fontSize: 12)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F1DE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2D2A5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16, color: _gold),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('5 أسئلة', style: TextStyle(color: _ink, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    Icon(Icons.remove_rounded, size: 16, color: _gold),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(20)),
            child: const Text(
              'ابدأ الاختبار',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );

  /// A covered page: two visible lines, then paper-coloured blocks with
  /// the ayah markers between them, and the cue card.
  Widget _pagePicture() {
    Widget line({bool covered = false, double width = double.infinity}) => Container(
          height: 14,
          width: width,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: covered ? _paper : null,
            border: covered ? Border.all(color: const Color(0xFFE6E2B8)) : null,
            borderRadius: BorderRadius.circular(3),
          ),
          child: covered
              ? null
              : Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    for (final w in [34.0, 22.0, 40.0, 18.0, 30.0])
                      Container(
                        width: w,
                        height: 7,
                        margin: const EdgeInsetsDirectional.only(end: 6),
                        decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(3)),
                      ),
                  ],
                ),
        );
    Widget marker(String n) => Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFC9A227))),
          child: Text(n, style: const TextStyle(fontSize: 7, color: _ink)),
        );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: _paper, borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(),
          Row(textDirection: TextDirection.rtl, children: [Expanded(child: line()), marker('4')]),
          Row(textDirection: TextDirection.rtl, children: [Expanded(child: line(covered: true)), marker('5')]),
          line(covered: true),
          Row(textDirection: TextDirection.rtl, children: [Expanded(child: line(covered: true)), marker('6')]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xE6FFFDF3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _gold.withValues(alpha: 0.4)),
            ),
            child: const Text(
              'اختبار 1 / 5\nسورة البقرة، من الآية 5 — 3 آيات (5–7)\nبعد قوله تعالى: ﴿… وأولئك هم المفلحون﴾',
              textAlign: TextAlign.right,
              style: TextStyle(color: _ink, fontSize: 10, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  /// The session bar, with a number on every button.
  Widget _barPicture(HifzPalette p) {
    final items = silent
        ? const [
            (Icons.lightbulb_outline_rounded, 'كلمة'),
            (Icons.visibility_rounded, 'الآية'),
            (Icons.replay_circle_filled_rounded, 'أعد الآية'),
            (Icons.restart_alt_rounded, 'الصفحة'),
            (Icons.close_rounded, 'إنهاء'),
          ]
        : const [
            (Icons.lightbulb_outline_rounded, 'كلمة'),
            (Icons.visibility_rounded, 'الآية'),
            (Icons.replay_circle_filled_rounded, 'أعد الآية'),
            (Icons.skip_next_rounded, 'تخطَّ'),
            (Icons.restart_alt_rounded, 'الصفحة'),
            (Icons.close_rounded, 'إنهاء'),
          ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6FFFDF3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withValues(alpha: 0.4)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.rtl,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: silent
                  ? const Icon(Icons.visibility_off_rounded, size: 16, color: _gold)
                  : Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(color: _good, shape: BoxShape.circle),
                    ),
            ),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: p.title, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: TextStyle(color: p.onTitle, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    Icon(items[i].$1, size: 20, color: _gold),
                    Text(items[i].$2, style: const TextStyle(color: _gold, fontSize: 8, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// What comes after a question: the self-verdict rows, or the result.
  Widget _afterPicture() {
    if (silent) {
      Widget mark(String t, Color c, bool on) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            margin: const EdgeInsetsDirectional.only(start: 4),
            decoration: BoxDecoration(
              color: on ? c : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: on ? c : const Color(0xFFE2D2A5)),
            ),
            child: Text(t, style: TextStyle(color: on ? Colors.white : _ink, fontSize: 10)),
          );
      Widget row(String ayah, bool wrong) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(ayah, style: TextStyle(color: wrong ? _bad : _ink, fontSize: 12))),
                mark('صحيح', _good, !wrong),
                mark('خطأ', _bad, wrong),
              ],
            ),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('كيف قرأتها؟', style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.bold)),
          row('الآية 5', false),
          row('الآية 6', true),
          row('الآية 7', false),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(8)),
            child: const Text('السؤال التالي', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: _bad, size: 16),
            SizedBox(width: 4),
            Text('فيها ملاحظات', style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        const Text('• كلمة أخرى: «يعلمون» — الآية 6 — قرأت «تعلمون»', style: TextStyle(color: _ink, fontSize: 10.5)),
        const Text('• كُشفت بطلب: «الذين» — الآية 7', style: TextStyle(color: _ink, fontSize: 10.5)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(8)),
                child: const Text('السؤال التالي', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: _gold)),
                child: const Text('إنهاء الاختبار', textAlign: TextAlign.center, style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    return SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        silent ? 'كيف يعمل الاختبار الذاتي' : 'كيف يعمل اختبار الحفظ',
                        style: TextStyle(color: p.title, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        silent
                            ? 'آيات الصفحة مخفية. تقرأ من حفظك في نفسك، تكشف لتتحقق، وتحكم على نفسك. لا ميكروفون ولا تسجيل.'
                            : 'التطبيق يختار لك مواضع من المصحف، ويخفي آياتها، وتقرأ من حفظك عبر الميكروفون؛ ما تقرؤه صحيحًا ينكشف، والخطأ يوقفك عنده.',
                        style: TextStyle(color: p.sub, fontSize: 13.5, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                      _step(
                        p,
                        1,
                        'اختر النطاق وعدد الأسئلة',
                        'النطاق: الصفحة التي أنت فيها، أو سور أو أحزاب أو أثمان أو صفحات. '
                            'ومع الأثمان كل ثمن سؤال كامل. فعّل «اختبار مفتوح» ليستمر صفحة بعد صفحة حتى تُنهيه. '
                            'ثم اضغط «ابدأ الاختبار».',
                        _setupPicture(),
                      ),
                      _step(
                        p,
                        2,
                        'اقرأ من موضع البداية',
                        silent
                            ? 'ينقلك كل سؤال إلى صفحته والآيات مخفية. البطاقة تقول من أين تبدأ وتذكّرك بآخر الآية التي قبلها، '
                                'فإن كان السؤال في وسط الصفحة فالآيات التي قبله ظاهرة. اقرأ الآيات في نفسك.'
                            : 'ينقلك كل سؤال إلى صفحته والآيات مخفية. البطاقة تقول من أين تبدأ وتذكّرك بآخر الآية التي قبلها. '
                                'اقرأ بصوت واضح قريبًا من الميكروفون؛ كل كلمة تقرؤها صحيحة تنكشف، وعند الخطأ يتوقف التطبيق عند الكلمة (تحمرّ) حتى تعيدها.',
                        _pagePicture(),
                      ),
                      _step(
                        p,
                        3,
                        'شريط الأزرار',
                        silent
                            ? '1 «كلمة»: تكشف الكلمة التالية وحدها لتتحقق منها. 2 «الآية»: تكشف الآية كلها. '
                                '3 «أعد الآية»: تخفيها من جديد لتعيد قراءتها. 4 «الصفحة»: يبدأ السؤال من أوله. 5 «إنهاء»: ينهي الاختبار ويعرض النتيجة. '
                                'الكشف هنا للتحقق فقط ولا يُحسب خطأً.'
                            : '1 «كلمة»: تكشف الكلمة التي توقفت عندها (تُحسب ملاحظة). 2 «الآية»: تكشف الآية كلها وتنتقل. '
                                '3 «أعد الآية»: تخفيها لتقرأها من أولها. 4 «تخطَّ»: تتجاوز الآية. 5 «الصفحة»: يبدأ السؤال من أوله. 6 «إنهاء»: ينهي الاختبار ويعرض النتيجة. '
                                'النقطة الخضراء تعني أن التطبيق يسمعك.',
                        _barPicture(p),
                      ),
                      _step(
                        p,
                        4,
                        silent ? 'احكم على نفسك' : 'نتيجة السؤال',
                        silent
                            ? 'بعد آخر آية في السؤال تظهر آياته واحدةً واحدة؛ علّم ما أخطأت فيه بـ«خطأ» واترك الباقي «صحيح»، ثم «السؤال التالي». '
                                'ما علّمته خطأً يُحفظ لتُختبر فيه لاحقًا.'
                            : 'بعد آخر آية في السؤال تظهر ملاحظاته: الكلمة، ونوع الخطأ، وما قرأته. ثم «السؤال التالي». '
                                'الأخطاء تُحفظ في «تقارير التسميع والأخطاء» وتُستعمل في «من أخطائي».',
                        _afterPicture(),
                      ),
                      Text(
                        'في النهاية تظهر النتيجة وتُحفظ في «الإحصاءات». يمكنك فتح هذا الشرح من زر «؟» في صفحة الإعداد.',
                        style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.title,
                      foregroundColor: p.onTitle,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'فهمت',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

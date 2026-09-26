import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hifz_palette.dart';

const String _seenPref = 'tasmee_guide_seen';

/// Shows the Tasmee guide the first time the feature is opened. Returns
/// once the sheet is closed (or at once when it was seen before).
Future<void> showTasmeeGuideOnce(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_seenPref) ?? false) return;
  await prefs.setBool(_seenPref, true);
  if (!context.mounted) return;
  await showTasmeeGuide(context);
}

/// One button of the bar as the guide draws it.
class _Item {
  const _Item(this.icon, this.label, this.what);
  final IconData? icon; // null = the listening dot
  final String label;
  final String what;
}

const List<_Item> _items = [
  _Item(
    null,
    'النقطة',
    'خضراء: التطبيق يسمعك، وتكبر مع صوتك. حمراء: خطأ ينتظر التصويب.',
  ),
  _Item(
    Icons.lightbulb_outline_rounded,
    'كلمة',
    'تكشف الكلمة التالية (أو الكلمة المتوقَّف عندها) وتُحسب ملاحظة.',
  ),
  _Item(
    Icons.visibility_rounded,
    'الآية',
    'تكشف الآية الحالية كاملة وتنتقل بك إلى التي بعدها.',
  ),
  _Item(
    Icons.replay_circle_filled_rounded,
    'أعد الآية',
    'تُخفي الآية الحالية من جديد لتقرأها من أولها.',
  ),
  _Item(
    Icons.skip_next_rounded,
    'تخطَّ',
    'تتجاوز الآية الحالية إلى التي بعدها.',
  ),
  _Item(Icons.restart_alt_rounded, 'الصفحة', 'تبدأ الصفحة من أولها.'),
  _Item(Icons.close_rounded, 'إنهاء', 'ينهي التسميع ويعرض تقرير الجلسة.'),
  _Item(
    Icons.keyboard_arrow_down_rounded,
    'إخفاء',
    'يطوي الشريط إلى نقطة صغيرة؛ اضغطها ليعود.',
  ),
];

/// The guide: what Tasmee does, a picture of its bar with a number on
/// every button, and what each button does.
Future<void> showTasmeeGuide(BuildContext context) {
  final p = HifzPalette.of(context);
  const barGold = Color(0xFF8A6D2F);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final scroll = ScrollController();
      Widget para(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(color: p.text, fontSize: 14.5, height: 1.6),
        ),
      );
      Widget badge(int n) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.title, shape: BoxShape.circle),
        child: Text(
          '$n',
          style: TextStyle(
            color: p.onTitle,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      // The bar as it looks on the page: cream, gold icons, tiny labels.
      Widget barPicture() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE6FFFDF3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: barGold.withValues(alpha: 0.4)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.rtl,
            children: [
              for (var i = 0; i < _items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      badge(i + 1),
                      Container(width: 1.5, height: 8, color: p.title),
                      if (_items[i].icon == null)
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      else
                        Icon(_items[i].icon, size: 22, color: barGold),
                      Text(
                        _items[i].label,
                        style: const TextStyle(
                          color: barGold,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
      return SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
            ),
            // The guide is longer than most screens: a scrollbar that is
            // always visible says so, instead of leaving the end unseen.
            child: RawScrollbar(
              controller: scroll,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 7,
              radius: const Radius.circular(4),
              thumbColor: p.title,
              trackColor: p.title.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'كيف يعمل التسميع',
                      style: TextStyle(
                        color: p.title,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Tajawal',
                      ),
                    ),
                    const SizedBox(height: 10),
                    para(
                      'تُغطَّى كلمات الصفحة، فتقرأ من حفظك بصوت واضح قريبًا من '
                      'الميكروفون، وكل كلمة تُقرأ صحيحة تنكشف. يمكنك البدء من أي '
                      'آية في الصفحة.',
                    ),
                    para(
                      'عند الخطأ يتوقف الكشف عند الكلمة وتُظلَّل بالأحمر مع اهتزاز؛ '
                      'أعدها حتى تُقبل، أو استعن بأزرار الشريط. وعند اكتمال الصفحة '
                      'ينتقل التسميع إلى الصفحة التالية من نفسه.',
                    ),
                    Text(
                      'شريط التسميع',
                      style: TextStyle(
                        color: p.title,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Tajawal',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(child: barPicture()),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _items.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            badge(i + 1),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    color: p.text,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '${_items[i].label}: ',
                                      style: TextStyle(
                                        color: p.title,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(text: _items[i].what),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    para(
                      'اضغط مطوّلًا على الشريط لتحريكه إلى حيث لا يحجب النص. '
                      'وتجد التنبيهات (اهتزاز أو صوت عند الخطأ وعند التصويب) '
                      'وتقارير الجلسات في «أدوات الحفظ».',
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: p.title,
                          foregroundColor: p.onTitle,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text(
                          'فهمت',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

import 'package:flutter/material.dart';

/// The "أدوات الحفظ" sheet opened from the bottom action bar: one place for
/// the memorization tools -- the recitation test (التسميع) and the page
/// concealment lens (وضع الحفظ).
Future<void> showHifzToolsSheet(
  BuildContext context, {
  required bool tasmeeActive,
  required bool hifzModeActive,
  required VoidCallback onTasmee,
  required VoidCallback onHifzMode,
  required VoidCallback onLogs,
}) {
  const gold = Color(0xFFD2B97E);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      Widget tile({
        required IconData icon,
        required String title,
        required String subtitle,
        required bool active,
        required VoidCallback onTap,
      }) {
        return ListTile(
          leading: Icon(icon, color: gold, size: 28),
          title: Text(
            title,
            style: const TextStyle(
              color: gold,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          trailing: active
              ? const Icon(Icons.stop_circle_outlined, color: gold)
              : const Icon(Icons.chevron_left_rounded, color: gold),
          onTap: () {
            Navigator.of(sheetContext).pop();
            onTap();
          },
        );
      }

      return SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'أدوات الحفظ',
                  style: TextStyle(
                    color: gold,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ),
              tile(
                icon: Icons.mic_rounded,
                title: tasmeeActive ? 'إنهاء التسميع' : 'التسميع',
                subtitle: tasmeeActive
                    ? 'الجلسة الحالية جارية على هذه الصفحة.'
                    : 'تُغطّى آيات الصفحة الحالية، واقرأ من حفظك؛ تنكشف كل '
                        'آية عند إتمامها، مع تنبيه عند الخطأ أو التجاوز.',
                active: tasmeeActive,
                onTap: onTasmee,
              ),
              tile(
                icon: Icons.blur_on_rounded,
                title: hifzModeActive ? 'إيقاف وضع الحفظ' : 'وضع الحفظ',
                subtitle: 'تُخفى الصفحة كلها، واضغط مطوّلًا لكشف ما تحت '
                    'إصبعك للمراجعة الذاتية.',
                active: hifzModeActive,
                onTap: onHifzMode,
              ),
              tile(
                icon: Icons.receipt_long_rounded,
                title: 'سجلات التسميع',
                subtitle: 'كل جلسة تُسجَّل تلقائيًا (الصوت وسجل القرارات). '
                    'شارك السجلات للتحليل، أو احذفها، أو حدّد عدد الجلسات المحفوظة.',
                active: false,
                onTap: onLogs,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

import 'package:flutter/material.dart';

import '../../services/tasmee_report_store.dart';

/// «تقوية الحفظ» (the strengthening drills) is hidden for now: a drill can
/// open on a fully covered page with nothing to start from. Mistakes are
/// still collected meanwhile; set this to true to show the entry again.
const bool kTasmeeDrillsEnabled = false;

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
  required VoidCallback onReports,
  required VoidCallback onWeakPoints,
}) {
  const gold = Color(0xFFD2B97E);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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
          // Scrolls on short screens instead of overflowing.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.88,
            ),
            child: SingleChildScrollView(
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
              if (kTasmeeDrillsEnabled)
                tile(
                  icon: Icons.fitness_center_rounded,
                  title: 'تقوية الحفظ',
                  subtitle: 'مراجعة مواضع أخطائك في التسميع: تبدأ من آية أو '
                      'آيتين قبل الخطأ، وما قرأته صحيحًا يُحذف من القائمة.',
                  active: false,
                  onTap: onWeakPoints,
                ),
              tile(
                icon: Icons.fact_check_rounded,
                title: 'تقارير التسميع',
                subtitle: 'أخطاء كل صفحة سمّعتها: الكلمة، ونوع الخطأ، وما قرأته.',
                active: false,
                onTap: onReports,
              ),
              const _AlertModeTile(),
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
          ),
        ),
      );
    },
  );
}

/// How a mistake is signalled during Tasmee: tap to cycle through the modes.
class _AlertModeTile extends StatefulWidget {
  const _AlertModeTile();

  @override
  State<_AlertModeTile> createState() => _AlertModeTileState();
}

class _AlertModeTileState extends State<_AlertModeTile> {
  static const gold = Color(0xFFD2B97E);
  TasmeeAlertMode? _mode;

  @override
  void initState() {
    super.initState();
    TasmeeAlert.mode().then((m) {
      if (mounted) setState(() => _mode = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode ?? TasmeeAlertMode.vibrate;
    return ListTile(
      leading: const Icon(Icons.vibration_rounded, color: gold, size: 28),
      title: const Text(
        'تنبيه الخطأ في التسميع',
        style: TextStyle(color: gold, fontSize: 17, fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
      ),
      subtitle: Text(
        'الحالي: ${TasmeeAlert.label(mode)} — اضغط للتغيير',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
      ),
      trailing: DropdownButton<TasmeeAlertMode>(
        value: mode,
        dropdownColor: const Color(0xFF2C2C2E),
        underline: const SizedBox.shrink(),
        iconEnabledColor: gold,
        items: [
          for (final m in TasmeeAlertMode.values)
            DropdownMenuItem(
              value: m,
              child: Text(TasmeeAlert.label(m), style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
        ],
        onChanged: (m) async {
          if (m == null) return;
          await TasmeeAlert.setMode(m);
          if (mounted) setState(() => _mode = m);
          TasmeeAlert.fire();
        },
      ),
    );
  }
}

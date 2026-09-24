import 'package:flutter/material.dart';

import '../../services/tasmee_report_store.dart';
import 'hifz_palette.dart';
import 'tasmee_guide_sheet.dart';

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
  final p = HifzPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
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
          leading: Icon(icon, color: p.title, size: 28),
          title: Text(
            title,
            style: TextStyle(
              color: p.title,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: p.sub,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          trailing: active
              ? Icon(Icons.stop_circle_outlined, color: p.title)
              : Icon(Icons.chevron_left_rounded, color: p.title),
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
              Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'أدوات الحفظ',
                  style: TextStyle(
                    color: p.title,
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
                icon: Icons.help_outline_rounded,
                title: 'شرح التسميع',
                subtitle: 'كيف يعمل، وما يفعله كل زر في شريط التسميع.',
                active: false,
                onTap: () => showTasmeeGuide(context),
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

/// «تنبيهات»: how a mistake and a correction are signalled, side by side,
/// so the session can be followed without looking at the screen.
class _AlertModeTileState extends State<_AlertModeTile> {
  final Map<TasmeeAlertKind, TasmeeAlertMode> _modes = {};

  @override
  void initState() {
    super.initState();
    for (final k in TasmeeAlertKind.values) {
      TasmeeAlert.mode(kind: k).then((m) {
        if (mounted) setState(() => _modes[k] = m);
      });
    }
  }

  Widget _choice(HifzPalette p, TasmeeAlertKind kind, String title) {
    final mode = _modes[kind] ?? TasmeeAlertMode.vibrate;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: p.sub, fontSize: 12.5)),
          DropdownButton<TasmeeAlertMode>(
            value: mode,
            isExpanded: true,
            dropdownColor: p.raised,
            underline: const SizedBox.shrink(),
            iconEnabledColor: p.title,
            items: [
              for (final m in TasmeeAlertMode.values)
                DropdownMenuItem(
                  value: m,
                  child: Text(
                    TasmeeAlert.label(m),
                    style: TextStyle(color: p.text, fontSize: 13),
                  ),
                ),
            ],
            onChanged: (m) async {
              if (m == null) return;
              await TasmeeAlert.setMode(m, kind: kind);
              if (mounted) setState(() => _modes[kind] = m);
              TasmeeAlert.fire(kind: kind); // a taste of the choice
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    return ListTile(
      leading: Icon(Icons.vibration_rounded, color: p.title, size: 28),
      title: Text(
        'تنبيهات',
        style: TextStyle(color: p.title, fontSize: 17, fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            _choice(p, TasmeeAlertKind.mistake, 'عند الخطأ'),
            const SizedBox(width: 12),
            _choice(p, TasmeeAlertKind.corrected, 'عند التصويب'),
          ],
        ),
      ),
    );
  }
}

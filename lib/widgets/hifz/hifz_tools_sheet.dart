import 'package:flutter/material.dart';

import '../../services/tasmee_report_store.dart';
import 'hifz_palette.dart';
import 'tasmee_guide_sheet.dart';

/// «تقوية الحفظ» (the strengthening drills) is hidden for now: a drill can
/// open on a fully covered page with nothing to start from. Mistakes are
/// still collected meanwhile; set this to true to show the entry again.
const bool kTasmeeDrillsEnabled = false;

/// The "أدوات الحفظ" sheet opened from the bottom action bar: one place for
/// the memorization tools -- the recitation test (التسميع), the two tests
/// (اختبار الحفظ by microphone, اختبار ذاتي on the covered page without one)
/// and the page concealment lens (وضع الحفظ). Settings sit behind the gear.
Future<void> showHifzToolsSheet(
  BuildContext context, {
  required bool tasmeeActive,
  required bool hifzModeActive,
  required VoidCallback onTasmee,
  required VoidCallback onHifzMode,

  /// The tests are given a closer for this menu: they call it once a test
  /// really starts, so backing out of the setup sheet lands here again.
  required void Function(VoidCallback closeMenu) onTest,
  required void Function(VoidCallback closeMenu) onTextTest,
  required VoidCallback onLogs,
  required VoidCallback onReports,
  required VoidCallback onStats,
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
      // Entries that open another sheet or page leave this menu underneath
      // (keepOpen), so the back button returns here rather than to the
      // mushaf; entries that switch a mode on close it.
      void closeMenu() {
        if (sheetContext.mounted && Navigator.of(sheetContext).canPop()) {
          Navigator.of(sheetContext).pop();
        }
      }

      Widget tile({
        required IconData icon,
        required String title,
        String? subtitle,
        bool active = false,
        bool keepOpen = false,
        required VoidCallback onTap,
      }) {
        return ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -1),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          leading: Icon(icon, color: p.title, size: 25),
          title: Text(
            title,
            style: TextStyle(
              color: p.title,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.sub, fontSize: 12.5),
                ),
          trailing: active
              ? Icon(Icons.stop_circle_outlined, color: p.title, size: 22)
              : Icon(Icons.chevron_left_rounded, color: p.sub, size: 22),
          onTap: () {
            if (!keepOpen) closeMenu();
            onTap();
          },
        );
      }

      Widget link(String label, VoidCallback onTap) => TextButton(
            onPressed: onTap,
            child: Text(
              label,
              style: TextStyle(color: p.title, fontSize: 13.5),
            ),
          );

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
                    padding: const EdgeInsets.fromLTRB(18, 8, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'أدوات الحفظ',
                            style: TextStyle(
                              color: p.title,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Tajawal',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'إعدادات التسميع',
                          icon: Icon(Icons.settings_outlined, color: p.title),
                          onPressed: () => showTasmeeSettingsSheet(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  tile(
                    icon: Icons.mic_rounded,
                    title: tasmeeActive ? 'إنهاء التسميع' : 'التسميع',
                    subtitle: tasmeeActive
                        ? 'الجلسة جارية على هذه الصفحة'
                        : 'اقرأ الصفحة من حفظك، وتنكشف كلماتها كلمةً كلمة',
                    active: tasmeeActive,
                    onTap: onTasmee,
                  ),
                  tile(
                    icon: Icons.quiz_outlined,
                    title: 'اختبار الحفظ',
                    subtitle: 'بالميكروفون: أسئلة من أخطائك أو عشوائية في نطاق تختاره',
                    keepOpen: true,
                    onTap: () => onTest(closeMenu),
                  ),
                  tile(
                    icon: Icons.visibility_off_rounded,
                    title: 'اختبار ذاتي',
                    subtitle: 'بلا ميكروفون: الآيات مخفية، اقرأ في نفسك واكشف كلمةً أو آية',
                    keepOpen: true,
                    onTap: () => onTextTest(closeMenu),
                  ),
                  tile(
                    icon: Icons.blur_on_rounded,
                    title: hifzModeActive ? 'إيقاف وضع الحفظ' : 'وضع الحفظ',
                    subtitle: 'تُخفى الصفحة، واضغط مطوّلًا لكشف ما تحت إصبعك',
                    active: hifzModeActive,
                    onTap: onHifzMode,
                  ),
                  if (kTasmeeDrillsEnabled)
                    tile(
                      icon: Icons.fitness_center_rounded,
                      title: 'تقوية الحفظ',
                      subtitle: 'مراجعة مواضع أخطائك في التسميع',
                      onTap: onWeakPoints,
                    ),
                  tile(
                    icon: Icons.fact_check_rounded,
                    title: 'تقارير التسميع والأخطاء',
                    subtitle: 'كل صفحة سُمِّعت، وسجل الأخطاء: تعثّر ثم أصاب، أو كُشفت بطلب',
                    keepOpen: true,
                    onTap: onReports,
                  ),
                  tile(
                    icon: Icons.insights_rounded,
                    title: 'الإحصاءات',
                    subtitle: 'زمن الصفحة والحزب، الأخطاء والتصويبات، ونتائج الاختبارات',
                    keepOpen: true,
                    onTap: onStats,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        link('شرح التسميع', () => showTasmeeGuide(sheetContext)),
                        Text('·', style: TextStyle(color: p.sub)),
                        link('سجلات التسميع', onLogs),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// «إعدادات التسميع» (behind the gear): how a mistake and a correction are
/// signalled. Both default to vibration only.
Future<void> showTasmeeSettingsSheet(BuildContext context) {
  final p = HifzPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'إعدادات التسميع',
                style: TextStyle(
                  color: p.title,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Tajawal',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'التنبيه أثناء التسميع، لتتابع الجلسة دون النظر إلى الشاشة.',
                style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 8),
              const _AlertModeRow(),
              const SizedBox(height: 10),
              const _LocateAnywhereRow(),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The two alert dropdowns («عند الخطأ», «عند التصويب») on one row.
/// «التسميع من أي موضع»: off unless chosen.
class _LocateAnywhereRow extends StatefulWidget {
  const _LocateAnywhereRow();

  @override
  State<_LocateAnywhereRow> createState() => _LocateAnywhereRowState();
}

class _LocateAnywhereRowState extends State<_LocateAnywhereRow> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    TasmeeLocateAnywhere.enabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    return Row(
      children: [
        Icon(Icons.travel_explore_rounded, color: p.title, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'التسميع من أي موضع',
                style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'افتح أي صفحة واقرأ من حيث شئت؛ بعد أول كلمات ينتقل المصحف إلى موضعك '
                '(أول موضع يطابق قراءتك، مرة واحدة في الجلسة). لا يعمل في الاختبارات.',
                style: TextStyle(color: p.sub, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        Switch(
          value: _on,
          activeThumbColor: p.title,
          onChanged: (v) async {
            setState(() => _on = v);
            await TasmeeLocateAnywhere.set(v);
          },
        ),
      ],
    );
  }
}

class _AlertModeRow extends StatefulWidget {
  const _AlertModeRow();

  @override
  State<_AlertModeRow> createState() => _AlertModeRowState();
}

class _AlertModeRowState extends State<_AlertModeRow> {
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
    return Row(
      children: [
        Icon(Icons.vibration_rounded, color: p.title, size: 24),
        const SizedBox(width: 12),
        _choice(p, TasmeeAlertKind.mistake, 'عند الخطأ'),
        const SizedBox(width: 12),
        _choice(p, TasmeeAlertKind.corrected, 'عند التصويب'),
      ],
    );
  }
}

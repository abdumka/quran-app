import 'package:flutter/material.dart';

import '../../services/hifz_data_cleaner.dart';
import '../../utils/quran_display_text.dart';
import 'hifz_palette.dart';

String _testsCount(int n) => arabicCount(
  n,
  one: 'اختبار واحد',
  two: 'اختباران',
  few: 'اختبارات',
  many: 'اختبارًا',
);
String _mistakesCount(int n) =>
    arabicCount(n, one: 'خطأ واحد', two: 'خطآن', few: 'أخطاء', many: 'خطأً');

/// «مسح الإحصاءات» (from the statistics) or «حذف الأخطاء» (from the
/// mistakes log): pick the dates and what goes, then one button. There is
/// no confirmation dialog; the caller offers «تراجع» with the returned
/// undo instead ([showHifzClearedSnack]). Null when nothing was cleared.
Future<({HifzClearUndo undo, String summary})?> showHifzClearSheet(
  BuildContext context, {
  required bool forMistakes,
}) async {
  final p = HifzPalette.of(context);
  final choice = await HifzClearChoice.load(forMistakes: forMistakes);
  final data = await HifzSavedData.load();
  if (!context.mounted) return null;
  return showModalBottomSheet<({HifzClearUndo undo, String summary})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        HifzClearSheet(initial: choice, data: data, forMistakes: forMistakes),
  );
}

/// The «تم المسح · تراجع» line after a clear; [reload] refreshes the page
/// after the clear and again after an undo.
void showHifzClearedSnack(
  BuildContext context, {
  required HifzClearUndo undo,
  required String summary,
  required VoidCallback reload,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(summary, textDirection: TextDirection.rtl),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'تراجع',
        onPressed: () async {
          await HifzDataCleaner.undo(undo);
          reload();
        },
      ),
    ),
  );
  reload();
}

@visibleForTesting
class HifzClearSheet extends StatefulWidget {
  const HifzClearSheet({
    super.key,
    required this.initial,
    required this.data,
    required this.forMistakes,
  });

  final HifzClearChoice initial;
  final HifzSavedData data;
  final bool forMistakes;

  @override
  State<HifzClearSheet> createState() => _HifzClearSheetState();
}

class _HifzClearSheetState extends State<HifzClearSheet> {
  late HifzClearChoice _c = widget.initial;
  final DateTime _now = DateTime.now();
  bool _busy = false;

  static const List<HifzClearRange> _presets = [
    HifzClearRange(HifzClearSpan.recent, 7),
    HifzClearRange(HifzClearSpan.recent, 30),
    HifzClearRange(HifzClearSpan.older, 30),
    HifzClearRange.all(),
  ];

  void _setRange(HifzClearRange r) =>
      setState(() => _c = _c.copyWith(range: r));

  /// One day at a time up to 10, then 5, then 10 (a year is 365 taps
  /// otherwise).
  void _step(int sign) {
    final r = _c.range;
    final at = sign > 0 ? r.days : r.days - 1;
    final delta = sign * (at < 10 ? 1 : (at < 30 ? 5 : 10));
    final span = r.span == HifzClearSpan.all ? HifzClearSpan.recent : r.span;
    final days = (r.days + delta)
        .clamp(HifzClearRange.minDays, HifzClearRange.maxDays)
        .toInt();
    _setRange(HifzClearRange(span, days));
  }

  int get _sessions => widget.data.sessionsIn(_c.range, _now);
  int get _tests => widget.data.testsIn(_c.range, _now);
  int get _mistakes => widget.data.mistakesIn(_c.range, _now);

  int get _total =>
      (_c.sessions ? _sessions : 0) +
      (_c.tests ? _tests : 0) +
      (_c.mistakes ? _mistakes : 0);

  String _summary() {
    final parts = [
      if (_c.sessions && _sessions > 0) pagesCount(_sessions),
      if (_c.tests && _tests > 0) _testsCount(_tests),
      if (_c.mistakes && _mistakes > 0) _mistakesCount(_mistakes),
    ];
    return '${widget.forMistakes ? 'حُذف' : 'مُسح'}: ${parts.join('، ')}';
  }

  Future<void> _go() async {
    if (_busy || _total == 0) return;
    setState(() => _busy = true);
    final summary = _summary();
    await _c.save(forMistakes: widget.forMistakes);
    final undo = await HifzDataCleaner.clear(_c, now: _now);
    if (!mounted) return;
    Navigator.of(context).pop((undo: undo, summary: summary));
  }

  Widget _chip(HifzPalette p, String label, bool on, VoidCallback tap) =>
      ChoiceChip(
        label: Text(label),
        selected: on,
        showCheckmark: false,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        selectedColor: p.title,
        backgroundColor: p.bg,
        side: BorderSide(color: p.border),
        labelStyle: TextStyle(color: on ? p.onTitle : p.text, fontSize: 13),
        onSelected: (_) => tap(),
      );

  Widget _check(
    HifzPalette p,
    String label,
    int count,
    bool on,
    ValueChanged<bool> set,
  ) => InkWell(
    onTap: () => set(!on),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: on,
            activeColor: p.title,
            visualDensity: VisualDensity.compact,
            onChanged: (v) => set(v ?? false),
          ),
          Expanded(
            child: Text(
              '$label ($count)',
              style: TextStyle(color: p.text, fontSize: 14),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    final r = _c.range;
    final custom = r.span != HifzClearSpan.all && !_presets.contains(r);
    final dayWord = r.days <= 2 ? 'يوم' : (r.days <= 10 ? 'أيام' : 'يومًا');
    final title = TextStyle(color: p.sub, fontSize: 12.5);
    return SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.forMistakes ? 'حذف الأخطاء' : 'مسح الإحصاءات',
                style: TextStyle(
                  color: p.title,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Tajawal',
                ),
              ),
              const SizedBox(height: 10),
              Text('المدة', style: title),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  for (final preset in _presets)
                    _chip(
                      p,
                      preset.label,
                      r == preset,
                      () => _setRange(preset),
                    ),
                ],
              ),
              // Any number of days, recent or older.
              Row(
                children: [
                  _chip(
                    p,
                    'آخر',
                    custom && r.span == HifzClearSpan.recent,
                    () =>
                        _setRange(HifzClearRange(HifzClearSpan.recent, r.days)),
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    p,
                    'أقدم من',
                    custom && r.span == HifzClearSpan.older,
                    () =>
                        _setRange(HifzClearRange(HifzClearSpan.older, r.days)),
                  ),
                  IconButton(
                    tooltip: 'يوم أقل',
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      color: p.title,
                    ),
                    onPressed: () => _step(-1),
                  ),
                  Text(
                    '${r.days}',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    tooltip: 'يوم أكثر',
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      color: p.title,
                    ),
                    onPressed: () => _step(1),
                  ),
                  Text(
                    dayWord,
                    style: TextStyle(color: p.text, fontSize: 13.5),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('يشمل', style: title),
              _check(
                p,
                'جلسات التسميع وتقاريرها',
                _sessions,
                _c.sessions,
                (v) => setState(() => _c = _c.copyWith(sessions: v)),
              ),
              _check(
                p,
                'نتائج الاختبارات',
                _tests,
                _c.tests,
                (v) => setState(() => _c = _c.copyWith(tests: v)),
              ),
              _check(
                p,
                'الأخطاء المحفوظة (ومنها أسئلة «من الأخطاء»)',
                _mistakes,
                _c.mistakes,
                (v) => setState(() => _c = _c.copyWith(mistakes: v)),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.bad,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _total == 0 || _busy ? null : _go,
                  child: Text(
                    _total == 0
                        ? 'لا شيء لمسحه في هذه المدة'
                        : '${widget.forMistakes ? 'حذف' : 'مسح'} ${r.label}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'يمكنك التراجع بعد المسح مباشرة. سجلات التسميع الصوتية لا تُمسح من هنا.',
                style: TextStyle(color: p.sub, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

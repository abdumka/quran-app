import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../quran_constants.dart';
import '../../services/hifz_test_plan.dart';
import '../../services/tasmee_report_store.dart';
import '../../services/tasmee_weak_point_store.dart';
import '../../surah_data.dart';
import '../../utils/quran_display_text.dart';
import 'hifz_palette.dart';

String _sourceLabel(HifzTestSource s) => switch (s) {
      HifzTestSource.mistakes => 'من أخطائي',
      HifzTestSource.random => 'عشوائي',
      HifzTestSource.both => 'كلاهما',
    };

/// The setup of a test: where its questions come from, what part of the
/// mushaf, how many, and (microphone test only) how long each one is.
/// Returns null when dismissed. The last choice is remembered per test.
Future<HifzTestConfig?> showHifzTestSetup(
  BuildContext context, {
  required bool textMode,
  required int mistakesInPool,
}) async {
  final prefKey = textMode ? 'hifz_text_test_config' : 'hifz_test_config';
  var initial = const HifzTestConfig();
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKey);
    if (raw != null) {
      initial = HifzTestConfig.fromJson(json.decode(raw) as Map<String, dynamic>);
    }
  } catch (_) {}
  if (mistakesInPool == 0 && initial.source != HifzTestSource.random) {
    initial = initial.copyWith(source: HifzTestSource.random);
  }
  if (!context.mounted) return null;
  final p = HifzPalette.of(context);
  final result = await showModalBottomSheet<HifzTestConfig>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _SetupSheet(
      textMode: textMode,
      mistakesInPool: mistakesInPool,
      initial: initial,
    ),
  );
  if (result != null) {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, json.encode(result.toJson()));
    } catch (_) {}
  }
  return result;
}

class _SetupSheet extends StatefulWidget {
  const _SetupSheet({
    required this.textMode,
    required this.mistakesInPool,
    required this.initial,
  });

  final bool textMode;
  final int mistakesInPool;
  final HifzTestConfig initial;

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  late HifzTestConfig _config = widget.initial;
  late final TextEditingController _pageFrom;
  late final TextEditingController _pageTo;

  @override
  void initState() {
    super.initState();
    final r = _config.range;
    final pages = r.kind == HifzRangeKind.pages;
    _pageFrom = TextEditingController(text: pages ? '${r.from}' : '1');
    _pageTo = TextEditingController(text: pages ? '${r.to}' : '1');
  }

  @override
  void dispose() {
    _pageFrom.dispose();
    _pageTo.dispose();
    super.dispose();
  }

  HifzRange get _range => _config.range;

  void _setRange(HifzRangeKind kind, {int? from, int? to}) {
    final current = _range.kind == kind ? _range : HifzRange(kind);
    setState(() {
      _config = _config.copyWith(
        range: HifzRange(
          kind,
          from: from ?? current.from,
          to: to ?? current.to,
        ),
      );
    });
  }

  Widget _section(HifzPalette p, String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: p.title,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );

  ButtonStyle _segmentStyle(HifzPalette p) => ButtonStyle(
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onTitle : p.text,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.title : p.raised,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: p.border)),
      );

  Widget _dropdown<T>({
    required HifzPalette p,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.border),
        ),
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: p.raised,
          underline: const SizedBox.shrink(),
          iconEnabledColor: p.title,
          style: TextStyle(color: p.text, fontSize: 13.5),
          items: items,
          onChanged: onChanged,
        ),
      );

  Widget _fromTo(HifzPalette p, Widget from, Widget to) => Row(
        children: [
          Text('من', style: TextStyle(color: p.sub, fontSize: 12.5)),
          const SizedBox(width: 6),
          Expanded(child: from),
          const SizedBox(width: 10),
          Text('إلى', style: TextStyle(color: p.sub, fontSize: 12.5)),
          const SizedBox(width: 6),
          Expanded(child: to),
        ],
      );

  Widget _rangeDetail(HifzPalette p) {
    final r = _range;
    switch (r.kind) {
      case HifzRangeKind.all:
        return const SizedBox.shrink();
      case HifzRangeKind.surahs:
        List<DropdownMenuItem<int>> items() => [
              for (final s in surahList)
                DropdownMenuItem(
                  value: s['number'] as int,
                  child: Text('${s['number']}. ${s['name']}'),
                ),
            ];
        return _fromTo(
          p,
          _dropdown<int>(
            p: p,
            value: r.from.clamp(1, 114),
            items: items(),
            onChanged: (v) => _setRange(HifzRangeKind.surahs, from: v),
          ),
          _dropdown<int>(
            p: p,
            value: r.to.clamp(1, 114),
            items: items(),
            onChanged: (v) => _setRange(HifzRangeKind.surahs, to: v),
          ),
        );
      case HifzRangeKind.hizbs:
        List<DropdownMenuItem<int>> items() => [
              for (var h = 1; h <= 60; h++)
                DropdownMenuItem(
                  value: h,
                  child: Text(
                    '$h. ${h - 1 < hizbTitles.length ? hizbTitles[h - 1] : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ];
        return _fromTo(
          p,
          _dropdown<int>(
            p: p,
            value: r.from.clamp(1, 60),
            items: items(),
            onChanged: (v) => _setRange(HifzRangeKind.hizbs, from: v),
          ),
          _dropdown<int>(
            p: p,
            value: r.to.clamp(1, 60),
            items: items(),
            onChanged: (v) => _setRange(HifzRangeKind.hizbs, to: v),
          ),
        );
      case HifzRangeKind.pages:
        Widget field(TextEditingController c, void Function(int) onValue) =>
            TextField(
              controller: c,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: p.raised,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: p.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: p.border),
                ),
              ),
              onChanged: (t) {
                final v = int.tryParse(t);
                if (v != null) onValue(v);
              },
            );
        return _fromTo(
          p,
          field(_pageFrom, (v) => _setRange(HifzRangeKind.pages, from: v)),
          field(_pageTo, (v) => _setRange(HifzRangeKind.pages, to: v)),
        );
    }
  }

  Widget _chips(
    HifzPalette p,
    List<int> values,
    int selected,
    String Function(int) label,
    ValueChanged<int> onPick,
  ) =>
      Wrap(
        spacing: 6,
        children: [
          for (final v in values)
            ChoiceChip(
              label: Text(label(v)),
              selected: v == selected,
              showCheckmark: false,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              selectedColor: p.title,
              backgroundColor: p.raised,
              side: BorderSide(color: p.border),
              labelStyle: TextStyle(
                color: v == selected ? p.onTitle : p.text,
                fontSize: 12.5,
              ),
              onSelected: (_) => onPick(v),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    final noMistakes = widget.mistakesInPool == 0;
    return SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              18,
              14,
              18,
              12 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.textMode ? 'اختبار نصّي' : 'اختبار الحفظ',
                  style: TextStyle(
                    color: p.title,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.textMode
                      ? 'تُعرض عليك آية، فتذكر التي بعدها من حفظك ثم تكشفها وتحكم على نفسك.'
                      : 'ينقلك كل سؤال إلى موضع في المصحف تقرأ منه من حفظك عبر الميكروفون.',
                  style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.4),
                ),
                _section(
                  p,
                  'مصدر الأسئلة',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<HifzTestSource>(
                          style: _segmentStyle(p),
                          showSelectedIcon: false,
                          segments: [
                            for (final s in HifzTestSource.values)
                              ButtonSegment(
                                value: s,
                                label: Text(_sourceLabel(s)),
                                enabled: !noMistakes || s == HifzTestSource.random,
                              ),
                          ],
                          selected: {_config.source},
                          onSelectionChanged: (s) => setState(
                            () => _config = _config.copyWith(source: s.first),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          noMistakes
                              ? 'لم تُسجَّل أخطاء بعد؛ سمِّع أولًا لتُختبر فيها.'
                              : 'أخطاؤك المسجّلة في التسميع: ${widget.mistakesInPool} موضعًا.',
                          style: TextStyle(color: p.sub, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
                _section(
                  p,
                  'النطاق',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<HifzRangeKind>(
                          style: _segmentStyle(p),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: HifzRangeKind.all,
                              label: Text('المصحف كله'),
                            ),
                            ButtonSegment(
                              value: HifzRangeKind.surahs,
                              label: Text('سور'),
                            ),
                            ButtonSegment(
                              value: HifzRangeKind.hizbs,
                              label: Text('أحزاب'),
                            ),
                            ButtonSegment(
                              value: HifzRangeKind.pages,
                              label: Text('صفحات'),
                            ),
                          ],
                          selected: {_range.kind},
                          onSelectionChanged: (s) {
                            final kind = s.first;
                            if (kind == HifzRangeKind.pages) {
                              _setRange(
                                kind,
                                from: int.tryParse(_pageFrom.text) ?? 1,
                                to: int.tryParse(_pageTo.text) ?? 1,
                              );
                            } else {
                              _setRange(kind);
                            }
                          },
                        ),
                      ),
                      if (_range.kind != HifzRangeKind.all)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _rangeDetail(p),
                        ),
                    ],
                  ),
                ),
                _section(
                  p,
                  'عدد الأسئلة',
                  _chips(
                    p,
                    const [3, 5, 10, 20],
                    _config.questions,
                    (v) => '$v',
                    (v) => setState(() => _config = _config.copyWith(questions: v)),
                  ),
                ),
                if (!widget.textMode)
                  _section(
                    p,
                    'طول كل سؤال',
                    _chips(
                      p,
                      const [1, 3, 5],
                      _config.ayahsPerQuestion,
                      (v) => switch (v) {
                        1 => 'آية واحدة',
                        _ => '$v آيات',
                      },
                      (v) => setState(
                        () => _config = _config.copyWith(ayahsPerQuestion: v),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: p.title,
                          foregroundColor: p.onTitle,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.of(context).pop(
                          _config.copyWith(range: _range.normalized()),
                        ),
                        child: const Text(
                          'ابدأ',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'إلغاء',
                        style: TextStyle(color: p.title, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One error, as the result sheets list it.
Widget hifzErrorLine(HifzPalette p, TasmeeError e) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        quranDisplayText(
          e.kind == 'extra' && e.heard.isNotEmpty
              ? '• ${e.kindLabel}: «${e.heard}» قبل «${e.expected}» — الآية ${e.ayah}'
              : '• ${e.kindLabel}: «${e.expected}» — الآية ${e.ayah}'
                  '${e.heard.isEmpty ? '' : ' — قرأت «${e.heard}»'}',
        ),
        style: TextStyle(color: p.text, fontSize: 13.5, height: 1.5),
      ),
    );

/// After one question of the microphone test: clean, or its errors. Returns
/// true to go on to the next question.
Future<bool> showHifzTestQuestionResult(
  BuildContext context,
  TasmeeDrillResult result, {
  required bool hasNext,
}) async {
  final p = HifzPalette.of(context);
  final choice = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final clean = result.clean;
      return SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        clean
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        color: clean ? p.good : p.bad,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          clean ? 'أحسنت — بلا أخطاء' : 'فيها ملاحظات',
                          style: TextStyle(
                            color: p.title,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ),
                      Text(
                        result.drill.label,
                        style: TextStyle(color: p.sub, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final e in result.errors) hifzErrorLine(p, e),
                  if (result.passed.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        quranDisplayText(
                          'أصبت ما كنت تخطئ فيه: '
                          '${result.passed.map((t) => '«${t.expected}»').join('، ')}',
                        ),
                        style: TextStyle(color: p.good, fontSize: 13.5, height: 1.5),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (hasNext)
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: p.title,
                              foregroundColor: p.onTitle,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.of(sheetContext).pop(true),
                            child: const Text(
                              'السؤال التالي',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Tajawal',
                              ),
                            ),
                          ),
                        ),
                      if (hasNext) const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.title,
                            side: BorderSide(color: p.title),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.of(sheetContext).pop(false),
                          child: Text(
                            hasNext ? 'إنهاء الاختبار' : 'النتيجة',
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Tajawal',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  return choice ?? false;
}

/// The end of a microphone test: the score and every question's outcome.
Future<void> showHifzTestSummary(BuildContext context, HifzTestRun run) {
  final p = HifzPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نتيجة الاختبار: ${run.correct} من ${run.answered}',
                  style: TextStyle(
                    color: p.title,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${run.config.range.label} · ${_sourceLabel(run.config.source)}',
                  style: TextStyle(color: p.sub, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < run.results.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          run.results[i].clean
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 20,
                          color: run.results[i].clean ? p.good : p.bad,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${i + 1}. ${run.questions[i].title}'
                            '${run.results[i].clean ? '' : ' — ${run.results[i].errors.length} ملاحظات'}',
                            style: TextStyle(color: p.text, fontSize: 14, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (run.answered < run.questions.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'أُنهي الاختبار قبل تمام أسئلته (${run.questions.length}).',
                      style: TextStyle(color: p.sub, fontSize: 12.5),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'الأخطاء تُحفظ لتُختبر فيها لاحقًا، ويُرفع الموضع من القائمة بعد إصابته في يومين مختلفين.',
                  style: TextStyle(color: p.sub, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 14),
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
                      'إغلاق',
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
}

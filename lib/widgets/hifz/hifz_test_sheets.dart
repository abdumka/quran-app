import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

String _kindLabel(HifzRangeKind k) => switch (k) {
      HifzRangeKind.all => 'المصحف كله',
      HifzRangeKind.surahs => 'سور',
      HifzRangeKind.hizbs => 'أحزاب',
      HifzRangeKind.athman => 'أثمان',
      HifzRangeKind.pages => 'صفحات',
    };

/// The setup of a test: where its questions come from, what part of the
/// mushaf, how many, and how long each one is. Returns null when
/// dismissed. The last choice is remembered per test.
Future<HifzTestConfig?> showHifzTestSetup(
  BuildContext context, {
  required bool silentMode,
  required int mistakesInPool,
}) async {
  final prefKey = silentMode ? 'hifz_text_test_config' : 'hifz_test_config';
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
      silentMode: silentMode,
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
    required this.silentMode,
    required this.mistakesInPool,
    required this.initial,
  });

  final bool silentMode;
  final int mistakesInPool;
  final HifzTestConfig initial;

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  late HifzTestConfig _config = widget.initial;
  late final TextEditingController _pageFrom;
  late final TextEditingController _pageTo;

  /// The bounds last chosen for each kind, so switching kinds and back
  /// keeps what was picked.
  final Map<HifzRangeKind, (int, int)> _bounds = {};

  @override
  void initState() {
    super.initState();
    final r = _config.range;
    _bounds[r.kind] = (r.from, r.to);
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

  /// «إلى» can never be before «من»: moving one past the other drags the
  /// other along.
  void _setRange(HifzRangeKind kind, {int? from, int? to}) {
    final have = _bounds[kind] ?? (1, 1);
    var a = from ?? have.$1;
    var b = to ?? have.$2;
    if (from != null && b < a) b = a;
    if (to != null && b < a) a = b;
    _bounds[kind] = (a, b);
    if (kind == HifzRangeKind.pages) {
      if (_pageFrom.text != '$a') _pageFrom.text = '$a';
      if (_pageTo.text != '$b') _pageTo.text = '$b';
    }
    setState(() {
      _config = _config.copyWith(range: HifzRange(kind, from: a, to: b));
    });
  }

  Widget _section(HifzPalette p, String title, Widget child, {String? note}) =>
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: p.title,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Text(
                  note,
                  style: TextStyle(color: p.sub, fontSize: 11.5, height: 1.4),
                ),
              ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );

  Widget _chip(
    HifzPalette p,
    String label, {
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) =>
      ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
        selectedColor: p.title,
        backgroundColor: p.raised,
        disabledColor: p.raised.withValues(alpha: 0.5),
        side: BorderSide(color: p.border),
        labelStyle: TextStyle(
          color: !enabled
              ? p.sub.withValues(alpha: 0.5)
              : selected
                  ? p.onTitle
                  : p.text,
          fontSize: 13,
        ),
        onSelected: enabled ? (_) => onTap() : null,
      );

  Widget _chips<T>(
    HifzPalette p,
    List<T> values,
    T selected,
    String Function(T) label,
    ValueChanged<T> onPick, {
    bool Function(T)? enabled,
  }) =>
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final v in values)
            _chip(
              p,
              label(v),
              selected: v == selected,
              enabled: enabled?.call(v) ?? true,
              onTap: () => onPick(v),
            ),
        ],
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

  /// A field with its name beside it («الحزب», «الثمن», «السورة»).
  Widget _named(HifzPalette p, String name, Widget field) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(name, style: TextStyle(color: p.sub, fontSize: 12.5)),
            ),
            Expanded(child: field),
          ],
        ),
      );

  /// One bound of the range («من» or «إلى») with its fields under it.
  Widget _bound(HifzPalette p, String title, List<Widget> fields) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: p.title,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ...fields,
          ],
        ),
      );

  List<DropdownMenuItem<int>> _surahItems({int min = 1}) => [
        for (final s in surahList)
          if ((s['number'] as int) >= min)
            DropdownMenuItem(
              value: s['number'] as int,
              child: Text('${s['number']}. ${s['name']}'),
            ),
      ];

  /// «١٢. قال رجلان — المائدة»: the hizb's number, name and surah.
  List<DropdownMenuItem<int>> _hizbItems({int min = 1}) => [
        for (var h = min; h <= 60; h++)
          DropdownMenuItem(
            value: h,
            child: Text(
              HifzRange.hizbLabel(h),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ];

  /// The athman of hizb [h] from the [min]th on, by their opening words.
  List<DropdownMenuItem<int>> _thumnItems(int h, {int min = 1}) => [
        for (var k = min; k <= HifzRange.athmanPerHizb; k++)
          DropdownMenuItem(
            value: k,
            child: Text(
              HifzRange.thumnLabel(HifzRange.thumnNumber(h, k)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ];

  /// The fields of a thumn bound: its hizb, then its place inside the hizb.
  /// [notBefore] keeps the «إلى» bound at or after the «من» one.
  List<Widget> _thumnFields(
    HifzPalette p,
    int thumn,
    ValueChanged<int> onPick, {
    int notBefore = 1,
  }) {
    final h = HifzRange.hizbOfThumn(thumn);
    final k = HifzRange.thumnInHizb(thumn);
    final minHizb = HifzRange.hizbOfThumn(notBefore);
    final minK = h == minHizb ? HifzRange.thumnInHizb(notBefore) : 1;
    return [
      _named(
        p,
        'الحزب',
        _dropdown<int>(
          p: p,
          value: h,
          items: _hizbItems(min: minHizb),
          onChanged: (v) {
            if (v != null) onPick(HifzRange.thumnNumber(v, k));
          },
        ),
      ),
      _named(
        p,
        'الثمن',
        _dropdown<int>(
          p: p,
          value: k.clamp(minK, HifzRange.athmanPerHizb),
          items: _thumnItems(h, min: minK),
          onChanged: (v) {
            if (v != null) onPick(HifzRange.thumnNumber(h, v));
          },
        ),
      ),
    ];
  }

  Widget _rangeDetail(HifzPalette p) {
    final r = _range;
    switch (r.kind) {
      case HifzRangeKind.all:
        return const SizedBox.shrink();
      case HifzRangeKind.surahs:
        final from = r.from.clamp(1, 114);
        final to = r.to.clamp(from, 114);
        return Column(
          children: [
            _bound(p, 'من', [
              _named(
                p,
                'السورة',
                _dropdown<int>(
                  p: p,
                  value: from,
                  items: _surahItems(),
                  onChanged: (v) => _setRange(HifzRangeKind.surahs, from: v),
                ),
              ),
            ]),
            _bound(p, 'إلى', [
              _named(
                p,
                'السورة',
                _dropdown<int>(
                  p: p,
                  value: to,
                  items: _surahItems(min: from),
                  onChanged: (v) => _setRange(HifzRangeKind.surahs, to: v),
                ),
              ),
            ]),
          ],
        );
      case HifzRangeKind.hizbs:
        final from = r.from.clamp(1, 60);
        final to = r.to.clamp(from, 60);
        return Column(
          children: [
            _bound(p, 'من', [
              _named(
                p,
                'الحزب',
                _dropdown<int>(
                  p: p,
                  value: from,
                  items: _hizbItems(),
                  onChanged: (v) => _setRange(HifzRangeKind.hizbs, from: v),
                ),
              ),
            ]),
            _bound(p, 'إلى', [
              _named(
                p,
                'الحزب',
                _dropdown<int>(
                  p: p,
                  value: to,
                  items: _hizbItems(min: from),
                  onChanged: (v) => _setRange(HifzRangeKind.hizbs, to: v),
                ),
              ),
            ]),
          ],
        );
      case HifzRangeKind.athman:
        final from = r.from.clamp(1, 480);
        final to = r.to.clamp(from, 480);
        return Column(
          children: [
            _bound(
              p,
              'من',
              _thumnFields(p, from, (v) => _setRange(HifzRangeKind.athman, from: v)),
            ),
            _bound(
              p,
              'إلى',
              _thumnFields(
                p,
                to,
                (v) => _setRange(HifzRangeKind.athman, to: v),
                notBefore: from,
              ),
            ),
          ],
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
                hintText: '1 – 602',
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
              // Bounds are put in order when the field is left, so typing
              // "12" as the start while the end still says "3" is allowed.
              onEditingComplete: () {
                final v = int.tryParse(c.text);
                if (v != null) onValue(v.clamp(1, 602));
                FocusScope.of(context).unfocus();
              },
              onTapOutside: (_) {
                final v = int.tryParse(c.text);
                if (v != null) onValue(v.clamp(1, 602));
              },
            );
        return Column(
          children: [
            _bound(p, 'من', [
              _named(
                p,
                'الصفحة',
                field(_pageFrom, (v) => _setRange(HifzRangeKind.pages, from: v)),
              ),
            ]),
            _bound(p, 'إلى', [
              _named(
                p,
                'الصفحة',
                field(_pageTo, (v) => _setRange(HifzRangeKind.pages, to: v)),
              ),
            ]),
          ],
        );
    }
  }

  /// The range the sheet will return: typed page numbers are read once
  /// more here, since a field may not have been left yet.
  HifzRange _finalRange() {
    if (_range.kind == HifzRangeKind.pages) {
      final a = int.tryParse(_pageFrom.text) ?? _range.from;
      final b = int.tryParse(_pageTo.text) ?? _range.to;
      return HifzRange(HifzRangeKind.pages, from: a, to: b).normalized();
    }
    return _range.normalized();
  }

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    final noMistakes = widget.mistakesInPool == 0;
    return SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
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
                  widget.silentMode ? 'اختبار ذاتي' : 'اختبار الحفظ',
                  style: TextStyle(
                    color: p.title,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.silentMode
                      ? 'تُخفى آيات الصفحة، ويظهر لك موضع البداية. اقرأ في نفسك، '
                          'واكشف كلمةً أو آيةً للتحقق، ثم احكم على نفسك في كل سؤال.'
                      : 'ينقلك كل سؤال إلى موضع في المصحف تقرأ منه من حفظك عبر الميكروفون.',
                  style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.45),
                ),
                _section(
                  p,
                  'مصدر الأسئلة',
                  _chips<HifzTestSource>(
                    p,
                    HifzTestSource.values,
                    _config.source,
                    _sourceLabel,
                    (s) => setState(() => _config = _config.copyWith(source: s)),
                    enabled: (s) => !noMistakes || s == HifzTestSource.random,
                  ),
                  note: noMistakes
                      ? 'لم تُسجَّل أخطاء بعد؛ سمِّع أولًا لتُختبر فيها.'
                      : 'أخطاؤك المسجّلة: ${widget.mistakesInPool} موضعًا.',
                ),
                _section(
                  p,
                  'النطاق',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _chips<HifzRangeKind>(
                        p,
                        HifzRangeKind.values,
                        _range.kind,
                        _kindLabel,
                        (kind) => _setRange(kind),
                      ),
                      if (_range.kind != HifzRangeKind.all) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Text(
                            _range.normalized().label,
                            style: TextStyle(
                              color: p.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _rangeDetail(p),
                      ],
                    ],
                  ),
                ),
                _section(
                  p,
                  'عدد الأسئلة',
                  _chips<int>(
                    p,
                    const [3, 5, 10, 20],
                    _config.questions,
                    (v) => '$v',
                    (v) => setState(() => _config = _config.copyWith(questions: v)),
                  ),
                ),
                _section(
                  p,
                  'طول كل سؤال',
                  _chips<int>(
                    p,
                    const [1, 3, 5, 0],
                    _config.ayahsPerQuestion,
                    (v) => switch (v) {
                      0 => 'بلا حد',
                      1 => 'آية واحدة',
                      _ => '$v آيات',
                    },
                    (v) => setState(
                      () => _config = _config.copyWith(ayahsPerQuestion: v),
                    ),
                  ),
                  note: _config.openEnded
                      ? 'بلا حد: تقرأ ما شئت حتى آخر ${widget.silentMode ? 'الصفحة' : 'السورة'}، '
                          'وزر «سؤال جديد» في الشريط ينقلك متى شئت.'
                      : widget.silentMode
                          ? 'السؤال لا يتجاوز نهاية الصفحة التي يبدأ فيها.'
                          : null,
                ),
                const SizedBox(height: 18),
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
                          _config.copyWith(range: _finalRange()),
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

ButtonStyle _filled(HifzPalette p, [Color? color]) => FilledButton.styleFrom(
      backgroundColor: color ?? p.title,
      foregroundColor: p.onTitle,
      padding: const EdgeInsets.symmetric(vertical: 12),
    );

ButtonStyle _outlined(HifzPalette p, [Color? color]) => OutlinedButton.styleFrom(
      foregroundColor: color ?? p.title,
      side: BorderSide(color: color ?? p.title),
      padding: const EdgeInsets.symmetric(vertical: 12),
    );

const TextStyle _buttonText = TextStyle(
  fontSize: 15.5,
  fontWeight: FontWeight.bold,
  fontFamily: 'Tajawal',
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
                            style: _filled(p),
                            onPressed: () => Navigator.of(sheetContext).pop(true),
                            child: const Text('السؤال التالي', style: _buttonText),
                          ),
                        ),
                      if (hasNext) const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: _outlined(p),
                          onPressed: () => Navigator.of(sheetContext).pop(false),
                          child: Text(
                            hasNext ? 'إنهاء الاختبار' : 'النتيجة',
                            style: _buttonText,
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

/// What the reader said of a self-test question, and whether to go on.
class HifzSelfJudgement {
  const HifzSelfJudgement({
    required this.correct,
    required this.next,
    this.missed = const [],
  });

  /// Null when the reader ended the test without judging the question.
  final bool? correct;

  /// The ayahs of the question marked wrong.
  final List<AyahRef> missed;
  final bool next;
}

/// After one question of the self-test: every ayah of it with a right /
/// wrong mark (all right to begin with). Going on records the marks; a
/// small link ends the test instead.
Future<HifzSelfJudgement> showHifzSelfJudge(
  BuildContext context, {
  required HifzTestQuestion question,
  required String label,
  required bool hasNext,
}) async {
  final p = HifzPalette.of(context);
  final choice = await showModalBottomSheet<HifzSelfJudgement>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _SelfJudgeSheet(
      question: question,
      label: label,
      hasNext: hasNext,
    ),
  );
  return choice ?? const HifzSelfJudgement(correct: null, next: false);
}

class _SelfJudgeSheet extends StatefulWidget {
  const _SelfJudgeSheet({
    required this.question,
    required this.label,
    required this.hasNext,
  });

  final HifzTestQuestion question;
  final String label;
  final bool hasNext;

  @override
  State<_SelfJudgeSheet> createState() => _SelfJudgeSheetState();
}

class _SelfJudgeSheetState extends State<_SelfJudgeSheet> {
  final Set<int> _wrong = {};

  List<AyahRef> get _ayahs => widget.question.ayahs.isEmpty
      ? [widget.question.start]
      : widget.question.ayahs;

  Widget _mark(HifzPalette p, int i) {
    final wrong = _wrong.contains(i);
    Widget button(bool asWrong) {
      final on = wrong == asWrong;
      final color = asWrong ? p.bad : p.good;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => asWrong ? _wrong.add(i) : _wrong.remove(i)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: on ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? color : p.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                asWrong ? Icons.close_rounded : Icons.check_rounded,
                size: 18,
                color: on ? Colors.white : color,
              ),
              const SizedBox(width: 4),
              Text(
                asWrong ? 'خطأ' : 'صحيح',
                style: TextStyle(
                  color: on ? Colors.white : p.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [button(false), const SizedBox(width: 6), button(true)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    final ayahs = _ayahs;
    return SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'كيف قرأتها؟',
                        style: TextStyle(
                          color: p.title,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                    ),
                    Text(widget.label, style: TextStyle(color: p.sub, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'سورة ${widget.question.start.surahName} — علّم كل آية',
                  style: TextStyle(color: p.sub, fontSize: 13),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < ayahs.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'الآية ${ayahs[i].ayah}',
                            style: TextStyle(
                              color: _wrong.contains(i) ? p.bad : p.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _mark(p, i),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: _filled(p),
                    onPressed: () => Navigator.of(context).pop(
                      HifzSelfJudgement(
                        correct: _wrong.isEmpty,
                        missed: [for (final i in _wrong) ayahs[i]],
                        next: widget.hasNext,
                      ),
                    ),
                    child: Text(
                      widget.hasNext ? 'السؤال التالي' : 'النتيجة',
                      style: _buttonText,
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      const HifzSelfJudgement(correct: null, next: false),
                    ),
                    child: Text(
                      widget.hasNext ? 'إنهاء الاختبار دون حكم' : 'إغلاق دون حكم',
                      style: TextStyle(color: p.sub, fontSize: 13.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The end of a test: the score and every question's outcome.
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
                  '${run.config.range.label} · ${_sourceLabel(run.config.source)}'
                  '${run.silent ? ' · اختبار ذاتي' : ''}'
                  ' · ${DateTime.now().difference(run.startedAt).inMinutes} د',
                  style: TextStyle(color: p.sub, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < run.answered; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          run.isCorrect(i)
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 20,
                          color: run.isCorrect(i) ? p.good : p.bad,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${i + 1}. ${run.questions[i].title}'
                            '${!run.silent && !run.isCorrect(i) ? ' — ${run.results[i].errors.length} ملاحظات' : ''}',
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
                  'تُحفظ النتيجة في «الإحصاءات»، والأخطاء تُحفظ لتُختبر فيها لاحقًا، '
                  'ويُرفع الموضع من القائمة بعد إصابته في يومين مختلفين.',
                  style: TextStyle(color: p.sub, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: _filled(p),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('إغلاق', style: _buttonText),
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

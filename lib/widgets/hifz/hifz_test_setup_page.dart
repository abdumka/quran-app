import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/hifz_test_plan.dart';
import '../../surah_data.dart';
import '../../utils/quran_display_text.dart';
import 'hifz_palette.dart';
import 'hifz_test_guide_sheet.dart';

String _sourceLabel(HifzTestSource s) => switch (s) {
      HifzTestSource.mistakes => 'من أخطائي',
      HifzTestSource.random => 'عشوائي',
      HifzTestSource.both => 'كلاهما',
    };

String _kindLabel(HifzRangeKind k) => switch (k) {
      HifzRangeKind.all => 'المصحف كله',
      HifzRangeKind.currentPage => 'الصفحة الحالية',
      HifzRangeKind.fromCurrentPage => 'من الصفحة الحالية', // older saves only
      HifzRangeKind.surahs => 'سور',
      HifzRangeKind.hizbs => 'أحزاب',
      HifzRangeKind.athman => 'أثمان',
      HifzRangeKind.pages => 'صفحات',
    };

const TextStyle _buttonText = TextStyle(
  fontSize: 15.5,
  fontWeight: FontWeight.bold,
  fontFamily: 'Tajawal',
);

/// The setup of a test, as a page of its own: where its questions come
/// from, what part of the mushaf (chosen in its own picker), how many and
/// how long, or an open test. Returns null when the reader backs out. The
/// last choice is remembered per test.
Future<HifzTestConfig?> showHifzTestSetup(
  BuildContext context, {
  required bool silentMode,
  required int mistakesInPool,
  required int currentPage,
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
  // The first time: what the test does and what its buttons do.
  await showHifzTestGuideOnce(context, silent: silentMode);
  if (!context.mounted) return null;
  final result = await Navigator.of(context).push<HifzTestConfig>(
    MaterialPageRoute<HifzTestConfig>(
      builder: (_) => _SetupPage(
        silentMode: silentMode,
        mistakesInPool: mistakesInPool,
        currentPage: currentPage,
        initial: initial,
      ),
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

class _SetupPage extends StatefulWidget {
  const _SetupPage({
    required this.silentMode,
    required this.mistakesInPool,
    required this.currentPage,
    required this.initial,
  });

  final bool silentMode;
  final int mistakesInPool;

  /// The page open behind the sheet (1-based), for «الصفحة الحالية».
  final int currentPage;
  final HifzTestConfig initial;

  @override
  State<_SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<_SetupPage> {
  late HifzTestConfig _config = widget.initial;

  bool get _noMistakes => widget.mistakesInPool == 0;

  void _set(HifzTestConfig c) => setState(() => _config = c);

  /// What the range card says under its chips.
  String _rangeDetail() {
    final r = _config.range;
    return switch (r.kind) {
      HifzRangeKind.all => 'كل آيات المصحف.',
      HifzRangeKind.currentPage || HifzRangeKind.fromCurrentPage => _config.endless
          ? 'من الصفحة ${widget.currentPage} إلى آخر المصحف، بالترتيب.'
          : 'الصفحة ${widget.currentPage} وحدها.',
      HifzRangeKind.athman => () {
          final n = r.normalized();
          final end = n.to;
          return n.athmanCount > 1
              ? '${n.label} (حتى الثمن ${HifzRange.thumnInHizb(end)} من الحزب ${HifzRange.hizbOfThumn(end)}).'
              : '${n.label}.';
        }(),
      _ => r.normalized().label,
    };
  }

  void _setRangeKind(HifzRange r) => _set(_config.copyWith(range: r));

  bool get _byThumn => _config.range.kind == HifzRangeKind.athman;

  Widget _card(HifzPalette p, String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.border),
        ),
        // A Material of its own, so the range row's ink shows on the card.
        child: Material(
          color: p.raised,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                title,
                style: TextStyle(
                  color: p.title,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Tajawal',
                ),
              ),
            ),
            ...children,
            const SizedBox(height: 6),
          ],
          ),
        ),
      );

  Widget _row(
    HifzPalette p,
    String title,
    Widget trailing, {
    String? subtitle,
    bool dim = false,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Opacity(
          opacity: dim ? 0.45 : 1,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: p.text, fontSize: 15)),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(color: p.sub, fontSize: 11.5, height: 1.4),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
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
            ChoiceChip(
              label: Text(label(v)),
              selected: v == selected,
              showCheckmark: false,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selectedColor: p.title,
              backgroundColor: p.bg,
              disabledColor: p.bg.withValues(alpha: 0.5),
              side: BorderSide(color: p.border),
              labelStyle: TextStyle(
                color: !(enabled?.call(v) ?? true)
                    ? p.sub.withValues(alpha: 0.5)
                    : v == selected
                        ? p.onTitle
                        : p.text,
                fontSize: 13,
              ),
              onSelected: (enabled?.call(v) ?? true) ? (_) => onPick(v) : null,
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    final endless = _config.endless;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.bg,
          foregroundColor: p.title,
          title: Text(widget.silentMode ? 'اختبار ذاتي' : 'اختبار الحفظ'),
          actions: [
            IconButton(
              tooltip: 'شرح الاختبار',
              icon: const Icon(Icons.help_outline_rounded),
              onPressed: () => showHifzTestGuide(context, silent: widget.silentMode),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
              child: Text(
                widget.silentMode
                    ? 'الآيات مخفية: اقرأ في نفسك، واكشف كلمةً أو آية، ثم احكم على نفسك.'
                    : 'كل سؤال موضع في المصحف تقرأ منه من حفظك عبر الميكروفون.',
                style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.5),
              ),
            ),
            _card(p, 'النطاق', [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                child: _RangeEditor(
                  range: _config.range,
                  currentPage: widget.currentPage,
                  onChanged: _setRangeKind,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                child: Text(
                  _rangeDetail(),
                  style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.4),
                ),
              ),
            ]),
            _card(p, 'الأسئلة', [
              _row(
                p,
                'اختبار مفتوح',
                Switch(
                  value: endless,
                  activeThumbColor: p.title,
                  onChanged: (v) => _set(_config.copyWith(endless: v)),
                ),
                subtitle: _byThumn
                    ? 'كل أثمان النطاق بترتيبها، بلا توقف، حتى تُنهيه أنت'
                    : _config.range.kind == HifzRangeKind.currentPage
                        ? 'من هذه الصفحة إلى آخر المصحف، صفحة بعد صفحة، حتى تُنهيه أنت'
                        : 'صفحة بعد صفحة بالترتيب، لا ينتهي حتى تُنهيه أنت',
              ),
              Divider(height: 1, color: p.border, indent: 16, endIndent: 16),
              if (_byThumn && endless)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'كل ثمن سؤال، والأثمان كلها بترتيبها: ${questionsCount(_config.range.athmanCount)}.',
                    style: TextStyle(color: p.text, fontSize: 13.5, height: 1.5),
                  ),
                ),
              if (!(_byThumn && endless))
              _row(
                p,
                _byThumn ? 'عدد الأثمان في الاختبار' : 'عدد الأسئلة',
                _Stepper(
                  value: _byThumn
                      ? _config.questions.clamp(1, _config.range.athmanCount)
                      : _config.questions.clamp(1, HifzTestConfig.maxQuestions),
                  min: 1,
                  max: _byThumn ? _config.range.athmanCount : HifzTestConfig.maxQuestions,
                  enabled: !endless,
                  label: _byThumn ? athmanCount : questionsCount,
                  onChanged: (v) => _set(_config.copyWith(questions: v)),
                ),
                subtitle: _byThumn
                    ? 'كل ثمن سؤال كامل، تُختار من النطاق عشوائيًا (${athmanCount(_config.range.athmanCount)} في النطاق)'
                    : null,
                dim: endless,
              ),
              if (!_byThumn)
              _row(
                p,
                'آيات كل سؤال',
                _Stepper(
                  value: _config.ayahsPerQuestion.clamp(1, HifzTestConfig.maxAyahsPerQuestion),
                  min: 1,
                  max: HifzTestConfig.maxAyahsPerQuestion,
                  enabled: !endless,
                  label: ayatCount,
                  onChanged: (v) => _set(_config.copyWith(ayahsPerQuestion: v)),
                ),
                subtitle: endless
                    ? 'في الاختبار المفتوح كل صفحة سؤال'
                    : 'لا يتجاوز السؤال نهاية السورة، ويتابع إلى الصفحة التالية إن لزم',
                dim: endless,
              ),
            ]),
            _card(p, 'مصدر الأسئلة', [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                child: Opacity(
                  opacity: endless || _byThumn ? 0.45 : 1,
                  child: _chips<HifzTestSource>(
                    p,
                    HifzTestSource.values,
                    _config.source,
                    _sourceLabel,
                    (s) => _set(_config.copyWith(source: s)),
                    enabled: (s) =>
                        !endless && !_byThumn && (!_noMistakes || s == HifzTestSource.random),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                child: Text(
                  endless
                      ? 'في الاختبار المفتوح تأتي الأسئلة بالترتيب من أول النطاق.'
                      : _byThumn
                          ? 'مع الأثمان كل سؤال ثمن كامل.'
                          : _noMistakes
                          ? 'لم تُسجَّل أخطاء بعد؛ سمِّع أولًا لتُختبر فيها.'
                          : 'أخطاؤك المسجّلة: ${placesCount(widget.mistakesInPool)}.',
                  style: TextStyle(color: p.sub, fontSize: 11.5, height: 1.4),
                ),
              ),
            ]),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: p.title,
                  foregroundColor: p.onTitle,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.of(context).pop(
                  _config.copyWith(range: _config.range.normalized()),
                ),
                icon: Icon(widget.silentMode ? Icons.visibility_off_rounded : Icons.mic_rounded),
                label: const Text('ابدأ الاختبار', style: _buttonText),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The range, edited in place: the kind of range as chips, then its
/// bounds under them.
class _RangeEditor extends StatefulWidget {
  const _RangeEditor({
    required this.range,
    required this.currentPage,
    required this.onChanged,
  });
  final HifzRange range;
  final int currentPage;
  final ValueChanged<HifzRange> onChanged;

  @override
  State<_RangeEditor> createState() => _RangePickerState();
}

class _RangePickerState extends State<_RangeEditor> {
  HifzRange get _range => widget.range;
  late final TextEditingController _pageFrom;
  late final TextEditingController _pageTo;

  /// The bounds last chosen for each kind, so switching kinds and back
  /// keeps what was picked.
  final Map<HifzRangeKind, (int, int)> _bounds = {};

  @override
  void initState() {
    super.initState();
    final r = widget.range.normalized();
    _bounds[r.kind] = (r.from, r.to);
    final pages = r.kind == HifzRangeKind.pages;
    _pageFrom = TextEditingController(text: pages ? '${r.from}' : '${widget.currentPage}');
    _pageTo = TextEditingController(text: pages ? '${r.to}' : '${widget.currentPage}');
  }

  @override
  void dispose() {
    _pageFrom.dispose();
    _pageTo.dispose();
    super.dispose();
  }

  /// «إلى» can never be before «من»: moving one past the other drags the
  /// other along.
  void _setRange(HifzRangeKind kind, {int? from, int? to}) {
    final have = _bounds[kind] ??
        (kind == HifzRangeKind.pages
            ? (widget.currentPage, widget.currentPage)
            : (1, 1));
    var a = from ?? have.$1;
    var b = to ?? have.$2;
    if (from != null && b < a) b = a;
    if (to != null && b < a) a = b;
    _bounds[kind] = (a, b);
    if (kind == HifzRangeKind.pages) {
      if (_pageFrom.text != '$a') _pageFrom.text = '$a';
      if (_pageTo.text != '$b') _pageTo.text = '$b';
    }
    widget.onChanged(HifzRange(kind, from: a, to: b));
  }

  Widget _dropdown<T>({
    required HifzPalette p,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: p.bg,
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
          style: TextStyle(color: p.text, fontSize: 13),
          items: items,
          onChanged: onChanged,
        ),
      );

  Widget _named(HifzPalette p, String name, Widget field, {double width = 30}) =>
      Row(
        children: [
          SizedBox(
            width: width,
            child: Text(name, style: TextStyle(color: p.sub, fontSize: 12.5)),
          ),
          Expanded(child: field),
        ],
      );

  Widget _fromTo(HifzPalette p, Widget from, Widget to) => Row(
        children: [
          Expanded(child: _named(p, 'من', from)),
          const SizedBox(width: 10),
          Expanded(child: _named(p, 'إلى', to)),
        ],
      );

  List<DropdownMenuItem<int>> _surahItems({int min = 1}) => [
        for (final s in surahList)
          if ((s['number'] as int) >= min)
            DropdownMenuItem(
              value: s['number'] as int,
              child: Text(
                '${s['number']}. ${s['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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

  /// One bound of an athman range: its heading, then the hizb and the
  /// thumn inside it. [notBefore] keeps «إلى» at or after «من».
  Widget _thumnColumn(
    HifzPalette p,
    String title,
    int thumn,
    ValueChanged<int> onPick, {
    int notBefore = 1,
  }) {
    final h = HifzRange.hizbOfThumn(thumn);
    final k = HifzRange.thumnInHizb(thumn);
    final minHizb = HifzRange.hizbOfThumn(notBefore);
    final minK = h == minHizb ? HifzRange.thumnInHizb(notBefore) : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: p.title, fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
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
          width: 40,
        ),
        const SizedBox(height: 6),
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
          width: 40,
        ),
      ],
    );
  }

  Widget _pageField(HifzPalette p, TextEditingController c, void Function(int) onValue) =>
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
          fillColor: p.bg,
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
        onChanged: (t) {
          final v = int.tryParse(t);
          if (v != null && v >= 1 && v <= 602) onValue(v);
        },
        onEditingComplete: () => FocusScope.of(context).unfocus(),
      );

  Widget _detail(HifzPalette p) {
    final r = _range;
    switch (r.kind) {
      case HifzRangeKind.all:
      case HifzRangeKind.currentPage:
      case HifzRangeKind.fromCurrentPage:
        return const SizedBox.shrink();
      case HifzRangeKind.surahs:
        final from = r.from.clamp(1, 114);
        final to = r.to.clamp(from, 114);
        return _fromTo(
          p,
          _dropdown<int>(
            p: p,
            value: from,
            items: _surahItems(),
            onChanged: (v) => _setRange(HifzRangeKind.surahs, from: v),
          ),
          _dropdown<int>(
            p: p,
            value: to,
            items: _surahItems(min: from),
            onChanged: (v) => _setRange(HifzRangeKind.surahs, to: v),
          ),
        );
      case HifzRangeKind.hizbs:
        final from = r.from.clamp(1, 60);
        final to = r.to.clamp(from, 60);
        return _fromTo(
          p,
          _dropdown<int>(
            p: p,
            value: from,
            items: _hizbItems(),
            onChanged: (v) => _setRange(HifzRangeKind.hizbs, from: v),
          ),
          _dropdown<int>(
            p: p,
            value: to,
            items: _hizbItems(min: from),
            onChanged: (v) => _setRange(HifzRangeKind.hizbs, to: v),
          ),
        );
      case HifzRangeKind.athman:
        // From one thumn to another, each named by its hizb and its place
        // in it; «إلى» never comes before «من».
        final from = r.from.clamp(1, 480);
        final to = r.to.clamp(from, 480);
        // One under the other, full width, so the hizb names stay readable.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _thumnColumn(
              p,
              'من',
              from,
              (v) => _setRange(HifzRangeKind.athman, from: v),
            ),
            const SizedBox(height: 10),
            _thumnColumn(
              p,
              'إلى',
              to,
              (v) => _setRange(HifzRangeKind.athman, to: v),
              notBefore: from,
            ),
          ],
        );
      case HifzRangeKind.pages:
        return _fromTo(
          p,
          _pageField(p, _pageFrom, (v) => _setRange(HifzRangeKind.pages, from: v)),
          _pageField(p, _pageTo, (v) => _setRange(HifzRangeKind.pages, to: v)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    final detail = _detail(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final k in HifzRangeKind.values)
              if (k != HifzRangeKind.fromCurrentPage)
              ChoiceChip(
                label: Text(_kindLabel(k)),
                selected: _range.kind == k,
                showCheckmark: false,
                visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                selectedColor: p.title,
                backgroundColor: p.bg,
                side: BorderSide(color: p.border),
                labelStyle: TextStyle(
                  color: _range.kind == k ? p.onTitle : p.text,
                  fontSize: 13,
                ),
                onSelected: (_) => _setRange(k),
              ),
          ],
        ),
        if (detail is! SizedBox) ...[const SizedBox(height: 10), detail],
      ],
    );
  }
}

/// A number with − and + beside it: tap to step, hold to run.
class _Stepper extends StatefulWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });

  final int value;
  final int min;
  final int max;
  final String Function(int) label;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper> {
  Timer? _repeat;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _step(int by) {
    final next = (widget.value + by).clamp(widget.min, widget.max);
    if (next != widget.value) widget.onChanged(next);
  }

  void _startRepeat(int by) {
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 120), (_) => _step(by));
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  Widget _button(HifzPalette p, IconData icon, int by, bool enabled) =>
      GestureDetector(
        onLongPressStart: enabled ? (_) => _startRepeat(by) : null,
        onLongPressEnd: (_) => _stopRepeat(),
        onLongPressCancel: _stopRepeat,
        child: IconButton(
          onPressed: enabled ? () => _step(by) : null,
          icon: Icon(icon),
          color: p.title,
          iconSize: 22,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    final on = widget.enabled;
    return Container(
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(p, Icons.add_rounded, 1, on && widget.value < widget.max),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 88),
            child: Text(
              widget.label(widget.value),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          _button(p, Icons.remove_rounded, -1, on && widget.value > widget.min),
        ],
      ),
    );
  }
}

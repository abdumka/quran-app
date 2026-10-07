import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/hifz_test_plan.dart';
import '../../services/tasmee_report_store.dart';
import '../../services/tasmee_weak_point_store.dart';
import '../../utils/quran_display_text.dart';
import 'hifz_palette.dart';

String _sourceLabel(HifzTestSource s) => switch (s) {
      HifzTestSource.mistakes => 'من أخطائي',
      HifzTestSource.random => 'عشوائي',
      HifzTestSource.both => 'كلاهما',
    };

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
/// wrong mark, none chosen to begin with; going on needs a mark on each.
/// A small link ends the test instead.
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
  /// Each ayah's verdict once given: true = wrong. Unmarked until tapped.
  final Map<int, bool> _verdict = {};

  /// Once every ayah is marked the sheet goes on by itself after a
  /// moment; another tap restarts the moment, so a mark can be changed.
  Timer? _auto;
  static const Duration autoAdvance = Duration(milliseconds: 1200);

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  void _marked() {
    _auto?.cancel();
    if (_allMarked) _auto = Timer(autoAdvance, _submit);
  }

  void _submit() {
    _auto?.cancel();
    if (!mounted) return;
    final ayahs = _ayahs;
    Navigator.of(context).pop(
      HifzSelfJudgement(
        correct: _wrong.isEmpty,
        missed: [for (final i in _wrong) ayahs[i]],
        next: widget.hasNext,
      ),
    );
  }

  bool get _allMarked => _verdict.length >= _ayahs.length;
  Iterable<int> get _wrong => [for (final e in _verdict.entries) if (e.value) e.key];

  List<AyahRef> get _ayahs => widget.question.ayahs.isEmpty
      ? [widget.question.start]
      : widget.question.ayahs;

  /// The marks of ayah [i]; with [i] < 0 the pair that marks every ayah at
  /// once (lit only when every ayah carries that mark).
  Widget _mark(HifzPalette p, int i) {
    final bool? wrong;
    if (i >= 0) {
      wrong = _verdict[i];
    } else {
      final n = _ayahs.length;
      final all = [for (var k = 0; k < n; k++) _verdict[k]];
      wrong = _allMarked && all.every((v) => v == all.first) ? all.first : null;
    }
    Widget button(bool asWrong) {
      final on = wrong == asWrong;
      final color = asWrong ? p.bad : p.good;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
          if (i >= 0) {
            _verdict[i] = asWrong;
          } else {
            for (var k = 0; k < _ayahs.length; k++) {
              _verdict[k] = asWrong;
            }
          }
          });
          _marked();
        },
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
                if (ayahs.length >= 3) ...[
                  // Many ayahs: one pair marks them all, then fix the odd one.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.raised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'كل الآيات',
                            style: TextStyle(
                              color: p.title,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _mark(p, -1),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                for (var i = 0; i < ayahs.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            ayahs[i].surah == widget.question.start.surah
                                ? 'الآية ${ayahs[i].ayah}'
                                : '${ayahs[i].surahName} ${ayahs[i].ayah}',
                            style: TextStyle(
                              color: _verdict[i] == true ? p.bad : p.text,
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
                    // Only once every ayah has been judged.
                    onPressed: _allMarked ? _submit : null,
                    child: Text(
                      widget.hasNext ? 'السؤال التالي' : 'النتيجة',
                      style: _buttonText,
                    ),
                  ),
                ),
                if (_allMarked)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'ينتقل بعد لحظة؛ غيّر ما شئت قبل ذلك.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.sub, fontSize: 12),
                    ),
                  ),
                Center(
                  child: TextButton(
                    onPressed: () {
                      _auto?.cancel();
                      Navigator.of(context).pop(
                        const HifzSelfJudgement(correct: null, next: false),
                      );
                    },
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
                  run.silent && run.endless
                      ? 'اختبار ذاتي مفتوح: ${pagesCount(run.pagesRead)}'
                      : 'نتيجة الاختبار: ${run.correct} من ${run.answered}',
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
                  '${run.silent ? ' · اختبار ذاتي' : ''}${run.endless ? ' · مفتوح' : ''}'
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
                            '${i + 1}. ${run.questionOf(i).title}'
                            '${!run.silent && !run.isCorrect(i) ? ' — ${notesCount(run.results[i].errors.length)}' : ''}',
                            style: TextStyle(color: p.text, fontSize: 14, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!run.endless && run.answered < run.questions.length)
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

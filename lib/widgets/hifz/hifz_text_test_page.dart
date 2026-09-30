import 'package:flutter/material.dart';

import '../../services/hifz_test_plan.dart';
import '../../services/tasmee_report_store.dart';
import '../../services/tasmee_weak_point_store.dart';
import '../../utils/quran_display_text.dart';
import 'hifz_palette.dart';

/// «اختبار نصّي»: one ayah is shown, the reader says the next one from
/// memory (aloud or silently, no microphone), uncovers it and judges
/// themself. A miss is kept with the Tasmee mistakes so later tests come
/// back to it; a hit on a kept mistake counts towards retiring it.
class HifzTextTestPage extends StatefulWidget {
  const HifzTextTestPage({
    super.key,
    required this.questions,
    required this.config,
    required this.onGoToPage,
  });

  /// Planned with one ayah per question: [HifzTestQuestion.before] is
  /// shown, [HifzTestQuestion.start] is the answer.
  final List<HifzTestQuestion> questions;
  final HifzTestConfig config;

  /// Opens the mushaf at a 1-based page (the test page closes first).
  final void Function(int page) onGoToPage;

  @override
  State<HifzTextTestPage> createState() => _HifzTextTestPageState();
}

class _HifzTextTestPageState extends State<HifzTextTestPage> {
  int _i = 0;
  bool _revealed = false;

  /// Per question: null until judged, then whether the reader got it.
  late final List<bool?> _results = List<bool?>.filled(widget.questions.length, null);

  bool get _done => _i >= widget.questions.length;
  int get _correct => _results.where((r) => r == true).length;
  int get _answered => _results.where((r) => r != null).length;

  HifzTestQuestion get _q => widget.questions[_i];

  void _judge(bool hit) {
    final q = _q;
    setState(() => _results[_i] = hit);
    final now = DateTime.now();
    if (hit) {
      if (q.fromMistakes) {
        TasmeeWeakPointStore.notePassed(q.targets.map((t) => t.key), now);
      }
    } else {
      final firstWord = q.start.text
          .split(RegExp(r'\s+'))
          .firstWhere((w) => w.isNotEmpty, orElse: () => '');
      TasmeeWeakPointStore.addErrors(
        q.start.page,
        [
          TasmeeError(
            surah: q.start.surah,
            ayah: q.start.ayah,
            wordInAyah: 1,
            expected: firstWord,
            kind: 'recall',
          ),
        ],
        now,
      );
    }
  }

  void _next() => setState(() {
        _i++;
        _revealed = false;
      });

  void _open(int page) {
    Navigator.of(context).pop();
    widget.onGoToPage(page);
  }

  Widget _ayahCard(HifzPalette p, String heading, String text, {bool answer = false}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: answer ? p.title : p.border, width: answer ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: TextStyle(color: p.sub, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              quranDisplayText(text),
              textAlign: TextAlign.right,
              style: TextStyle(color: p.text, fontSize: 22, height: 1.9),
            ),
          ],
        ),
      );

  Widget _button(
    HifzPalette p,
    String label, {
    required VoidCallback onTap,
    bool filled = true,
    Color? color,
  }) {
    final c = color ?? p.title;
    final style = filled
        ? FilledButton.styleFrom(
            backgroundColor: c,
            foregroundColor: p.onTitle,
            padding: const EdgeInsets.symmetric(vertical: 12),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: c,
            side: BorderSide(color: c),
            padding: const EdgeInsets.symmetric(vertical: 12),
          );
    final text = Text(
      label,
      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
    );
    return filled
        ? FilledButton(style: style, onPressed: onTap, child: text)
        : OutlinedButton(style: style, onPressed: onTap, child: text);
  }

  Widget _question(HifzPalette p) {
    final q = _q;
    final before = q.before;
    final answered = _results[_i] != null;
    final last = _i == widget.questions.length - 1;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        Text(
          'السؤال ${_i + 1} من ${widget.questions.length}',
          style: TextStyle(color: p.sub, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (before != null)
          _ayahCard(p, 'سورة ${before.surahName} · الآية ${before.ayah}', before.text)
        else
          _ayahCard(p, 'سورة ${q.start.surahName}', 'أول السورة'),
        const SizedBox(height: 12),
        Text(
          before != null ? 'اذكر الآية التالية من حفظك.' : 'اذكر أول آية من السورة من حفظك.',
          style: TextStyle(color: p.title, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (!_revealed)
          _button(p, 'أظهر الآية', onTap: () => setState(() => _revealed = true))
        else ...[
          _ayahCard(p, 'الآية ${q.start.ayah}', q.start.text, answer: true),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _open(q.start.page),
              icon: Icon(Icons.menu_book_rounded, size: 18, color: p.title),
              label: Text(
                'افتح الصفحة ${q.start.page} في المصحف',
                style: TextStyle(color: p.title, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (!answered)
            Row(
              children: [
                Expanded(
                  child: _button(p, 'أصبتُ', color: p.good, onTap: () => _judge(true)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _button(p, 'أخطأتُ', color: p.bad, onTap: () => _judge(false)),
                ),
              ],
            )
          else ...[
            Row(
              children: [
                Icon(
                  _results[_i]! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: _results[_i]! ? p.good : p.bad,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Text(
                  _results[_i]! ? 'أحسنت' : 'حُفظت لتُختبر فيها لاحقًا',
                  style: TextStyle(color: p.text, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _button(p, last ? 'النتيجة' : 'السؤال التالي', onTap: _next),
          ],
        ],
      ],
    );
  }

  Widget _summary(HifzPalette p) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        Text(
          'النتيجة: $_correct من $_answered',
          style: TextStyle(
            color: p.title,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFamily: 'Tajawal',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.config.range.label,
          style: TextStyle(color: p.sub, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < widget.questions.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              switch (_results[i]) {
                true => Icons.check_circle_rounded,
                false => Icons.cancel_rounded,
                null => Icons.remove_circle_outline_rounded,
              },
              color: switch (_results[i]) {
                true => p.good,
                false => p.bad,
                null => p.sub,
              },
            ),
            title: Text(
              '${i + 1}. ${widget.questions[i].title}',
              style: TextStyle(color: p.text, fontSize: 14),
            ),
            trailing: Icon(Icons.menu_book_rounded, color: p.title, size: 20),
            onTap: () => _open(widget.questions[i].start.page),
          ),
        const SizedBox(height: 14),
        _button(p, 'إغلاق', onTap: () => Navigator.of(context).pop()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.bg,
          foregroundColor: p.title,
          title: const Text('اختبار نصّي'),
          actions: [
            if (!_done)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 16),
                child: Center(
                  child: Text(
                    '$_correct / $_answered',
                    style: TextStyle(color: p.sub, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
        body: _done ? _summary(p) : _question(p),
      ),
    );
  }
}

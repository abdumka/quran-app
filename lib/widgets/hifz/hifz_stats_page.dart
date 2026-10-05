import 'package:flutter/material.dart';

import '../../quran_index_page.dart' show kQuranPageCount;
import '../../services/hifz_test_stats_store.dart';
import '../../services/tasmee_report_store.dart';
import '../../utils/quran_display_text.dart';
import 'hifz_palette.dart';

/// «الإحصاءات»: what the saved Tasmee reports and test records add up to --
/// pace per page and per hizb, mistakes, stops and corrections; tests taken
/// and their scores.
class HifzStatsPage extends StatefulWidget {
  const HifzStatsPage({super.key});

  @override
  State<HifzStatsPage> createState() => _HifzStatsPageState();
}

class _HifzStatsPageState extends State<HifzStatsPage> {
  late Future<(List<TasmeeReport>, List<HifzTestRecord>)> _data = _load();

  static Future<(List<TasmeeReport>, List<HifzTestRecord>)> _load() async =>
      (await TasmeeReportStore.loadAll(), await HifzTestStatsStore.loadAll());

  static String duration(num seconds) {
    final s = seconds.round();
    if (s < 60) return '$s ث';
    final m = s ~/ 60;
    if (m < 60) return '$m د ${s % 60} ث';
    return '${m ~/ 60} س ${m % 60} د';
  }

  static String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _stat(HifzPalette p, String label, String value, {String? note}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: p.sub, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: p.title,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Tajawal',
              ),
            ),
            if (note != null)
              Text(note, style: TextStyle(color: p.sub, fontSize: 11)),
          ],
        ),
      );

  Widget _grid(List<Widget> tiles) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.1,
        children: tiles,
      );

  Widget _heading(HifzPalette p, String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: p.title,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            fontFamily: 'Tajawal',
          ),
        ),
      );

  List<Widget> _tasmee(HifzPalette p, List<TasmeeReport> reports) {
    if (reports.isEmpty) {
      return [
        Text('لا جلسات تسميع محفوظة بعد.', style: TextStyle(color: p.sub)),
      ];
    }
    final finished = reports.where((r) => r.finished).toList();
    final pages = finished.length;
    final seconds = finished.fold<int>(0, (s, r) => s + r.seconds);
    final perPage = pages == 0 ? 0.0 : seconds / pages;
    // The mushaf's 602 pages over 60 hizbs and 30 juz.
    final perHizb = perPage * kQuranPageCount / 60;
    final perJuz = perPage * kQuranPageCount / 30;
    final errors = reports.fold<int>(0, (s, r) => s + r.errors.length);
    final holds = reports.fold<int>(0, (s, r) => s + r.holds);
    final repairs = reports.fold<int>(0, (s, r) => s + r.repairs);
    final allSeconds = reports.fold<int>(0, (s, r) => s + r.seconds);
    final kinds = <String, int>{};
    final categories = <String, int>{};
    for (final r in reports) {
      for (final e in r.errors) {
        kinds[e.kindLabel] = (kinds[e.kindLabel] ?? 0) + 1;
        categories[e.category] = (categories[e.category] ?? 0) + 1;
      }
    }
    final topKinds = kinds.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final thisWeek = reports.where((r) => r.at.isAfter(weekAgo)).length;
    final cleanPages = reports.where((r) => r.errors.isEmpty).length;
    return [
      _grid([
        _stat(p, 'صفحات سُمِّعت', '${reports.length}', note: '$pages مكتملة · $thisWeek هذا الأسبوع'),
        _stat(p, 'زمن التسميع', duration(allSeconds)),
        _stat(
          p,
          'الصفحة الواحدة',
          pages == 0 ? '—' : duration(perPage),
          note: 'متوسط الصفحة المكتملة',
        ),
        _stat(
          p,
          'الحزب تقديرًا',
          pages == 0 ? '—' : duration(perHizb),
          note: pages == 0 ? null : 'الجزء: ${duration(perJuz)}',
        ),
        _stat(
          p,
          'الأخطاء',
          '$errors',
          note: '${(errors / reports.length).toStringAsFixed(1)} في الصفحة · ${pagesCount(cleanPages)} بلا أخطاء',
        ),
        _stat(
          p,
          'توقّفات وتصويبات',
          '$holds / $repairs',
          note: 'مرات التوقف عند كلمة / أعدتها صحيحة',
        ),
      ]),
      if (errors > 0) ...[
        const SizedBox(height: 8),
        Text(
          [
            for (final c in const ['repaired', 'asked', 'wrong'])
              '${TasmeeError.categoryLabel(c)} ${categories[c] ?? 0}',
          ].join(' · '),
          style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.5),
        ),
      ],
      if (topKinds.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          'أكثر الأخطاء: ${topKinds.take(3).map((e) => '${e.key} (${e.value})').join('، ')}',
          style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.5),
        ),
      ],
    ];
  }

  List<Widget> _tests(HifzPalette p, List<HifzTestRecord> tests) {
    if (tests.isEmpty) {
      return [Text('لم تُجرَ اختبارات بعد.', style: TextStyle(color: p.sub))];
    }
    final answered = tests.fold<int>(0, (s, t) => s + t.answered);
    final correct = tests.fold<int>(0, (s, t) => s + t.correct);
    final best = tests.map((t) => t.percent).reduce((a, b) => a > b ? a : b);
    final seconds = tests.fold<int>(0, (s, t) => s + t.seconds);
    final recent = tests.take(5).toList();
    final recentAnswered = recent.fold<int>(0, (s, t) => s + t.answered);
    final recentCorrect = recent.fold<int>(0, (s, t) => s + t.correct);
    return [
      _grid([
        _stat(p, 'اختبارات', '${tests.length}', note: 'زمنها ${duration(seconds)}'),
        _stat(
          p,
          'النتيجة',
          answered == 0 ? '—' : '${(correct * 100 / answered).round()}٪',
          note: '$correct من ${questionsCount(answered)} · الأفضل $best٪',
        ),
        _stat(
          p,
          'آخر ٥ اختبارات',
          recentAnswered == 0 ? '—' : '${(recentCorrect * 100 / recentAnswered).round()}٪',
        ),
        _stat(p, 'مواضع الخطأ فيها', '${tests.fold<int>(0, (s, t) => s + t.mistakes)}'),
      ]),
      const SizedBox(height: 8),
      for (final t in tests.take(15))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            t.silent ? Icons.visibility_off_rounded : Icons.mic_rounded,
            color: p.title,
            size: 20,
          ),
          title: Text(
            '${t.correct} من ${t.answered} — ${t.range}',
            style: TextStyle(color: p.text, fontSize: 14),
          ),
          subtitle: Text(
            '${date(t.at)} · ${duration(t.seconds)}'
            '${t.answered < t.questions ? ' · لم يكتمل' : ''}',
            style: TextStyle(color: p.sub, fontSize: 12),
          ),
          trailing: Text(
            '${t.percent}٪',
            style: TextStyle(color: p.title, fontWeight: FontWeight.bold),
          ),
        ),
    ];
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
          title: const Text('إحصاءات الحفظ'),
        ),
        body: FutureBuilder<(List<TasmeeReport>, List<HifzTestRecord>)>(
          future: _data,
          builder: (context, snap) {
            final data = snap.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              onRefresh: () async => setState(() => _data = _load()),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  _heading(p, 'التسميع'),
                  ..._tasmee(p, data.$1),
                  _heading(p, 'الاختبارات'),
                  ..._tests(p, data.$2),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

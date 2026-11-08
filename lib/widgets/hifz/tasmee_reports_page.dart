import 'package:flutter/material.dart';

import 'hifz_clear_sheet.dart';
import 'hifz_palette.dart';
import '../../services/hifz_data_cleaner.dart';
import '../../services/tasmee_report_store.dart';
import '../../utils/quran_display_text.dart';

/// «تقارير التسميع والأخطاء»: the saved reports, one row per recited page
/// (tab «الجلسات»), and the same mistakes gathered per word across all of
/// them (tab «الأخطاء»), filed as stumbled-then-corrected, asked for with
/// a button, or never put right.
class TasmeeReportsPage extends StatefulWidget {
  const TasmeeReportsPage({super.key, this.onGoToPage});

  /// Opens the mushaf at a 1-based page (the reports page closes first).
  final void Function(int page)? onGoToPage;

  @override
  State<TasmeeReportsPage> createState() => _TasmeeReportsPageState();
}

class _TasmeeReportsPageState extends State<TasmeeReportsPage> {
  late Future<List<TasmeeReport>> _reports = TasmeeReportStore.loadAll();

  void _reload() {
    if (mounted) setState(() => _reports = TasmeeReportStore.loadAll());
  }

  /// 🗑: old mistakes in bulk (the same sheet as the statistics' clear).
  Future<void> _clear() async {
    final done = await showHifzClearSheet(context, forMistakes: true);
    if (done == null || !mounted) return;
    showHifzClearedSnack(
      context,
      undo: done.undo,
      summary: done.summary,
      reload: _reload,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: p.bg,
            foregroundColor: p.title,
            title: const Text('تقارير التسميع والأخطاء'),
            actions: [
              IconButton(
                tooltip: 'حذف الأخطاء',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _clear,
              ),
            ],
            bottom: TabBar(
              labelColor: p.title,
              unselectedLabelColor: p.sub,
              indicatorColor: p.title,
              tabs: const [
                Tab(text: 'الجلسات'),
                Tab(text: 'الأخطاء'),
              ],
            ),
          ),
          body: FutureBuilder<List<TasmeeReport>>(
            future: _reports,
            builder: (context, snap) {
              final list = snap.data;
              if (list == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return TabBarView(
                children: [
                  _sessions(p, list),
                  _MistakesLog(
                    reports: list,
                    onGoToPage: widget.onGoToPage,
                    onChanged: _reload,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sessions(HifzPalette p, List<TasmeeReport> list) {
    if (list.isEmpty) {
      return Center(
        child: Text('لا تقارير بعد', style: TextStyle(color: p.sub)),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView.separated(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        itemCount: list.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: p.border),
        itemBuilder: (context, i) => TasmeeReportTile(report: list[i]),
      ),
    );
  }
}

/// One line of an error as the report tile shows it.
String tasmeeErrorLine(TasmeeError e) => quranDisplayText(
  e.kind == 'extra' && e.heard.isNotEmpty
      ? '${e.kindLabel}: «${e.heard}» قبل «${e.expected}»'
      : '${e.kindLabel}: «${e.expected}»',
);

class TasmeeReportTile extends StatelessWidget {
  const TasmeeReportTile({super.key, required this.report});

  final TasmeeReport report;

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    final r = report;
    final d = r.at;
    final when =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    // Only counted mistakes make a page "with mistakes"; the microphone's
    // stops are listed too, as alerts (TasmeeError.counts).
    final mistakes = r.mistakes.length;
    final clean = mistakes == 0;
    final alerts = r.alerts;
    return ExpansionTile(
      iconColor: p.title,
      collapsedIconColor: p.title,
      leading: Icon(
        clean ? Icons.check_circle_rounded : Icons.error_outline_rounded,
        color: clean ? p.good : Color(0xFFE08A00),
      ),
      title: Text(
        'الصفحة ${r.page}${r.finished ? '' : ' (غير مكتملة)'}',
        style: TextStyle(color: p.title, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '$when · ${r.correct} من ${r.words} كلمة · '
        '${clean ? 'بلا أخطاء' : notesCount(mistakes)}'
        '${alerts > 0 ? ' · تنبيهات لا تُحسب $alerts' : ''}',
        style: TextStyle(color: p.sub, fontSize: 12.5),
      ),
      children: [
        if (r.errors.isEmpty)
          Padding(
            padding: EdgeInsets.all(12),
            child: Text('أحسنت، لا ملاحظات.', style: TextStyle(color: p.sub)),
          ),
        for (final e in r.errors)
          ListTile(
            dense: true,
            leading: Icon(
              switch (e.category) {
                'repaired' => Icons.check_circle_outline_rounded,
                'asked' => Icons.lightbulb_outline_rounded,
                _ => Icons.close_rounded,
              },
              size: 20,
              color: switch (e.category) {
                'repaired' => p.good,
                'asked' => const Color(0xFFE08A00),
                _ => p.bad,
              },
            ),
            title: Text(
              tasmeeErrorLine(e),
              style: TextStyle(color: p.text, fontSize: 15),
            ),
            subtitle: Text(
              quranDisplayText(
                'الآية ${e.ayah}، الكلمة ${e.wordInAyah}'
                '${e.heard.isEmpty || e.kind == 'extra' ? '' : ' — قرأت «${e.heard}»'}'
                '${e.repaired ? ' — ثم أصبتها' : ''}',
              ),
              style: TextStyle(color: p.sub, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

/// One word of the mistakes log: every time it was missed, by category.
class _LogEntry {
  _LogEntry(this.surah, this.ayah, this.word, this.expected, this.page);
  final int surah;
  final int ayah;
  final int word;
  final String expected;
  int page;
  final Map<String, int> byCategory = {};
  DateTime last = DateTime(2000);
  int get count => byCategory.values.fold(0, (a, b) => a + b);
  String get key => '$surah:$ayah:$word';
}

/// The mistakes of every saved report gathered per word (see
/// [TasmeeError.category]); a chip row narrows to one category.
class _MistakesLog extends StatefulWidget {
  const _MistakesLog({
    required this.reports,
    this.onGoToPage,
    required this.onChanged,
  });
  final List<TasmeeReport> reports;
  final void Function(int page)? onGoToPage;

  /// After a word was deleted (and again after «تراجع»).
  final VoidCallback onChanged;

  @override
  State<_MistakesLog> createState() => _MistakesLogState();
}

class _MistakesLogState extends State<_MistakesLog> {
  String? _category; // null = all

  /// Words swiped away, hidden at once while the reload runs.
  final Set<String> _gone = {};

  Future<void> _delete(_LogEntry e) async {
    setState(() => _gone.add(e.key));
    final undo = await HifzDataCleaner.deleteWord(e.key);
    if (!mounted) return;
    showHifzClearedSnack(
      context,
      undo: undo,
      summary: quranDisplayText('حُذف «${e.expected}» من الأخطاء'),
      reload: () {
        if (mounted) setState(() => _gone.clear());
        widget.onChanged();
      },
    );
  }

  static const List<String> _categories = ['asked', 'repaired', 'wrong'];

  /// Entries newest-miss first, with the category totals.
  (List<_LogEntry>, Map<String, int>) _gather() {
    final byKey = <String, _LogEntry>{};
    final totals = <String, int>{};
    for (final r in widget.reports) {
      for (final e in r.errors) {
        if (e.surah <= 0 || e.ayah <= 0) continue;
        final key = '${e.surah}:${e.ayah}:${e.wordInAyah}';
        final entry = byKey[key] ??= _LogEntry(
          e.surah,
          e.ayah,
          e.wordInAyah,
          e.expected,
          r.page,
        );
        final c = e.category;
        entry.byCategory[c] = (entry.byCategory[c] ?? 0) + 1;
        totals[c] = (totals[c] ?? 0) + 1;
        if (r.at.isAfter(entry.last)) {
          entry.last = r.at;
          entry.page = r.page;
        }
      }
    }
    final list = [
      for (final e in byKey.values)
        if (!_gone.contains(e.key)) e,
    ]..sort((a, b) => b.last.compareTo(a.last));
    return (list, totals);
  }

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    final (all, totals) = _gather();
    final shown = _category == null
        ? all
        : [
            for (final e in all)
              if (e.byCategory.containsKey(_category)) e,
          ];
    if (all.isEmpty) {
      return Center(
        child: Text('لا أخطاء مسجّلة بعد', style: TextStyle(color: p.sub)),
      );
    }
    Widget chip(String label, String? value, int count) => ChoiceChip(
      label: Text('$label ($count)'),
      selected: _category == value,
      showCheckmark: false,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      selectedColor: p.title,
      backgroundColor: p.raised,
      side: BorderSide(color: p.border),
      labelStyle: TextStyle(
        color: _category == value ? p.onTitle : p.text,
        fontSize: 12.5,
      ),
      onSelected: (_) => setState(() => _category = value),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  chip('الكل', null, all.length),
                  for (final c in _categories)
                    chip(TasmeeError.categoryLabel(c), c, totals[c] ?? 0),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'من آخر ${widget.reports.length} صفحة سُمِّعت. بطلب: كشفتها بزر «كلمة» أو «الآية» '
                'أو تخطّيتها، وهذه وحدها تُحسب أخطاء. الباقي تنبيهات من الميكروفون (الكلمة الوردية) '
                'لا تُحسب. اسحب الكلمة جانبًا لحذفها.',
                style: TextStyle(color: p.sub, fontSize: 11.5, height: 1.4),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: shown.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: p.border),
            itemBuilder: (context, i) {
              final e = shown[i];
              final parts = [
                for (final c in _categories)
                  if ((e.byCategory[c] ?? 0) > 0)
                    '${TasmeeError.categoryLabel(c)} ×${e.byCategory[c]}',
              ];
              Widget swipeBg(AlignmentGeometry align) => Container(
                color: p.bad,
                alignment: align,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Text(
                  'حذف',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
              // A swipe either way deletes the word (with «تراجع»).
              return Dismissible(
                key: ValueKey(e.key),
                background: swipeBg(AlignmentDirectional.centerStart),
                secondaryBackground: swipeBg(AlignmentDirectional.centerEnd),
                onDismissed: (_) => _delete(e),
                child: ListTile(
                  dense: true,
                  title: Text(
                    quranDisplayText('«${e.expected}»'),
                    style: TextStyle(color: p.text, fontSize: 16),
                  ),
                  subtitle: Text(
                    'سورة ${e.surah}، الآية ${e.ayah}، الكلمة ${e.word} · صفحة ${e.page}\n'
                    '${parts.join(' · ')}',
                    style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.4),
                  ),
                  trailing: widget.onGoToPage == null
                      ? null
                      : Icon(Icons.menu_book_rounded, color: p.title, size: 20),
                  onTap: widget.onGoToPage == null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          widget.onGoToPage!(e.page);
                        },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Shown when a Tasmee run ends: the pages just recited with their errors.
Future<void> showTasmeeRunSummary(
  BuildContext context,
  List<TasmeeReport> reports,
) {
  final p = HifzPalette.of(context);
  final errors = reports.fold<int>(0, (a, r) => a + r.mistakes.length);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                  errors == 0
                      ? 'تقرير الجلسة: أحسنت، بلا أخطاء'
                      : 'تقرير الجلسة: ${notesCount(errors)} في ${pagesCount(reports.length)}',
                  style: TextStyle(
                    color: p.title,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                'يُحفظ التقرير في «أدوات الحفظ» ← «تقارير التسميع والأخطاء».',
                style: TextStyle(color: p.sub, fontSize: 12.5),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in reports) TasmeeReportTile(report: r),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

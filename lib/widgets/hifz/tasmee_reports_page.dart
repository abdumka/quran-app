import 'package:flutter/material.dart';

import 'hifz_palette.dart';
import '../../services/tasmee_report_store.dart';

/// Saved Tasmee reports: one row per recited page, newest first; tap a row
/// for its errors.
class TasmeeReportsPage extends StatefulWidget {
  const TasmeeReportsPage({super.key});

  @override
  State<TasmeeReportsPage> createState() => _TasmeeReportsPageState();
}

class _TasmeeReportsPageState extends State<TasmeeReportsPage> {
  late Future<List<TasmeeReport>> _reports = TasmeeReportStore.loadAll();

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
          title: const Text('تقارير التسميع'),
        ),
        body: FutureBuilder<List<TasmeeReport>>(
          future: _reports,
          builder: (context, snap) {
            final list = snap.data;
            if (list == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (list.isEmpty) {
              return Center(
                child: Text('لا تقارير بعد', style: TextStyle(color: p.sub)),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => setState(() => _reports = TasmeeReportStore.loadAll()),
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: p.border),
                itemBuilder: (context, i) => TasmeeReportTile(report: list[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

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
    final clean = r.errors.isEmpty;
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
        '${clean ? 'بلا أخطاء' : '${r.errors.length} ملاحظات'}',
        style: TextStyle(color: p.sub, fontSize: 12.5),
      ),
      children: [
        if (clean)
          Padding(
            padding: EdgeInsets.all(12),
            child: Text('أحسنت، لا ملاحظات.', style: TextStyle(color: p.sub)),
          ),
        for (final e in r.errors)
          ListTile(
            dense: true,
            title: Text(
              e.kind == 'extra' && e.heard.isNotEmpty
                  ? '${e.kindLabel}: «${e.heard}» قبل «${e.expected}»'
                  : '${e.kindLabel}: «${e.expected}»',
              style: TextStyle(color: p.text, fontSize: 15),
            ),
            subtitle: Text(
              'الآية ${e.ayah}، الكلمة ${e.wordInAyah}'
              '${e.heard.isEmpty || e.kind == 'extra' ? '' : ' — قرأت «${e.heard}»'}',
              style: TextStyle(color: p.sub, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

/// Shown when a Tasmee run ends: the pages just recited with their errors.
Future<void> showTasmeeRunSummary(BuildContext context, List<TasmeeReport> reports) {
  final p = HifzPalette.of(context);
  final errors = reports.fold<int>(0, (a, r) => a + r.errors.length);
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
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                  errors == 0
                      ? 'تقرير الجلسة: أحسنت، بلا أخطاء'
                      : 'تقرير الجلسة: $errors ملاحظات في ${reports.length} صفحات',
                  style: TextStyle(color: p.title, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                'يُحفظ التقرير في «أدوات الحفظ» ← «تقارير التسميع».',
                style: TextStyle(color: p.sub, fontSize: 12.5),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [for (final r in reports) TasmeeReportTile(report: r)],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

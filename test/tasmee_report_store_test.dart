import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_report_store.dart';

TasmeeReport _report(int page, int hour) => TasmeeReport(
      page: page,
      at: DateTime(2026, 9, 30, hour),
      seconds: 40,
      words: 100,
      correct: 90,
      errors: const [],
      finished: true,
      holds: 2,
      repairs: 1,
    );

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tasmee_reports_test');
    TasmeeReportStore.directoryOverride = dir;
  });

  tearDown(() {
    TasmeeReportStore.directoryOverride = null;
    dir.deleteSync(recursive: true);
  });

  test('reports are written whole and read back newest first', () async {
    await TasmeeReportStore.save(_report(5, 9));
    await TasmeeReportStore.save(_report(7, 11));
    expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    final all = await TasmeeReportStore.loadAll();
    expect(all.map((r) => r.page), [7, 5]);
    expect(all.first.holds, 2);
    expect(all.first.repairs, 1);
  });

  test('an empty or broken report file hides nothing else', () async {
    await TasmeeReportStore.save(_report(5, 9));
    // An install over the running app once left files like these behind.
    File('${dir.path}${Platform.pathSeparator}report_2026-09-30T22-05-31_p583.json')
        .writeAsStringSync('');
    File('${dir.path}${Platform.pathSeparator}report_2026-09-30T22-06-00_p584.json')
        .writeAsStringSync('{not json');
    final all = await TasmeeReportStore.loadAll();
    expect(all.map((r) => r.page), [5]);
    // The empty one is cleaned up; the broken one is left for inspection.
    expect(
      dir.listSync().map((f) => f.path.split(Platform.pathSeparator).last).toList()..sort(),
      ['report_2026-09-30T09-00-00_p5.json', 'report_2026-09-30T22-06-00_p584.json'],
    );
  });
}

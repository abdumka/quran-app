import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/hifz_data_cleaner.dart';
import 'package:islamic_dawah_mushaf/services/hifz_test_stats_store.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_report_store.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_weak_point_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final DateTime now = DateTime(2026, 11, 3, 12);

TasmeeError err(int word, String kind) => TasmeeError(
      surah: 2,
      ayah: 10,
      wordInAyah: word,
      expected: 'w$word',
      kind: kind,
    );

TasmeeReport report(int daysAgo, int page, List<TasmeeError> errors) => TasmeeReport(
      page: page,
      at: now.subtract(Duration(days: daysAgo)),
      seconds: 60,
      words: 100,
      correct: 90,
      errors: errors,
      finished: true,
    );

HifzTestRecord record(int daysAgo) => HifzTestRecord.fromJson({
      'at': now.subtract(Duration(days: daysAgo)).toIso8601String(),
      'silent': true,
      'source': 'random',
      'range': 'x',
      'questions': 3,
      'answered': 3,
      'correct': 2,
      'mistakes': 1,
      'seconds': 30,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    support = Directory.systemTemp.createTempSync('hifz_clear_');
    TasmeeReportStore.directoryOverride = Directory('${support.path}/reports');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );
    // Reports 1, 10 and 40 days old; tests 2 and 50 days old; pool points.
    await TasmeeReportStore.save(report(1, 5, [err(1, 'revealed'), err(2, 'word')]));
    await TasmeeReportStore.save(report(10, 6, [err(3, 'revealed')]));
    await TasmeeReportStore.save(report(40, 7, [err(4, 'skippedAyah')]));
    await HifzTestStatsStore.add(record(50));
    await HifzTestStatsStore.add(record(2));
    await TasmeeWeakPointStore.addErrors(5, [err(1, 'revealed')], now.subtract(const Duration(days: 1)));
    await TasmeeWeakPointStore.addErrors(7, [err(4, 'skippedAyah')], now.subtract(const Duration(days: 40)));
  });

  tearDown(() {
    TasmeeReportStore.directoryOverride = null;
    support.deleteSync(recursive: true);
  });

  test('ranges: recent, older and all, with Arabic labels', () {
    const week = HifzClearRange(HifzClearSpan.recent, 7);
    const old = HifzClearRange(HifzClearSpan.older, 30);
    expect(week.covers(now.subtract(const Duration(days: 6)), now), isTrue);
    expect(week.covers(now.subtract(const Duration(days: 8)), now), isFalse);
    expect(old.covers(now.subtract(const Duration(days: 31)), now), isTrue);
    expect(old.covers(now.subtract(const Duration(days: 29)), now), isFalse);
    expect(const HifzClearRange.all().covers(DateTime(2000), now), isTrue);
    expect(week.label, 'آخر 7 أيام');
    expect(old.label, 'أقدم من 30 يومًا');
    expect(const HifzClearRange(HifzClearSpan.recent, 2).label, 'آخر يومين');
    expect(const HifzClearRange.all().label, 'الكل');
  });

  test('the choice survives its prefs string', () {
    const c = HifzClearChoice(
      range: HifzClearRange(HifzClearSpan.older, 45),
      sessions: false,
      tests: true,
      mistakes: true,
    );
    final back = HifzClearChoice.decode(c.encode())!;
    expect(back.range, c.range);
    expect([back.sessions, back.tests, back.mistakes], [false, true, true]);
    expect(HifzClearChoice.decode('junk'), isNull);
  });

  test('counts follow the range', () async {
    final data = await HifzSavedData.load();
    const week = HifzClearRange(HifzClearSpan.recent, 7);
    expect(data.sessionsIn(week, now), 1);
    expect(data.testsIn(week, now), 1);
    // Words 1 and 2 of the 1-day report (word 1 is also in the pool).
    expect(data.mistakesIn(week, now), 2);
    expect(data.mistakesIn(const HifzClearRange.all(), now), 4);
  });

  test('clearing the last week removes only its sessions and tests; undo restores', () async {
    final undo = await HifzDataCleaner.clear(HifzClearChoice.statsDefault, now: now);
    var reports = await TasmeeReportStore.loadAll();
    expect(reports.map((r) => r.page), [6, 7]);
    expect((await HifzTestStatsStore.loadAll()).length, 1);
    expect((await TasmeeWeakPointStore.load()).length, 2, reason: 'mistakes not ticked');

    await HifzDataCleaner.undo(undo);
    reports = await TasmeeReportStore.loadAll();
    expect(reports.map((r) => r.page), [5, 6, 7]);
    expect((await HifzTestStatsStore.loadAll()).length, 2);
  });

  test('deleting old mistakes keeps the sessions but empties their errors and the pool', () async {
    final undo = await HifzDataCleaner.clear(HifzClearChoice.mistakesDefault, now: now);
    final reports = await TasmeeReportStore.loadAll();
    expect(reports.length, 3, reason: 'sessions stay');
    expect(reports.firstWhere((r) => r.page == 7).errors, isEmpty);
    expect(reports.firstWhere((r) => r.page == 5).errors.length, 2, reason: 'recent ones stay');
    expect((await TasmeeWeakPointStore.load()).map((p) => p.word), [1]);

    await HifzDataCleaner.undo(undo);
    expect((await TasmeeReportStore.loadAll()).firstWhere((r) => r.page == 7).errors.length, 1);
    expect((await TasmeeWeakPointStore.load()).length, 2);
  });

  test('one word goes from every report and from the pool', () async {
    final undo = await HifzDataCleaner.deleteWord('2:10:1');
    final reports = await TasmeeReportStore.loadAll();
    expect(reports.firstWhere((r) => r.page == 5).errors.map((e) => e.wordInAyah), [2]);
    expect((await TasmeeWeakPointStore.load()).map((p) => p.word), [4]);
    await HifzDataCleaner.undo(undo);
    expect((await TasmeeReportStore.loadAll()).firstWhere((r) => r.page == 5).errors.length, 2);
  });

  test('only button reveals, skips and recall count as mistakes', () {
    final r = report(0, 1, [err(1, 'word'), err(2, 'revealed'), err(3, 'skipped'), err(4, 'recall')]);
    expect(r.mistakes.map((e) => e.wordInAyah), [2, 4]);
    expect(r.alerts, 2);
  });
}

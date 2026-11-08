import 'package:shared_preferences/shared_preferences.dart';

import 'hifz_test_stats_store.dart';
import 'tasmee_report_store.dart';
import 'tasmee_weak_point_store.dart';

/// Which dates «مسح الإحصاءات» covers.
enum HifzClearSpan {
  /// The last [HifzClearRange.days] days.
  recent,

  /// Everything older than [HifzClearRange.days] days.
  older,

  /// Every date.
  all,
}

/// A span of dates to clear: «آخر 7 أيام», «أقدم من 30 يومًا», «الكل».
class HifzClearRange {
  const HifzClearRange(this.span, this.days);

  const HifzClearRange.all() : span = HifzClearSpan.all, days = 7;

  final HifzClearSpan span;

  /// Ignored for [HifzClearSpan.all] (kept so the stepper remembers it).
  final int days;

  static const int minDays = 1;
  static const int maxDays = 365;

  bool covers(DateTime at, DateTime now) {
    final cut = now.subtract(Duration(days: days));
    return switch (span) {
      HifzClearSpan.all => true,
      HifzClearSpan.recent => !at.isBefore(cut),
      HifzClearSpan.older => at.isBefore(cut),
    };
  }

  /// «آخر 7 أيام», «أقدم من يومين», «الكل».
  String get label => switch (span) {
    HifzClearSpan.all => 'الكل',
    HifzClearSpan.recent => 'آخر ${_days(days)}',
    HifzClearSpan.older => 'أقدم من ${_days(days)}',
  };

  static String _days(int n) => switch (n) {
    1 => 'يوم',
    2 => 'يومين',
    _ when n <= 10 => '$n أيام',
    _ => '$n يومًا',
  };

  @override
  bool operator ==(Object other) =>
      other is HifzClearRange &&
      other.span == span &&
      (span == HifzClearSpan.all || other.days == days);

  @override
  int get hashCode =>
      span == HifzClearSpan.all ? span.hashCode : Object.hash(span, days);
}

/// What to clear and over which dates; remembered per place it is opened
/// from (the statistics, the mistakes log).
class HifzClearChoice {
  const HifzClearChoice({
    required this.range,
    required this.sessions,
    required this.tests,
    required this.mistakes,
  });

  final HifzClearRange range;

  /// Tasmee page reports (time, pages, and the mistakes in them).
  final bool sessions;

  /// Test results (اختبار الحفظ / الاختبار الذاتي).
  final bool tests;

  /// Mistakes: taken out of the reports (which stay) and out of the pool
  /// the «من الأخطاء» tests are drawn from.
  final bool mistakes;

  bool get any => sessions || tests || mistakes;

  HifzClearChoice copyWith({
    HifzClearRange? range,
    bool? sessions,
    bool? tests,
    bool? mistakes,
  }) => HifzClearChoice(
    range: range ?? this.range,
    sessions: sessions ?? this.sessions,
    tests: tests ?? this.tests,
    mistakes: mistakes ?? this.mistakes,
  );

  String encode() =>
      '${range.span.name},${range.days},${sessions ? 1 : 0},${tests ? 1 : 0},${mistakes ? 1 : 0}';

  static HifzClearChoice? decode(String? s) {
    final parts = s?.split(',');
    if (parts == null || parts.length != 5) return null;
    final span = HifzClearSpan.values.where((v) => v.name == parts[0]);
    final days = int.tryParse(parts[1]);
    if (span.isEmpty || days == null) return null;
    return HifzClearChoice(
      range: HifzClearRange(
        span.first,
        days.clamp(HifzClearRange.minDays, HifzClearRange.maxDays).toInt(),
      ),
      sessions: parts[2] == '1',
      tests: parts[3] == '1',
      mistakes: parts[4] == '1',
    );
  }

  /// From the statistics page: the last week's sessions and tests.
  static const HifzClearChoice statsDefault = HifzClearChoice(
    range: HifzClearRange(HifzClearSpan.recent, 7),
    sessions: true,
    tests: true,
    mistakes: false,
  );

  /// From the mistakes log: mistakes older than a month.
  static const HifzClearChoice mistakesDefault = HifzClearChoice(
    range: HifzClearRange(HifzClearSpan.older, 30),
    sessions: false,
    tests: false,
    mistakes: true,
  );

  static String _pref(bool forMistakes) =>
      forMistakes ? 'hifz_clear_mistakes' : 'hifz_clear_stats';

  static Future<HifzClearChoice> load({required bool forMistakes}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final c = decode(prefs.getString(_pref(forMistakes)));
      if (c != null) return c;
    } catch (_) {}
    return forMistakes ? mistakesDefault : statsDefault;
  }

  Future<void> save({required bool forMistakes}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pref(forMistakes), encode());
    } catch (_) {}
  }
}

/// Everything saved that the clear sheet counts over.
class HifzSavedData {
  const HifzSavedData(this.reports, this.tests, this.pool);

  final List<TasmeeReport> reports;
  final List<HifzTestRecord> tests;
  final List<TasmeeWeakPoint> pool;

  static Future<HifzSavedData> load() async => HifzSavedData(
    await TasmeeReportStore.loadAll(),
    await HifzTestStatsStore.loadAll(),
    await TasmeeWeakPointStore.load(),
  );

  int sessionsIn(HifzClearRange r, DateTime now) =>
      reports.where((x) => r.covers(x.at, now)).length;

  int testsIn(HifzClearRange r, DateTime now) =>
      tests.where((x) => r.covers(x.at, now)).length;

  /// Distinct words with a mistake in [r]: in a report of those dates, or
  /// a «من الأخطاء» point last missed then.
  int mistakesIn(HifzClearRange r, DateTime now) => {
    for (final x in reports)
      if (r.covers(x.at, now))
        for (final e in x.errors) '${e.surah}:${e.ayah}:${e.wordInAyah}',
    for (final p in pool)
      if (r.covers(p.lastAt, now)) p.key,
  }.length;
}

/// What a clear took away, put back by [HifzDataCleaner.undo].
class HifzClearUndo {
  HifzClearUndo({this.reportFiles = const {}, this.tests, this.pool});

  final Map<String, String> reportFiles;
  final List<HifzTestRecord>? tests;
  final List<TasmeeWeakPoint>? pool;
}

/// «مسح الإحصاءات» and «حذف» in the mistakes log.
class HifzDataCleaner {
  static Future<HifzClearUndo> clear(HifzClearChoice c, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final range = c.range;
    var files = const <String, String>{};
    if (c.sessions || c.mistakes) {
      files = await TasmeeReportStore.edit((r) {
        if (!range.covers(r.at, at)) return r;
        if (c.sessions) return null;
        return r.errors.isEmpty ? r : r.withErrors((_) => false);
      });
    }
    final tests = c.tests
        ? await HifzTestStatsStore.removeWhere((t) => range.covers(t.at, at))
        : null;
    final pool = c.mistakes
        ? await TasmeeWeakPointStore.removeWhere(
            (p) => range.covers(p.lastAt, at),
          )
        : null;
    return HifzClearUndo(reportFiles: files, tests: tests, pool: pool);
  }

  /// Takes one word ("surah:ayah:word") out of every report and out of the
  /// «من الأخطاء» pool.
  static Future<HifzClearUndo> deleteWord(String key) async {
    bool other(TasmeeError e) => '${e.surah}:${e.ayah}:${e.wordInAyah}' != key;
    final files = await TasmeeReportStore.edit(
      (r) => r.errors.every(other) ? r : r.withErrors(other),
    );
    final pool = await TasmeeWeakPointStore.removeWhere((p) => p.key == key);
    return HifzClearUndo(reportFiles: files, pool: pool);
  }

  static Future<void> undo(HifzClearUndo u) async {
    await TasmeeReportStore.restore(u.reportFiles);
    final tests = u.tests;
    if (tests != null) await HifzTestStatsStore.replaceAll(tests);
    final pool = u.pool;
    if (pool != null) await TasmeeWeakPointStore.replaceAll(pool);
  }
}

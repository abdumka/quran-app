import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'tasmee_report_store.dart';

/// One place of the mushaf the reciter got wrong during Tasmee and has not
/// yet recited correctly in a strengthening drill.
class TasmeeWeakPoint {
  TasmeeWeakPoint({
    required this.surah,
    required this.ayah,
    required this.word,
    required this.page,
    required this.expected,
    required this.kind,
    this.heard = '',
    this.count = 1,
    DateTime? lastAt,
    this.passes = 0,
    this.lastPassAt,
  }) : lastAt = lastAt ?? DateTime.now();

  final int surah;
  final int ayah;

  /// 1-based position of the word inside its ayah.
  final int word;

  /// 1-based mushaf page the word was on when it was missed.
  final int page;
  final String expected;

  /// Kind of the latest error there (see [TasmeeError.kind]).
  String kind;
  String heard;

  /// How many times an error was recorded at this word.
  int count;
  DateTime lastAt;

  /// Days on which the word was then recited correctly in a test (a pass
  /// on the same day counts once); [TasmeeWeakPointStore.passesToClear]
  /// of them retire the point. A new miss starts the count over.
  int passes;
  DateTime? lastPassAt;

  String get key => '$surah:$ayah:$word';
  String get ayahKey => '$page:$surah:$ayah';

  Map<String, Object?> toJson() => {
        'surah': surah,
        'ayah': ayah,
        'word': word,
        'page': page,
        'expected': expected,
        'kind': kind,
        if (heard.isNotEmpty) 'heard': heard,
        'count': count,
        'lastAt': lastAt.toIso8601String(),
        if (passes > 0) 'passes': passes,
        if (lastPassAt != null) 'lastPassAt': lastPassAt!.toIso8601String(),
      };

  factory TasmeeWeakPoint.fromJson(Map<String, dynamic> j) => TasmeeWeakPoint(
        surah: j['surah'] as int? ?? 0,
        ayah: j['ayah'] as int? ?? 0,
        word: j['word'] as int? ?? 0,
        page: j['page'] as int? ?? 0,
        expected: j['expected'] as String? ?? '',
        kind: j['kind'] as String? ?? 'distance',
        heard: j['heard'] as String? ?? '',
        count: j['count'] as int? ?? 1,
        lastAt: DateTime.tryParse(j['lastAt'] as String? ?? ''),
        passes: j['passes'] as int? ?? 0,
        lastPassAt: DateTime.tryParse(j['lastPassAt'] as String? ?? ''),
      );
}

/// One strengthening drill or test question: recite from an ayah or two
/// before [ayah] up to its end; [targets] are the weak words inside it
/// (none for a random test question).
class TasmeeDrill {
  TasmeeDrill({
    required this.page,
    required this.surah,
    required this.ayah,
    required this.targets,
    this.index = 1,
    this.total = 1,
    this.title = 'تقوية الحفظ',
    this.cue,
    this.startPage,
    this.startAyahIndex,
    this.open = false,
  });

  /// An open-ended test question: it runs on until the reciter moves on
  /// (the bar offers «سؤال جديد»), or until [ayah] at the latest.
  final bool open;

  /// 1-based page holding the target ayah (where the drill ends).
  final int page;
  final int surah;
  final int ayah;
  final List<TasmeeWeakPoint> targets;

  /// Position of this drill in the run (for the "2 / 5" label).
  int index;
  int total;

  /// What the bar calls it («تقوية الحفظ», «اختبار»).
  final String title;

  /// Shown on the page while the drill runs: where to start and the words
  /// to continue from, for a start the covered page cannot show (a page's
  /// first ayah). Null: nothing shown.
  final String? cue;

  /// Where the drill begins, when the planner decided it (page and ayah
  /// index on that page); null: two ayahs before the target.
  final int? startPage;
  final int? startAyahIndex;

  String get label => '$title $index / $total';
}

/// Outcome of a drill: the weak words recited correctly and the ones that
/// still need work, plus every error made along the way.
class TasmeeDrillResult {
  const TasmeeDrillResult({
    required this.drill,
    required this.passed,
    required this.failed,
    this.errors = const [],
  });
  final TasmeeDrill drill;
  final List<TasmeeWeakPoint> passed;
  final List<TasmeeWeakPoint> failed;

  /// All errors noted between the drill's start and its end, on every page
  /// it ran over.
  final List<TasmeeError> errors;

  /// A drill with nothing to point at (a random test question) is clean
  /// when nothing at all went wrong.
  bool get clean => failed.isEmpty && errors.isEmpty;
}

/// The pool of weak points, fed by every Tasmee report and drained by the
/// strengthening drills. One JSON file in the app's support directory.
class TasmeeWeakPointStore {
  /// The drills open once this many weak points have been collected.
  static const int minToStart = 3;

  /// How many ayahs one run of drills covers at most.
  static const int maxDrillsPerRun = 10;

  static const int _maxPool = 2000;
  static Future<void> _queue = Future<void>.value();

  static Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}${Platform.pathSeparator}tasmee_weak_points.json');
  }

  static Future<List<TasmeeWeakPoint>> load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return [];
      final raw = json.decode(f.readAsStringSync()) as List<dynamic>;
      return [
        for (final e in raw)
          TasmeeWeakPoint.fromJson(e as Map<String, dynamic>),
      ];
    } catch (e) {
      debugPrint('TasmeeWeakPointStore: load failed: $e');
      return [];
    }
  }

  static Future<int> count() async => (await load()).length;

  static Future<void> _save(List<TasmeeWeakPoint> pool) async {
    try {
      final f = await _file();
      f.writeAsStringSync(json.encode([for (final p in pool) p.toJson()]));
    } catch (e) {
      debugPrint('TasmeeWeakPointStore: save failed: $e');
    }
  }

  /// Serializes read-modify-write cycles (reports of consecutive pages are
  /// saved moments apart).
  static Future<void> _locked(Future<void> Function() body) {
    final next = _queue.then((_) => body()).catchError((Object e) {
      debugPrint('TasmeeWeakPointStore: $e');
    });
    _queue = next;
    return next;
  }

  /// Adds the errors of one recited page to the pool.
  static Future<void> addErrors(int page, List<TasmeeError> errors, DateTime at) {
    if (errors.isEmpty) return Future<void>.value();
    return _locked(() async {
      final pool = await load();
      final byKey = {for (final p in pool) p.key: p};
      for (final e in errors) {
        if (e.surah <= 0 || e.ayah <= 0 || e.wordInAyah <= 0) continue;
        final key = '${e.surah}:${e.ayah}:${e.wordInAyah}';
        final have = byKey[key];
        if (have != null) {
          have
            ..count += 1
            ..kind = e.kind
            ..heard = e.heard
            ..lastAt = at
            ..passes = 0
            ..lastPassAt = null;
        } else {
          final p = TasmeeWeakPoint(
            surah: e.surah,
            ayah: e.ayah,
            word: e.wordInAyah,
            page: page,
            expected: e.expected,
            kind: e.kind,
            heard: e.heard,
            lastAt: at,
          );
          byKey[key] = p;
          pool.add(p);
        }
      }
      if (pool.length > _maxPool) {
        pool.sort((a, b) => b.lastAt.compareTo(a.lastAt));
        pool.removeRange(_maxPool, pool.length);
      }
      await _save(pool);
    });
  }

  /// Removes weak points the reciter has now recited correctly in a drill.
  static Future<void> resolve(Iterable<String> keys) {
    final gone = keys.toSet();
    if (gone.isEmpty) return Future<void>.value();
    return _locked(() async {
      final pool = await load();
      pool.removeWhere((p) => gone.contains(p.key));
      await _save(pool);
    });
  }

  /// Passes on different days that retire a weak point: one good reading
  /// proves little, the same word right again another day proves it is
  /// learnt.
  static const int passesToClear = 2;

  /// Records that the words [keys] were recited correctly in a test at
  /// [at]; a point retires once [passesToClear] different days have passed
  /// it.
  static Future<void> notePassed(Iterable<String> keys, DateTime at) {
    final passed = keys.toSet();
    if (passed.isEmpty) return Future<void>.value();
    return _locked(() async {
      await _save(applyPass(await load(), passed, at));
    });
  }

  /// The pool after the words [passed] were recited correctly at [at]
  /// (pure; [notePassed] persists it).
  static List<TasmeeWeakPoint> applyPass(
    List<TasmeeWeakPoint> pool,
    Set<String> passed,
    DateTime at,
  ) {
    final out = <TasmeeWeakPoint>[];
    for (final p in pool) {
      if (!passed.contains(p.key)) {
        out.add(p);
        continue;
      }
      final last = p.lastPassAt;
      final sameDay = last != null &&
          last.year == at.year &&
          last.month == at.month &&
          last.day == at.day;
      if (!sameDay) {
        p.passes += 1;
        p.lastPassAt = at;
      }
      if (p.passes < passesToClear) out.add(p);
    }
    return out;
  }

  static Future<void> clear() => _locked(() => _save([]));

  /// Groups the pool into drills, one per ayah: most-missed first, then the
  /// ones missed longest ago.
  static List<TasmeeDrill> plan(List<TasmeeWeakPoint> pool) {
    final groups = <String, List<TasmeeWeakPoint>>{};
    for (final p in pool) {
      (groups[p.ayahKey] ??= []).add(p);
    }
    final list = groups.values.toList()
      ..sort((a, b) {
        int weight(List<TasmeeWeakPoint> g) => g.fold(0, (s, p) => s + p.count);
        final w = weight(b).compareTo(weight(a));
        if (w != 0) return w;
        DateTime oldest(List<TasmeeWeakPoint> g) =>
            g.map((p) => p.lastAt).reduce((x, y) => x.isBefore(y) ? x : y);
        return oldest(a).compareTo(oldest(b));
      });
    final drills = [
      for (final g in list.take(maxDrillsPerRun))
        TasmeeDrill(
          page: g.first.page,
          surah: g.first.surah,
          ayah: g.first.ayah,
          targets: g..sort((a, b) => a.word.compareTo(b.word)),
        ),
    ];
    for (var i = 0; i < drills.length; i++) {
      drills[i]
        ..index = i + 1
        ..total = drills.length;
    }
    return drills;
  }
}

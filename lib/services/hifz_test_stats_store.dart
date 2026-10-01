import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'hifz_test_plan.dart';

/// One finished (or abandoned) test, as the statistics page shows it.
class HifzTestRecord {
  const HifzTestRecord({
    required this.at,
    required this.silent,
    required this.source,
    required this.range,
    required this.questions,
    required this.answered,
    required this.correct,
    required this.mistakes,
    required this.seconds,
  });

  final DateTime at;
  final bool silent;
  final String source;

  /// The range as the setup sheet described it («سورة البقرة»).
  final String range;
  final int questions;
  final int answered;
  final int correct;
  final int mistakes;
  final int seconds;

  /// Score in percent of the questions answered (0 when none).
  int get percent => answered == 0 ? 0 : (correct * 100 / answered).round();

  factory HifzTestRecord.ofRun(HifzTestRun run, DateTime at) => HifzTestRecord(
        at: at,
        silent: run.silent,
        source: run.config.source.name,
        range: run.config.range.label,
        questions: run.questions.length,
        answered: run.answered,
        correct: run.correct,
        mistakes: run.mistakes,
        seconds: at.difference(run.startedAt).inSeconds,
      );

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'silent': silent,
        'source': source,
        'range': range,
        'questions': questions,
        'answered': answered,
        'correct': correct,
        'mistakes': mistakes,
        'seconds': seconds,
      };

  factory HifzTestRecord.fromJson(Map<String, dynamic> j) => HifzTestRecord(
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2000),
        silent: j['silent'] as bool? ?? false,
        source: j['source'] as String? ?? 'random',
        range: j['range'] as String? ?? '',
        questions: j['questions'] as int? ?? 0,
        answered: j['answered'] as int? ?? 0,
        correct: j['correct'] as int? ?? 0,
        mistakes: j['mistakes'] as int? ?? 0,
        seconds: j['seconds'] as int? ?? 0,
      );
}

/// Every test taken, newest first, in one JSON file in the app's support
/// directory (kept to the last [_keep]).
class HifzTestStatsStore {
  static const int _keep = 500;
  static Future<void> _queue = Future<void>.value();

  static Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}${Platform.pathSeparator}hifz_tests.json');
  }

  static Future<List<HifzTestRecord>> loadAll() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return const [];
      final raw = json.decode(f.readAsStringSync()) as List<dynamic>;
      return [
        for (final e in raw) HifzTestRecord.fromJson(e as Map<String, dynamic>),
      ];
    } catch (e) {
      debugPrint('HifzTestStatsStore: load failed: $e');
      return const [];
    }
  }

  static Future<void> add(HifzTestRecord record) {
    final next = _queue.then((_) async {
      try {
        final list = [record, ...await loadAll()];
        if (list.length > _keep) list.removeRange(_keep, list.length);
        final f = await _file();
        f.writeAsStringSync(json.encode([for (final r in list) r.toJson()]));
      } catch (e) {
        debugPrint('HifzTestStatsStore: save failed: $e');
      }
    });
    _queue = next;
    return next;
  }
}

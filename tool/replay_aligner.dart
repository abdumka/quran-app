// Replays recognized segments (as produced offline by
// tasmee_work/segments.py from a real session WAV) through the exact
// QuranWordAligner the app uses, and prints the per-word verdicts.
//
//   dart run tool/replay_aligner.dart <segments.json>
//
// segments.json: {"page": N, "segments": [{"text": "...", "final": true}, ...]}
// Expected words come from assets/data/output.json.
import 'dart:convert';
import 'dart:io';

import 'package:islamic_dawah_mushaf/utils/quran_word_aligner.dart';

void main(List<String> args) {
  final input = jsonDecode(File(args[0]).readAsStringSync()) as Map;
  final page = input['page'] as int;
  final pages = jsonDecode(
    File('assets/data/output.json').readAsStringSync(),
  ) as List;
  final pageData = pages.whereType<Map>().firstWhere((p) => p['page'] == page);
  final words = <String>[];
  final ayahOf = <int>[];
  for (final ayah in pageData['ayahs'] as List) {
    for (final w in (ayah['text'] as String).split(RegExp(r'\s+'))) {
      if (w.isEmpty) continue;
      words.add(w);
      ayahOf.add(ayah['ayah'] as int);
    }
  }
  final aligner = QuranWordAligner(words);
  var carried = 0; // unused budget carried over, as the service does
  for (final seg in input['segments'] as List) {
    final text = seg['text'] as String;
    final isFinal = seg['final'] as bool;
    final speechMs = (seg['speechMs'] as num?)?.toInt() ?? -1;
    final own = speechMs < 0 ? 0 : (speechMs * 4.0 / 1000).ceil() + 2;
    final maxNew = own > 0 ? own + carried : 0;
    final before = aligner.cursor;
    final out = aligner.submitRecognizedSegment(
      text,
      isFinal: isFinal,
      maxNewWords: maxNew,
    );
    if (maxNew > 0) {
      carried = (maxNew - out.correct.length).clamp(0, 20);
    }
    stdout.writeln(
      '${isFinal ? 'F' : 'i'}${maxNew > 0 ? maxNew.toString().padLeft(2) : '  '} ${before.toString().padLeft(3)}->'
      '${aligner.cursor.toString().padLeft(3)} '
      'ok=${out.correct} sk=${out.skipped} mi=${out.mistakes} '
      'un=${out.unclearIndex} rep=${out.repeatOfHistory}  «$text»',
    );
  }
  final counts = <WordStatus, int>{};
  for (var i = 0; i < aligner.cursor; i++) {
    counts[aligner.statuses[i]] = (counts[aligner.statuses[i]] ?? 0) + 1;
  }
  stdout.writeln('--- reached word ${aligner.cursor}/${words.length}: $counts');
  final bad = <String>[];
  for (var i = 0; i < aligner.cursor; i++) {
    final s = aligner.statuses[i];
    if (s == WordStatus.skipped || s == WordStatus.mistake) {
      bad.add('${ayahOf[i]}:${words[i]}(${s.name[0]})');
    }
  }
  stdout.writeln('--- flagged: ${bad.join(' ')}');
}

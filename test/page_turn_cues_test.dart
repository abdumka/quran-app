import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/page_span_data.dart';
import 'package:islamic_dawah_mushaf/page_turn_cues.dart';

/// Guards the per-reciter page-turn moments (lib/page_turn_cues.dart).
///
/// Five ayat are printed across a page break, and during التلاوة the page turns
/// when the sheikh finishes the last word on the earlier page. Where that is
/// differs for every recording, so it is measured per reciter. A reciter
/// without measurements falls back to an estimate (AudioService._pageTurnFor),
/// which is why a missing entry fails here rather than in the app.
///
/// After adding a reciter to [Reciter.all], or re-uploading one's audio, run in
/// WSL from the repo root:
///
///     /root/quran-venv/bin/python tools/measure_page_turn_cues.py --only <id>
void main() {
  final pages = <int, List<Map<String, dynamic>>>{};

  setUpAll(() {
    final decoded = json.decode(
      File('assets/data/output.json').readAsStringSync(),
    );
    void add(Object? item) {
      if (item is List) {
        for (final sub in item) {
          add(sub);
        }
      } else if (item is Map<String, dynamic>) {
        pages[item['page'] as int] = (item['ayahs'] as List)
            .cast<Map<String, dynamic>>();
      }
    }

    add(decoded);
  });

  test('every offered reciter has a moment for every page-spanning ayah', () {
    for (final reciter in Reciter.all) {
      final cues = pageTurnCues[reciter.id];
      expect(
        cues,
        isNotNull,
        reason:
            '${reciter.id} has no page-turn cues — run '
            'tools/measure_page_turn_cues.py --only ${reciter.id}',
      );
      expect(
        cues!.keys.toSet(),
        spannedAyahHead.keys.toSet(),
        reason: '${reciter.id} is missing a page — re-run the tool',
      );
    }
  });

  test('no cues are kept for a reciter the app no longer has', () {
    final known = {for (final r in Reciter.allDefined) r.id};
    expect(known.containsAll(pageTurnCues.keys), isTrue);
  });

  test(
    'each moment is in the spanning ayah, or one before it on the page before',
    () {
      for (final MapEntry(key: id, value: cues) in pageTurnCues.entries) {
        for (final MapEntry(key: page, value: cue) in cues.entries) {
          final spanning = pages[page]!.first;
          expect(cue.surah, spanning['surah'], reason: '$id p$page');
          if (cue.ayah == spanning['ayah']) continue;
          // Read inside an earlier ayah's breath: that ayah plays on the
          // page before, and the app turns the page mid-way through it.
          expect(cue.ayah, lessThan(spanning['ayah'] as int));
          expect(
            pages[page - 1]!.any(
              (a) => a['surah'] == cue.surah && a['ayah'] == cue.ayah,
            ),
            isTrue,
            reason: '$id p$page: ${cue.surah}:${cue.ayah} is not on p${page - 1}',
          );
        }
      }
    },
  );

  test('each moment names a file of its reciter\'s own scheme', () {
    for (final reciter in Reciter.allDefined) {
      final cues = pageTurnCues[reciter.id];
      if (cues == null) continue;
      for (final MapEntry(key: page, value: cue) in cues.entries) {
        final surah = cue.surah.toString().padLeft(3, '0');
        if (reciter.scheme == AudioScheme.timedSurah) {
          expect(cue.file, '$surah.mp3', reason: '${reciter.id} p$page');
        } else {
          expect(
            cue.file,
            matches(RegExp('^$surah\\d{3}\\.mp3\$')),
            reason: '${reciter.id} p$page',
          );
        }
        expect(cue.atMs, greaterThan(0), reason: '${reciter.id} p$page');
        // A sheikh whose spanning ayah's own file is a silent placeholder
        // reads it inside the ayah before — the cue must be there too.
        if (reciter.coveredAyat[cue.surah]?.contains(
              pages[page]!.first['ayah'],
            ) ??
            false) {
          expect(cue.ayah, lessThan(pages[page]!.first['ayah'] as int));
        }
      }
    }
  });
}

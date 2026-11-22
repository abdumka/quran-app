import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/reciter.dart';
import 'audio_download_service.dart';
import 'reciter_service.dart';
import 'surah_timings_service.dart';

/// Moves downloaded surahs onto the recording the server names now.
///
/// A corrected surah is published under a new file name ([Reciter.surahFiles],
/// e.g. `040_v2.mp3`); the old `040.mp3` stays on the server and on phones.
/// Phones that only stream get the new file the next time they play the
/// surah. A phone that DOWNLOADED the old file keeps playing it (old spans,
/// old audio: still a matching pair, see `SurahTimingsService`) until this
/// fetches the new one, so the surah never stops working offline.
///
/// One pass per launch, well after the first frame, one file at a time:
/// * the new file is on the phone and an older one too: the older one (and
///   its timings) is deleted, unless it is the one playing in this run;
/// * an older file is fully downloaded and the new one is not: the new
///   timings, then the new audio, are downloaded (the older pair is removed
///   on a later pass, once nothing holds it);
/// * only partial leftovers of an older file (stream cache, interrupted
///   download): deleted once the new timings are on the phone.
/// Offline, or anything failing, ends the pass; the next launch tries again.
class SurahFileUpgrade {
  SurahFileUpgrade._();

  static bool _running = false;

  /// Starts one pass after [delay] (after the content check, which may bring
  /// newer reciter data for the NEXT launch: overrides apply at launch).
  static void schedule({Duration delay = const Duration(seconds: 45)}) {
    if (kIsWeb) return;
    Future<void>.delayed(delay, () => run());
  }

  /// `SSS.mp3`, `SSS_<tag>.mp3`, and their `.seg` / `.seg.json` / `.part` /
  /// `.upgrade` companions: (surah, the `.mp3` name, whether complete).
  static final RegExp _audioRe = RegExp(
    r'^((\d{3})(?:_[a-z0-9]{1,16})?\.mp3)(\.seg|\.seg\.json|\.part|\.upgrade)?$',
  );

  /// One pass over every offered timed reciter with corrected surahs.
  static Future<void> run({http.Client? client}) async {
    if (kIsWeb || _running) return;
    _running = true;
    final c = client ?? http.Client();
    try {
      final support = (await getApplicationSupportDirectory()).path;
      for (final r in Reciter.offered) {
        if (r.scheme != AudioScheme.timedSurah || r.surahFiles.isEmpty) continue;
        final dir = Directory(p.join(support, r.cacheFolder));
        if (!await dir.exists()) continue;
        final names = <String>{};
        await for (final e in dir.list()) {
          if (e is File) names.add(p.basename(e.path));
        }
        var changed = false;
        var stop = false;
        for (final entry in r.surahFiles.entries) {
          final surah = entry.key;
          final want = entry.value;
          final older = <String>[];
          var olderComplete = false;
          for (final n in names) {
            final m = _audioRe.firstMatch(n);
            if (m == null || int.parse(m.group(2)!) != surah) continue;
            if (m.group(1) == want) continue;
            older.add(n);
            if (m.group(3) == null) olderComplete = true;
          }
          if (older.isEmpty) continue;

          final timings = SurahTimingsService.instance;
          if (names.contains(want)) {
            // The corrected recording is in place. Keep the older one only
            // while this run is playing it.
            final held = timings.heldFile(r, surah);
            if (held != null && held != want) continue;
            await _delete(dir, older);
            await timings.prune(r, surah);
            changed = true;
            continue;
          }
          if (!olderComplete) {
            // Only leftovers of a partly heard / interrupted older file: no
            // use once the current timings are here (they play the new file).
            if (await timings.isCachedOnDisk(r, surah)) {
              await _delete(dir, older);
              await timings.prune(r, surah);
            }
            continue;
          }
          // A downloaded older recording: fetch the corrected one. Timings
          // first, so the new file is never on the phone without its spans.
          await timings.download(r, surah);
          if (!await timings.isCachedOnDisk(r, surah)) {
            stop = true; // offline, or not published yet
            break;
          }
          if (!await _fetch(c, '${r.audioBaseUrl}$want', File(p.join(dir.path, want)))) {
            stop = true;
            break;
          }
          names.add(want);
          changed = true;
          debugPrint('SurahFileUpgrade: ${r.id} surah $surah -> $want');
        }
        if (changed && r.id == ReciterService.instance.selected.value.id) {
          AudioDownloadService.instance.refresh();
        }
        if (stop) break;
      }
    } catch (e) {
      debugPrint('SurahFileUpgrade: pass ended: $e');
    } finally {
      if (client == null) c.close();
      _running = false;
    }
  }

  static Future<void> _delete(Directory dir, List<String> names) async {
    for (final n in names) {
      try {
        final f = File(p.join(dir.path, n));
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Downloads [url] to [dest] through a temp file of its own (a download
  /// from the settings screen may write `<dest>.part` at the same time).
  /// True when [dest] is complete afterwards.
  static Future<bool> _fetch(http.Client c, String url, File dest) async {
    final tmp = File('${dest.path}.upgrade');
    try {
      final response = await c
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return false;
      final sink = tmp.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
        }
      } finally {
        await sink.close();
      }
      final expected = response.contentLength;
      if (received == 0 || (expected != null && expected != received)) {
        await tmp.delete();
        return false;
      }
      if (await dest.exists()) {
        await tmp.delete(); // the stream cache or a download finished first
      } else {
        await tmp.rename(dest.path);
      }
      return true;
    } catch (e) {
      debugPrint('SurahFileUpgrade: $url failed: $e');
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return false;
    }
  }
}

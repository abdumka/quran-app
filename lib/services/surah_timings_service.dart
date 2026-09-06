import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/audio_clip.dart';
import '../models/reciter.dart';

/// Ayah boundaries inside one whole-surah recording.
///
/// The JSON that backs this is the whole of a [AudioScheme.timedSurah]
/// reciter's per-ayah knowledge — it replaces the `coveredAyat`, `missingAyat`
/// and breath-continuation tables that the per-ayah schemes need in Dart:
///
/// ```json
/// {
///   "surah": 15,
///   "file": "015.mp3",
///   "duration_ms": 943300,
///   "ayat": { "1": [0, 15400], "2": null, ... }
/// }
/// ```
///
/// * the basmala is folded into ayah 1's own span, not a separate span of its
///   own — the standard for every timed-surah reciter, every surah except
///   At-Tawba (which has no basmala at all). An explicit key `"0"` is no
///   longer produced by the build pipeline, but [clipsFor] still checks for
///   one defensively, so a hand-edited or future-format file that ever does
///   carry a separate basmala span keeps working rather than losing it.
/// * a `null` range means this ayah has no clip of its own — either the mirror
///   never published it, or the sheikh recites it inside a neighbour's breath
///   (الوقف الهبطي). Both cases behave exactly like the per-ayah schemes'
///   "return no file": playback advances to the next ayah that does have audio.
class SurahTimings {
  final int surah;
  final String file;
  final Duration duration;

  /// Ayah number → its span in [file]. Ayat with no audio are absent, so a
  /// lookup miss and an explicit `null` in the JSON mean the same thing.
  final Map<int, (Duration, Duration)> spans;

  const SurahTimings({
    required this.surah,
    required this.file,
    required this.duration,
    required this.spans,
  });

  factory SurahTimings.fromJson(Map<String, dynamic> json) {
    final spans = <int, (Duration, Duration)>{};
    final ayat = json['ayat'] as Map<String, dynamic>? ?? const {};
    for (final entry in ayat.entries) {
      final range = entry.value;
      if (range is! List || range.length < 2) continue; // null => no audio
      final n = int.tryParse(entry.key);
      if (n == null) continue;
      final from = (range[0] as num).round();
      final to = (range[1] as num).round();
      if (to <= from) continue; // zero-width => nothing to play
      spans[n] = (
        Duration(milliseconds: from),
        Duration(milliseconds: to),
      );
    }
    return SurahTimings(
      surah: json['surah'] as int? ?? 0,
      file: json['file'] as String? ?? '',
      duration: Duration(milliseconds: (json['duration_ms'] as num?)?.round() ?? 0),
      spans: spans,
    );
  }
}

/// Loads and caches the per-surah timing files for [AudioScheme.timedSurah]
/// reciters.
///
/// These are tiny (a few KB per surah) but there are 114 of them per reciter, so
/// they are fetched lazily per surah, kept in memory for the session, and
/// mirrored to disk next to that reciter's audio cache so offline playback works
/// exactly like it does for the per-ayah reciters. On web there is no disk cache
/// (same as tafsir), so they are fetched over the network and held in memory.
class SurahTimingsService {
  static final SurahTimingsService instance = SurahTimingsService._();
  SurahTimingsService._();

  /// reciter id → surah → timings.
  final Map<String, Map<int, SurahTimings>> _memory = {};

  /// In-flight fetches, so a page whose ayat all belong to one surah issues a
  /// single request rather than one per ayah.
  final Map<String, Future<SurahTimings?>> _inFlight = {};

  static String fileNameFor(int surah) => '${surah.toString().padLeft(3, '0')}.json';

  /// The timings already held in memory for ([reciter], [surah]), if any.
  /// Synchronous so the audio path can resolve a clip without awaiting when the
  /// surah has already been loaded — which is the common case, since a page's
  /// ayat almost always share one surah.
  SurahTimings? cached(Reciter reciter, int surah) =>
      _memory[reciter.id]?[surah];

  /// Loads ([reciter], [surah])'s timings, from memory, then disk, then network.
  /// Returns null if it cannot be obtained (offline and not yet cached).
  Future<SurahTimings?> load(Reciter reciter, int surah) async {
    final hit = cached(reciter, surah);
    if (hit != null) return hit;

    final key = '${reciter.id}/$surah';
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _load(reciter, surah);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<SurahTimings?> _load(Reciter reciter, int surah) async {
    final name = fileNameFor(surah);

    if (!kIsWeb) {
      try {
        final file = File(p.join((await _timingsDir(reciter)).path, name));
        if (await file.exists()) {
          return _remember(reciter, surah, await file.readAsString());
        }
      } catch (_) {}
    }

    try {
      final response = await http
          .get(Uri.parse('${reciter.timingsBaseUrl}$name'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        if (!kIsWeb) await _write(reciter, surah, body);
        return _remember(reciter, surah, body);
      }
    } catch (e) {
      debugPrint('timings fetch failed for ${reciter.id} surah $surah: $e');
    }
    return null;
  }

  SurahTimings? _remember(Reciter reciter, int surah, String body) {
    try {
      final timings =
          SurahTimings.fromJson(jsonDecode(body) as Map<String, dynamic>);
      (_memory[reciter.id] ??= {})[surah] = timings;
      return timings;
    } catch (e) {
      debugPrint('timings parse failed for ${reciter.id} surah $surah: $e');
      return null;
    }
  }

  Future<Directory> _timingsDir(Reciter reciter) async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, reciter.cacheFolder, 'timings'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _write(Reciter reciter, int surah, String body) async {
    try {
      final file =
          File(p.join((await _timingsDir(reciter)).path, fileNameFor(surah)));
      await file.writeAsString(body, flush: true);
    } catch (_) {}
  }

  /// Whether ([reciter], [surah])'s timings are already on disk — used by the
  /// download flow to report a surah as fully available offline.
  Future<bool> isCachedOnDisk(Reciter reciter, int surah) async {
    if (kIsWeb) return false;
    try {
      final file =
          File(p.join((await _timingsDir(reciter)).path, fileNameFor(surah)));
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Fetches and stores ([reciter], [surah])'s timings for offline use.
  /// Returns the bytes written, or 0 if it was already present or failed.
  Future<int> download(Reciter reciter, int surah) async {
    if (kIsWeb) return 0;
    if (await isCachedOnDisk(reciter, surah)) return 0;
    try {
      final response = await http
          .get(Uri.parse('${reciter.timingsBaseUrl}${fileNameFor(surah)}'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return 0;
      final body = utf8.decode(response.bodyBytes);
      await _write(reciter, surah, body);
      _remember(reciter, surah, body);
      return response.bodyBytes.length;
    } catch (_) {
      return 0;
    }
  }

  /// Drops the in-memory copies for one reciter (used when downloads are
  /// deleted, so a later play re-reads from disk or network).
  void forget(Reciter reciter) => _memory.remove(reciter.id);

  /// Resolves the clips for a displayed ayah under the timed scheme.
  ///
  /// Returns an empty list when the surah's timings are not loaded yet, or when
  /// the ayah has no audio of its own — the same "no files" signal the per-ayah
  /// schemes give, which the playback engine already knows how to advance past.
  List<AudioClip> clipsFor(Reciter reciter, int surah, int ayah) {
    final timings = cached(reciter, surah);
    if (timings == null) return const [];

    final clips = <AudioClip>[];

    // Standard is a merged basmala: it lives inside ayah 1's own span, not a
    // separate one, so the "1" lookup below already covers it. This "0" span
    // is dead under that standard (the build pipeline never emits one) — kept
    // only so a hand-edited or future-format file that does carry a separate
    // basmala span still plays it, instead of silently losing it.
    if (ayah == 1) {
      final basmala = timings.spans[0];
      if (basmala != null) {
        clips.add(AudioClip(timings.file, start: basmala.$1, end: basmala.$2));
      }
    }

    final span = timings.spans[ayah];
    if (span != null) {
      clips.add(AudioClip(timings.file, start: span.$1, end: span.$2));
    }
    return clips;
  }
}

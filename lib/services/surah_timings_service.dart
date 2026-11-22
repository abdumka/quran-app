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
///
/// **Corrections.** A surah's timings are current when they were fetched under
/// the reciter's [Reciter.timingsRevision] and [Reciter.surahTimingsRevision]
/// and name the file [Reciter.audioFileFor] gives. Anything else on disk is an
/// older copy: it is never preferred online, but it still pairs with the audio
/// it names, so it is kept while that audio is downloaded (and used offline
/// when nothing current can be had). When the current copy's audio is not on
/// the phone but an older copy's is (a downloaded surah whose recording was
/// corrected since), the older pair plays until `SurahFileUpgrade` has fetched
/// the new file: a downloaded surah never stops playing offline because of a
/// correction.
///
/// On disk: `<cacheFolder>/timings[_rN]/<stem>[.tM].json`, where `<stem>` is
/// the audio file's name without `.mp3` (`040`, `040_v2`) and `.tM` marks a
/// per-surah revision above 1. A first-revision `SSS.mp3` surah keeps the
/// plain `SSS.json` every earlier build wrote.
class SurahTimingsService {
  static final SurahTimingsService instance = SurahTimingsService._();
  SurahTimingsService._();

  /// reciter id → surah → (what it was chosen for, timings).
  final Map<String, Map<int, (String, SurahTimings)>> _memory = {};

  /// In-flight fetches, so a page whose ayat all belong to one surah issues a
  /// single request rather than one per ayah.
  final Map<String, Future<SurahTimings?>> _inFlight = {};

  /// The server's name for [surah]'s timings (always the current ones).
  static String fileNameFor(int surah) => '${surah.toString().padLeft(3, '0')}.json';

  /// The on-disk name of [surah]'s timings for audio [file] at per-surah
  /// revision [rev] (see the class comment).
  static String cacheNameFor(int surah, String file, int rev) {
    final stem = file.endsWith('.mp3') ? file.substring(0, file.length - 4) : file;
    return '$stem${rev > 1 ? '.t$rev' : ''}.json';
  }

  static final RegExp _cacheNameRe =
      RegExp(r'^(\d{3})(_[a-z0-9]{1,16})?(?:\.t(\d+))?\.json$');

  /// Everything a choice of timings for ([reciter], [surah]) depends on; a held
  /// copy chosen under another key is stale.
  static String _wantKey(Reciter reciter, int surah) =>
      '${reciter.timingsBaseUrl}|${reciter.timingsRevision}|'
      '${reciter.audioFileFor(surah)}|${reciter.surahTimingsRevision(surah)}';

  /// The timings already held in memory for ([reciter], [surah]), if any.
  /// Synchronous so the audio path can resolve a clip without awaiting when the
  /// surah has already been loaded — which is the common case, since a page's
  /// ayat almost always share one surah.
  SurahTimings? cached(Reciter reciter, int surah) {
    final held = _memory[reciter.id]?[surah];
    if (held == null || held.$1 != _wantKey(reciter, surah)) return null;
    return held.$2;
  }

  /// The audio file the held timings of ([reciter], [surah]) play, whatever
  /// they were chosen for; null when none are held.
  String? heldFile(Reciter reciter, int surah) =>
      _memory[reciter.id]?[surah]?.$2.file;

  /// Loads ([reciter], [surah])'s timings, from memory, then disk, then network.
  /// Returns null if it cannot be obtained (offline and not yet cached).
  Future<SurahTimings?> load(Reciter reciter, int surah) async {
    final hit = cached(reciter, surah);
    if (hit != null) return hit;

    final key = '${reciter.id}/$surah/${_wantKey(reciter, surah)}';
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
    if (kIsWeb) {
      final fetched = await _fetch(reciter, surah);
      return fetched == null ? null : _hold(reciter, surah, fetched.$1);
    }

    final want = reciter.audioFileFor(surah);
    SurahTimings? current = await _readCurrent(reciter, surah);
    SurahTimings? fetchedOther;
    if (current == null) {
      final fetched = await _fetch(reciter, surah);
      if (fetched != null) {
        await _store(reciter, surah, fetched.$1, fetched.$2);
        if (fetched.$1.file == want) {
          current = fetched.$1;
        } else {
          // The server's timings name another file than this build expects
          // (a correction half published). They still pair with their own
          // audio, so they play; the next load asks again.
          fetchedOther = fetched.$1;
        }
      }
    }

    final audioDir = await _audioDir(reciter);
    bool onPhone(String file) => File(p.join(audioDir, file)).existsSync();

    if (current != null && onPhone(current.file)) {
      return _hold(reciter, surah, current);
    }
    // A downloaded older recording keeps playing until its replacement is on
    // the phone (see SurahFileUpgrade), online or not.
    final older = await _olderCopies(reciter, surah, current);
    for (final c in older) {
      if (c.file != current?.file && onPhone(c.file)) {
        return _hold(reciter, surah, c);
      }
    }
    if (current != null) return _hold(reciter, surah, current);
    if (fetchedOther != null) return _hold(reciter, surah, fetchedOther);
    // Offline with nothing current: the newest older copy still pairs with
    // its own audio (partly cached, perhaps).
    if (older.isNotEmpty) return _hold(reciter, surah, older.first);
    return null;
  }

  SurahTimings _hold(Reciter reciter, int surah, SurahTimings t) {
    (_memory[reciter.id] ??= {})[surah] = (_wantKey(reciter, surah), t);
    return t;
  }

  /// GET the server's current timings for [surah]: parsed + raw body.
  Future<(SurahTimings, String)?> _fetch(Reciter reciter, int surah) async {
    try {
      final response = await http
          .get(Uri.parse('${reciter.timingsBaseUrl}${fileNameFor(surah)}'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final t = _parse(body);
        if (t != null) return (t, body);
      }
    } catch (e) {
      debugPrint('timings fetch failed for ${reciter.id} surah $surah: $e');
    }
    return null;
  }

  SurahTimings? _parse(String body) {
    try {
      return SurahTimings.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('timings parse failed: $e');
      return null;
    }
  }

  /// The current copy on disk, if there is one and it names the right file.
  Future<SurahTimings?> _readCurrent(Reciter reciter, int surah) async {
    try {
      final name = cacheNameFor(
        surah,
        reciter.audioFileFor(surah),
        reciter.surahTimingsRevision(surah),
      );
      final file = File(p.join((await _timingsDir(reciter)).path, name));
      if (!await file.exists()) return null;
      final t = _parse(await file.readAsString());
      return t != null && t.file == reciter.audioFileFor(surah) ? t : null;
    } catch (_) {
      return null;
    }
  }

  /// Writes [body] under its own file's name in the current revision folder,
  /// then drops the copies it supersedes.
  Future<void> _store(
    Reciter reciter,
    int surah,
    SurahTimings t,
    String body,
  ) async {
    try {
      final dir = await _timingsDir(reciter);
      final name = cacheNameFor(surah, t.file, reciter.surahTimingsRevision(surah));
      await File(p.join(dir.path, name)).writeAsString(body, flush: true);
      if (t.file == reciter.audioFileFor(surah)) {
        await prune(reciter, surah);
      }
    } catch (_) {}
  }

  /// Every other copy of [surah]'s timings on disk (all revision folders),
  /// newest first: current folder before older ones, higher per-surah
  /// revision first. [current] itself is left out.
  Future<List<SurahTimings>> _olderCopies(
    Reciter reciter,
    int surah,
    SurahTimings? current,
  ) async {
    final out = <(int, int, SurahTimings)>[];
    final currentName = cacheNameFor(
      surah,
      reciter.audioFileFor(surah),
      reciter.surahTimingsRevision(surah),
    );
    for (final (folderRev, dir) in await _timingsFolders(reciter)) {
      final isCurrentFolder = folderRev == reciter.timingsRevision;
      try {
        await for (final e in dir.list()) {
          if (e is! File) continue;
          final name = p.basename(e.path);
          final m = _cacheNameRe.firstMatch(name);
          if (m == null || int.parse(m.group(1)!) != surah) continue;
          if (isCurrentFolder && name == currentName && current != null) {
            continue;
          }
          final t = _parse(await e.readAsString());
          if (t == null) continue;
          out.add((folderRev, int.tryParse(m.group(3) ?? '') ?? 1, t));
        }
      } catch (_) {}
    }
    out.sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : b.$2.compareTo(a.$2));
    return [for (final e in out) e.$3];
  }

  /// Drops the copies of [surah]'s timings that the current one supersedes:
  /// any naming the same file, and any whose audio is not on the phone. A copy
  /// whose (other) audio IS downloaded stays: it is that recording's only way
  /// to play until `SurahFileUpgrade` replaces it. Revision folders left
  /// empty go too.
  Future<void> prune(Reciter reciter, int surah) async {
    if (kIsWeb) return;
    try {
      final want = reciter.audioFileFor(surah);
      final currentName =
          cacheNameFor(surah, want, reciter.surahTimingsRevision(surah));
      final audioDir = await _audioDir(reciter);
      for (final (folderRev, dir) in await _timingsFolders(reciter)) {
        final isCurrentFolder = folderRev == reciter.timingsRevision;
        final files = <File>[];
        await for (final e in dir.list()) {
          if (e is File) files.add(e);
        }
        var left = files.length;
        for (final f in files) {
          final name = p.basename(f.path);
          final m = _cacheNameRe.firstMatch(name);
          if (m == null || int.parse(m.group(1)!) != surah) continue;
          if (isCurrentFolder && name == currentName) continue;
          final t = _parse(await f.readAsString());
          final keep = t != null &&
              t.file != want &&
              File(p.join(audioDir, t.file)).existsSync();
          if (!keep) {
            await f.delete();
            left--;
          }
        }
        if (!isCurrentFolder && left == 0) await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Folder name for [reciter]'s current [Reciter.timingsRevision]: `timings`
  /// for the first, `timings_r2`, `timings_r3`… after a correction.
  static String timingsFolderName(Reciter reciter) => reciter.timingsRevision <= 1
      ? 'timings'
      : 'timings_r${reciter.timingsRevision}';

  Future<String> _audioDir(Reciter reciter) async =>
      p.join((await getApplicationSupportDirectory()).path, reciter.cacheFolder);

  /// The current revision's folder, created if needed. Older revision folders
  /// are no longer dropped here: their copies are the offline fallback until
  /// the current ones arrive, and [prune] removes them surah by surah.
  Future<Directory> _timingsDir(Reciter reciter) async {
    final dir = Directory(
      p.join(await _audioDir(reciter), timingsFolderName(reciter)),
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Every timings folder of [reciter] on disk: (revision, folder).
  Future<List<(int, Directory)>> _timingsFolders(Reciter reciter) async {
    final out = <(int, Directory)>[];
    try {
      final base = Directory(await _audioDir(reciter));
      if (!await base.exists()) return out;
      await for (final e in base.list()) {
        if (e is! Directory) continue;
        final n = p.basename(e.path);
        if (n == 'timings') {
          out.add((1, e));
        } else if (n.startsWith('timings_r')) {
          final rev = int.tryParse(n.substring('timings_r'.length));
          if (rev != null) out.add((rev, e));
        }
      }
    } catch (_) {}
    return out;
  }

  /// Whether ([reciter], [surah])'s current timings are already on disk — used
  /// by the download flow to report a surah as fully available offline.
  Future<bool> isCachedOnDisk(Reciter reciter, int surah) async {
    if (kIsWeb) return false;
    return await _readCurrent(reciter, surah) != null;
  }

  /// Fetches and stores ([reciter], [surah])'s current timings for offline
  /// use. Returns the bytes written, or 0 if they were already present or the
  /// fetch failed. What is held in memory is left alone: the next load
  /// chooses again (the audio may not be downloaded yet).
  Future<int> download(Reciter reciter, int surah) async {
    if (kIsWeb) return 0;
    if (await isCachedOnDisk(reciter, surah)) return 0;
    final fetched = await _fetch(reciter, surah);
    if (fetched == null) return 0;
    await _store(reciter, surah, fetched.$1, fetched.$2);
    return utf8.encode(fetched.$2).length;
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
    // a span that runs on into «صدق الله العظيم» stops before it
    final cap = Reciter.endCapFor(reciter.id, timings.file);
    if (cap == null) return clips;
    final limit = Duration(milliseconds: (cap * 1000).round());
    return [
      for (final c in clips)
        if (c.end != null && c.end! > limit && c.start! < limit)
          AudioClip(c.file, start: c.start, end: limit)
        else
          c,
    ];
  }
}

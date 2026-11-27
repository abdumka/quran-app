import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/athkar.dart';
import '../models/reciter.dart';
import 'athkar_audio.dart';
import 'athkar_service.dart';
import 'audio_ayah_map_service.dart';
import 'audio_service.dart';

/// What «أصوات الأذكار» in the downloads page shows.
@immutable
class AthkarDownloadState {
  const AthkarDownloadState({
    this.total = 0,
    this.done = 0,
    this.bytes = 0,
    this.estimate = 0,
    this.voices = const [],
    this.downloading = false,
    this.failed = false,
  });

  /// Files the athkar play in the voices listened to, and how many of them
  /// are on the phone.
  final int total;
  final int done;

  /// Everything kept for the athkar on the phone (also the clips kept as
  /// they were heard, and other voices').
  final int bytes;

  /// About how much all of [total] comes to.
  final int estimate;

  /// The voices the athkar play in, the chosen one first.
  final List<String> voices;
  final bool downloading;

  /// The last download stopped on files it could not fetch.
  final bool failed;

  bool get complete => total > 0 && done >= total;

  AthkarDownloadState copyWith({
    int? total,
    int? done,
    int? bytes,
    int? estimate,
    List<String>? voices,
    bool? downloading,
    bool? failed,
  }) => AthkarDownloadState(
    total: total ?? this.total,
    done: done ?? this.done,
    bytes: bytes ?? this.bytes,
    estimate: estimate ?? this.estimate,
    voices: voices ?? this.voices,
    downloading: downloading ?? this.downloading,
    failed: failed ?? this.failed,
  );
}

/// Downloads the athkar's recordings for listening without internet (owner,
/// 2026-11-20): every dhikr in the voice it plays in (the chosen voice, and
/// the one standing in where it did not record a dhikr) and the athkar's
/// verses when their reciter has one file per ayah (a timed reciter's
/// surahs come with the mushaf's own downloads). Not every voice: that would
/// be some 250 MB for voices never heard. The files go where the player
/// already keeps what it has heard, so nothing else changes.
class AthkarDownloadService {
  AthkarDownloadService._();
  static final AthkarDownloadService instance = AthkarDownloadService._();

  final ValueNotifier<AthkarDownloadState> state = ValueNotifier(
    const AthkarDownloadState(),
  );

  bool _stop = false;

  /// About how big one clip of each voice is (bytes, measured 2026-11-26 on
  /// the v3 copies that hold only the dhikr), for the size shown before
  /// downloading.
  static const Map<String, int> _clipBytes = {
    'ghamdi': 164000,
    'duraihem': 99000,
    'rashid': 111000,
    'shuwaihi': 126000,
    'hajwani': 156000,
    'abbad': 183000,
  };
  static const int _ayahBytes = 150000;

  /// The addresses to download, with each one's voice id (or '' for a
  /// verse), and the voice names in order.
  Future<(List<(String, String)>, List<String>)> _wanted() async {
    // the downloads page can open before the athkar ever have
    await AthkarService.instance.load();
    await AthkarStore.instance.load();
    final data = AthkarService.instance.data;
    final audio = AthkarAudio.instance;
    final urls = <String, String>{};
    final count = <String, int>{};
    final names = <String, String>{};
    final seen = <int>{};
    for (final section in data.sections) {
      for (final item in section.items) {
        if (!seen.add(item.id)) continue;
        if (item.isQuran) continue;
        final voice = audio.voiceFor(item);
        final url = voice?.urlFor(item);
        if (voice == null || url == null) continue;
        urls[url] = voice.id;
        count[voice.id] = (count[voice.id] ?? 0) + 1;
        names[voice.id] = voice.name;
      }
    }
    final chosen = audio.reciter?.id;
    final order = names.keys.toList()
      ..sort((a, b) {
        if (a == chosen) return -1;
        if (b == chosen) return 1;
        return (count[b] ?? 0).compareTo(count[a] ?? 0);
      });
    // the verses, when their reciter has one file per ayah (looked up the
    // way the mushaf does, which fetches nothing); a file the mushaf has
    // downloaded already plays from there
    final quran = audio.quranReciter;
    if (quran.scheme != AudioScheme.timedSurah) {
      await AudioAyahMapService.instance.load();
      Directory? own;
      try {
        own = Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            quran.cacheFolder,
          ),
        );
      } catch (_) {}
      for (final item in _quranItems(data)) {
        for (final v in item.verses) {
          for (var a = v.from; a <= v.to; a++) {
            for (final c in AudioService.instance.clipsForAyahOf(
              quran,
              v.surah,
              a,
            )) {
              if (c.start != null) continue;
              if (own != null && File(p.join(own.path, c.file)).existsSync()) {
                continue;
              }
              urls['${quran.audioBaseUrl}${c.file}'] = '';
            }
          }
        }
      }
    }
    return (
      [for (final e in urls.entries) (e.key, e.value)],
      [for (final id in order) names[id]!],
    );
  }

  static Iterable<AthkarItem> _quranItems(AthkarData data) sync* {
    final seen = <int>{};
    for (final s in data.sections) {
      for (final i in s.items) {
        if (i.isQuran && seen.add(i.id)) yield i;
      }
    }
  }

  /// Reads what is on the phone; the page calls it once it has opened.
  Future<void> refresh() async {
    if (kIsWeb || state.value.downloading) return;
    try {
      final (wanted, voices) = await _wanted();
      var done = 0;
      var estimate = 0;
      for (final (url, voice) in wanted) {
        final f = await AthkarAudio.clipFile(url);
        if (f.existsSync() && f.lengthSync() > 0) done++;
        estimate += voice.isEmpty ? _ayahBytes : (_clipBytes[voice] ?? 220000);
      }
      state.value = state.value.copyWith(
        total: wanted.length,
        done: done,
        bytes: await _folderBytes(),
        estimate: estimate,
        voices: voices,
      );
    } catch (e) {
      debugPrint('AthkarDownloadService: refresh failed: $e');
    }
  }

  Future<int> _folderBytes() async {
    try {
      final dir = Directory(
        p.join(
          (await getApplicationSupportDirectory()).path,
          AthkarAudio.clipFolder,
        ),
      );
      if (!dir.existsSync()) return 0;
      var total = 0;
      await for (final e in dir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Downloads what is missing, four at a time. Stops on [cancel], or when
  /// files keep failing (no internet), keeping what arrived.
  Future<void> download() async {
    if (kIsWeb || state.value.downloading) return;
    try {
      await _download();
    } catch (e) {
      debugPrint('AthkarDownloadService: download failed: $e');
      state.value = state.value.copyWith(downloading: false, failed: true);
    }
  }

  Future<void> _download() async {
    _stop = false;
    state.value = state.value.copyWith(downloading: true, failed: false);
    final (wanted, voices) = await _wanted();
    state.value = state.value.copyWith(
      total: wanted.length,
      voices: voices,
      downloading: true,
      failed: false,
    );
    var done = 0;
    final missing = <String>[];
    for (final (url, _) in wanted) {
      final f = await AthkarAudio.clipFile(url);
      if (f.existsSync() && f.lengthSync() > 0) {
        done++;
      } else {
        missing.add(url);
      }
    }
    state.value = state.value.copyWith(done: done);
    var failures = 0;
    var next = 0;
    Future<void> worker() async {
      while (!_stop && next < missing.length && failures < 8) {
        final url = missing[next++];
        var ok = await AthkarAudio.keepOnPhone(url);
        if (!ok && !_stop) ok = await AthkarAudio.keepOnPhone(url);
        if (ok) {
          done++;
          failures = 0;
        } else {
          failures++;
        }
        state.value = state.value.copyWith(done: done);
      }
    }

    await Future.wait([for (var k = 0; k < 4; k++) worker()]);
    state.value = state.value.copyWith(
      downloading: false,
      failed: !_stop && done < wanted.length,
      bytes: await _folderBytes(),
    );
  }

  void cancel() => _stop = true;

  /// Deletes every athkar recording on the phone (downloaded or kept as it
  /// was heard); they stream again when played.
  Future<void> delete() async {
    cancel();
    try {
      final dir = Directory(
        p.join(
          (await getApplicationSupportDirectory()).path,
          AthkarAudio.clipFolder,
        ),
      );
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('AthkarDownloadService: delete failed: $e');
    }
    state.value = state.value.copyWith(done: 0, bytes: 0, failed: false);
    await refresh();
  }
}

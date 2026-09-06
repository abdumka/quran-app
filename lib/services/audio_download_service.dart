import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/reciter.dart';
import 'reciter_service.dart';
import 'surah_timings_service.dart';

class AudioDownloadState {
  final bool isDownloading;
  final bool isPaused;
  final int downloadedFiles;
  final int totalFiles;
  final bool isComplete;
  final int installedBytes;

  /// How far through the file currently downloading, 0..1.
  ///
  /// Only ever non-zero for [AudioScheme.timedSurah], where a "file" is a whole
  /// surah: al-Baqarah alone is ~90 MB, so a purely file-counted bar would sit
  /// frozen for minutes and look broken. Folding the in-flight file's progress
  /// into [progressFraction] keeps the bar moving at the same rhythm users see
  /// for the per-ayah reciters. Stays 0 for every other scheme, so their bar
  /// behaves exactly as before.
  final double partialFileFraction;

  const AudioDownloadState({
    this.isDownloading = false,
    this.isPaused = false,
    this.downloadedFiles = 0,
    this.totalFiles = 0,
    this.isComplete = false,
    this.installedBytes = 0,
    this.partialFileFraction = 0,
  });

  double get progressFraction => totalFiles > 0
      ? ((downloadedFiles + partialFileFraction) / totalFiles).clamp(0.0, 1.0)
      : 0;

  String get progressLabel => '$downloadedFiles / $totalFiles ملف';
  String get percentLabel => '${(progressFraction * 100).round()}%';

  String get installedSizeLabel {
    const mb = 1024 * 1024;
    if (installedBytes <= 0) return '0 MB';
    final value = installedBytes / mb;
    if (value >= 100) return '${value.toStringAsFixed(0)} MB';
    if (value >= 10) return '${value.toStringAsFixed(1)} MB';
    return '${value.toStringAsFixed(2)} MB';
  }

  AudioDownloadState copyWith({
    bool? isDownloading,
    bool? isPaused,
    int? downloadedFiles,
    int? totalFiles,
    bool? isComplete,
    int? installedBytes,
    double? partialFileFraction,
  }) {
    return AudioDownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      isPaused: isPaused ?? this.isPaused,
      downloadedFiles: downloadedFiles ?? this.downloadedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
      isComplete: isComplete ?? this.isComplete,
      installedBytes: installedBytes ?? this.installedBytes,
      partialFileFraction: partialFileFraction ?? this.partialFileFraction,
    );
  }
}

/// Live progress for a single-surah download initiated from the picker. Only
/// one surah downloads at a time; [surah] is 0 when no surah download is active.
class SurahDownloadState {
  final int surah;
  final bool isDownloading;
  final int downloadedFiles;
  final int totalFiles;

  /// Progress through the file currently downloading, 0..1. Matters most for
  /// [AudioScheme.timedSurah], where a surah IS one file: without it the bar
  /// would sit at 0% and then jump straight to 100%.
  final double partialFileFraction;

  const SurahDownloadState({
    this.surah = 0,
    this.isDownloading = false,
    this.downloadedFiles = 0,
    this.totalFiles = 0,
    this.partialFileFraction = 0,
  });

  double get progressFraction => totalFiles > 0
      ? ((downloadedFiles + partialFileFraction) / totalFiles).clamp(0.0, 1.0)
      : 0;
}

/// Cached/total file counts for one surah, used to render its row in the
/// download picker (idle / partial / complete).
class SurahDownloadStatus {
  final int cached;
  final int total;
  const SurahDownloadStatus(this.cached, this.total);

  bool get isComplete => total > 0 && cached >= total;
  bool get isPartial => cached > 0 && cached < total;
}

class AudioDownloadService {
  static final AudioDownloadService instance = AudioDownloadService._();
  AudioDownloadService._();

  /// Base URL + cache folder follow the currently selected reciter.
  String get _baseUrl => ReciterService.instance.selected.value.audioBaseUrl;
  String get _cacheFolder => ReciterService.instance.selected.value.cacheFolder;

  final ValueNotifier<AudioDownloadState> state =
      ValueNotifier(const AudioDownloadState());

  /// Live progress for a single-surah download from the picker sheet.
  final ValueNotifier<SurahDownloadState> surahState =
      ValueNotifier(const SurahDownloadState());

  bool _cancelRequested = false;
  bool _pauseRequested = false;
  bool _isDownloading = false;
  bool _didInitialize = false;
  bool _listeningForReciterChange = false;

  // Standard Quran ayah counts per surah (Hafs numbering used by the app).
  static const List<int> _surahAyahCounts = [
    7,   286, 200, 176, 120, 165, 206, 75,  129, 109, // 1-10
    123, 111, 43,  52,  99,  128, 111, 110, 98,  135, // 11-20
    112, 78,  118, 64,  77,  227, 93,  88,  69,  60,  // 21-30
    34,  30,  73,  54,  45,  83,  182, 88,  75,  85,  // 31-40
    54,  53,  89,  59,  37,  35,  38,  29,  18,  45,  // 41-50
    60,  49,  62,  55,  78,  96,  29,  22,  24,  13,  // 51-60
    14,  11,  11,  18,  12,  12,  30,  52,  52,  44,  // 61-70
    28,  28,  20,  56,  40,  31,  50,  40,  46,  42,  // 71-80
    29,  19,  36,  25,  22,  17,  19,  26,  30,  20,  // 81-90
    15,  21,  11,  8,   8,   19,  5,   8,   8,   11,  // 91-100
    11,  8,   3,   9,   5,   4,   7,   3,   6,   3,   // 101-110
    5,   4,   5,   6,                                   // 111-114
  ];

  // Surahs where the Qaloun recording merges the last ayah(s) into a single
  // file starting at the given ayah number (mirrors AudioService logic).
  static const Map<int, int> _mergedThresholds = {
    5: 120, 6: 165, 8: 75,  9: 129, 13: 43, 14: 52,
    23: 118, 27: 93, 47: 38, 56: 96, 71: 28, 89: 30,
    91: 15,  96: 19, 106: 4,
  };

  /// Returns the complete list of unique MP3 filenames required to play the
  /// entire Quran with the currently selected reciter.
  List<String> getAllFilenames() {
    final filenames = <String>{};
    for (int s = 1; s <= 114; s++) {
      filenames.addAll(getSurahFilenames(s));
    }
    return filenames.toList()..sort();
  }

  /// Returns the unique MP3 filenames required to play a single [surah] with
  /// the currently selected reciter (1-based surah number).
  List<String> getSurahFilenames(int surah) {
    final reciter = ReciterService.instance.selected.value;
    switch (reciter.scheme) {
      case AudioScheme.nativeQaloun:
        return _nativeSurahFilenames(reciter, surah);
      case AudioScheme.covered:
        return _coveredSurahFilenames(reciter, surah);
      case AudioScheme.timedSurah:
        // One file for the whole surah; the ayah boundaries live in the timing
        // JSON, which is fetched separately (see _downloadTimings) because it is
        // not an .mp3 and must not be counted as one.
        return ['${surah.toString().padLeft(3, '0')}.mp3'];
      case AudioScheme.mergedTail:
        break;
    }
    final filenames = <String>{};
    final ayahCount = _surahAyahCounts[surah - 1];
    final surahStr = surah.toString().padLeft(3, '0');
    final mergedFrom = _mergedThresholds[surah];
    for (int a = 1; a <= ayahCount; a++) {
      final String filename;
      if (mergedFrom != null && a >= mergedFrom) {
        filename = '$surahStr${mergedFrom.toString().padLeft(3, '0')}.mp3';
      } else {
        filename = '$surahStr${a.toString().padLeft(3, '0')}.mp3';
      }
      filenames.add(filename);
    }
    return filenames.toList()..sort();
  }

  /// Native-scheme mirrors (al-Naihi / قنيوه / أبوسنينة) per-surah: per-ayah
  /// files `SSS001..SSSmax` plus a basmala file `SSS000` for every surah except
  /// At-Tawba (9).
  ///
  /// Ayat the mirror never published are left out — counting a file that can
  /// only 404 would hold the surah (and the whole download) permanently short of
  /// "complete". Breath continuations are NOT left out: those files do exist in
  /// the bucket, they just duplicate the previous ayah's audio.
  List<String> _nativeSurahFilenames(Reciter reciter, int surah) {
    final filenames = <String>{};
    final surahStr = surah.toString().padLeft(3, '0');
    if (surah != 9) filenames.add('${surahStr}000.mp3');
    for (int a = 1; a <= Reciter.madaniAyahCounts[surah - 1]; a++) {
      if (reciter.isMissing(surah, a)) continue;
      filenames.add('$surahStr${a.toString().padLeft(3, '0')}.mp3');
    }
    return filenames.toList()..sort();
  }

  /// al-Hudaifi per-surah: one file per displayed ayah, no basmala file. The
  /// ayat he reads as part of a neighbouring ayah are left out — their file
  /// holds silence and playback never requests it, so counting it here would
  /// leave the surah permanently short of "complete".
  List<String> _coveredSurahFilenames(Reciter reciter, int surah) {
    final covered = reciter.coveredAyat[surah] ?? const <int>{};
    final surahStr = surah.toString().padLeft(3, '0');
    final filenames = <String>{};
    for (int a = 1; a <= Reciter.madaniAyahCounts[surah - 1]; a++) {
      if (covered.contains(a) || reciter.isMissing(surah, a)) continue;
      filenames.add('$surahStr${a.toString().padLeft(3, '0')}.mp3');
    }
    return filenames.toList()..sort();
  }

  Future<Directory> _getCacheDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, _cacheFolder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Whether the selected reciter stores one file per surah plus timings.
  bool get _isTimedScheme =>
      ReciterService.instance.selected.value.scheme == AudioScheme.timedSurah;

  /// Downloads [url] to [dest], returning the bytes written (0 on failure).
  ///
  /// When [onProgress] is given the body is streamed so the caller can report
  /// progress inside a single large file; otherwise the simpler buffered fetch
  /// is used, which is what every per-ayah reciter has always done. Either way
  /// the bytes land in a `.part` file first, so an interrupted download can
  /// never leave a truncated MP3 that later looks like a complete one.
  Future<int> _fetchFile(
    http.Client client,
    String url,
    File dest, {
    void Function(double fraction)? onProgress,
  }) async {
    final part = File('${dest.path}.part');
    try {
      if (onProgress == null) {
        final response = await client.get(Uri.parse(url));
        if (response.statusCode != 200) return 0;
        await part.writeAsBytes(response.bodyBytes, flush: true);
        await part.rename(dest.path);
        return response.bodyBytes.length;
      }

      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) return 0;
      final total = response.contentLength ?? 0;
      final sink = part.openWrite();
      int received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }
      } finally {
        await sink.close();
      }
      await part.rename(dest.path);
      return received;
    } catch (_) {
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      return 0;
    }
  }

  /// Fetches the per-surah timing JSONs for a timed-scheme reciter. They are a
  /// few KB each and are not `.mp3`, so they never enter the file counters —
  /// but without them the audio cannot be cut into ayat offline.
  Future<void> _downloadTimings(Iterable<int> surahs) async {
    if (!_isTimedScheme) return;
    final reciter = ReciterService.instance.selected.value;
    for (final s in surahs) {
      if (_cancelRequested) return;
      await SurahTimingsService.instance.download(reciter, s);
    }
  }

  Future<void> initialize() async {
    await ReciterService.instance.load();
    if (!_listeningForReciterChange) {
      _listeningForReciterChange = true;
      ReciterService.instance.selected.addListener(_handleReciterChanged);
    }
    if (_didInitialize) return;
    _didInitialize = true;

    final dir = await _getCacheDir();
    final total = getAllFilenames().length;
    int cachedCount = 0;
    int installedBytes = 0;

    try {
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.mp3')) {
            cachedCount++;
            try {
              installedBytes += await entity.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    state.value = AudioDownloadState(
      downloadedFiles: cachedCount.clamp(0, total),
      totalFiles: total,
      isComplete: cachedCount >= total,
      installedBytes: installedBytes,
    );
  }

  void refresh() {
    _didInitialize = false;
    initialize();
  }

  /// When the user switches reciter, cancel any in-flight download and recompute
  /// the download state for the newly selected reciter's cache folder.
  void _handleReciterChanged() {
    if (_isDownloading) _cancelRequested = true;
    state.value = const AudioDownloadState();
    surahState.value = const SurahDownloadState();
    _didInitialize = false;
    initialize();
  }

  Future<void> downloadAll() async {
    if (_isDownloading) return;
    _isDownloading = true;
    _cancelRequested = false;
    _pauseRequested = false;

    final dir = await _getCacheDir();
    final allFiles = getAllFilenames();
    final client = http.Client();

    int downloaded = state.value.downloadedFiles;
    int installedBytes = state.value.installedBytes;

    state.value = state.value.copyWith(
      isDownloading: true,
      isPaused: false,
      totalFiles: allFiles.length,
      downloadedFiles: downloaded,
    );

    try {
      // Timings first: they are tiny, and a surah's audio is useless without
      // them. Doing them up front also means an interrupted download still
      // leaves every already-fetched surah fully playable.
      await _downloadTimings(List.generate(114, (i) => i + 1));

      for (final filename in allFiles) {
        if (_cancelRequested || _pauseRequested) break;

        final file = File(p.join(dir.path, filename));
        if (await file.exists()) continue;

        try {
          final written = await _fetchFile(
            client,
            '$_baseUrl$filename',
            file,
            onProgress: _isTimedScheme
                ? (f) => state.value = state.value.copyWith(
                      partialFileFraction: f,
                    )
                : null,
          );
          if (written > 0) {
            downloaded++;
            installedBytes += written;
            state.value = state.value.copyWith(
              downloadedFiles: downloaded,
              installedBytes: installedBytes,
              partialFileFraction: 0,
            );
          }
        } catch (_) {
          // File will be downloaded on-demand during playback if skipped here.
        }
      }

      if (_cancelRequested) {
        state.value = state.value.copyWith(
          isDownloading: false,
          isPaused: false,
          partialFileFraction: 0,
        );
      } else if (_pauseRequested) {
        state.value = state.value.copyWith(
          isDownloading: false,
          isPaused: true,
          partialFileFraction: 0,
        );
      } else {
        state.value = state.value.copyWith(
          isDownloading: false,
          isPaused: false,
          isComplete: downloaded >= allFiles.length,
          partialFileFraction: 0,
        );
      }
    } finally {
      client.close();
      _isDownloading = false;
      _cancelRequested = false;
      _pauseRequested = false;
    }
  }

  /// Downloads only the files for a single [surah] (1-based). Shares the
  /// cancel/`_isDownloading` guard with [downloadAll], so only one download —
  /// full or per-surah — runs at a time. Progress is reported on [surahState],
  /// and the overall [state] (count / installed size / completeness) is kept in
  /// sync as files land so the main tile stays accurate.
  Future<void> downloadSurah(int surah) async {
    if (_isDownloading) return;
    _isDownloading = true;
    _cancelRequested = false;
    _pauseRequested = false;

    final dir = await _getCacheDir();
    final files = getSurahFilenames(surah);
    final client = http.Client();

    int overallDownloaded = state.value.downloadedFiles;
    int installedBytes = state.value.installedBytes;
    int surahDownloaded =
        files.length - await _missingCount(dir, files);

    surahState.value = SurahDownloadState(
      surah: surah,
      isDownloading: true,
      downloadedFiles: surahDownloaded,
      totalFiles: files.length,
    );

    try {
      await _downloadTimings([surah]);

      for (final filename in files) {
        if (_cancelRequested) break;

        final file = File(p.join(dir.path, filename));
        if (await file.exists()) continue;

        try {
          final written = await _fetchFile(
            client,
            '$_baseUrl$filename',
            file,
            onProgress: _isTimedScheme
                ? (f) => surahState.value = SurahDownloadState(
                      surah: surah,
                      isDownloading: true,
                      downloadedFiles: surahDownloaded,
                      totalFiles: files.length,
                      partialFileFraction: f,
                    )
                : null,
          );
          if (written > 0) {
            surahDownloaded++;
            overallDownloaded++;
            installedBytes += written;
            surahState.value = SurahDownloadState(
              surah: surah,
              isDownloading: true,
              downloadedFiles: surahDownloaded,
              totalFiles: files.length,
            );
            state.value = state.value.copyWith(
              downloadedFiles: overallDownloaded,
              installedBytes: installedBytes,
              isComplete: overallDownloaded >= state.value.totalFiles,
            );
          }
        } catch (_) {
          // File will be downloaded on-demand during playback if skipped here.
        }
      }
    } finally {
      client.close();
      _isDownloading = false;
      _cancelRequested = false;
      _pauseRequested = false;
      surahState.value = const SurahDownloadState();
    }
  }

  /// Counts how many of [files] are not yet present in [dir].
  Future<int> _missingCount(Directory dir, List<String> files) async {
    int missing = 0;
    for (final filename in files) {
      if (!await File(p.join(dir.path, filename)).exists()) missing++;
    }
    return missing;
  }

  /// Cached/total counts for every surah (1..114), for the picker list. Reads
  /// the cache directory once, then tallies each surah's expected filenames.
  Future<List<SurahDownloadStatus>> computeSurahStatuses() async {
    final dir = await _getCacheDir();
    final present = <String>{};
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.mp3')) {
            present.add(p.basename(entity.path));
          }
        }
      }
    } catch (_) {}

    final statuses = <SurahDownloadStatus>[];
    for (int s = 1; s <= 114; s++) {
      final files = getSurahFilenames(s);
      final cached = files.where(present.contains).length;
      statuses.add(SurahDownloadStatus(cached, files.length));
    }
    return statuses;
  }

  void pauseDownload() {
    if (_isDownloading) _pauseRequested = true;
  }

  void cancelDownload() {
    if (_isDownloading) {
      _cancelRequested = true;
    } else {
      state.value = state.value.copyWith(
        isDownloading: false,
        isPaused: false,
      );
    }
  }

  Future<void> deleteDownloads() async {
    if (_isDownloading) {
      _cancelRequested = true;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    surahState.value = const SurahDownloadState();

    final dir = await _getCacheDir();
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) await entity.delete();
          // The timed scheme keeps its per-surah timing JSONs in a `timings/`
          // subfolder. Deleting only files would leave them behind, so the
          // reciter would still claim ayah boundaries for audio that is gone.
          if (entity is Directory) await entity.delete(recursive: true);
        }
      }
    } catch (_) {}
    SurahTimingsService.instance
        .forget(ReciterService.instance.selected.value);

    _didInitialize = false;
    await initialize();
  }
}

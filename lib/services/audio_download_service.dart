import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioDownloadState {
  final bool isDownloading;
  final bool isPaused;
  final int downloadedFiles;
  final int totalFiles;
  final bool isComplete;
  final int installedBytes;

  const AudioDownloadState({
    this.isDownloading = false,
    this.isPaused = false,
    this.downloadedFiles = 0,
    this.totalFiles = 0,
    this.isComplete = false,
    this.installedBytes = 0,
  });

  double get progressFraction =>
      totalFiles > 0 ? downloadedFiles / totalFiles : 0;

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
  }) {
    return AudioDownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      isPaused: isPaused ?? this.isPaused,
      downloadedFiles: downloadedFiles ?? this.downloadedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
      isComplete: isComplete ?? this.isComplete,
      installedBytes: installedBytes ?? this.installedBytes,
    );
  }
}

class AudioDownloadService {
  static final AudioDownloadService instance = AudioDownloadService._();
  AudioDownloadService._();

  static const String _baseUrl =
      'https://raw.githubusercontent.com/quran-by-verses/alhosary-qaloon-32/main/verses/';
  static const String _cacheFolder = 'audio_cache';

  final ValueNotifier<AudioDownloadState> state =
      ValueNotifier(const AudioDownloadState());

  bool _cancelRequested = false;
  bool _pauseRequested = false;
  bool _isDownloading = false;
  bool _didInitialize = false;

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
  /// entire Quran with this reciter.
  static List<String> getAllFilenames() {
    final filenames = <String>{};
    for (int s = 1; s <= 114; s++) {
      final ayahCount = _surahAyahCounts[s - 1];
      final surahStr = s.toString().padLeft(3, '0');
      final mergedFrom = _mergedThresholds[s];
      for (int a = 1; a <= ayahCount; a++) {
        final String filename;
        if (mergedFrom != null && a >= mergedFrom) {
          filename = '$surahStr${mergedFrom.toString().padLeft(3, '0')}.mp3';
        } else {
          filename = '$surahStr${a.toString().padLeft(3, '0')}.mp3';
        }
        filenames.add(filename);
      }
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

  Future<void> initialize() async {
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
      for (final filename in allFiles) {
        if (_cancelRequested || _pauseRequested) break;

        final file = File(p.join(dir.path, filename));
        if (await file.exists()) continue;

        try {
          final response = await client.get(Uri.parse('$_baseUrl$filename'));
          if (response.statusCode == 200) {
            await file.writeAsBytes(response.bodyBytes);
            downloaded++;
            installedBytes += response.bodyBytes.length;
            state.value = state.value.copyWith(
              downloadedFiles: downloaded,
              installedBytes: installedBytes,
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
        );
      } else if (_pauseRequested) {
        state.value = state.value.copyWith(
          isDownloading: false,
          isPaused: true,
        );
      } else {
        state.value = state.value.copyWith(
          isDownloading: false,
          isPaused: false,
          isComplete: downloaded >= allFiles.length,
        );
      }
    } finally {
      client.close();
      _isDownloading = false;
      _cancelRequested = false;
      _pauseRequested = false;
    }
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

    final dir = await _getCacheDir();
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) await entity.delete();
        }
      }
    } catch (_) {}

    _didInitialize = false;
    await initialize();
  }
}

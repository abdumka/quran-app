import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/tafsir_edition.dart';

/// Total size on disk of every cached online-tafsir page, for the downloads
/// management screen. Mirrors the state shape of the other managed caches
/// (audio, margin images).
class TafsirCacheState {
  final int installedBytes;
  const TafsirCacheState({this.installedBytes = 0});

  bool get hasCache => installedBytes > 0;

  String get installedSizeLabel {
    const mb = 1024 * 1024;
    if (installedBytes <= 0) return '0 MB';
    final value = installedBytes / mb;
    if (value >= 100) return '${value.toStringAsFixed(0)} MB';
    if (value >= 10) return '${value.toStringAsFixed(1)} MB';
    return '${value.toStringAsFixed(2)} MB';
  }

  TafsirCacheState copyWith({int? installedBytes}) =>
      TafsirCacheState(installedBytes: installedBytes ?? this.installedBytes);
}

/// Progress of a whole-edition download. [editionId] is '' when idle.
class TafsirDownloadState {
  final String editionId;
  final bool isDownloading;
  final int done;
  final int total;

  const TafsirDownloadState({
    this.editionId = '',
    this.isDownloading = false,
    this.done = 0,
    this.total = 0,
  });

  double get fraction =>
      total > 0 ? (done / total).clamp(0.0, 1.0).toDouble() : 0.0;
  String get label => '$done / $total صفحة';
}

/// Owns the on-disk cache of fetched tafsir pages for the **online** editions
/// (Ibn Kathir, Tabari, Qurtubi, Zad al-Masir). Bundled editions (Sa'di,
/// Muyassar) never touch this — they read straight from their bundled asset.
///
/// Each online edition caches its pages under its own folder
/// ([TafsirEdition.cacheFolder]) in the app-support dir, one small JSON per
/// Qur'an page (`page_NNN.json`). This service is the single reader/writer of
/// that cache, keeps [state] (`installedBytes`) accurate, and exposes
/// [deleteCache] so users can free the space from إدارة الملفات المحمّلة.
class TafsirCacheService {
  TafsirCacheService._();
  static final TafsirCacheService instance = TafsirCacheService._();

  final ValueNotifier<TafsirCacheState> state =
      ValueNotifier<TafsirCacheState>(const TafsirCacheState());

  /// Live progress while downloading a whole edition (idle by default).
  final ValueNotifier<TafsirDownloadState> downloadState =
      ValueNotifier<TafsirDownloadState>(const TafsirDownloadState());

  bool _scanned = false;
  bool _cancelDownload = false;

  Future<Directory> _editionDir(TafsirEdition edition) async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, edition.cacheFolder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Scans the cache once and publishes the total size. Cheap (a directory
  /// listing) and safe to call off the launch critical path.
  Future<void> initialize() async {
    if (_scanned) return;
    _scanned = true;
    await _recomputeSize();
  }

  Future<void> _recomputeSize() async {
    int total = 0;
    try {
      final appDir = await getApplicationSupportDirectory();
      for (final edition in TafsirEdition.onlineEditions) {
        final dir = Directory(p.join(appDir.path, edition.cacheFolder));
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              total += await entity.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    state.value = TafsirCacheState(installedBytes: total);
  }

  /// Returns the cached JSON for [edition]'s [pageNumber] (1-based), or null if
  /// it has not been fetched yet.
  Future<String?> readPage(TafsirEdition edition, int pageNumber) async {
    if (!edition.isOnline) return null;
    try {
      final dir = await _editionDir(edition);
      final file =
          File(p.join(dir.path, TafsirEdition.pageFileName(pageNumber)));
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {}
    return null;
  }

  /// Writes [jsonString] as [edition]'s cached [pageNumber] and updates the
  /// tracked cache size. Best-effort — failures are swallowed.
  Future<void> writePage(
    TafsirEdition edition,
    int pageNumber,
    String jsonString,
  ) async {
    if (!edition.isOnline) return;
    try {
      final dir = await _editionDir(edition);
      final file =
          File(p.join(dir.path, TafsirEdition.pageFileName(pageNumber)));
      final existed = await file.exists();
      final oldLen = existed ? await file.length() : 0;
      await file.writeAsString(jsonString);
      final newLen = await file.length();
      state.value = state.value.copyWith(
        installedBytes: (state.value.installedBytes + newLen - oldLen)
            .clamp(0, 1 << 62),
      );
    } catch (_) {}
  }

  /// Deletes every cached tafsir page for all online editions.
  Future<void> deleteCache() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      for (final edition in TafsirEdition.onlineEditions) {
        final dir = Directory(p.join(appDir.path, edition.cacheFolder));
        if (await dir.exists()) {
          await for (final entity in dir.list()) {
            if (entity is File) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
    state.value = const TafsirCacheState();
  }

  /// How many pages of [edition] are cached on disk (out of
  /// [TafsirEdition.onlinePageCount]).
  Future<int> cachedPageCount(TafsirEdition edition) async {
    if (!edition.isOnline) return 0;
    int count = 0;
    try {
      final dir = await _editionDir(edition);
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) count++;
      }
    } catch (_) {}
    return count;
  }

  /// Downloads every page of [edition] that isn't cached yet, reporting progress
  /// on [downloadState]. Only one edition downloads at a time; call
  /// [cancelDownload] to stop. Already-cached pages are kept.
  Future<void> downloadEdition(TafsirEdition edition) async {
    if (!edition.isOnline || downloadState.value.isDownloading) return;
    _cancelDownload = false;

    final total = TafsirEdition.onlinePageCount;
    final dir = await _editionDir(edition);

    int done = await cachedPageCount(edition);
    downloadState.value = TafsirDownloadState(
      editionId: edition.id,
      isDownloading: true,
      done: done,
      total: total,
    );

    final client = http.Client();
    try {
      for (int page = 1; page <= total; page++) {
        if (_cancelDownload) break;
        final file =
            File(p.join(dir.path, TafsirEdition.pageFileName(page)));
        if (await file.exists()) continue;
        try {
          final response = await client.get(Uri.parse(edition.pageUrl(page)));
          if (response.statusCode == 200) {
            await file.writeAsBytes(response.bodyBytes);
            done++;
            state.value = state.value.copyWith(
              installedBytes: state.value.installedBytes + response.bodyBytes.length,
            );
            downloadState.value = TafsirDownloadState(
              editionId: edition.id,
              isDownloading: true,
              done: done,
              total: total,
            );
          }
        } catch (_) {
          // Skipped pages fetch on-demand later when viewed.
        }
      }
    } finally {
      client.close();
      _cancelDownload = false;
      downloadState.value = const TafsirDownloadState();
    }
  }

  /// Requests the in-flight [downloadEdition] to stop after the current page.
  void cancelDownload() {
    if (downloadState.value.isDownloading) _cancelDownload = true;
  }

  /// Deletes just [edition]'s cached pages (cancels its download first if it is
  /// the one running), then recomputes the total size.
  Future<void> deleteEdition(TafsirEdition edition) async {
    if (!edition.isOnline) return;
    if (downloadState.value.editionId == edition.id) _cancelDownload = true;
    try {
      final dir = await _editionDir(edition);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    await _recomputeSize();
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<void>? _recutPurge;

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
    if (_scanned || kIsWeb) return;
    _scanned = true;
    await _recomputeSize();
  }

  Future<void> _recomputeSize() async {
    if (kIsWeb) return;
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
  /// it has not been fetched yet. Always null on web — no persistent disk
  /// cache there (dart:io is unavailable), so tafsir_service falls straight
  /// through to a network fetch, which now works since the R2 bucket serves
  /// CORS headers.
  Future<String?> readPage(TafsirEdition edition, int pageNumber) async {
    if (!edition.isOnline || kIsWeb) return null;
    await _ensureRecutPagesPurged();
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
    if (!edition.isOnline || kIsWeb) return;
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

  // ── One-off migration: the 2026-08 page re-cut ───────────────────────────
  //
  // 50 pages of assets/data/output.json were re-cut against the printed mushaf
  // (an ayah had been filed under the wrong page — e.g. 20:86 was listed on
  // p318 but is printed on p317). The per-page tafsir files on R2 were rebuilt
  // to match, but a cached page is never re-fetched — writePage/readPage have
  // no version check and downloadEdition skips files that already exist. So a
  // device holding the old bundle for one of these pages would keep showing
  // 'تفسير غير متوفر' for the ayat that moved in. Deleting just those files
  // makes them re-download lazily; everything else stays cached.
  static const String _recutPurgeKey = 'tafsir_cache_purge_page_recut_2026_08';

  /// Pages whose ayah set changed in the re-cut. Only these are stale — the
  /// other 552 page files rebuilt byte-identical, so they are left alone.
  static const List<int> _recutPages = [
    42, 43, 116, 117, 118, 119, 120, 121, 122, 123,
    200, 201, 202, 208, 209, 270, 271, 272, 273, 274,
    317, 318, 330, 331, 381, 382, 383, 384,
    419, 420, 421, 422, 423, 424, 440, 441,
    497, 498, 499, 500, 553, 554, 555, 556,
    561, 562, 564, 565, 566, 567,
  ];

  /// Runs [_purgeRecutPages] at most once per process, before the first cache
  /// read. Off the launch path by construction — nothing touches the tafsir
  /// cache until a tafsir is actually opened.
  Future<void> _ensureRecutPagesPurged() =>
      _recutPurge ??= _purgeRecutPages();

  Future<void> _purgeRecutPages() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_recutPurgeKey) ?? false) return;

      var freed = 0;
      final appDir = await getApplicationSupportDirectory();
      for (final edition in TafsirEdition.onlineEditions) {
        final dir = Directory(p.join(appDir.path, edition.cacheFolder));
        if (!await dir.exists()) continue;
        for (final page in _recutPages) {
          final file =
              File(p.join(dir.path, TafsirEdition.pageFileName(page)));
          try {
            if (await file.exists()) {
              freed += await file.length();
              await file.delete();
            }
          } catch (_) {}
        }
      }
      await prefs.setBool(_recutPurgeKey, true);

      if (freed > 0) {
        state.value = state.value.copyWith(
          installedBytes: (state.value.installedBytes - freed).clamp(0, 1 << 62),
        );
      }
    } catch (_) {
      // Leave the flag unset so the purge is retried next launch.
    }
  }

  /// Deletes every cached tafsir page for all online editions.
  Future<void> deleteCache() async {
    if (kIsWeb) return;
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
    if (!edition.isOnline || kIsWeb) return 0;
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
    // Whole-edition download is a persistent-disk-cache feature; nothing to
    // do on web (matches the offline full-audio download tile, also hidden
    // there — see project notes on web platform limitations).
    if (!edition.isOnline || downloadState.value.isDownloading || kIsWeb) {
      return;
    }
    _cancelDownload = false;
    // Before counting what's cached: the loop below keeps every existing file,
    // so a stale re-cut page would survive a full download untouched.
    await _ensureRecutPagesPurged();

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
    if (!edition.isOnline || kIsWeb) return;
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

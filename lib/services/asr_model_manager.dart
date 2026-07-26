import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Download state for the on-device recognition model files.
enum AsrModelState { notDownloaded, downloading, ready, failed }

/// Manages the on-device speech-recognition model files used by the
/// memorization test: the Quran-tuned Whisper encoder/decoder (ONNX,
/// exported from tarteel-ai/whisper-base-ar-quran via sherpa-onnx's export
/// pipeline), its tokens file, and the Silero VAD model.
///
/// Follows `HighQualityImagesService`'s precedent: big binaries are never
/// bundled in the app package -- they're downloaded once on explicit user
/// action and cached under the app-support directory. Download progress is
/// exposed via `ValueNotifier`s per this codebase's service pattern.
///
/// Files are served from [baseUrl] (the app's existing Cloudflare R2
/// bucket). For development, files pushed manually into [modelDirectory]
/// (e.g. via `adb push`) are honored without any download -- [refresh]
/// only checks local presence.
class AsrModelManager {
  AsrModelManager._internal();
  static final AsrModelManager instance = AsrModelManager._internal();

  /// Base URL the model files are fetched from. Must end with a slash.
  ///
  /// Points at the `quran-content` R2 bucket under `asr/` (same bucket that
  /// hosts the tafsir editions). The four files (base-encoder.int8.onnx,
  /// base-decoder.int8.onnx, base-tokens.txt, silero_vad.onnx) live there;
  /// the in-app download prompt (see `_promptAndDownloadAsrModel` in
  /// quran_pages.dart) fetches them on first use. All four verified live
  /// (HTTP 200, correct sizes) on 2026-07-24.
  static const String baseUrl =
      'https://pub-5025f0d14b9046309795201770f30da1.r2.dev/asr/';

  /// Expected files with their sizes in bytes (the actual exported int8
  /// artifacts). Sizes drive progress reporting and a sanity floor (a
  /// small "not found" HTML page must never be accepted as a model file);
  /// they are NOT an exact-match check, so a re-export whose size shifts a
  /// little won't brick the download flow.
  static const Map<String, int> _files = {
    'base-encoder.int8.onnx': 29104806,
    'base-decoder.int8.onnx': 130659024,
    'base-tokens.txt': 866987,
    'silero_vad.onnx': 643854,
  };

  final ValueNotifier<AsrModelState> state =
      ValueNotifier(AsrModelState.notDownloaded);

  /// 0..1 while [state] is `downloading`.
  final ValueNotifier<double> progress = ValueNotifier(0);

  Directory? _internalDir;
  http.Client? _client;

  /// Where downloads are written: app-private support storage.
  Future<Directory> modelDirectory() async {
    if (_internalDir != null) return _internalDir!;
    final support = await getApplicationSupportDirectory();
    _internalDir =
        Directory('${support.path}${Platform.pathSeparator}asr_model');
    return _internalDir!;
  }

  /// App-scoped external "dev drop" (`/sdcard/Android/data/[pkg]/files/
  /// asr_model` on Android), or null where unavailable. This location is
  /// writable by `adb push` WITHOUT root, so model files can be placed on a
  /// device for testing before R2 hosting exists. Read-only as far as the
  /// app is concerned -- downloads never target it.
  Future<Directory?> _externalDropDirectory() async {
    if (kIsWeb) return null;
    try {
      final ext = await getExternalStorageDirectory();
      if (ext == null) return null;
      return Directory('${ext.path}${Platform.pathSeparator}asr_model');
    } catch (_) {
      return null;
    }
  }

  /// The directory the model is actually read from: the external dev-drop
  /// when it holds a complete set, otherwise the internal download dir.
  Future<Directory> effectiveModelDirectory() async {
    final drop = await _externalDropDirectory();
    if (drop != null && await _dirHasAllFiles(drop)) return drop;
    return modelDirectory();
  }

  Future<String> pathFor(String fileName) async {
    final dir = await effectiveModelDirectory();
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }

  /// True when [dir] contains every expected file at a plausible size.
  /// Sanity floor at 1% of the expected size catches truncated files and
  /// error-page responses without rejecting legitimate re-exports whose
  /// size shifted.
  Future<bool> _dirHasAllFiles(Directory dir) async {
    for (final entry in _files.entries) {
      final file = File('${dir.path}${Platform.pathSeparator}${entry.key}');
      if (!await file.exists() || await file.length() < entry.value ~/ 100) {
        return false;
      }
    }
    return true;
  }

  /// Rough total download size, for the user-facing prompt.
  int get totalDownloadBytes =>
      _files.values.fold(0, (sum, size) => sum + size);

  /// Re-checks local file presence (external dev-drop or internal dir) and
  /// updates [state]. Never touches the network.
  Future<bool> refresh() async {
    final allPresent = await _dirHasAllFiles(await effectiveModelDirectory());
    if (state.value != AsrModelState.downloading) {
      state.value =
          allPresent ? AsrModelState.ready : AsrModelState.notDownloaded;
    }
    return allPresent;
  }

  /// Downloads any missing model files. No-op if already [AsrModelState.ready]
  /// or a download is in flight.
  Future<void> download() async {
    if (state.value == AsrModelState.downloading) return;
    if (await refresh()) return;

    state.value = AsrModelState.downloading;
    progress.value = 0;
    final client = http.Client();
    _client = client;
    try {
      final dir = await modelDirectory();
      await dir.create(recursive: true);

      final total = totalDownloadBytes;
      var doneBytes = 0;

      for (final entry in _files.entries) {
        final target = File(
          '${dir.path}${Platform.pathSeparator}${entry.key}',
        );
        if (await target.exists() &&
            await target.length() >= entry.value ~/ 100) {
          doneBytes += entry.value;
          progress.value = doneBytes / total;
          continue;
        }

        final partFile = File('${target.path}.part');
        final request = http.Request('GET', Uri.parse('$baseUrl${entry.key}'));
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw HttpException(
            'HTTP ${response.statusCode} for ${entry.key}',
            uri: request.url,
          );
        }

        final sink = partFile.openWrite();
        var fileBytes = 0;
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            fileBytes += chunk.length;
            progress.value =
                ((doneBytes + fileBytes) / total).clamp(0.0, 1.0);
          }
        } finally {
          await sink.close();
        }

        if (fileBytes < entry.value ~/ 100) {
          await partFile.delete();
          throw HttpException(
            'Suspiciously small download for ${entry.key} ($fileBytes bytes)',
            uri: request.url,
          );
        }
        if (await target.exists()) await target.delete();
        await partFile.rename(target.path);
        doneBytes += entry.value;
      }

      state.value = AsrModelState.ready;
      progress.value = 1;
    } catch (error) {
      debugPrint('AsrModelManager: download failed: $error');
      state.value = AsrModelState.failed;
    } finally {
      _client = null;
      client.close();
    }
  }

  /// Aborts an in-flight download (files partially downloaded stay as
  /// `.part` and are resumed-from-scratch next time -- model files are
  /// small enough that byte-range resume isn't worth the complexity here).
  void cancelDownload() {
    _client?.close();
  }
}

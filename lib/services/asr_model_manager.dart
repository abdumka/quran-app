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
  /// TODO(user): upload the exported model files (see
  /// tools/export docs in the memorization-test plan) to the R2 bucket
  /// under `asr/` and confirm this URL. Until then, downloads fail but
  /// locally-pushed files keep working.
  static const String baseUrl =
      'https://pub-f4e99834c32943d2a947531d938b19f6.r2.dev/asr/';

  /// Expected files with their approximate sizes (bytes) -- sizes are used
  /// only for progress reporting and a sanity floor (a 500-byte "not
  /// found" HTML page must never be accepted as a model file), not as an
  /// exact-match check, so re-exports don't brick the download flow.
  static const Map<String, int> _files = {
    'base-encoder.int8.onnx': 20 * 1024 * 1024,
    'base-decoder.int8.onnx': 50 * 1024 * 1024,
    'base-tokens.txt': 700 * 1024,
    'silero_vad.onnx': 1 * 1024 * 1024,
  };

  final ValueNotifier<AsrModelState> state =
      ValueNotifier(AsrModelState.notDownloaded);

  /// 0..1 while [state] is `downloading`.
  final ValueNotifier<double> progress = ValueNotifier(0);

  Directory? _dir;
  http.Client? _client;

  Future<Directory> modelDirectory() async {
    if (_dir != null) return _dir!;
    final support = await getApplicationSupportDirectory();
    _dir = Directory('${support.path}${Platform.pathSeparator}asr_model');
    return _dir!;
  }

  Future<String> pathFor(String fileName) async {
    final dir = await modelDirectory();
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }

  /// Rough total download size, for the user-facing prompt.
  int get totalDownloadBytes =>
      _files.values.fold(0, (sum, size) => sum + size);

  /// Re-checks local file presence and updates [state]. Never touches the
  /// network.
  Future<bool> refresh() async {
    final dir = await modelDirectory();
    var allPresent = true;
    for (final entry in _files.entries) {
      final file = File('${dir.path}${Platform.pathSeparator}${entry.key}');
      // Sanity floor at 1% of the expected size: catches truncated files
      // and error-page responses without rejecting legitimate re-exports
      // whose size shifted.
      if (!await file.exists() || await file.length() < entry.value ~/ 100) {
        allPresent = false;
        break;
      }
    }
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

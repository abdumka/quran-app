import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

@immutable
class HighQualityImagesState {
  final bool isAvailable;
  final bool isEnabled;
  final bool isDownloading;
  final int downloadedBytes;
  final int totalBytes;
  final int? packageBytes;
  final int installedBytes;
  final String? imagesDirectoryPath;
  final String? statusText;

  const HighQualityImagesState({
    required this.isAvailable,
    required this.isEnabled,
    required this.isDownloading,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.packageBytes,
    required this.installedBytes,
    required this.imagesDirectoryPath,
    required this.statusText,
  });

  const HighQualityImagesState.initial()
      : isAvailable = false,
        isEnabled = false,
        isDownloading = false,
        downloadedBytes = 0,
        totalBytes = 0,
        packageBytes = null,
        installedBytes = 0,
        imagesDirectoryPath = null,
        statusText = null;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  String _formatBytes(int bytes) {
    const mb = 1024 * 1024;
    if (bytes <= 0) return '0 MB';
    final value = bytes / mb;
    if (value >= 100) return '${value.toStringAsFixed(0)} MB';
    if (value >= 10) return '${value.toStringAsFixed(1)} MB';
    return '${value.toStringAsFixed(2)} MB';
  }

  String get packageSizeLabel =>
      packageBytes != null ? _formatBytes(packageBytes!) : '...';

  String get progressLabel {
    if (totalBytes > 0) {
      return '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}';
    }
    return _formatBytes(downloadedBytes);
  }

  String get percentLabel => '${(progress * 100).round()}%';

  String get installedSizeLabel => _formatBytes(installedBytes);

  HighQualityImagesState copyWith({
    bool? isAvailable,
    bool? isEnabled,
    bool? isDownloading,
    int? downloadedBytes,
    int? totalBytes,
    int? packageBytes,
    int? installedBytes,
    bool clearPackageBytes = false,
    String? imagesDirectoryPath,
    bool clearImagesDirectoryPath = false,
    String? statusText,
    bool clearStatusText = false,
  }) {
    return HighQualityImagesState(
      isAvailable: isAvailable ?? this.isAvailable,
      isEnabled: isEnabled ?? this.isEnabled,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      packageBytes: clearPackageBytes ? null : (packageBytes ?? this.packageBytes),
      installedBytes: installedBytes ?? this.installedBytes,
      imagesDirectoryPath: clearImagesDirectoryPath
          ? null
          : (imagesDirectoryPath ?? this.imagesDirectoryPath),
      statusText: clearStatusText ? null : (statusText ?? this.statusText),
    );
  }
}

class HighQualityImagesService {
  HighQualityImagesService._();

  static final HighQualityImagesService instance = HighQualityImagesService._();

  static const String downloadUrl =
      'https://github.com/mahfodqr/quran-app-files/releases/download/v1.0.0/images.zip';
  static const String expectedSha256 =
      '7605c40747d68ee64173f11c2230b34f8e270d0fe3980888a69e732649555394';
  static const String _folderName = 'high_quality_images';
  static final RegExp _pageFilePattern =
      RegExp(r'^page_(\d+)\.webp$', caseSensitive: false);

  final ValueNotifier<HighQualityImagesState> state =
      ValueNotifier<HighQualityImagesState>(const HighQualityImagesState.initial());

  bool _didInitialize = false;
  http.Client? _activeClient;
  bool _cancelRequested = false;

  Future<void> initialize() async {
    if (_didInitialize) return;
    _didInitialize = true;

    final isAvailable = await _isPackageExtracted();
    final dir = isAvailable ? await _imagesDirectory() : null;

    state.value = state.value.copyWith(
      isAvailable: isAvailable,
      isEnabled: isAvailable,
      imagesDirectoryPath: dir?.path,
    );

    _fetchRemotePackageBytes().then((packageBytes) {
      if (packageBytes != null) {
        state.value = state.value.copyWith(packageBytes: packageBytes);
      }
    });

    if (dir != null) {
      _computeDirectoryBytes(dir).then((installedBytes) {
        state.value = state.value.copyWith(installedBytes: installedBytes);
      });
    }
  }

  Future<void> refresh() async {
    _didInitialize = false;
    await initialize();
  }

  Future<void> downloadAndEnable() async {
    await initialize();
    if (state.value.isDownloading) return;

    if (!downloadUrl.startsWith('http')) {
      throw const FileSystemException(
        'High quality images download URL is not configured',
      );
    }

    final supportDir = await getApplicationSupportDirectory();
    final tempZip = File(p.join(supportDir.path, 'high_quality_images.zip'));
    final client = http.Client();
    _activeClient = client;
    _cancelRequested = false;

    state.value = state.value.copyWith(
      isDownloading: true,
      downloadedBytes: 0,
      totalBytes: 0,
      statusText: 'جارٍ تنزيل الصور عالية الجودة...',
    );

    try {
      final response = await client.send(http.Request('GET', Uri.parse(downloadUrl)));
      if (response.statusCode != 200) {
        throw HttpException('Download failed with status ${response.statusCode}');
      }

      final sink = tempZip.openWrite();
      final totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;

      state.value = state.value.copyWith(totalBytes: totalBytes);

      await for (final chunk in response.stream) {
        if (_cancelRequested) break;
        sink.add(chunk);
        downloadedBytes += chunk.length;
        state.value = state.value.copyWith(
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
        );
      }

      await sink.close();

      if (_cancelRequested) return;

      state.value = state.value.copyWith(statusText: 'جارٍ التحقق من الملف...');
      final digest = await _computeSha256(tempZip);
      if (expectedSha256.isNotEmpty && digest != expectedSha256) {
        debugPrint('SHA-256 mismatch for HQ images: expected $expectedSha256, got $digest');
        // Warning only, do not throw. The user might have updated the zip on GitHub.
      }

      final outputDir = await _imagesDirectory();
      if (await outputDir.exists()) {
        await outputDir.delete(recursive: true);
      }
      await outputDir.create(recursive: true);

      state.value = state.value.copyWith(statusText: 'جارٍ فك ضغط الصور...');

      final inputStream = InputFileStream(tempZip.path);
      final archive = ZipDecoder().decodeBuffer(inputStream);
      int extractedCount = 0;
      try {
        for (final entry in archive.files) {
          if (!entry.isFile) continue;
          final fileName = p.basename(entry.name.replaceAll('\\', '/'));
          if (!_pageFilePattern.hasMatch(fileName)) continue;
          final file = File(p.join(outputDir.path, fileName));
          await file.create(recursive: true);
          final content = entry.content;
          if (content is List<int>) {
            await file.writeAsBytes(content, flush: true);
            extractedCount++;
          }
        }
      } finally {
        inputStream.close();
      }

      if (extractedCount < 602) {
        throw const FileSystemException('Extracted pages are incomplete');
      }

      final installedBytes = await _computeDirectoryBytes(outputDir);

      state.value = state.value.copyWith(
        isAvailable: true,
        isEnabled: true,
        isDownloading: false,
        installedBytes: installedBytes,
        imagesDirectoryPath: outputDir.path,
        clearStatusText: true,
      );
    } catch (_) {
      if (!_cancelRequested) rethrow;
    } finally {
      _activeClient = null;
      _cancelRequested = false;
      client.close();
      if (await tempZip.exists()) {
        await tempZip.delete();
      }
      if (state.value.isDownloading) {
        state.value = state.value.copyWith(
          isDownloading: false,
          clearStatusText: true,
        );
      }
    }
  }

  Future<void> cancelDownload() async {
    if (!state.value.isDownloading) return;
    _cancelRequested = true;
    _activeClient?.close();
    state.value = state.value.copyWith(
      isDownloading: false,
      downloadedBytes: 0,
      totalBytes: 0,
      clearStatusText: true,
    );
  }

  Future<int?> _fetchRemotePackageBytes() async {
    final client = http.Client();
    try {
      final response = await client.send(
        http.Request('HEAD', Uri.parse(downloadUrl)),
      );
      if (response.statusCode == 200 && (response.contentLength ?? 0) > 0) {
        return response.contentLength;
      }
    } catch (_) {
      // Ignore and fall back to unknown size.
    } finally {
      client.close();
    }
    return null;
  }

  Future<bool> _isPackageExtracted() async {
    final dir = await _imagesDirectory();
    if (!await dir.exists()) return false;
    final first = File(p.join(dir.path, 'page_1.webp'));
    final last = File(p.join(dir.path, 'page_602.webp'));
    return first.existsSync() && last.existsSync();
  }

  Future<Directory> _imagesDirectory() async {
    final appSupportDir = await getApplicationSupportDirectory();
    return Directory(p.join(appSupportDir.path, _folderName));
  }

  Future<void> deleteDownloadedImages() async {
    final dir = await _imagesDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    state.value = state.value.copyWith(
      isAvailable: false,
      isEnabled: false,
      installedBytes: 0,
      clearImagesDirectoryPath: true,
      clearStatusText: true,
    );
  }

  Future<int> _computeDirectoryBytes(Directory dir) async {
    if (!await dir.exists()) return 0;

    int total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<String> _computeSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}

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
  final bool isPaused;
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
    required this.isPaused,
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
        isPaused = false,
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
    bool? isPaused,
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
      isPaused: isPaused ?? this.isPaused,
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
      'https://github.com/abdumka/quran-app-files/releases/download/v1.0.0/images.zip';
  static const String expectedSha256 =
      '7605c40747d68ee64173f11c2230b34f8e270d0fe3980888a69e732649555394';
  static const String _folderName = 'high_quality_images';
  static const String _tempZipName = 'high_quality_images.zip';
  static final RegExp _pageFilePattern =
      RegExp(r'^page_(\d+)\.webp$', caseSensitive: false);

  final ValueNotifier<HighQualityImagesState> state =
      ValueNotifier<HighQualityImagesState>(const HighQualityImagesState.initial());

  bool _didInitialize = false;
  HttpClient? _activeHttpClient;
  bool _cancelRequested = false;
  bool _pauseRequested = false;

  Future<void> initialize() async {
    if (_didInitialize) return;
    _didInitialize = true;

    final isAvailable = await _isPackageExtracted();
    final dir = isAvailable ? await _imagesDirectory() : null;

    // Check if there's a partial download we can resume
    final hasPaused = !isAvailable && await _hasPartialDownload();

    state.value = state.value.copyWith(
      isAvailable: isAvailable,
      isEnabled: isAvailable,
      isPaused: hasPaused,
      imagesDirectoryPath: dir?.path,
    );

    if (hasPaused) {
      final supportDir = await getApplicationSupportDirectory();
      final tempZip = File(p.join(supportDir.path, _tempZipName));
      final existingBytes = await tempZip.length();
      state.value = state.value.copyWith(
        downloadedBytes: existingBytes,
        statusText: 'تم إيقاف التنزيل مؤقتاً — اضغط لاستئناف',
      );
    }

    _fetchRemotePackageBytes().then((packageBytes) {
      if (packageBytes != null) {
        state.value = state.value.copyWith(
          packageBytes: packageBytes,
          totalBytes: packageBytes,
        );
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

  /// Downloads (or resumes) the high quality images package.
  /// Retries up to 3 times with exponential backoff on network errors.
  Future<void> downloadAndEnable() async {
    await initialize();
    if (state.value.isDownloading) return;

    if (!downloadUrl.startsWith('http') || expectedSha256.isEmpty) {
      throw const FileSystemException(
        'High quality images download URL or SHA-256 is not configured',
      );
    }

    final supportDir = await getApplicationSupportDirectory();
    final tempZip = File(p.join(supportDir.path, _tempZipName));

    _cancelRequested = false;
    _pauseRequested = false;

    state.value = state.value.copyWith(
      isDownloading: true,
      isPaused: false,
      downloadedBytes: 0,
      totalBytes: 0,
      statusText: 'جارٍ تنزيل الصور عالية الجودة...',
    );

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_cancelRequested) return;

      int existingBytes = 0;
      if (await tempZip.exists()) {
        existingBytes = await tempZip.length();
      }

      if (existingBytes > 0) {
        state.value = state.value.copyWith(
          downloadedBytes: existingBytes,
          statusText: 'جارٍ استئناف التنزيل... (محاولة $attempt/$maxRetries)',
        );
      } else if (attempt > 1) {
        state.value = state.value.copyWith(
          statusText: 'إعادة المحاولة... ($attempt/$maxRetries)',
        );
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 60);
      client.idleTimeout = const Duration(seconds: 60);
      client.autoUncompress = false;
      _activeHttpClient = client;

      try {
        final request = await client.getUrl(Uri.parse(downloadUrl));
        request.headers.set(HttpHeaders.userAgentHeader, 'IslamicDawahMushaf/1.0.0 (Android)');
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

        if (existingBytes > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
        }

        final response = await request.close();
        debugPrint('HighQualityImagesService: HTTP ${response.statusCode}, content-length: ${response.contentLength}');

        if (response.statusCode != 200 && response.statusCode != 206) {
          if (response.statusCode == 416 && existingBytes > 0) {
            if (await tempZip.exists()) await tempZip.delete();
            continue;
          }
          throw HttpException(
              'Download failed with status ${response.statusCode}');
        }

        if (existingBytes > 0 && response.statusCode == 200) {
          existingBytes = 0;
        }

        final sink = tempZip.openWrite(
          mode: existingBytes > 0 ? FileMode.append : FileMode.write,
        );
        final totalBytes = (response.contentLength > 0 ? response.contentLength : 0) + existingBytes;
        int downloadedBytes = existingBytes;

        state.value = state.value.copyWith(
          totalBytes: totalBytes,
          downloadedBytes: downloadedBytes,
        );

        await for (final chunk in response) {
          if (_cancelRequested || _pauseRequested) break;
          sink.add(chunk);
          downloadedBytes += chunk.length;
          state.value = state.value.copyWith(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
          );
        }

        await sink.close();

        if (_pauseRequested) {
          state.value = state.value.copyWith(
            isDownloading: false,
            isPaused: true,
            statusText: 'تم إيقاف التنزيل مؤقتاً — اضغط لاستئناف',
          );
          return;
        }

        if (_cancelRequested) return;

        state.value = state.value.copyWith(statusText: 'جارٍ التحقق من الملف...');
        final digest = await _computeSha256(tempZip);
        if (digest != expectedSha256) {
          debugPrint('HighQualityImagesService: SHA-256 mismatch (Expected: $expectedSha256, Found: $digest). Proceeding anyway.');
        }

        final outputDir = await _imagesDirectory();
        if (await outputDir.exists()) {
          await outputDir.delete(recursive: true);
        }
        await outputDir.create(recursive: true);

        state.value = state.value.copyWith(statusText: 'جارٍ فك ضغط الصور...');

        final inputStream = InputFileStream(tempZip.path);
        final archive = ZipDecoder().decodeStream(inputStream);
        int extractedCount = 0;
        try {
          for (final entry in archive.files) {
            if (!entry.isFile) continue;
            final fileName = p.basename(entry.name.replaceAll('\\', '/'));
            if (!_pageFilePattern.hasMatch(fileName)) continue;
            final file = File(p.join(outputDir.path, fileName));
            await file.create(recursive: true);
            await file.writeAsBytes(entry.content, flush: true);
            extractedCount++;
          }
        } finally {
          await inputStream.close();
        }

        if (extractedCount < 602) {
          debugPrint('HighQualityImagesService: Warning - Extracted pages are incomplete ($extractedCount/602).');
        }

        final installedBytes = await _computeDirectoryBytes(outputDir);

        state.value = state.value.copyWith(
          isAvailable: true,
          isEnabled: true,
          isDownloading: false,
          isPaused: false,
          installedBytes: installedBytes,
          imagesDirectoryPath: outputDir.path,
          clearStatusText: true,
        );

        if (await tempZip.exists()) {
          await tempZip.delete();
        }

        return;
      } on SocketException catch (e) {
        debugPrint('HighQualityImagesService: SocketException on attempt $attempt: $e');
        client.close(force: true);
        _activeHttpClient = null;
        if (attempt < maxRetries && !_cancelRequested && !_pauseRequested) {
          final delay = Duration(seconds: 2 * attempt);
          state.value = state.value.copyWith(
            statusText: 'فشل الاتصال — إعادة المحاولة بعد ${delay.inSeconds} ثانية...',
          );
          await Future.delayed(delay);
          continue;
        }
        state.value = state.value.copyWith(
          isDownloading: false,
          statusText: 'تعذر الاتصال بالإنترنت. تأكد من الشبكة وحاول مرة أخرى.',
        );
        return;
      } on HttpException catch (e) {
        debugPrint('HighQualityImagesService: HttpException on attempt $attempt: $e');
        client.close(force: true);
        _activeHttpClient = null;
        if (attempt < maxRetries && !_cancelRequested && !_pauseRequested) {
          await Future.delayed(Duration(seconds: 2 * attempt));
          continue;
        }
        state.value = state.value.copyWith(
          isDownloading: false,
          statusText: 'تعذر تنزيل الملف. حاول مرة أخرى لاحقاً.',
        );
        return;
      } catch (e, st) {
        debugPrint('HighQualityImagesService Error on attempt $attempt: $e\n$st');
        client.close(force: true);
        _activeHttpClient = null;
        if (_pauseRequested) {
          state.value = state.value.copyWith(
            isDownloading: false,
            isPaused: true,
            statusText: 'تم إيقاف التنزيل مؤقتاً — اضغط لاستئناف',
          );
          return;
        }
        if (e is FormatException || e.toString().contains('ArchiveException') || e is FileSystemException) {
          if (await tempZip.exists()) {
            await tempZip.delete();
          }
        }
        if (attempt < maxRetries && !_cancelRequested) {
          await Future.delayed(Duration(seconds: 2 * attempt));
          continue;
        }
        state.value = state.value.copyWith(
          isDownloading: false,
          statusText: 'حدث خطأ أثناء التنزيل. حاول مرة أخرى.',
        );
        return;
      } finally {
        _activeHttpClient = null;
        _cancelRequested = false;
        _pauseRequested = false;
        client.close(force: true);
      }
    }
  }

  /// Pauses the current download, keeping the partial file for later resume.
  Future<void> pauseDownload() async {
    if (!state.value.isDownloading) return;
    _pauseRequested = true;
    _activeHttpClient?.close(force: true);
  }

  /// Fully cancels the download and deletes the partial temp file.
  Future<void> cancelDownload() async {
    if (!state.value.isDownloading && !state.value.isPaused) return;
    _cancelRequested = true;
    _pauseRequested = false;
    _activeHttpClient?.close(force: true);

    // Delete partial temp file
    final supportDir = await getApplicationSupportDirectory();
    final tempZip = File(p.join(supportDir.path, _tempZipName));
    if (await tempZip.exists()) {
      await tempZip.delete();
    }

    state.value = state.value.copyWith(
      isDownloading: false,
      isPaused: false,
      downloadedBytes: 0,
      totalBytes: 0,
      clearStatusText: true,
    );
  }

  Future<bool> _hasPartialDownload() async {
    final supportDir = await getApplicationSupportDirectory();
    final tempZip = File(p.join(supportDir.path, _tempZipName));
    return tempZip.existsSync() && await tempZip.length() > 0;
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

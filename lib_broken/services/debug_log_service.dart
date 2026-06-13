import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class DebugLogService {
  DebugLogService._();

  static final DebugLogService instance = DebugLogService._();

  File? _logFile;
  bool _initialized = false;
  int _sequence = 0;
  final List<String> _memoryLines = <String>[];

  String? get logFilePath => _logFile?.path;

  Future<void> initialize() async {
    if (_initialized) return;

    _initialized = true;
    final logFile = await _tryOpenLogFile();
    if (logFile != null) {
      _logFile = logFile;
      log('DebugLogService initialized path=${_logFile!.path}');
    } else {
      log('DebugLogService initialized without file sink');
    }
    divider('session-start');
  }

  Future<File?> _tryOpenLogFile() async {
    for (final directory in await _resolveLogDirectories()) {
      try {
        await directory.create(recursive: true);
        final file = File(
          '${directory.path}${Platform.pathSeparator}quran_debug.log',
        );
        await file.writeAsString('', flush: true);
        return file;
      } catch (_) {
        // Try the next candidate path.
      }
    }
    return null;
  }

  Future<List<Directory>> _resolveLogDirectories() async {
    final candidates = <String>{};
    void addPath(String? path) {
      if (path == null || path.isEmpty) return;
      candidates.add(path);
    }

    addPath(Platform.environment['TMPDIR']);
    addPath(Platform.environment['TEMP']);
    addPath(Platform.environment['TMP']);
    addPath(Directory.systemTemp.path);
    addPath(Directory.current.path);

    return candidates
        .map(
          (path) => Directory(
            '$path${Platform.pathSeparator}islamic_dawah_mushaf_logs',
          ),
        )
        .toList();
  }

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _sequence += 1;
    final line = '[#$_sequence][$timestamp] $message';
    _memoryLines.add(line);
    if (_memoryLines.length > 4000) {
      _memoryLines.removeRange(0, _memoryLines.length - 4000);
    }
    debugPrint(line);
    final file = _logFile;
    if (file != null) {
      unawaited(
        file.writeAsString(
          '$line\n',
          mode: FileMode.append,
          flush: true,
        ).catchError((_) => file),
      );
    }
  }

  void divider([String label = '']) {
    final suffix = label.isEmpty ? '' : ' $label ';
    log('================$suffix================');
  }

  void event(String source, String name, [Map<String, Object?> details = const {}]) {
    final payload = details.entries
        .map((entry) => '${entry.key}=${_sanitize(entry.value)}')
        .join(' ');
    if (payload.isEmpty) {
      log('[$source] $name');
      return;
    }
    log('[$source] $name $payload');
  }

  String _sanitize(Object? value) {
    if (value == null) return 'null';
    return value.toString().replaceAll('\n', '\\n');
  }

  Future<void> flush() async {
    return;
  }

  Future<String> readAll() async {
    final file = _logFile;
    if (file == null || !await file.exists()) {
      if (_memoryLines.isEmpty) {
        return 'No debug log file found.';
      }
      return _memoryLines.join('\n');
    }
    return file.readAsString();
  }

  Future<void> clear() async {
    _memoryLines.clear();
    _sequence = 0;
    final file = _logFile;
    if (file != null) {
      try {
        await file.writeAsString('', flush: true);
      } catch (_) {
        // Ignore file clear failures and keep memory log empty.
      }
    }
  }

  Future<void> dispose() async {
    return;
  }
}

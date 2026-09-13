import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved session on disk (its audio and/or log file).
class TasmeeSessionFiles {
  const TasmeeSessionFiles({
    required this.stem,
    required this.files,
    required this.bytes,
    required this.modified,
  });

  /// `tasmee_<timestamp>_p<page>` -- shared by the .wav and .jsonl.
  final String stem;
  final List<File> files;
  final int bytes;
  final DateTime modified;

  int? get page {
    final m = RegExp(r'_p(\d+)$').firstMatch(stem);
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}

/// Keeps a copy of every memorization-test session on disk -- the raw mic
/// audio as a 16 kHz mono WAV (real-engine sessions only) and an event log
/// (segments, decisions, feedback, decode timings, help buttons) as JSON
/// lines -- so a session that "felt wrong" can be shared and replayed
/// through the same pipeline offline.
///
/// Files live under the app's support directory in `tasmee_sessions/`;
/// only the most recent [keepCount] sessions are kept (user-configurable).
/// Nothing leaves the device unless the user explicitly shares the files.
class TasmeeSessionRecorder {
  TasmeeSessionRecorder._(this._dir, this._stem);

  static const String _keepPref = 'tasmee_log_keep_sessions';
  static const int defaultKeep = 20;
  static const List<int> keepChoices = [5, 10, 20, 50, 100];
  static const int _sampleRate = 16000;

  final Directory _dir;
  final String _stem;
  IOSink? _pcmSink;
  IOSink? _logSink;
  int _pcmBytes = 0;
  final Stopwatch _clock = Stopwatch();

  String get audioPath => '${_dir.path}${Platform.pathSeparator}$_stem.wav';
  String get logPath => '${_dir.path}${Platform.pathSeparator}$_stem.jsonl';
  String get _pcmPath => '${_dir.path}${Platform.pathSeparator}$_stem.pcm';

  static Future<Directory?> _sessionsDir() async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(
        '${support.path}${Platform.pathSeparator}tasmee_sessions',
      );
      await dir.create(recursive: true);
      return dir;
    } catch (error) {
      debugPrint('TasmeeSessionRecorder: no sessions dir: $error');
      return null;
    }
  }

  /// How many sessions to keep on disk.
  static Future<int> keepCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keepPref) ?? defaultKeep;
    } catch (_) {
      return defaultKeep;
    }
  }

  static Future<void> setKeepCount(int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keepPref, value);
    } catch (_) {}
    await prune();
  }

  /// Opens a new session's files, or returns null when the platform can't
  /// provide a directory (e.g. under `flutter test`).
  static Future<TasmeeSessionRecorder?> begin({
    required int page,
    required Map<String, Object?> info,
  }) async {
    final dir = await _sessionsDir();
    if (dir == null) return null;
    try {
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final recorder = TasmeeSessionRecorder._(dir, 'tasmee_${stamp}_p$page');
      recorder._pcmSink = File(recorder._pcmPath).openWrite();
      recorder._logSink = File(recorder.logPath).openWrite();
      recorder._clock.start();
      recorder.log('start', {'page': page, 'at': DateTime.now().toIso8601String(), ...info});
      await prune();
      return recorder;
    } catch (error) {
      debugPrint('TasmeeSessionRecorder: recording unavailable: $error');
      return null;
    }
  }

  void addAudio(Uint8List chunk) {
    _pcmSink?.add(chunk);
    _pcmBytes += chunk.length;
  }

  /// Appends one event. [data] must be JSON-encodable.
  void log(String event, [Map<String, Object?> data = const {}]) {
    final sink = _logSink;
    if (sink == null) return;
    sink.writeln(jsonEncode({
      't': _clock.elapsedMilliseconds,
      'ev': event,
      ...data,
    }));
  }

  /// Closes the log and turns the raw PCM into a playable WAV (or removes
  /// the empty PCM file when the session had no mic).
  Future<void> finish() async {
    log('end');
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
    await _pcmSink?.flush();
    await _pcmSink?.close();
    _pcmSink = null;
    try {
      final pcm = File(_pcmPath);
      if (await pcm.exists()) {
        if (_pcmBytes > 0) {
          final wav = File(audioPath).openWrite();
          wav.add(_wavHeader(_pcmBytes));
          await wav.addStream(pcm.openRead());
          await wav.close();
        }
        await pcm.delete();
      }
    } catch (error) {
      debugPrint('TasmeeSessionRecorder: wav conversion failed: $error');
    }
  }

  /// Every saved session, newest first.
  static Future<List<TasmeeSessionFiles>> listSessions() async {
    final dir = await _sessionsDir();
    if (dir == null) return const [];
    final byStem = <String, List<File>>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      byStem.putIfAbsent(stem, () => []).add(entity);
    }
    final out = <TasmeeSessionFiles>[];
    for (final entry in byStem.entries) {
      var bytes = 0;
      var modified = DateTime.fromMillisecondsSinceEpoch(0);
      for (final f in entry.value) {
        final stat = await f.stat();
        bytes += stat.size;
        if (stat.modified.isAfter(modified)) modified = stat.modified;
      }
      out.add(TasmeeSessionFiles(
        stem: entry.key,
        files: entry.value..sort((a, b) => a.path.compareTo(b.path)),
        bytes: bytes,
        modified: modified,
      ));
    }
    out.sort((a, b) => b.stem.compareTo(a.stem));
    return out;
  }

  static Future<void> deleteSession(TasmeeSessionFiles session) async {
    for (final f in session.files) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  static Future<void> deleteAll() async {
    for (final s in await listSessions()) {
      await deleteSession(s);
    }
  }

  /// Drops the oldest sessions beyond [keepCount].
  static Future<void> prune() async {
    final keep = await keepCount();
    final sessions = await listSessions();
    for (final s in sessions.skip(keep)) {
      await deleteSession(s);
    }
  }

  static Uint8List _wavHeader(int dataBytes) {
    final h = ByteData(44);
    void str(int at, String s) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    h.setUint32(4, 36 + dataBytes, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little); // PCM
    h.setUint16(22, 1, Endian.little); // mono
    h.setUint32(24, _sampleRate, Endian.little);
    h.setUint32(28, _sampleRate * 2, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    str(36, 'data');
    h.setUint32(40, dataBytes, Endian.little);
    return h.buffer.asUint8List();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps a copy of one memorization-test session on disk -- the raw mic
/// audio as a 16 kHz mono WAV and an event log (segments, decisions, decode
/// timings, help buttons) as JSON lines -- so a session that "felt wrong"
/// can be shared and replayed through the same pipeline offline.
///
/// Files live under the app's support directory in `tasmee_sessions/`;
/// only the most recent [_keep] sessions are kept. Nothing leaves the
/// device unless the user explicitly shares the files.
class TasmeeSessionRecorder {
  TasmeeSessionRecorder._(this._dir, this._stem);

  static const int _keep = 5;
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

  /// Opens a new session's files, or returns null when the platform can't
  /// provide a directory (e.g. under `flutter test`).
  static Future<TasmeeSessionRecorder?> begin({required int page}) async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}${Platform.pathSeparator}tasmee_sessions');
      await dir.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final recorder = TasmeeSessionRecorder._(dir, 'tasmee_${stamp}_p$page');
      recorder._pcmSink = File(recorder._pcmPath).openWrite();
      recorder._logSink = File(recorder.logPath).openWrite();
      recorder._clock.start();
      recorder.log('start', {'page': page});
      await recorder._prune();
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

  /// Closes the log and turns the raw PCM into a playable WAV.
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
        final wav = File(audioPath).openWrite();
        wav.add(_wavHeader(_pcmBytes));
        await wav.addStream(pcm.openRead());
        await wav.close();
        await pcm.delete();
      }
    } catch (error) {
      debugPrint('TasmeeSessionRecorder: wav conversion failed: $error');
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

  Future<void> _prune() async {
    try {
      final files = await _dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      final stems = <String>{};
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final dot = name.lastIndexOf('.');
        stems.add(dot > 0 ? name.substring(0, dot) : name);
      }
      final sorted = stems.toList()..sort();
      if (sorted.length <= _keep) return;
      final doomed = sorted.sublist(0, sorted.length - _keep).toSet();
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final dot = name.lastIndexOf('.');
        final stem = dot > 0 ? name.substring(0, dot) : name;
        if (doomed.contains(stem)) await f.delete();
      }
    } catch (_) {}
  }
}

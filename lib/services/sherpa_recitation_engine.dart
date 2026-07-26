import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'recitation_engine.dart';

/// Paths to the on-device model files (see `AsrModelManager`).
class SherpaModelPaths {
  const SherpaModelPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.vad,
  });

  final String encoder;
  final String decoder;
  final String tokens;
  final String vad;
}

/// The real recitation engine: microphone -> Silero VAD utterance
/// segmentation -> offline Whisper (Quran-tuned, ONNX) decoding, fully
/// on-device via sherpa_onnx.
///
/// All sherpa_onnx work (VAD + decoding) runs inside a dedicated long-lived
/// [Isolate] so multi-hundred-millisecond decode calls can never jank the
/// UI thread. Mic capture stays on the main isolate (the `record` plugin
/// needs the root isolate's platform channels) and raw PCM chunks are
/// forwarded to the worker.
///
/// ## Latency design
///
/// Waiting for a VAD-detected pause before decoding makes every reveal lag
/// the voice by (pause + decode) -- ~2s felt on a phone. Two measures cut
/// that:
///
///  * INTERIM decodes: while the VAD reports speech in progress, the worker
///    decodes the accumulated utterance every [_interimInterval]. Interim
///    text drops its last word (it may be a half-spoken word cut mid-air;
///    see [trimInterimResult]) and is fed to the aligner, whose
///    window/history design absorbs the resulting overlaps and repeats, so
///    words reveal WHILE the reciter keeps going.
///  * The FINAL decode of each VAD segment (after a pause) is authoritative
///    and re-covers the same audio in full.
///
/// The mic level ([audioLevel]) and decode activity ([busy]) are reported
/// so the UI can show live "I hear you" feedback.
class SherpaRecitationEngine extends RecitationEngine {
  SherpaRecitationEngine(this._paths);

  final SherpaModelPaths _paths;
  final _controller = StreamController<String>.broadcast();
  final _recorder = AudioRecorder();

  Isolate? _isolate;
  SendPort? _workerPort;
  StreamSubscription<Uint8List>? _micSub;
  ReceivePort? _receivePort;

  /// Interim (mid-utterance) results with fewer words than this are
  /// discarded outright -- one-word interims are most exposed to
  /// half-spoken-word noise.
  static const int _minInterimWords = 2;

  @override
  Stream<String> get segments => _controller.stream;

  /// Drops the trailing word of an interim (mid-utterance) transcription:
  /// the audio was cut while a word was possibly still being spoken, so the
  /// last decoded word is the least trustworthy and, if wrong twice in a
  /// row, could push the aligner's two-strike rule into a false `mistake`.
  /// Returns '' when fewer than [_minInterimWords] words remain.
  @visibleForTesting
  static String trimInterimResult(String text) {
    final words = text.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.length < _minInterimWords) return '';
    return words.sublist(0, words.length - 1).join(' ');
  }

  @override
  Future<void> start() async {
    // 1. Spawn the worker and wait for it to finish loading the models
    //    (decoder init is the slow part; doing it before opening the mic
    //    keeps us from dropping the first utterance).
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final readyCompleter = Completer<SendPort>();

    receivePort.listen((message) {
      if (message is SendPort) {
        readyCompleter.complete(message);
      } else if (message is String) {
        if (!_controller.isClosed) _controller.add(message);
      } else if (message is _LevelEvent) {
        audioLevel.value = message.level;
      } else if (message is _BusyEvent) {
        busy.value = message.busy;
      } else if (message is _WorkerError) {
        debugPrint('SherpaRecitationEngine worker error: ${message.message}');
        if (!_controller.isClosed) _controller.addError(message.message);
      }
    });

    _isolate = await Isolate.spawn(
      _workerMain,
      _WorkerInit(receivePort.sendPort, _paths),
      debugName: 'sherpa-asr-worker',
    );
    _workerPort = await readyCompleter.future;

    // 2. Open the mic as a 16kHz mono PCM16 stream and forward chunks.
    final micStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _micSub = micStream.listen((chunk) => _workerPort?.send(chunk));
  }

  @override
  Future<void> stop() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _recorder.dispose();
    _workerPort?.send(const _WorkerShutdown());
    // Give the worker a beat to free native resources before killing it.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _workerPort = null;
    _receivePort?.close();
    _receivePort = null;
    audioLevel.value = 0;
    busy.value = false;
    await _controller.close();
  }
}

class _WorkerInit {
  const _WorkerInit(this.replyTo, this.paths);
  final SendPort replyTo;
  final SherpaModelPaths paths;
}

class _WorkerShutdown {
  const _WorkerShutdown();
}

class _WorkerError {
  const _WorkerError(this.message);
  final String message;
}

class _LevelEvent {
  const _LevelEvent(this.level);
  final double level;
}

class _BusyEvent {
  const _BusyEvent(this.busy);
  final bool busy;
}

const int _sampleRate = 16000;

/// How often, at most, an interim decode may start while speech continues.
const Duration _interimInterval = Duration(milliseconds: 1300);

/// Minimum accumulated speech before the first interim decode -- avoids
/// wasting a decode (and risking hallucination) on a fraction of a word.
const Duration _minInterimAudio = Duration(milliseconds: 1000);

/// Rolling pre-roll kept while no speech is detected, prepended to the
/// utterance buffer so the first word's onset isn't clipped (the VAD flips
/// to "detected" only after min_speech_duration of voiced audio).
const Duration _preRoll = Duration(milliseconds: 400);

/// Entry point of the ASR worker isolate. Owns every sherpa_onnx object;
/// nothing native ever crosses the isolate boundary -- only PCM bytes in
/// and recognized text / level / busy events out.
Future<void> _workerMain(_WorkerInit init) async {
  final commandPort = ReceivePort();
  sherpa.initBindings();

  sherpa.VoiceActivityDetector? vad;
  sherpa.OfflineRecognizer? recognizer;
  try {
    vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: init.paths.vad,
          // 300ms of silence closes an utterance. Short enough to feel
          // responsive after a pause; recitation pauses within a phrase
          // (breath, short madd) that exceed it merely split the audio into
          // more segments, which the aligner handles.
          minSilenceDuration: 0.3,
          minSpeechDuration: 0.25,
        ),
        sampleRate: _sampleRate,
        numThreads: 1,
      ),
      bufferSizeInSeconds: 30,
    );
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: init.paths.encoder,
            decoder: init.paths.decoder,
            language: 'ar',
            task: 'transcribe',
            // Extra trailing zero-padding before the mel window ends; the
            // export verification showed short segments losing their last
            // syllable with the default.
            tailPaddings: 2000,
          ),
          tokens: init.paths.tokens,
          modelType: 'whisper',
          // Whisper-base decode dominates end-to-end latency; give it the
          // big cores. (VAD stays on 1 thread -- it's negligible.)
          numThreads: 4,
        ),
      ),
    );
  } catch (error) {
    init.replyTo.send(_WorkerError('model init failed: $error'));
    commandPort.close();
    return;
  }

  init.replyTo.send(commandPort.sendPort);

  String decode(Float32List samples) {
    init.replyTo.send(const _BusyEvent(true));
    final stream = recognizer!.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
      init.replyTo.send(const _BusyEvent(false));
    }
  }

  // A single trailing byte carried over when a chunk ends mid-sample, so
  // PCM16 sample boundaries stay aligned across chunk splits (otherwise one
  // odd-length chunk would desync every sample that follows into noise).
  var carry = Uint8List(0);

  // Rolling pre-roll (kept while idle) + current utterance accumulation.
  final preRollMax = _preRoll.inMilliseconds * _sampleRate ~/ 1000;
  final minInterimSamples =
      _minInterimAudio.inMilliseconds * _sampleRate ~/ 1000;
  var preRollBuffer = <Float32List>[];
  var preRollLength = 0;
  var utterance = <Float32List>[];
  var utteranceLength = 0;
  var speechActive = false;
  var lastDecodeStarted = DateTime.fromMillisecondsSinceEpoch(0);
  var lastLevelSent = DateTime.fromMillisecondsSinceEpoch(0);
  var peakRms = 0.0;

  Float32List concat(List<Float32List> chunks, int total) {
    final out = Float32List(total);
    var offset = 0;
    for (final c in chunks) {
      out.setAll(offset, c);
      offset += c.length;
    }
    return out;
  }

  await for (final message in commandPort) {
    if (message is _WorkerShutdown) break;
    if (message is! Uint8List) continue;

    final bytes = carry.isEmpty
        ? message
        : (Uint8List(carry.length + message.length)
          ..setAll(0, carry)
          ..setAll(carry.length, message));
    final sampleCount = bytes.lengthInBytes ~/ 2;
    final usableBytes = sampleCount * 2;
    carry = bytes.length > usableBytes
        ? Uint8List.sublistView(bytes, usableBytes)
        : Uint8List(0);
    if (sampleCount == 0) continue;

    // PCM16 little-endian -> Float32 in [-1, 1]. Read via ByteData.getInt16
    // rather than Int16List.view: the Uint8List arriving over the port can
    // start at an odd byte offset (observed offset 5 from the record
    // plugin's buffers), which Int16List.view rejects with a
    // "must be a multiple of BYTES_PER_ELEMENT" RangeError. getInt16 reads
    // at any alignment.
    final byteData = ByteData.sublistView(bytes);
    final float32 = Float32List(sampleCount);
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final v = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      float32[i] = v;
      sumSquares += v * v;
    }

    // Mic level feedback, throttled to ~10 events/second. Normal speech
    // RMS sits around 0.05-0.2, so scale up and clamp for a lively meter.
    peakRms = math.max(peakRms, math.sqrt(sumSquares / sampleCount));
    final now = DateTime.now();
    if (now.difference(lastLevelSent).inMilliseconds >= 100) {
      init.replyTo.send(_LevelEvent((peakRms * 6).clamp(0.0, 1.0)));
      lastLevelSent = now;
      peakRms = 0.0;
    }

    vad.acceptWaveform(float32);

    // Track the in-progress utterance for interim decoding.
    if (vad.isDetected()) {
      if (!speechActive) {
        speechActive = true;
        utterance = List.of(preRollBuffer);
        utteranceLength = preRollLength;
      }
      utterance.add(float32);
      utteranceLength += float32.length;
    } else if (!speechActive) {
      preRollBuffer.add(float32);
      preRollLength += float32.length;
      while (preRollLength - preRollBuffer.first.length >= preRollMax &&
          preRollBuffer.length > 1) {
        preRollLength -= preRollBuffer.first.length;
        preRollBuffer.removeAt(0);
      }
    }

    // Final segments (utterance closed by a pause, or force-split at the
    // VAD's max_speech_duration): decode in full, authoritative.
    var poppedFinal = false;
    while (!vad.isEmpty()) {
      poppedFinal = true;
      final segment = vad.front();
      vad.pop();
      final text = decode(segment.samples);
      if (text.isNotEmpty) init.replyTo.send(text);
      lastDecodeStarted = DateTime.now();
    }
    if (poppedFinal) {
      // The utterance the buffers were tracking is covered by the final
      // decode; start fresh.
      speechActive = false;
      utterance = [];
      utteranceLength = 0;
      preRollBuffer = [];
      preRollLength = 0;
      continue;
    }

    // Interim decode: speech still in progress, enough audio accumulated,
    // and the previous decode long enough ago. (Decodes run synchronously
    // in this isolate, so they're naturally serial; queued mic chunks just
    // wait in the port and VAD timing is sample-based, not wall-clock.)
    if (speechActive &&
        utteranceLength >= minInterimSamples &&
        DateTime.now().difference(lastDecodeStarted) >= _interimInterval) {
      lastDecodeStarted = DateTime.now();
      final text = SherpaRecitationEngine.trimInterimResult(
        decode(concat(utterance, utteranceLength)),
      );
      if (text.isNotEmpty) init.replyTo.send(text);
    }
  }

  vad.free();
  recognizer.free();
  commandPort.close();
  Isolate.exit();
}

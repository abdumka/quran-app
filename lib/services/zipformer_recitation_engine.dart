import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'recitation_engine.dart';

/// Model files of the streaming phoneme recognizer.
class ZipformerModelPaths {
  const ZipformerModelPaths({required this.model, required this.tokens});
  final String model;
  final String tokens;
}

/// Streaming recitation engine: mic -> worker isolate -> sherpa-onnx
/// streaming Zipformer2-CTC (Quran-Lab `zipformer_p_arabic_v3.1`, 251
/// Quranic phoneme tokens, NPL-1.2) -> phoneme tokens with timestamps.
///
/// Unlike the Whisper engine there is no segmentation and no text: every
/// 100 ms of audio is pushed through the encoder with carried state and the
/// newly emitted phoneme tokens are forwarded at once as a
/// [RecognizedSegment] whose [RecognizedSegment.phonemes] is set. The
/// session service feeds them to a [PhonemeTracker]; the aligner and the
/// overlay are untouched.
class ZipformerRecitationEngine extends RecitationEngine {
  ZipformerRecitationEngine(this._paths);

  final ZipformerModelPaths _paths;
  final _controller = StreamController<RecognizedSegment>.broadcast();
  final _audioController = StreamController<Uint8List>.broadcast();
  final _recorder = AudioRecorder();

  @override
  Stream<Uint8List> get audioChunks => _audioController.stream;

  Isolate? _isolate;
  SendPort? _workerPort;
  DateTime? _micStartedAt;
  StreamSubscription<Uint8List>? _micSub;
  ReceivePort? _receivePort;

  @override
  Stream<RecognizedSegment> get segments => _controller.stream;

  @override
  bool get emitsPhonemes => true;

  @override
  Future<void> start() async {
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final readyCompleter = Completer<SendPort>();

    receivePort.listen((message) {
      if (message is SendPort) {
        readyCompleter.complete(message);
      } else if (message is _PhonemeEvent) {
        final micStart = _micStartedAt;
        final lag = micStart == null
            ? -1
            : DateTime.now().difference(micStart).inMilliseconds -
                message.audioEndMs;
        if (!_controller.isClosed) {
          _controller.add(RecognizedSegment(
            message.tokens.join(),
            isFinal: true,
            audioEndMs: message.audioEndMs,
            speechMs: 0,
            maxNewWords: 0,
            lagMs: lag,
            phonemes: message.tokens,
            phonemeTimesMs: message.timesMs,
          ));
        }
      } else if (message is _LevelEvent) {
        audioLevel.value = message.level;
      } else if (message is _DecodeStats) {
        lastDecodeMs.value = message.milliseconds;
      } else if (message is _WorkerError) {
        debugPrint('ZipformerRecitationEngine worker error: ${message.message}');
        if (!_controller.isClosed) _controller.addError(message.message);
      }
    });

    _isolate = await Isolate.spawn(
      _workerMain,
      _WorkerInit(receivePort.sendPort, _paths),
      debugName: 'zipformer-asr-worker',
    );
    _workerPort = await readyCompleter.future;

    final micStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // iOS mutes haptics and system sounds while an app records unless
        // told otherwise, which silenced the mistake alerts (vibration and
        // tone) there. Android ignores this.
        iosConfig: IosRecordConfig(
          allowHapticsAndSystemSoundsDuringRecording: true,
        ),
      ),
    );
    _micStartedAt = DateTime.now();
    _micSub = micStream.listen((chunk) {
      _workerPort?.send(chunk);
      if (_audioController.hasListener) _audioController.add(chunk);
    });
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
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _workerPort = null;
    _receivePort?.close();
    _receivePort = null;
    audioLevel.value = 0;
    busy.value = false;
    await _controller.close();
    await _audioController.close();
  }
}

class _PhonemeEvent {
  const _PhonemeEvent(this.tokens, this.timesMs, this.audioEndMs);
  final List<String> tokens;
  final List<int> timesMs;
  final int audioEndMs;
}

class _DecodeStats {
  const _DecodeStats(this.milliseconds);
  final int milliseconds;
}

class _WorkerInit {
  const _WorkerInit(this.replyTo, this.paths);
  final SendPort replyTo;
  final ZipformerModelPaths paths;
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

const int _sampleRate = 16000;

/// Worker isolate: owns the sherpa objects; PCM bytes in, phoneme events out.
Future<void> _workerMain(_WorkerInit init) async {
  final commandPort = ReceivePort();
  sherpa.initBindings();

  sherpa.OnlineRecognizer? recognizer;
  sherpa.OnlineStream? stream;
  try {
    recognizer = sherpa.OnlineRecognizer(
      sherpa.OnlineRecognizerConfig(
        feat: const sherpa.FeatureConfig(sampleRate: _sampleRate, featureDim: 80),
        model: sherpa.OnlineModelConfig(
          zipformer2Ctc: sherpa.OnlineZipformer2CtcModelConfig(model: init.paths.model),
          tokens: init.paths.tokens,
          modelType: 'zipformer2_ctc',
          // Chunks are 0.48 s of audio; one thread keeps up at ~5-15 % of
          // real time and leaves the big cores to the UI.
          numThreads: 2,
          debug: false,
        ),
        decodingMethod: 'greedy_search',
        enableEndpoint: false,
      ),
    );
    stream = recognizer.createStream();
  } catch (error) {
    init.replyTo.send(_WorkerError('model init failed: $error'));
    commandPort.close();
    return;
  }

  init.replyTo.send(commandPort.sendPort);

  var carry = Uint8List(0);
  var audioSamples = 0;
  var sentTokens = 0;
  var lastLevelSent = DateTime.fromMillisecondsSinceEpoch(0);
  var peakRms = 0.0;
  var pendingSamples = 0;
  const decodeEvery = _sampleRate ~/ 10; // 100 ms

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

    final byteData = ByteData.sublistView(bytes);
    final float32 = Float32List(sampleCount);
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final v = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      float32[i] = v;
      sumSquares += v * v;
    }
    peakRms = math.max(peakRms, math.sqrt(sumSquares / sampleCount));
    final now = DateTime.now();
    if (now.difference(lastLevelSent).inMilliseconds >= 100) {
      init.replyTo.send(_LevelEvent((peakRms * 6).clamp(0.0, 1.0)));
      lastLevelSent = now;
      peakRms = 0.0;
    }

    audioSamples += sampleCount;
    pendingSamples += sampleCount;
    stream.acceptWaveform(samples: float32, sampleRate: _sampleRate);
    if (pendingSamples < decodeEvery) continue;
    pendingSamples = 0;

    final started = DateTime.now();
    var decoded = false;
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
      decoded = true;
    }
    if (!decoded) continue;
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    init.replyTo.send(_DecodeStats(elapsed));

    final result = recognizer.getResult(stream);
    final tokens = result.tokens;
    if (tokens.length > sentTokens) {
      final newTokens = tokens.sublist(sentTokens);
      final ts = result.timestamps;
      final times = <int>[
        for (var k = sentTokens; k < tokens.length; k++)
          k < ts.length ? (ts[k] * 1000).round() : audioSamples * 1000 ~/ _sampleRate,
      ];
      sentTokens = tokens.length;
      init.replyTo.send(_PhonemeEvent(
        newTokens,
        times,
        audioSamples * 1000 ~/ _sampleRate,
      ));
    }
  }

  stream.free();
  recognizer.free();
  commandPort.close();
  Isolate.exit();
}

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

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
/// UI thread -- per the memorization-test plan, we deliberately do NOT
/// assume the plugin's FFI offloads work itself. Mic capture stays on the
/// main isolate (the `record` plugin needs the root isolate's platform
/// channels) and raw PCM chunks are forwarded to the worker.
///
/// NOTE: isolate-safety of sherpa_onnx's FFI bindings is flagged in the
/// plan as needing a device spike. If the spike fails, the fallback is
/// moving `_workerMain`'s body onto the main isolate behind short
/// VAD-bounded segments -- the class's public surface doesn't change.
class SherpaRecitationEngine implements RecitationEngine {
  SherpaRecitationEngine(this._paths);

  final SherpaModelPaths _paths;
  final _controller = StreamController<String>.broadcast();
  final _recorder = AudioRecorder();

  Isolate? _isolate;
  SendPort? _workerPort;
  StreamSubscription<Uint8List>? _micSub;
  ReceivePort? _receivePort;

  @override
  Stream<String> get segments => _controller.stream;

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

/// Entry point of the ASR worker isolate. Owns every sherpa_onnx object;
/// nothing native ever crosses the isolate boundary -- only PCM bytes in
/// and recognized text out.
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
          // Tuned for deliberate recitation: a pause shorter than 500ms
          // (breath, madd) must not split an utterance.
          minSilenceDuration: 0.5,
          minSpeechDuration: 0.25,
        ),
        sampleRate: 16000,
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
            // Extra trailing zero-padding before the mel window ends. The
            // ONNX-export verification (verify_sherpa.py) showed the last
            // syllable of a short segment can get clipped with the default
            // (-1); a positive padding gives the decoder room to finish the
            // final word.
            tailPaddings: 2000,
          ),
          tokens: init.paths.tokens,
          modelType: 'whisper',
          numThreads: 2,
        ),
      ),
    );
  } catch (error) {
    init.replyTo.send(_WorkerError('model init failed: $error'));
    commandPort.close();
    return;
  }

  init.replyTo.send(commandPort.sendPort);

  await for (final message in commandPort) {
    if (message is _WorkerShutdown) break;
    if (message is! Uint8List) continue;

    // PCM16 little-endian -> Float32 in [-1, 1].
    final int16 = Int16List.view(
      message.buffer,
      message.offsetInBytes,
      message.lengthInBytes ~/ 2,
    );
    final float32 = Float32List(int16.length);
    for (var i = 0; i < int16.length; i++) {
      float32[i] = int16[i] / 32768.0;
    }

    vad.acceptWaveform(float32);
    while (!vad.isEmpty()) {
      final segment = vad.front();
      vad.pop();
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: segment.samples, sampleRate: 16000);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        if (text.isNotEmpty) {
          init.replyTo.send(text);
        }
      } finally {
        stream.free();
      }
    }
  }

  vad.free();
  recognizer.free();
  commandPort.close();
  Isolate.exit();
}

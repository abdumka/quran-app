import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'recitation_engine.dart';
import 'tasmee_report_store.dart'
    show TasmeeMicSource, TasmeeMicSourceSetting;
import 'zipformer_posterior.dart';

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
  ZipformerRecitationEngine(this._paths, {this.posterior = false});

  final ZipformerModelPaths _paths;

  /// Lab builds: also open the model through ONNX Runtime in the worker so
  /// [verifyScored] can read posteriors (see `ZipformerPosterior`).
  final bool posterior;
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

  /// Set by [stop]. A [start] still loading the model or opening the
  /// microphone then returns without opening it (the session ended while
  /// it was getting ready).
  bool _stopped = false;

  /// Completes with the worker's port once the model is loaded, with null
  /// when [stop] comes first, or with an error when the model fails to load.
  Completer<SendPort?>? _ready;

  /// Fresh re-decodes in flight ([verify], [verifyScored]), by request id.
  final Map<int, Completer<_VerifyResult?>> _verifies = {};
  int _verifySeq = 0;

  @override
  Stream<RecognizedSegment> get segments => _controller.stream;

  /// Wall-clock milliseconds the most recent [verify] decode took in the
  /// worker (0 until one has run).
  final ValueNotifier<int> lastVerifyMs = ValueNotifier(0);

  @override
  Future<List<String>?> verify({required int fromMs, required int toMs}) async =>
      (await _ask(fromMs, toMs, null))?.tokens;

  @override
  Future<ScoredVerify?> verifyScored({
    required int fromMs,
    required int toMs,
    required PosteriorQuery query,
  }) async {
    if (!posterior) return null;
    final r = await _ask(fromMs, toMs, query);
    if (r == null || r.tokens == null || !r.scored) return null;
    return ScoredVerify(
      tokens: r.tokens!,
      score: r.score,
      weakest: r.weakest,
      cleared: r.cleared,
      candidate: r.candidate,
      loadMs: r.loadMs,
    );
  }

  Future<_VerifyResult?> _ask(int fromMs, int toMs, PosteriorQuery? query) {
    final port = _workerPort;
    if (port == null || _stopped) return Future.value(null);
    final id = ++_verifySeq;
    final completer = Completer<_VerifyResult?>();
    _verifies[id] = completer;
    port.send(_VerifyRequest(id, fromMs, toMs, query));
    return completer.future;
  }

  @override
  bool get emitsPhonemes => true;

  @override
  Future<void> start() async {
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final readyCompleter = Completer<SendPort?>();
    _ready = readyCompleter;

    receivePort.listen((message) {
      if (message is SendPort) {
        if (_stopped) {
          // Stopped while the model was loading: the worker frees it and
          // ends on its own.
          message.send(const _WorkerShutdown());
          receivePort.close();
        } else if (!readyCompleter.isCompleted) {
          readyCompleter.complete(message);
        }
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
      } else if (message is _VerifyResult) {
        lastVerifyMs.value = message.milliseconds;
        _verifies.remove(message.id)?.complete(message);
      } else if (message is _WorkerNote) {
        debugPrint('ZipformerRecitationEngine: ${message.message}');
      } else if (message is _WorkerError) {
        debugPrint('ZipformerRecitationEngine worker error: ${message.message}');
        if (!readyCompleter.isCompleted) {
          // The model did not load: the start fails instead of waiting for
          // a worker that has already given up.
          readyCompleter.completeError(StateError(message.message));
        } else if (_stopped) {
          receivePort.close();
        } else if (!_controller.isClosed) {
          _controller.addError(message.message);
        }
      }
    });

    _isolate = await Isolate.spawn(
      _workerMain,
      _WorkerInit(receivePort.sendPort, _paths, posterior),
      debugName: 'zipformer-asr-worker',
    );
    final workerPort = await readyCompleter.future;
    if (workerPort == null) return;
    _workerPort = workerPort;

    final micStream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // Lab builds may ask for the raw or the speech-recognition source
        // (see TasmeeMicSourceSetting); the shipped app uses the default.
        androidConfig: AndroidRecordConfig(
          audioSource: switch (await TasmeeMicSourceSetting.mode()) {
            TasmeeMicSource.system => AndroidAudioSource.defaultSource,
            TasmeeMicSource.unprocessed => AndroidAudioSource.unprocessed,
            TasmeeMicSource.voiceRecognition =>
              AndroidAudioSource.voiceRecognition,
          },
        ),
        // iOS mutes haptics and system sounds while an app records unless
        // told otherwise, which silenced the mistake alerts (vibration and
        // tone) there. Android ignores this.
        iosConfig: const IosRecordConfig(
          allowHapticsAndSystemSoundsDuringRecording: true,
        ),
      ),
    );
    if (_stopped) {
      try {
        await _recorder.stop();
      } catch (_) {}
      return;
    }
    _micStartedAt = DateTime.now();
    if (!kIsWeb && Platform.isIOS) {
      // Set once more after the mic is live: the alerts (haptics and tone)
      // stay muted on iOS while recording unless the session allows them.
      try {
        await AVAudioSession()
            .setAllowHapticsAndSystemSoundsDuringRecording(true);
      } catch (e) {
        debugPrint('recitation engine: haptics-during-recording: $e');
      }
    }
    _micSub = micStream.listen((chunk) {
      _workerPort?.send(chunk);
      if (_audioController.hasListener) _audioController.add(chunk);
    });
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    // Still loading the model: [start] gives up now, and the worker shuts
    // itself down once loaded (the port stays open to tell it so; killing
    // it mid-load would leak the native model).
    final ready = _ready;
    final loading = ready != null && !ready.isCompleted;
    if (loading) ready.complete(null);
    for (final c in _verifies.values) {
      c.complete(null);
    }
    _verifies.clear();
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _recorder.dispose();
    _workerPort?.send(const _WorkerShutdown());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!loading) {
      _isolate?.kill(priority: Isolate.beforeNextEvent);
      _receivePort?.close();
    }
    _isolate = null;
    _workerPort = null;
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

/// Main -> worker: decode this window of the recent audio with a fresh
/// stream (see [RecitationEngine.verify]).
class _VerifyRequest {
  const _VerifyRequest(this.id, this.fromMs, this.toMs, this.query);
  final int id;
  final int fromMs;
  final int toMs;

  /// Set when the caller wants the posterior judgement too.
  final PosteriorQuery? query;
}

/// Worker -> main: the tokens the fresh decode heard (null when the window
/// was no longer in the buffer), how long it took, and, when the posterior
/// path answered ([scored]), the alignment result.
class _VerifyResult {
  const _VerifyResult(
    this.id,
    this.tokens,
    this.milliseconds, {
    this.scored = false,
    this.score,
    this.weakest,
    this.cleared = false,
    this.candidate,
    this.loadMs = 0,
  });
  final int id;
  final List<String>? tokens;
  final int milliseconds;
  final bool scored;
  final double? score;
  final double? weakest;
  final bool cleared;
  final String? candidate;
  final int loadMs;
}

/// Worker -> main: something worth a debug line, not an error.
class _WorkerNote {
  const _WorkerNote(this.message);
  final String message;
}

class _WorkerInit {
  const _WorkerInit(this.replyTo, this.paths, this.posterior);
  final SendPort replyTo;
  final ZipformerModelPaths paths;
  final bool posterior;
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

/// How much recent audio the worker keeps for [RecitationEngine.verify]:
/// the window is up to 6 s, and a second of slack covers the audio that
/// arrives while a request is on its way.
const int _ringSeconds = 7;

/// Silence appended to a verify window so the recognizer flushes the last
/// word's tokens (its decode runs a chunk behind the input).
const int _verifyPadSamples = _sampleRate ~/ 2;

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
          // Chunks are 0.32 s of audio (16-frame export); one thread keeps up at ~5-15 % of
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

  // Lab builds: the same model once more through ONNX Runtime, for the
  // posteriors. Loaded after the ready signal so the session starts at
  // once; the first seconds of audio queue up meanwhile and are decoded in a
  // burst. Any failure leaves the plain re-decode in charge.
  ZipformerPosterior? posterior;
  var posteriorLoadMs = 0;
  if (init.posterior) {
    final t0 = DateTime.now();
    try {
      posterior = ZipformerPosterior.load(init.paths.model, init.paths.tokens, threads: 2);
      posteriorLoadMs = DateTime.now().difference(t0).inMilliseconds;
      init.replyTo.send(_WorkerNote(posterior == null
          ? 'posterior path unavailable on this platform'
          : 'posterior model loaded in $posteriorLoadMs ms (ORT ${posterior.runtimeVersion})'));
    } catch (e) {
      posterior = null;
      init.replyTo.send(_WorkerNote('posterior model failed to load: $e'));
    }
  }

  var carry = Uint8List(0);
  var audioSamples = 0;
  var sentTokens = 0;
  // Ring buffer of the most recent audio, for fresh re-decodes.
  final ring = Float32List(_ringSeconds * _sampleRate);
  var ringPos = 0;
  var lastLevelSent = DateTime.fromMillisecondsSinceEpoch(0);
  var peakRms = 0.0;
  var pendingSamples = 0;
  const decodeEvery = _sampleRate ~/ 10; // 100 ms

  await for (final message in commandPort) {
    if (message is _WorkerShutdown) break;
    if (message is _VerifyRequest) {
      final started = DateTime.now();
      final clip = _clipWindow(ring, audioSamples, message.fromMs, message.toMs);
      final query = message.query;
      if (clip != null && query != null && posterior != null) {
        try {
          final v = posterior.verify(clip, query);
          init.replyTo.send(_VerifyResult(
            message.id,
            v.tokens,
            DateTime.now().difference(started).inMilliseconds,
            scored: true,
            score: v.score,
            weakest: v.weakest,
            cleared: v.cleared,
            candidate: v.candidate,
            loadMs: posteriorLoadMs,
          ));
          posteriorLoadMs = 0;
          continue;
        } catch (e) {
          init.replyTo.send(_WorkerNote('posterior verify failed, re-decoding instead: $e'));
        }
      }
      final tokens = clip == null ? null : _decodeFresh(recognizer, clip);
      init.replyTo.send(_VerifyResult(
        message.id,
        tokens,
        DateTime.now().difference(started).inMilliseconds,
      ));
      continue;
    }
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

    for (var i = 0; i < sampleCount; i++) {
      ring[ringPos] = float32[i];
      ringPos = ringPos + 1 == ring.length ? 0 : ringPos + 1;
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
  posterior?.dispose();
  commandPort.close();
  Isolate.exit();
}

/// [fromMs, toMs] of the audio in [ring] (whose last sample is sample
/// number [audioSamples] of the stream), padded with [_verifyPadSamples] of
/// silence; null when the window is not in the buffer any more.
Float32List? _clipWindow(Float32List ring, int audioSamples, int fromMs, int toMs) {
  final oldest = math.max(0, audioSamples - ring.length);
  final from = math.max(oldest, fromMs * _sampleRate ~/ 1000);
  final to = math.min(audioSamples, toMs * _sampleRate ~/ 1000);
  if (to - from < _sampleRate ~/ 2) return null;
  final clip = Float32List(to - from + _verifyPadSamples);
  for (var s = from; s < to; s++) {
    clip[s - from] = ring[s % ring.length];
  }
  return clip;
}

/// Decodes [clip] with a fresh stream of [recognizer].
List<String> _decodeFresh(sherpa.OnlineRecognizer recognizer, Float32List clip) {
  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(samples: clip, sampleRate: _sampleRate);
    stream.inputFinished();
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    return List<String>.of(recognizer.getResult(stream).tokens);
  } finally {
    stream.free();
  }
}

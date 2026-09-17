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
///  * The FINAL decode of each utterance (closed [_endGap] after the last
///    detected speech, gap included) is authoritative and re-covers the
///    same audio in full.
///
/// The mic level ([audioLevel]) and decode activity ([busy]) are reported
/// so the UI can show live "I hear you" feedback.
class SherpaRecitationEngine extends RecitationEngine {
  SherpaRecitationEngine(this._paths);

  final SherpaModelPaths _paths;
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

  /// Interim (mid-utterance) results with fewer words than this are
  /// discarded outright -- one-word interims are most exposed to
  /// half-spoken-word noise.
  static const int _minInterimWords = 2;

  @override
  Stream<RecognizedSegment> get segments => _controller.stream;

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
      } else if (message is _SegmentEvent) {
        // Lag = how long ago the last sample of this segment was captured.
        final micStart = _micStartedAt;
        final lag = micStart == null
            ? -1
            : DateTime.now().difference(micStart).inMilliseconds -
                message.audioEndMs;
        if (!_controller.isClosed) {
          _controller.add(RecognizedSegment(
            message.text,
            isFinal: message.isFinal,
            audioEndMs: message.audioEndMs,
            speechMs: message.speechMs,
            maxNewWords:
                (message.speechMs * _maxWordsPerSecond / 1000).ceil() + 2,
            lagMs: lag,
          ));
        }
      } else if (message is _LevelEvent) {
        audioLevel.value = message.level;
      } else if (message is _BusyEvent) {
        busy.value = message.busy;
      } else if (message is _DecodeStats) {
        lastDecodeMs.value = message.milliseconds;
        debugPrint(
          'SherpaRecitationEngine: ${message.kind} decode of '
          '${message.audioMs} ms audio took ${message.milliseconds} ms',
        );
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
    await _audioController.close();
  }

  /// Keeps only the trailing [maxSamples] of an utterance for an interim
  /// decode. Whisper's cost is flat per call (it always pads to 30 s), so
  /// re-decoding a 20 s utterance every interval buys nothing over decoding
  /// its tail -- and the tail's text arrives just as fast. Returns the
  /// slice and whether anything was cut from the front (the first decoded
  /// word is then unreliable and should be dropped, like the last).
  @visibleForTesting
  static (Float32List, bool) interimTail(Float32List samples, int maxSamples) {
    if (samples.length <= maxSamples) return (samples, false);
    return (
      Float32List.sublistView(samples, samples.length - maxSamples),
      true,
    );
  }

  /// Sample index of the quietest 100 ms frame within the last
  /// [searchSamples] of [samples] -- where a forced split should land so it
  /// falls between words rather than through one.
  @visibleForTesting
  static int quietestCut(Float32List samples, {required int searchSamples}) {
    const frame = 1600; // 100 ms at 16 kHz
    final from = math.max(0, samples.length - searchSamples);
    var best = samples.length;
    var bestEnergy = double.infinity;
    for (var i = from; i + frame <= samples.length; i += frame) {
      var e = 0.0;
      for (var k = i; k < i + frame; k++) {
        e += samples[k] * samples[k];
      }
      if (e < bestEnergy) {
        bestEnergy = e;
        best = i;
      }
    }
    return best;
  }

  /// Drops the first word of a tail-cut interim transcription, on top of
  /// [trimInterimResult]'s trailing-word drop.
  @visibleForTesting
  static String trimTailCutResult(String text) {
    final words = text.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.length < _minInterimWords + 1) return '';
    return words.sublist(1).join(' ');
  }
}

class _SegmentEvent {
  const _SegmentEvent(
    this.text, {
    required this.isFinal,
    required this.audioEndMs,
    required this.speechMs,
  });
  final String text;
  final bool isFinal;
  final int audioEndMs;
  final int speechMs;
}

class _DecodeStats {
  const _DecodeStats(this.kind, this.audioMs, this.milliseconds);
  final String kind;
  final int audioMs;
  final int milliseconds;
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
const Duration _preRoll = Duration(milliseconds: 1000);

/// An utterance closes once no speech has been detected for this long.
/// Silero flags a sustained madd (a long steady vowel at an ayah's end)
/// as silence within ~300 ms, so a short gap cut every "المؤمنون" down to
/// "المؤ" on real recordings; the gap audio itself is KEPT in the segment
/// because that is where the madd lives. 1 s recovered whole ayahs on the
/// user's sessions (see tasmee_work/sweep.py).
const Duration _endGap = Duration(milliseconds: 800);

/// Longest utterance before a soft force-split. The cut is placed at the
/// quietest 100 ms of the last [_softCutSearch] so it never lands inside a
/// word the way a hard cut did.
const Duration _maxUtterance = Duration(milliseconds: 12000);
const Duration _softCutSearch = Duration(milliseconds: 3000);

/// Audio before a soft cut that is replayed at the start of the next
/// utterance, so a word the cut landed on is heard whole in the second
/// segment (the aligner's history absorbs the duplicate).
const Duration _softCutOverlap = Duration(milliseconds: 800);

/// Digital silence appended to every segment before decoding. Whisper
/// drops the final word of a segment that ends right after speech
/// ("مُقْتَد" for مُقْتَدِرٍ); on the user's recordings 1 s of zeros restored
/// the word every time, while sherpa's tailPaddings did nothing for it.
const Duration _decodeSilencePad = Duration(milliseconds: 1200);

/// Every final segment is decoded twice: in full, and as a tail window
/// ending at the same point (the last [_tailCheck], or the segment minus
/// its first [_tailSkip] when it is shorter). Whisper-base is erratic about
/// the last word or two of a segment ("…وَهُوَ الْعَزِي" for "…وَهُوَ
/// الْعَزِيزُ الْحَكِيمُ") and the same audio decodes whole from a different
/// start point, so a second decode from another start is the cheapest
/// reliable fix; the aligner's history absorbs the overlap. When interim
/// decodes are running (fast phone) the tail goes FIRST, since it is
/// quicker to decode and carries the words the reciter just said.
const Duration _tailCheck = Duration(milliseconds: 4000);
const Duration _tailSkip = Duration(milliseconds: 500);
const Duration _tailCheckMin = Duration(milliseconds: 2000);

/// Words per second no reciter exceeds; with the speech actually heard
/// since the previous segment it bounds how many NEW words a segment may
/// resolve (see RecognizedSegment.speechMs).
const double _maxWordsPerSecond = 4.0;

/// Interim decodes look only at this much trailing audio (see
/// [SherpaRecitationEngine.interimTail]).
const Duration _interimWindow = Duration(milliseconds: 5000);

/// When one decode takes longer than this, the phone can't afford interim
/// decodes on top of the final ones without falling ever further behind
/// real time; interims are then skipped and only the final segments (one
/// per pause, at most [_maxUtterance] long) are decoded.
const int _interimDisableDecodeMs = 2200;

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
          // Segmentation is done by this worker (see _endGap); the VAD is
          // only consulted per chunk via isDetected(), so keep its own
          // segmenter permissive and drain whatever it emits.
          minSilenceDuration: 0.1,
          minSpeechDuration: 0.1,
          maxSpeechDuration: 60,
        ),
        sampleRate: _sampleRate,
        numThreads: 1,
      ),
      bufferSizeInSeconds: 120,
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

  var lastDecodeMs = 0;
  final silencePadSamples =
      _decodeSilencePad.inMilliseconds * _sampleRate ~/ 1000;
  String decode(Float32List samples, String kind) {
    init.replyTo.send(const _BusyEvent(true));
    final stream = recognizer!.createStream();
    final started = DateTime.now();
    try {
      final padded = Float32List(samples.length + silencePadSamples)
        ..setAll(0, samples);
      stream.acceptWaveform(samples: padded, sampleRate: _sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      lastDecodeMs = elapsed;
      init.replyTo.send(_DecodeStats(
        kind,
        samples.length * 1000 ~/ _sampleRate,
        elapsed,
      ));
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
  final interimWindowSamples =
      _interimWindow.inMilliseconds * _sampleRate ~/ 1000;
  final endGapSamples = _endGap.inMilliseconds * _sampleRate ~/ 1000;
  final maxUtteranceSamples =
      _maxUtterance.inMilliseconds * _sampleRate ~/ 1000;
  final softCutSamples = _softCutSearch.inMilliseconds * _sampleRate ~/ 1000;
  final softCutOverlapSamples =
      _softCutOverlap.inMilliseconds * _sampleRate ~/ 1000;
  final tailCheckSamples = _tailCheck.inMilliseconds * _sampleRate ~/ 1000;
  final tailSkipSamples = _tailSkip.inMilliseconds * _sampleRate ~/ 1000;
  final tailCheckMinSamples =
      _tailCheckMin.inMilliseconds * _sampleRate ~/ 1000;

  // Audio clock: samples received so far (the position of the newest
  // sample in the stream), and speech-flagged samples accumulated since the
  // previous emitted segment (the budget of new words it may carry).
  var audioSamples = 0;
  var speechSinceSegment = 0;

  void emit(String text, {required bool isFinal, required int audioEnd}) {
    if (text.isEmpty) return;
    init.replyTo.send(_SegmentEvent(
      text,
      isFinal: isFinal,
      audioEndMs: audioEnd * 1000 ~/ _sampleRate,
      speechMs: speechSinceSegment * 1000 ~/ _sampleRate,
    ));
    speechSinceSegment = 0;
  }

  /// Decodes a final segment twice (full + tail window, see _tailCheck).
  /// [audioEnd] is the stream position of the segment's last sample.
  void decodeFinal(Float32List samples, int audioEnd) {
    Float32List? tail;
    if (samples.length >= tailCheckMinSamples) {
      final from = math.max(
        tailSkipSamples,
        samples.length - tailCheckSamples,
      );
      tail = Float32List.sublistView(samples, from);
    }
    final tailFirst = tail != null && lastDecodeMs < _interimDisableDecodeMs;
    if (tailFirst) {
      emit(decode(tail, 'tail'), isFinal: true, audioEnd: audioEnd);
    }
    emit(decode(samples, 'final'), isFinal: true, audioEnd: audioEnd);
    if (tail != null && !tailFirst) {
      emit(decode(tail, 'tail'), isFinal: true, audioEnd: audioEnd);
    }
  }
  var preRollBuffer = <Float32List>[];
  var preRollLength = 0;
  var utterance = <Float32List>[];
  var utteranceLength = 0;
  var speechActive = false;
  // Samples accumulated into `utterance` since speech was last detected.
  var silenceRun = 0;
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

    audioSamples += float32.length;
    vad.acceptWaveform(float32);
    // Drain the VAD's own segments; only its live speech flag is used.
    while (!vad.isEmpty()) {
      vad.pop();
    }
    final speechNow = vad.isDetected();
    if (speechNow) speechSinceSegment += float32.length;

    if (speechActive) {
      utterance.add(float32);
      utteranceLength += float32.length;
      silenceRun = speechNow ? 0 : silenceRun + float32.length;
    } else if (speechNow) {
      speechActive = true;
      silenceRun = 0;
      utterance = List.of(preRollBuffer)..add(float32);
      utteranceLength = preRollLength + float32.length;
      preRollBuffer = [];
      preRollLength = 0;
    } else {
      preRollBuffer.add(float32);
      preRollLength += float32.length;
      while (preRollLength - preRollBuffer.first.length >= preRollMax &&
          preRollBuffer.length > 1) {
        preRollLength -= preRollBuffer.first.length;
        preRollBuffer.removeAt(0);
      }
    }

    if (!speechActive) continue;

    // FINAL segment: the reciter has paused for _endGap (the gap audio
    // stays in, so a trailing madd reaches the decoder whole).
    if (silenceRun >= endGapSamples) {
      final samples = concat(utterance, utteranceLength);
      speechActive = false;
      utterance = [];
      utteranceLength = 0;
      silenceRun = 0;
      decodeFinal(samples, audioSamples);
      lastDecodeStarted = DateTime.now();
      continue;
    }

    // SOFT SPLIT: a very long utterance is cut at its quietest recent
    // point; the remainder seeds the next utterance.
    if (utteranceLength >= maxUtteranceSamples) {
      final all = concat(utterance, utteranceLength);
      final cut = SherpaRecitationEngine.quietestCut(
        all,
        searchSamples: softCutSamples,
      );
      final head = Float32List.sublistView(all, 0, cut);
      final restStart = math.max(0, cut - softCutOverlapSamples);
      final rest =
          Float32List.fromList(Float32List.sublistView(all, restStart));
      utterance = [rest];
      utteranceLength = rest.length;
      decodeFinal(head, audioSamples - rest.length + softCutOverlapSamples);
      lastDecodeStarted = DateTime.now();
      continue;
    }

    // INTERIM decode: speech still in progress, enough audio accumulated,
    // and the previous decode long enough ago. (Decodes run synchronously
    // in this isolate, so they're naturally serial; queued mic chunks just
    // wait in the port and VAD timing is sample-based, not wall-clock.)
    // The cadence adapts to the phone: never start an interim sooner than
    // twice the last decode's duration, and skip interims altogether when
    // decoding is too slow to keep up (see _interimDisableDecodeMs).
    final interimInterval = lastDecodeMs * 2 > _interimInterval.inMilliseconds
        ? Duration(milliseconds: lastDecodeMs * 2)
        : _interimInterval;
    if (speechNow &&
        lastDecodeMs < _interimDisableDecodeMs &&
        utteranceLength >= minInterimSamples &&
        DateTime.now().difference(lastDecodeStarted) >= interimInterval) {
      lastDecodeStarted = DateTime.now();
      final (tail, cut) = SherpaRecitationEngine.interimTail(
        concat(utterance, utteranceLength),
        interimWindowSamples,
      );
      var text = SherpaRecitationEngine.trimInterimResult(
        decode(tail, 'interim'),
      );
      if (cut) text = SherpaRecitationEngine.trimTailCutResult(text);
      emit(text, isFinal: false, audioEnd: audioSamples);
    }
  }

  vad.free();
  recognizer.free();
  commandPort.close();
  Isolate.exit();
}

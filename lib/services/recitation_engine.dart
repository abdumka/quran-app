import 'dart:async';

import 'package:flutter/foundation.dart';

/// One piece of recognized speech. [isFinal] is false for interim decodes
/// of an utterance still in progress (cut mid-air, last word dropped, may
/// be garbled) and true for the authoritative decode of a whole utterance.
class RecognizedSegment {
  const RecognizedSegment(
    this.text, {
    this.isFinal = true,
    this.audioEndMs = -1,
    this.speechMs = -1,
    this.maxNewWords = 0,
    this.lagMs = -1,
    this.phonemes,
    this.phonemeTimesMs,
  });

  /// Streaming phoneme engines (see `ZipformerRecitationEngine`) set these:
  /// the newly emitted Quran-phonetic-script tokens and the audio time (ms
  /// from stream start) each was emitted at. [text] then holds the tokens
  /// joined, for display only, and the session feeds a phoneme tracker
  /// instead of the word aligner.
  final List<String>? phonemes;
  final List<int>? phonemeTimesMs;

  final String text;
  final bool isFinal;

  /// Position (ms) in the microphone stream of the segment's last sample,
  /// or -1 when the engine has no audio clock.
  final int audioEndMs;

  /// Speech-flagged audio (ms) heard since the previous segment, or -1.
  final int speechMs;

  /// Upper bound on how many NEW expected words this segment may resolve,
  /// derived from [speechMs]; 0 means unbounded.
  final int maxNewWords;

  /// Milliseconds between the capture of the segment's last sample and
  /// this segment reaching the service, or -1 when unknown. This is the
  /// latency the reciter feels for the words in the segment.
  final int lagMs;
}

/// Source of recognized-speech text segments for the memorization test.
///
/// The UI/service layer only ever consumes this interface; which concrete
/// engine sits behind it is an implementation detail:
///
///  * `ZipformerRecitationEngine` -- mic -> streaming on-device phoneme
///    model.
///  * `SherpaRecitationEngine` -- mic -> VAD -> on-device Whisper.
///
/// There is no scripted fallback: when neither can run (model not installed
/// / mic denied) the session does not start.
///
/// Besides the text stream, engines expose two bits of live state the UI
/// uses for "the app hears you" feedback:
///  * [audioLevel] -- smoothed 0..1 microphone level (always 0 for engines
///    without a mic).
///  * [busy] -- true while a recognition pass is running.
abstract class RecitationEngine {
  /// Smoothed microphone input level in 0..1, updated ~10x/second while
  /// the engine is live. Purely cosmetic (drives the listening indicator).
  final ValueNotifier<double> audioLevel = ValueNotifier(0);

  /// True while the engine is actively decoding audio into text.
  final ValueNotifier<bool> busy = ValueNotifier(false);

  /// Wall-clock milliseconds the most recent decode took (0 when unknown).
  /// Surfaced so the user can tell us how slow their phone is.
  final ValueNotifier<int> lastDecodeMs = ValueNotifier(0);

  /// Raw 16 kHz mono PCM16 mic chunks, when the engine has a mic. Lets the
  /// session recorder keep a copy of what was heard for offline analysis.
  Stream<Uint8List>? get audioChunks => null;

  /// Recognized text segments. Text is raw engine output -- normalization
  /// happens downstream in the aligner. Segments may overlap/repeat text
  /// that was already recognized (interim decodes); the aligner is designed
  /// to absorb that.
  Stream<RecognizedSegment> get segments;

  /// True for streaming phoneme engines whose segments carry
  /// [RecognizedSegment.phonemes] instead of words.
  bool get emitsPhonemes => false;

  /// Begins producing [segments]. Completes once the engine is live.
  Future<void> start();

  /// Stops producing segments and releases resources. The engine cannot be
  /// restarted after [stop]; create a new instance instead.
  Future<void> stop();
}

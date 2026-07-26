import 'dart:async';

import 'package:flutter/foundation.dart';

/// Source of recognized-speech text segments for the memorization test.
///
/// The UI/service layer only ever consumes this interface; which concrete
/// engine sits behind it is an implementation detail:
///
///  * [StubRecitationEngine] -- replays scripted segments on a timer. Used
///    when the real engine can't run (model not installed / mic denied) and
///    for demos/tests.
///  * `SherpaRecitationEngine` -- the real thing: mic -> VAD -> on-device
///    Whisper.
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

  /// Recognized text segments. Text is raw engine output -- normalization
  /// happens downstream in the aligner. Segments may overlap/repeat text
  /// that was already recognized (interim decodes); the aligner is designed
  /// to absorb that.
  Stream<String> get segments;

  /// Begins producing [segments]. Completes once the engine is live.
  Future<void> start();

  /// Stops producing segments and releases resources. The engine cannot be
  /// restarted after [stop]; create a new instance instead.
  Future<void> stop();
}

/// Replays a fixed list of segments at a steady interval, as if a very
/// punctual reciter were speaking them.
class StubRecitationEngine extends RecitationEngine {
  StubRecitationEngine(
    this._scriptedSegments, {
    Duration interval = const Duration(milliseconds: 900),
  }) : _interval = interval;

  final List<String> _scriptedSegments;
  final Duration _interval;
  final _controller = StreamController<String>.broadcast();
  Timer? _timer;
  int _next = 0;

  @override
  Stream<String> get segments => _controller.stream;

  @override
  Future<void> start() async {
    _timer = Timer.periodic(_interval, (timer) {
      if (_next >= _scriptedSegments.length) {
        timer.cancel();
        return;
      }
      // A touch of fake liveliness so the demo exercises the same feedback
      // UI as the real engine.
      audioLevel.value = 0.3 + (_next % 3) * 0.25;
      _controller.add(_scriptedSegments[_next++]);
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    audioLevel.value = 0;
    await _controller.close();
  }
}

import 'dart:async';

/// Source of recognized-speech text segments for the memorization test.
///
/// The UI/service layer only ever consumes this interface; which concrete
/// engine sits behind it is an implementation detail. Planned engines:
///
///  * [StubRecitationEngine] -- replays scripted segments on a timer. Used
///    to build/validate the whole reveal UI slice with zero microphone or
///    model risk (step 6 of the memorization-test plan), and useful
///    permanently for demos/screenshots.
///  * A sherpa_onnx-backed engine (mic -> VAD -> on-device Whisper) --
///    the real thing, added once the model pipeline lands.
abstract class RecitationEngine {
  /// Recognized text segments, one event per detected utterance. Text is
  /// raw engine output -- normalization happens downstream in the aligner.
  Stream<String> get segments;

  /// Begins producing [segments]. Completes once the engine is live.
  Future<void> start();

  /// Stops producing segments and releases resources. The engine cannot be
  /// restarted after [stop]; create a new instance instead.
  Future<void> stop();
}

/// Replays a fixed list of segments at a steady interval, as if a very
/// punctual reciter were speaking them.
class StubRecitationEngine implements RecitationEngine {
  StubRecitationEngine(
    this._scriptedSegments, {
    Duration interval = const Duration(milliseconds: 1800),
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
      _controller.add(_scriptedSegments[_next++]);
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _controller.close();
  }
}

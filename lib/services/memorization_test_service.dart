import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:permission_handler/permission_handler.dart';

import '../models/word_position_data.dart';
import '../utils/quran_word_aligner.dart';
import 'asr_model_manager.dart';
import 'audio_service.dart';
import 'quran_json_service.dart';
import 'recitation_engine.dart';
import 'sherpa_recitation_engine.dart';
import 'word_position_service.dart';

/// Lifecycle of a memorization-test session.
enum MemorizationTestStatus {
  /// No session. The reveal overlay is not shown.
  idle,

  /// `start()` is running (loading data / warming the engine).
  preparing,

  /// Live: words reveal as the engine recognizes them.
  listening,

  /// Every expected word has been resolved; the engine is stopped but the
  /// overlay stays up so the user can review mistake/skip tints.
  completed,

  /// `start()` failed (no word data for the page, engine failure, ...).
  failed,
}

/// Why a session is running on the scripted stub instead of the real
/// mic/ASR engine -- surfaced so the UI can tell the user, rather than
/// silently faking a live recitation check.
enum StubReason {
  /// Not a stub run -- the real mic engine is live.
  none,

  /// The on-device recognition model isn't installed yet.
  modelNotInstalled,

  /// The user declined (or hasn't granted) microphone access.
  micPermissionDenied,
}

/// Coordinates a memorization-test session: owns the [QuranWordAligner],
/// feeds it segments from a [RecitationEngine], and exposes the state the
/// reveal overlay renders. Singleton with `ValueNotifier` fields, matching
/// this codebase's service pattern (`AudioService.instance` etc.).
///
/// Currently wired to [StubRecitationEngine] (scripted reveals) -- the
/// microphone/on-device-ASR engine replaces it without touching this
/// class's consumers; see `recitation_engine.dart`.
class MemorizationTestService {
  MemorizationTestService._internal();
  static final MemorizationTestService instance =
      MemorizationTestService._internal();

  final ValueNotifier<MemorizationTestStatus> status =
      ValueNotifier(MemorizationTestStatus.idle);

  /// Bumped whenever any word's status changes -- the overlay listens to
  /// this (plus [status]) instead of diffing the statuses list itself.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// Whether the last session ran on the real mic/ASR engine (true) or fell
  /// back to the scripted stub (false) because the model wasn't downloaded
  /// or mic permission wasn't granted. Lets the UI explain a stub run.
  final ValueNotifier<bool> usingRealEngine = ValueNotifier(false);

  /// When [usingRealEngine] is false, why -- so the UI can show the right
  /// message ("download the model" vs "grant mic access") instead of a
  /// silent fake demo.
  final ValueNotifier<StubReason> stubReason =
      ValueNotifier(StubReason.none);

  /// Live mic level (0..1) mirrored from the active engine -- drives the
  /// overlay's "the app hears you" indicator. 0 when no session.
  final ValueNotifier<double> audioLevel = ValueNotifier(0);

  /// True while the active engine is decoding audio -- the overlay shows
  /// an "analyzing" hint so a decode pause doesn't read as deafness.
  final ValueNotifier<bool> engineBusy = ValueNotifier(false);

  QuranWordAligner? _aligner;
  WordPositionPageData? _pageData;
  RecitationEngine? _engine;
  StreamSubscription<String>? _segmentSub;
  VoidCallback? _levelListener;
  VoidCallback? _busyListener;

  /// Word boxes for the active session's page (null when idle/failed).
  WordPositionPageData? get pageData => _pageData;

  /// Per-word statuses in recitation order, parallel to
  /// [WordPositionPageData.wordsInRecitationOrder]. Empty when no session.
  List<WordStatus> get statuses => _aligner?.statuses ?? const [];

  /// Index of the word the reciter is currently expected to say (first
  /// unresolved word), or -1 when no session is active.
  int get currentWordIndex {
    final aligner = _aligner;
    if (aligner == null || aligner.isComplete) return -1;
    return aligner.cursor;
  }

  bool get isActive =>
      status.value == MemorizationTestStatus.preparing ||
      status.value == MemorizationTestStatus.listening ||
      status.value == MemorizationTestStatus.completed;

  /// Starts a session for [pageNumber] (1-based mushaf page). Returns false
  /// (with [status] = failed) when the page has no word-position data or
  /// the engine can't start. Any active session is stopped first.
  ///
  /// [engineOverride] substitutes the recognition engine (tests inject a
  /// hand-driven one); [stopPlayback] exists solely so tests can avoid
  /// touching [AudioService]'s platform channels, which don't exist under
  /// `flutter test` -- production callers leave both defaulted.
  Future<bool> start({
    required int pageNumber,
    RecitationEngine? engineOverride,
    bool stopPlayback = true,
  }) async {
    await stop();
    status.value = MemorizationTestStatus.preparing;

    // A live mic session and audio playback can't sensibly coexist (and on
    // iOS they'd fight over the shared audio session category).
    if (stopPlayback) {
      AudioService.instance.stop();
    }

    try {
      final pageData = await WordPositionService.forPage(pageNumber);
      if (pageData == null) {
        debugPrint(
          'MemorizationTestService: no word positions for page $pageNumber',
        );
        status.value = MemorizationTestStatus.failed;
        return false;
      }

      final pages = await QuranJsonService.loadQuranPages();
      final page = pages.firstWhere((p) => p.page == pageNumber);
      final expectedWordsByAyah = {
        for (final ayah in page.ayahs)
          if (ayah.surah == pageData.ayahs.first.surah)
            ayah.ayah: ayah.text.split(RegExp(r'\s+')),
      };

      // Warn (never crash) if the offline-generated boxes have drifted from
      // output.json -- output.json remains the source of truth for text.
      WordPositionService.validateAgainstExpectedWords(
        pageData,
        expectedWordsByAyah,
      );

      final expectedWords = [
        for (final ayah in pageData.ayahs) ...?expectedWordsByAyah[ayah.ayah],
      ];
      if (expectedWords.length !=
          pageData.wordsInRecitationOrder.length) {
        debugPrint(
          'MemorizationTestService: word count mismatch '
          '(${expectedWords.length} expected vs '
          '${pageData.wordsInRecitationOrder.length} boxes)',
        );
        status.value = MemorizationTestStatus.failed;
        return false;
      }

      final aligner = QuranWordAligner(expectedWords)
        ..onWordResolved = (_) => revision.value++;

      // Pick the engine: an injected one (tests) wins; otherwise use the
      // real mic/ASR engine when it's actually usable, else fall back to a
      // scripted stub so the feature still demonstrates end-to-end.
      final RecitationEngine engine;
      if (engineOverride != null) {
        engine = engineOverride;
        usingRealEngine.value = false;
        stubReason.value = StubReason.none;
      } else {
        final real = await _tryBuildRealEngine();
        if (real != null) {
          engine = real;
          usingRealEngine.value = true;
          stubReason.value = StubReason.none;
        } else {
          // Stub replays the passage one WORD at a time (not whole ayahs) so
          // the reveal visibly advances word-by-word, matching how the real
          // engine resolves within an utterance. stubReason was set by
          // _tryBuildRealEngine so the UI can explain why it's a demo.
          engine = StubRecitationEngine([
            for (final ayah in pageData.ayahs)
              ...expectedWordsByAyah[ayah.ayah]!,
          ]);
          usingRealEngine.value = false;
        }
      }

      _aligner = aligner;
      _pageData = pageData;
      _engine = engine;
      _levelListener = () => audioLevel.value = engine.audioLevel.value;
      _busyListener = () => engineBusy.value = engine.busy.value;
      engine.audioLevel.addListener(_levelListener!);
      engine.busy.addListener(_busyListener!);
      _segmentSub = engine.segments.listen(_handleSegment);
      await engine.start();
      status.value = MemorizationTestStatus.listening;
      revision.value++;
      return true;
    } catch (error, stack) {
      debugPrint('MemorizationTestService: start failed: $error\n$stack');
      await stop();
      status.value = MemorizationTestStatus.failed;
      return false;
    }
  }

  /// Builds the real mic/ASR engine, or returns null (caller falls back to
  /// the stub) when mic permission is denied or the model files aren't
  /// present, setting [stubReason] to say which.
  ///
  /// Permission is requested FIRST -- before the model check -- so tapping
  /// the mic always prompts the user for microphone access, tying the OS
  /// prompt to their deliberate action. (The earlier ordering checked the
  /// model first and returned before ever asking, which is why the prompt
  /// never appeared when the model wasn't installed.)
  Future<RecitationEngine?> _tryBuildRealEngine() async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      debugPrint('MemorizationTestService: mic permission $permission; '
          'using scripted stub.');
      stubReason.value = StubReason.micPermissionDenied;
      return null;
    }

    final manager = AsrModelManager.instance;
    if (!await manager.refresh()) {
      debugPrint('MemorizationTestService: ASR model not installed; '
          'using scripted stub.');
      stubReason.value = StubReason.modelNotInstalled;
      return null;
    }

    return SherpaRecitationEngine(
      SherpaModelPaths(
        encoder: await manager.pathFor('base-encoder.int8.onnx'),
        decoder: await manager.pathFor('base-decoder.int8.onnx'),
        tokens: await manager.pathFor('base-tokens.txt'),
        vad: await manager.pathFor('silero_vad.onnx'),
      ),
    );
  }

  void _handleSegment(String text) {
    final aligner = _aligner;
    if (aligner == null || status.value != MemorizationTestStatus.listening) {
      return;
    }
    aligner.submitRecognizedSegment(text);
    revision.value++;
    if (aligner.isComplete) {
      status.value = MemorizationTestStatus.completed;
      // Stop the engine but keep aligner/pageData so the overlay can keep
      // showing the final result until the user exits the mode.
      _stopEngineOnly();
    }
  }

  Future<void> _stopEngineOnly() async {
    await _segmentSub?.cancel();
    _segmentSub = null;
    final engine = _engine;
    if (engine != null) {
      if (_levelListener != null) {
        engine.audioLevel.removeListener(_levelListener!);
      }
      if (_busyListener != null) engine.busy.removeListener(_busyListener!);
      await engine.stop();
    }
    _levelListener = null;
    _busyListener = null;
    _engine = null;
    audioLevel.value = 0;
    engineBusy.value = false;
  }

  /// Ends the session and clears all state. Safe to call when idle.
  Future<void> stop() async {
    await _stopEngineOnly();
    _aligner = null;
    _pageData = null;
    usingRealEngine.value = false;
    stubReason.value = StubReason.none;
    if (status.value != MemorizationTestStatus.idle) {
      status.value = MemorizationTestStatus.idle;
      revision.value++;
    }
  }
}

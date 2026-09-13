import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:permission_handler/permission_handler.dart';

import '../models/ayah_region_data.dart';
import '../models/quran_page_data.dart';
import '../utils/quran_word_aligner.dart';
import 'asr_model_manager.dart';
import 'audio_service.dart';
import 'ayah_region_service.dart';
import 'quran_json_service.dart';
import 'recitation_engine.dart';
import 'sherpa_recitation_engine.dart';

/// Lifecycle of a memorization-test session.
enum MemorizationTestStatus {
  /// No session. The reveal overlay is not shown.
  idle,

  /// `start()` is running (loading data / warming the engine).
  preparing,

  /// Live: ayahs reveal as the engine recognizes their words.
  listening,

  /// Every expected word has been resolved; the engine is stopped but the
  /// overlay stays up so the user can review mistake/skip tints.
  completed,

  /// `start()` failed (no region data for the page, engine failure, ...).
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

/// What the reveal overlay shows for one ayah of the active page.
enum AyahRevealState {
  /// Not reached yet: fully masked.
  hidden,

  /// The ayah the reciter is inside right now: masked, with a position hint.
  current,

  /// Every word resolved correctly: the page shows through.
  revealed,

  /// Resolved, but at least one word was a mistake or was skipped: shown
  /// with a warning tint so the learner sees where it went wrong.
  flagged,
}

/// Coordinates a memorization-test session: owns the [QuranWordAligner],
/// feeds it segments from a [RecitationEngine], and exposes the state the
/// reveal overlay renders. Singleton with `ValueNotifier` fields, matching
/// this codebase's service pattern (`AudioService.instance` etc.).
///
/// Words are aligned individually (the aligner is word-level) but the page
/// is revealed per ayah, using the ayah regions generated for every page.
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
  AyahRegionPageData? _regions;
  List<int> _ayahWordStarts = const [];
  int? _activePage;
  RecitationEngine? _engine;
  StreamSubscription<String>? _segmentSub;
  VoidCallback? _levelListener;
  VoidCallback? _busyListener;
  int _startToken = 0;

  /// Ayah regions of the active session's page (null when idle/failed).
  AyahRegionPageData? get regions => _regions;

  /// 1-based mushaf page of the active session, or null.
  int? get activePage => _activePage;

  /// Per-word statuses in recitation order (all ayahs on the page, in
  /// order, words within each ayah in order). Empty when no session.
  List<WordStatus> get statuses => _aligner?.statuses ?? const [];

  /// Index of the word the reciter is currently expected to say (first
  /// unresolved word), or -1 when no session is active.
  int get currentWordIndex {
    final aligner = _aligner;
    if (aligner == null || aligner.isComplete) return -1;
    return aligner.cursor;
  }

  /// Index (into [AyahRegionPageData.ayahs]) of the ayah containing the
  /// current word, or -1 when no session is active or it is complete.
  int get currentAyahIndex {
    final cursor = currentWordIndex;
    if (cursor < 0) return -1;
    for (var i = 0; i + 1 < _ayahWordStarts.length; i++) {
      if (cursor < _ayahWordStarts[i + 1]) return i;
    }
    return -1;
  }

  /// Reveal state of every ayah on the page, parallel to
  /// [AyahRegionPageData.ayahs]. Empty when no session.
  List<AyahRevealState> get ayahStates {
    final aligner = _aligner;
    if (aligner == null) return const [];
    final cursor = aligner.cursor;
    final current = currentAyahIndex;
    final out = <AyahRevealState>[];
    for (var i = 0; i + 1 < _ayahWordStarts.length; i++) {
      final start = _ayahWordStarts[i];
      final end = _ayahWordStarts[i + 1];
      if (cursor >= end) {
        var flagged = false;
        for (var w = start; w < end; w++) {
          final s = aligner.statuses[w];
          if (s == WordStatus.mistake || s == WordStatus.skipped) {
            flagged = true;
            break;
          }
        }
        out.add(flagged ? AyahRevealState.flagged : AyahRevealState.revealed);
      } else if (i == current) {
        out.add(AyahRevealState.current);
      } else {
        out.add(AyahRevealState.hidden);
      }
    }
    return out;
  }

  bool get isActive =>
      status.value == MemorizationTestStatus.preparing ||
      status.value == MemorizationTestStatus.listening ||
      status.value == MemorizationTestStatus.completed;

  /// Starts a session for [pageNumber] (1-based mushaf page). Returns false
  /// (with [status] = failed) when the page has no region data or the
  /// engine can't start. Any active session is stopped first; a newer
  /// `start()` issued while this one is still preparing wins.
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
    final token = ++_startToken;
    await stop();
    if (token != _startToken) return false;
    status.value = MemorizationTestStatus.preparing;

    // A live mic session and audio playback can't sensibly coexist (and on
    // iOS they'd fight over the shared audio session category).
    if (stopPlayback) {
      AudioService.instance.stop();
    }

    try {
      final regions = await AyahRegionService.forPage(pageNumber);
      final pages = await QuranJsonService.loadQuranPages();
      if (token != _startToken) return false;

      QuranPageData? page;
      for (final p in pages) {
        if (p.page == pageNumber) {
          page = p;
          break;
        }
      }
      if (regions == null || page == null) {
        debugPrint(
          'MemorizationTestService: no data for page $pageNumber',
        );
        status.value = MemorizationTestStatus.failed;
        return false;
      }
      if (!_regionsMatchText(regions, page)) {
        status.value = MemorizationTestStatus.failed;
        return false;
      }

      final expectedWords = <String>[];
      final starts = <int>[];
      for (final ayah in page.ayahs) {
        starts.add(expectedWords.length);
        expectedWords.addAll(
          ayah.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty),
        );
      }
      starts.add(expectedWords.length);
      if (expectedWords.isEmpty) {
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
        if (token != _startToken) {
          await real?.stop();
          return false;
        }
        if (real != null) {
          engine = real;
          usingRealEngine.value = true;
          stubReason.value = StubReason.none;
        } else {
          // Stub replays the passage one WORD at a time so the reveal
          // visibly advances, matching how the real engine resolves within
          // an utterance. stubReason was set by _tryBuildRealEngine so the
          // UI can explain why it's a demo.
          engine = StubRecitationEngine(expectedWords);
          usingRealEngine.value = false;
        }
      }

      _aligner = aligner;
      _regions = regions;
      _ayahWordStarts = starts;
      _activePage = pageNumber;
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
      if (token == _startToken) {
        await stop();
        status.value = MemorizationTestStatus.failed;
      }
      return false;
    }
  }

  /// The regions were generated from the page images while the words come
  /// from output.json; both list the page's ayahs in reading order, so a
  /// count or numbering mismatch means the generated data has drifted.
  bool _regionsMatchText(AyahRegionPageData regions, QuranPageData page) {
    if (regions.ayahs.length != page.ayahs.length) {
      debugPrint(
        'MemorizationTestService: page ${regions.page} has '
        '${regions.ayahs.length} regions but ${page.ayahs.length} ayahs',
      );
      return false;
    }
    for (var i = 0; i < regions.ayahs.length; i++) {
      final r = regions.ayahs[i];
      final a = page.ayahs[i];
      if (r.surah != a.surah || r.ayah != a.ayah) {
        debugPrint(
          'MemorizationTestService: page ${regions.page} region $i is '
          '${r.surah}:${r.ayah} but text is ${a.surah}:${a.ayah}',
        );
        return false;
      }
    }
    return true;
  }

  /// Builds the real mic/ASR engine, or returns null (caller falls back to
  /// the stub) when mic permission is denied or the model files aren't
  /// present, setting [stubReason] to say which.
  ///
  /// Permission is requested FIRST -- before the model check -- so tapping
  /// the mic always prompts the user for microphone access, tying the OS
  /// prompt to their deliberate action.
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
      // Stop the engine but keep aligner/regions so the overlay can keep
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
    _regions = null;
    _ayahWordStarts = const [];
    _activePage = null;
    usingRealEngine.value = false;
    stubReason.value = StubReason.none;
    if (status.value != MemorizationTestStatus.idle) {
      status.value = MemorizationTestStatus.idle;
      revision.value++;
    }
  }
}

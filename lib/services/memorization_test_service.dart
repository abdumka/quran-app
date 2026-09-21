import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Rect;
import 'dart:math' as math;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:permission_handler/permission_handler.dart';

import '../models/ayah_region_data.dart';
import '../models/quran_page_data.dart';
import '../models/word_region_data.dart';
import '../utils/phoneme_tracker.dart';
import '../utils/quran_word_aligner.dart';
import 'install_id.dart';
import 'page_phoneme_service.dart';
import 'zipformer_recitation_engine.dart';
import 'asr_model_manager.dart';
import 'audio_service.dart';
import 'ayah_region_service.dart';
import 'quran_json_service.dart';
import 'recitation_engine.dart';
import 'sherpa_recitation_engine.dart';
import 'tasmee_session_recorder.dart';
import 'tasmee_report_store.dart';
import 'tasmee_weak_point_store.dart';
import 'word_region_service.dart';

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

  /// Resolved, but at least one word was a mistake or was skipped (or the
  /// user asked for it to be revealed/skipped): shown with a warning tint.
  flagged,
}

/// The kind of live feedback message, so the UI can colour it.
enum FeedbackKind {
  /// Neutral information (hint, restart, ...).
  info,

  /// The ayah just recited was completed correctly.
  good,

  /// Something to fix: wrong word, skipped words, wrong ayah.
  wrong,

  /// The app couldn't make out the last segment; repeat it.
  unclear,

  /// No sound has reached the mic for a while.
  silent,
}

/// One human-readable feedback line for the overlay panel.
class RecitationFeedback {
  const RecitationFeedback(this.kind, this.message);
  final FeedbackKind kind;
  final String message;
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

  /// Milliseconds the engine's last decode took (0 when unknown). Shown in
  /// the panel so a slow phone is visible rather than mysterious.
  final ValueNotifier<int> lastDecodeMs = ValueNotifier(0);

  /// Latency the reciter felt for the last segment: milliseconds from the
  /// capture of its last audio sample to its words being applied (-1 when
  /// unknown). The number to watch when tuning speed.
  final ValueNotifier<int> lastLagMs = ValueNotifier(-1);

  /// The most recent text the recognizer produced (raw), so the reciter
  /// can see what the app heard. Empty when nothing yet.
  final ValueNotifier<String> lastHeard = ValueNotifier('');

  /// The current feedback line (null when there's nothing to say).
  /// Transient messages clear themselves after a few seconds.
  final ValueNotifier<RecitationFeedback?> feedback = ValueNotifier(null);

  /// The latest message of the session whether or not the bar showed it
  /// (most are written to the log only): for the logs page and the tests.
  final ValueNotifier<RecitationFeedback?> lastMessage = ValueNotifier(null);

  /// Files of the most recent finished session that can be shared for
  /// offline analysis (empty when none / recording unavailable).
  final ValueNotifier<List<String>> lastSessionFiles = ValueNotifier(const []);

  QuranWordAligner? _aligner;

  /// Set while the streaming phoneme engine runs: the page's expected
  /// phonemes tracked online, judged into word verdicts that are applied
  /// to [_aligner] (which stays the single source of word statuses).
  PhonemeTracker? _tracker;
  VerdictTracer? _tracer;
  Timer? _trackerTimer;
  DateTime _lastPhonemeAt = DateTime.now();
  bool _settledApplied = false;

  /// Fires with the new 1-based page number when a finished page flows
  /// straight into the next one (the engine keeps listening; the page view
  /// only has to flip).
  final ValueNotifier<int> pageAdvanced = ValueNotifier<int>(0);

  /// The strengthening drill under way (null in an ordinary session), its
  /// "2 / 5" label for the bar, and its outcome once it ends.
  TasmeeDrill? _drill;
  final Set<String> _drillMissed = {};
  final ValueNotifier<String?> drillLabel = ValueNotifier<String?>(null);
  final ValueNotifier<TasmeeDrillResult?> drillResult =
      ValueNotifier<TasmeeDrillResult?>(null);
  bool get drillActive => _drill != null;

  /// The page's expected phonemes (kept so the tracker can be rebuilt at a
  /// word the reciter is sent back to).
  PhonemeReference? _reference;

  /// True while the hold is a HARD stop (skipped words): nothing releases
  /// it but reciting the held word or a help button, and the tracker is
  /// barred from moving past the held word's ayah.
  bool _holdHard = false;

  /// Extra line for the session log from the page view (page flips, bar
  /// taps, orientation, ...). Everything goes to the log while the feature
  /// is being tuned.
  void logUi(String what, [Map<String, Object?> data = const {}]) {
    _recorder?.log('ui', {'what': what, ...data});
  }

  // Error journal of the page being recited, and the reports of the pages
  // finished since the mode was switched on (shown when the run ends).
  final List<TasmeeError> _errors = [];
  final Set<String> _errorKeys = {};
  final List<TasmeeReport> _runReports = [];
  DateTime _pageStartedAt = DateTime.now();

  /// Reports of the run that just ended; clears them.
  List<TasmeeReport> takeRunReports() {
    final out = List<TasmeeReport>.of(_runReports);
    _runReports.clear();
    return out;
  }

  void _noteError(int word, String kind, [String heard = '']) {
    final ayah = _ayahIndexOfWord(word);
    final page = _page;
    if (ayah < 0 || page == null || word >= _expectedWords.length) return;
    if (!_errorKeys.add('$word:$kind')) return;
    final e = TasmeeError(
      surah: page.ayahs[ayah].surah,
      ayah: page.ayahs[ayah].ayah,
      wordInAyah: word - _ayahWordStarts[ayah] + 1,
      expected: _expectedWords[word],
      kind: kind,
      heard: heard,
    );
    _errors.add(e);
    if (_drill != null) _drillMissed.add('${e.surah}:${e.ayah}:${e.wordInAyah}');
    _recorder?.log('error', e.toJson());
  }

  /// Closes the page's journal into a saved report.
  void _saveReport({required bool finished}) {
    final aligner = _aligner;
    final pageNumber = _activePage;
    if (aligner == null || pageNumber == null) return;
    final correct = aligner.statuses.where((s) => s == WordStatus.correct).length;
    if (correct == 0 && _errors.isEmpty) return; // nothing was recited
    final report = TasmeeReport(
      page: pageNumber,
      at: _pageStartedAt,
      seconds: DateTime.now().difference(_pageStartedAt).inSeconds,
      words: aligner.length,
      correct: correct,
      errors: List.of(_errors),
      finished: finished,
    );
    _recorder?.log('report', report.toJson());
    _runReports.add(report);
    TasmeeReportStore.save(report);
    TasmeeWeakPointStore.addErrors(report.page, report.errors, report.at);
    _errors.clear();
    _errorKeys.clear();
  }
  bool _advancing = false;
  Map<String, Object?> _recorderInfo = const {};
  String _installId = '';

  /// Set once the first words of the session are committed: a session that
  /// starts mid-page reveals the ayahs before that point rather than
  /// leaving them masked (they are not being tested).
  bool _startResolved = false;
  static PhonemeLexicon? _lexicon;

  static Future<PhonemeLexicon?> _loadLexicon() async {
    if (_lexicon != null) return _lexicon;
    try {
      final raw = await rootBundle.loadString('assets/data/phoneme_lexicon.json');
      _lexicon = PhonemeLexicon((json.decode(raw) as List<dynamic>).cast<String>());
    } catch (e) {
      debugPrint('MemorizationTestService: no phoneme lexicon ($e)');
    }
    return _lexicon;
  }

  /// A word judged wrong that the reciter has not yet repaired: reveal is
  /// held at it (later words stay masked) until the tracker hears it said
  /// correctly, a help button resolves it, or the reciter has clearly gone
  /// on for a while ([_holdReleaseWords] committed words past it).
  int _holdWord = -1;
  int _wordsPastHold = 0;
  static const int _holdReleaseWords = 12;

  /// The word currently held for a mistake, or -1 (for the UI).
  final ValueNotifier<int> heldWord = ValueNotifier(-1);
  AyahRegionPageData? _regions;

  /// Per ayah (parallel to [regions]), the boxes of its words in order, or
  /// null when no usable word geometry exists for that ayah (the overlay
  /// then masks the whole ayah instead of word by word).
  List<List<WordBox>?> _wordBoxes = const [];
  QuranPageData? _page;
  List<String> _expectedWords = const [];
  List<int> _ayahWordStarts = const [];
  int? _activePage;
  RecitationEngine? _engine;
  StreamSubscription<RecognizedSegment>? _segmentSub;
  StreamSubscription<Uint8List>? _audioSub;
  VoidCallback? _levelListener;
  VoidCallback? _busyListener;
  VoidCallback? _decodeListener;
  Timer? _feedbackTimer;
  Timer? _silenceTimer;
  DateTime _lastVoiceOrSegment = DateTime.now();
  bool _silenceWarned = false;
  int _lastAyahIndex = -1;
  int _unexplainedFinals = 0;

  /// Speech budget a previous segment did not use (see
  /// [RecognizedSegment.maxNewWords]). A final is decoded twice; the first
  /// decode takes the whole budget, so if it was garbled the second one
  /// -- which may carry the words -- must inherit what was left.
  int _carriedBudget = 0;
  TasmeeSessionRecorder? _recorder;
  int _startToken = 0;

  /// Ayah regions of the active session's page (null when idle/failed).
  AyahRegionPageData? get regions => _regions;

  /// 1-based mushaf page of the active session, or null.
  int? get activePage => _activePage;

  /// Where the page image sits inside the margin-view (هوامش) image of the
  /// active page, as ratios of that image; null when unknown.
  Rect? get wordMarginRect => _wordMarginRect;
  Rect? _wordMarginRect;

  /// Word boxes of ayah [ayahIndex] in reading order, or null when the page
  /// has no usable word geometry for it.
  List<WordBox>? wordBoxesFor(int ayahIndex) =>
      ayahIndex >= 0 && ayahIndex < _wordBoxes.length
          ? _wordBoxes[ayahIndex]
          : null;

  /// Statuses of the words of ayah [ayahIndex], in reading order.
  List<WordStatus> wordStatusesOf(int ayahIndex) {
    final aligner = _aligner;
    if (aligner == null || ayahIndex < 0 || ayahIndex + 1 >= _ayahWordStarts.length) {
      return const [];
    }
    return aligner.statuses.sublist(
      _ayahWordStarts[ayahIndex],
      _ayahWordStarts[ayahIndex + 1],
    );
  }

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
  int get currentAyahIndex => _ayahIndexOfWord(currentWordIndex);

  int _ayahIndexOfWord(int word) {
    if (word < 0) return -1;
    for (var i = 0; i + 1 < _ayahWordStarts.length; i++) {
      if (word < _ayahWordStarts[i + 1]) return i;
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
      final end = _ayahWordStarts[i + 1];
      if (cursor >= end) {
        out.add(_ayahFlagged(i) ? AyahRevealState.flagged : AyahRevealState.revealed);
      } else if (i == current) {
        out.add(AyahRevealState.current);
      } else {
        out.add(AyahRevealState.hidden);
      }
    }
    return out;
  }

  bool _ayahFlagged(int i) {
    final aligner = _aligner;
    if (aligner == null) return false;
    for (var w = _ayahWordStarts[i]; w < _ayahWordStarts[i + 1]; w++) {
      final s = aligner.statuses[w];
      if (s == WordStatus.mistake || s == WordStatus.skipped || s == WordStatus.revealed) return true;
    }
    return false;
  }

  /// The words of the ayah being recited right now, paired with their
  /// statuses, so the panel can show them appearing one by one. Empty when
  /// no session or the page is complete.
  List<(String, WordStatus)> get currentAyahWords {
    final aligner = _aligner;
    final ayah = currentAyahIndex;
    if (aligner == null || ayah < 0) return const [];
    return [
      for (var w = _ayahWordStarts[ayah]; w < _ayahWordStarts[ayah + 1]; w++)
        (_expectedWords[w], aligner.statuses[w]),
    ];
  }

  /// Ayah counts for the completion summary: (revealed cleanly, flagged).
  (int, int) get summary {
    var clean = 0;
    var flagged = 0;
    for (final s in ayahStates) {
      if (s == AyahRevealState.revealed) clean++;
      if (s == AyahRevealState.flagged) flagged++;
    }
    return (clean, flagged);
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
    int? startAyahIndex,
    TasmeeDrill? drill,
  }) async {
    final token = ++_startToken;
    await stop();
    if (token != _startToken) return false;
    drillResult.value = null;
    status.value = MemorizationTestStatus.preparing;

    // A live mic session and audio playback can't sensibly coexist (and on
    // iOS they'd fight over the shared audio session category).
    if (stopPlayback) {
      AudioService.instance.stop();
    }

    try {
      final regions = await AyahRegionService.forPage(pageNumber);
      final wordRegions = await WordRegionService.forPage(pageNumber);
      _wordMarginRect = wordRegions?.marginRect;
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

      PhonemeTracker? tracker;
      VerdictTracer? tracer;
      if (engine.emitsPhonemes) {
        final phonemes = await PagePhonemeService.forPage(pageNumber);
        if (token != _startToken) {
          await engine.stop();
          return false;
        }
        if (phonemes == null || phonemes.words.length != expectedWords.length) {
          debugPrint('MemorizationTestService: page phonemes unusable for '
              'page $pageNumber (${phonemes?.words.length} vs '
              '${expectedWords.length} words)');
          await engine.stop();
          status.value = MemorizationTestStatus.failed;
          return false;
        }
        final reference =
            PhonemeReference(phonemes.collapsed(), PhonemeCostTable());
        _reference = reference;
        // A drill (or any session told where to begin) starts on that ayah
        // only; an ordinary session may start on any ayah of the page.
        tracker = PhonemeTracker(
          reference,
          startAnywhere: startAyahIndex == null,
          startWord: startAyahIndex == null
              ? 0
              : starts[startAyahIndex.clamp(0, starts.length - 2).toInt()],
        );
        tracer = VerdictTracer(tracker, lexicon: await _loadLexicon());
      }
      _tracker = tracker;
      _tracer = tracer;
      _settledApplied = false;
      _startResolved = startAyahIndex != null;
      _errors.clear();
      _errorKeys.clear();
      _pageStartedAt = DateTime.now();
      _lastPhonemeAt = DateTime.now();
      _holdWord = -1;
      _holdHard = false;
      _wordsPastHold = 0;
      heldWord.value = -1;
      _drill = drill;
      _drillMissed.clear();
      drillLabel.value = drill == null
          ? null
          : 'تقوية الحفظ ${drill.index} / ${drill.total}';
      if (startAyahIndex != null) {
        // The ayahs before the starting one are not under test: shown.
        final s = starts[startAyahIndex.clamp(0, starts.length - 2).toInt()];
        if (s > 0) aligner.forceResolveRange(0, s, WordStatus.correct);
      }

      _aligner = aligner;
      _regions = regions;
      _wordBoxes = _usableWordBoxes(wordRegions, page);
      _page = page;
      _expectedWords = expectedWords;
      _ayahWordStarts = starts;
      _activePage = pageNumber;
      _engine = engine;
      _lastAyahIndex = 0;
      _unexplainedFinals = 0;
      _carriedBudget = 0;
      lastLagMs.value = -1;
      lastHeard.value = '';
      _setFeedback(null);
      _levelListener = () {
        audioLevel.value = engine.audioLevel.value;
        if (engine.audioLevel.value > 0.12) {
          _lastVoiceOrSegment = DateTime.now();
          _silenceWarned = false;
        }
      };
      _busyListener = () => engineBusy.value = engine.busy.value;
      _decodeListener = () {
        lastDecodeMs.value = engine.lastDecodeMs.value;
        _recorder?.log('decode', {'ms': engine.lastDecodeMs.value});
      };
      engine.audioLevel.addListener(_levelListener!);
      engine.busy.addListener(_busyListener!);
      engine.lastDecodeMs.addListener(_decodeListener!);
      _segmentSub = engine.segments.listen(
        _handleSegment,
        onError: (Object error) {
          _recorder?.log('engineError', {'error': '$error'});
          _setFeedback(
            RecitationFeedback(FeedbackKind.wrong, 'خطأ في محرك التعرف: $error'),
            sticky: true,
            show: true,
          );
        },
      );

      // Keep a shareable copy of every session (decisions, plus audio when
      // the real mic engine is running).
      if (engineOverride == null) {
        final installId = await InstallId.get();
        String appVersion = '';
        try {
          final pkg = await PackageInfo.fromPlatform();
          appVersion = '${pkg.version}+${pkg.buildNumber}';
        } catch (_) {}
        _installId = installId;
        _recorderInfo = {
          'installId': installId,
          'appVersion': appVersion,
          'platform': Platform.operatingSystem,
          'os': Platform.operatingSystemVersion,
          'model': engine.emitsPhonemes ? 'zipformer_p_arabic_v3.1.int8' : 'whisper-base-ar-quran',
          'engine': engine.emitsPhonemes ? 'zipformer' : usingRealEngine.value ? 'sherpa' : 'stub',
          'stubReason': stubReason.value.name,
        };
        _recorder = await TasmeeSessionRecorder.begin(
          page: pageNumber,
          installId: installId,
          info: {
            'installId': installId,
            'appVersion': appVersion,
            'platform': Platform.operatingSystem,
            'os': Platform.operatingSystemVersion,
            'model': engine.emitsPhonemes ? 'zipformer_p_arabic_v3.1.int8' : 'whisper-base-ar-quran',
            'engine': engine.emitsPhonemes
                ? 'zipformer'
                : usingRealEngine.value
                    ? 'sherpa'
                    : 'stub',
            'stubReason': stubReason.value.name,
            'alertMode': (await TasmeeAlert.mode()).name,
            'ayahs': [
              for (final a in page.ayahs) '${a.surah}:${a.ayah}',
            ],
            'words': expectedWords.length,
            'startAyahIndex': ?startAyahIndex,
            if (drill != null)
              'drill': {
                'page': drill.page,
                'surah': drill.surah,
                'ayah': drill.ayah,
                'targets': [for (final t in drill.targets) t.key],
                'index': drill.index,
                'total': drill.total,
              },
          },
        );
        final audio = engine.audioChunks;
        if (audio != null && _recorder != null) {
          _audioSub = audio.listen(_recorder!.addAudio);
        }
      }

      await engine.start();
      if (token != _startToken) return false;
      status.value = MemorizationTestStatus.listening;
      _recorder?.log('listening');
      _lastVoiceOrSegment = DateTime.now();
      _silenceWarned = false;
      _silenceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _checkSilence();
      });
      if (tracker != null) {
        _trackerTimer = Timer.periodic(
          const Duration(milliseconds: 250),
          (_) => _tickTracker(),
        );
      }
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

  /// Starts the same page over from the first word.
  Future<bool> restart() async {
    final page = _activePage;
    if (page == null) return false;
    _recorder?.log('control', {'action': 'restart'});
    return start(pageNumber: page);
  }

  /// Word boxes are only trusted for an ayah whose generated box count
  /// equals its word count (and whose numbering matches); anything else
  /// falls back to ayah-level masking for that ayah.
  List<List<WordBox>?> _usableWordBoxes(
    WordRegionPageData? wordRegions,
    QuranPageData page,
  ) {
    return [
      for (var i = 0; i < page.ayahs.length; i++)
        () {
          if (wordRegions == null || i >= wordRegions.ayahs.length) {
            return null;
          }
          final w = wordRegions.ayahs[i];
          final a = page.ayahs[i];
          final count =
              a.text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
          if (w.surah != a.surah || w.ayah != a.ayah || w.words.length != count) {
            return null;
          }
          return w.words;
        }(),
    ];
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

    if (await manager.hasZipformer()) {
      return ZipformerRecitationEngine(
        ZipformerModelPaths(
          model: await manager.pathFor('zipformer_p_arabic_v3.1.int8.onnx'),
          tokens: await manager.pathFor('zipformer-tokens.txt'),
        ),
      );
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

  // ---------------------------------------------------------------------
  // Help buttons
  // ---------------------------------------------------------------------

  /// Reveals the next word on the page (the held word when a mistake is
  /// being held, else the first unresolved one) -- one word only, shown
  /// with the amber wash and counted as a flaw of its ayah.
  void showHint() {
    final aligner = _aligner;
    if (aligner == null || status.value != MemorizationTestStatus.listening) {
      return;
    }
    // The held word first (the one the reciter is stuck on); otherwise the
    // first word of the page that is still hidden, whatever its status.
    var word = _holdWord;
    if (word < 0) {
      final st = aligner.statuses;
      word = st.indexWhere(
        (s) => s != WordStatus.correct && s != WordStatus.revealed,
        _startResolved ? 0 : currentWordIndex.clamp(0, st.length),
      );
    }
    if (word < 0) return;
    _recorder?.log('control', {'action': 'hint', 'word': word});
    final wasHard = _holdHard && _holdWord == word;
    if (_holdWord == word) _releaseHold('control');
    aligner.forceResolveRange(word, word + 1, WordStatus.revealed);
    _noteError(word, 'revealed');
    // After a hard stop the tracker waits at the held word: move it on to
    // the word after the one just shown.
    if (wasHard) _rewindTracker(word + 1);
    _setFeedback(RecitationFeedback(
      FeedbackKind.info,
      'كُشفت الكلمة «${_expectedWords[word]}» — تابع من بعدها',
    ));
    revision.value++;
    _finishIfComplete();
  }

  /// Reveals the current ayah on the page (its unresolved words show with
  /// the amber wash and count as flaws) and moves on to the next one.
  void revealCurrentAyah() => _resolveCurrentAyah('reveal', WordStatus.revealed);

  /// Covers an ayah again and expects it from its first word: the current
  /// ayah when part of it has been recited, otherwise the one before it.
  void repeatAyah() {
    final aligner = _aligner;
    if (aligner == null || status.value != MemorizationTestStatus.listening) {
      return;
    }
    var ayah = currentAyahIndex;
    if (ayah < 0) ayah = _ayahWordStarts.length - 2;
    final started = aligner.cursor > _ayahWordStarts[ayah];
    if (!started && ayah > 0) ayah -= 1;
    _recorder?.log('control', {'action': 'repeatAyah', 'ayah': ayah});
    _releaseHold('control');
    aligner.resetRange(_ayahWordStarts[ayah], aligner.length);
    // As if the ayah had never been read: the tracker forgets what it heard
    // and waits at the ayah's first word (its old verdicts would otherwise
    // uncover the whole ayah again at the next sound).
    _rewindTracker(_ayahWordStarts[ayah]);
    final number = _page?.ayahs[ayah].ayah ?? ayah + 1;
    _setFeedback(RecitationFeedback(FeedbackKind.info, 'أعد الآية $number من أولها'));
    _lastAyahIndex = ayah;
    revision.value++;
  }

  /// Skips the current ayah (marks its unresolved words as skipped) and
  /// moves on to the next one.
  void skipCurrentAyah() => _resolveCurrentAyah('skip', WordStatus.skipped);

  void _resolveCurrentAyah(String action, WordStatus mark) {
    final aligner = _aligner;
    // The ayah of the held word when the session is stopped at one (the
    // cursor may already sit past it), else the ayah being recited.
    final ayah =
        _holdWord >= 0 ? _ayahIndexOfWord(_holdWord) : currentAyahIndex;
    if (aligner == null || ayah < 0 ||
        status.value != MemorizationTestStatus.listening) {
      return;
    }
    _recorder?.log('control', {'action': action, 'ayah': ayah});
    _releaseHold('control');
    for (var w = _ayahWordStarts[ayah]; w < _ayahWordStarts[ayah + 1]; w++) {
      if (aligner.statuses[w] != WordStatus.correct) {
        _noteError(w, action == 'skip' ? 'skippedAyah' : 'revealed');
        if (action == 'skip') break;
      }
    }
    aligner.forceResolveRange(
      _ayahWordStarts[ayah],
      _ayahWordStarts[ayah + 1],
      mark,
    );
    final number = _page?.ayahs[ayah].ayah ?? ayah + 1;
    _setFeedback(RecitationFeedback(
      FeedbackKind.info,
      action == 'skip' ? 'تم تخطي الآية $number' : 'تم كشف الآية $number',
    ));
    // The recitation goes on from the next ayah.
    _rewindTracker(_ayahWordStarts[ayah + 1]);
    _lastAyahIndex = currentAyahIndex;
    revision.value++;
    _finishIfComplete();
  }

  // ---------------------------------------------------------------------
  // Recognition handling
  // ---------------------------------------------------------------------

  void _handleSegment(RecognizedSegment segment) {
    final aligner = _aligner;
    if (aligner == null || status.value != MemorizationTestStatus.listening) {
      return;
    }
    if (segment.phonemes != null) {
      _handlePhonemes(segment);
      return;
    }
    final text = segment.text;
    _lastVoiceOrSegment = DateTime.now();
    _silenceWarned = false;
    lastHeard.value = text;

    final ayahBefore = currentAyahIndex;
    final cursorBefore = aligner.cursor;
    final budget = segment.maxNewWords > 0
        ? segment.maxNewWords + _carriedBudget
        : 0;
    final outcome = aligner.submitRecognizedSegment(
      text,
      isFinal: segment.isFinal,
      maxNewWords: budget,
    );
    if (budget > 0) {
      _carriedBudget = math.min(20, budget - outcome.correct.length);
    }
    if (segment.lagMs >= 0) lastLagMs.value = segment.lagMs;
    _recorder?.log('segment', {
      'text': text,
      'final': segment.isFinal,
      'audioEndMs': segment.audioEndMs,
      'speechMs': segment.speechMs,
      'maxNew': segment.maxNewWords,
      'lagMs': segment.lagMs,
      'cursorBefore': cursorBefore,
      'cursorAfter': aligner.cursor,
      'correct': outcome.correct,
      'skipped': outcome.skipped,
      'mistakes': outcome.mistakes,
      'unclear': outcome.unclearIndex,
      'repeat': outcome.repeatOfHistory,
    });
    revision.value++;

    _explain(outcome, text, ayahBefore, isFinal: segment.isFinal);
    _finishIfComplete();
  }

  // ---------------------------------------------------------------------
  // Streaming phoneme path
  // ---------------------------------------------------------------------

  /// Feeds newly emitted phoneme tokens to the tracker and applies what it
  /// can already judge. Verdicts that need the reciter to move on (dwell)
  /// or to pause (settle) arrive through [_tickTracker].
  void _handlePhonemes(RecognizedSegment segment) {
    final tracker = _tracker;
    if (tracker == null) return;
    final tokens = segment.phonemes!;
    if (tokens.isEmpty) return;
    final times = segment.phonemeTimesMs ?? const <int>[];
    _lastVoiceOrSegment = DateTime.now();
    _silenceWarned = false;
    final chars = <HeardChar>[];
    for (var k = 0; k < tokens.length; k++) {
      final ms = k < times.length ? times[k] : segment.audioEndMs;
      final frame = (ms / 40).round();
      for (final r in collapseMadd(tokens[k]).runes) {
        chars.add(HeardChar(String.fromCharCode(r), frame));
      }
    }
    tracker.feed(chars);
    if (feedback.value?.kind == FeedbackKind.silent) _setFeedback(null);
    _lastPhonemeAt = DateTime.now();
    _settledApplied = false;
    if (segment.lagMs >= 0) lastLagMs.value = segment.lagMs;
    final shown = lastHeard.value + tokens.join();
    lastHeard.value =
        shown.length > 40 ? shown.substring(shown.length - 40) : shown;
    _recorder?.log('phonemes', {
      'tokens': tokens,
      'timesMs': times,
      'audioEndMs': segment.audioEndMs,
      'lagMs': segment.lagMs,
    });
    _applyTrackerVerdicts(settled: false);
  }

  void _tickTracker() {
    if (_tracker == null || status.value != MemorizationTestStatus.listening) {
      return;
    }
    final settled =
        DateTime.now().difference(_lastPhonemeAt).inMilliseconds >= 1000;
    if (!settled || _settledApplied) return;
    _settledApplied = true;
    _applyTrackerVerdicts(settled: true);
  }

  /// Maps tracker verdicts onto word statuses. `ok`/`unsure` reveal the
  /// word; `skipped` marks it; `wrong` becomes a mistake only once the
  /// reciter has clearly moved on or paused, so a self-correction a moment
  /// later still repairs it. Words the cursor has passed without any
  /// verdict are swept as skipped so ayahs can complete.
  void _applyTrackerVerdicts({required bool settled}) {
    final tracker = _tracker;
    final tracer = _tracer;
    final aligner = _aligner;
    // A page whose last word is held for a mistake is not finished yet.
    if (tracker == null || tracer == null || aligner == null ||
        (aligner.isComplete && _holdWord < 0)) {
      return;
    }
    final ayahBefore = currentAyahIndex;
    final cursorWord = tracker.cursorWord;
    final verdicts = tracer.verdicts(settled: settled);
    final updates = <int, WordStatus>{};
    final wrongVerdicts = <WordVerdict>[];
    WordVerdict? repaired;
    for (final v in verdicts) {
      switch (v.state) {
        case VerdictState.ok:
        case VerdictState.unsure:
          // `unsure` (distance 0.15-0.4, or low-confidence phonemes) reveals
          // too: in the phone logs it is almost always a correctly recited
          // word with model noise at a boundary (a fifth of the words on
          // some pages), and a masked word would also stall the aligner's
          // cursor, so the ayah could never complete.
          if (v.word == _holdWord) {
            // A held word is repaired by a clean or a near reading only: a
            // loose `unsure` match (فأخذناهم heard for فإذا) must not lift
            // the hold.
            if (v.state == VerdictState.ok || v.distance <= 0.3) {
              updates[v.word] = WordStatus.correct;
              repaired = v;
            }
          } else {
            updates[v.word] = WordStatus.correct;
          }
        case VerdictState.skipped:
          updates[v.word] = WordStatus.skipped;
        case VerdictState.wrong:
          // A wrong reading (Hafs habit) is certain at once; other wrong
          // verdicts wait until the reciter has moved on or paused, so a
          // self-correction a moment later still repairs the word.
          // Until the first correct word has shown WHERE on the page the
          // reciter started, a wrong verdict is only the tracker guessing
          // the first ayah (a cough or a false start lands on the page's
          // first word): wait. A really wrong first word is flagged as soon
          // as the second one is heard.
          if (!_startResolved) break;
          if (v.reason == 'hafs' || settled || v.word < cursorWord - 1) {
            updates[v.word] = WordStatus.mistake;
            wrongVerdicts.add(v);
          }
        case VerdictState.pending:
          break;
      }
    }
    final behind = settled ? cursorWord : cursorWord - 2;
    for (var w = 0; w < behind && w < aligner.length; w++) {
      if (aligner.statuses[w] == WordStatus.pending &&
          !updates.containsKey(w)) {
        updates[w] = WordStatus.skipped;
      }
    }
    // A one-to-three-letter word (قل، من، ما، إن) with both neighbours
    // heard is almost always a recognizer drop, not a skip: the phone logs
    // show the model losing such words after a pause or a long madd, and
    // the offline decode of the same audio loses them too. Count it as
    // recited rather than nag about it.
    bool heard(int w) =>
        w >= 0 &&
        w < aligner.length &&
        (aligner.statuses[w] == WordStatus.correct ||
            updates[w] == WordStatus.correct);
    for (final e in updates.entries.toList()) {
      if (e.value != WordStatus.skipped) continue;
      final w = e.key;
      if (_isShortWord(w) && heard(w - 1) && heard(w + 1)) {
        updates[w] = WordStatus.correct;
        _recorder?.log('absorbed', {'word': w});
      }
    }

    // Hold: while a mistake stands, nothing after it is revealed.
    if (_holdWord >= 0) {
      if (cursorWord < _holdWord) {
        // The reciter went back (start of the ayah, previous ayah): a fresh
        // attempt is under way, so the moved-on counter restarts.
        _wordsPastHold = 0;
      }
      if (repaired != null) {
        _releaseHold('repaired');
      } else if (!_holdHard && _skippedRunAfter(_holdWord, updates, aligner) > 0) {
        // The "mistake" was the first word of a passage the reciter jumped
        // over (the next ayah's opening said in its place): the words after
        // it come back skipped. Stop hard there.
        final run = 1 + _skippedRunAfter(_holdWord, updates, aligner);
        updates.removeWhere((w, st) => w > _holdWord);
        _holdHard = true;
        _wordsPastHold = 0;
        _recorder?.log('holdHardened', {'word': _holdWord, 'run': run});
        _noteError(_holdWord, 'skipped');
        _setFeedback(
          const RecitationFeedback(
            FeedbackKind.wrong,
            'تجاوزت موضعًا — عد إلى الكلمة المظلَّلة، أو اضغط «كلمة» أو «الآية»',
          ),
          sticky: true,
          show: true,
        );
        _rewindTracker(_holdWord, barrier: true);
      } else {
        final past = updates.entries
            .where((e) => e.key > _holdWord && e.value == WordStatus.correct)
            .length;
        if (past > 0) _wordsPastHold = math.max(_wordsPastHold, past);
        if (_wordsPastHold >= _holdReleaseWords && !_holdHard) {
          _releaseHold('moved-on');
        } else {
          updates.removeWhere((w, st) => w > _holdWord);
        }
      }
    }
    // First commit of the session further down the page: the reciter
    // chose to start there, so the ayahs before it are not under test and
    // are shown (unflagged) rather than left masked.
    if (!_startResolved) {
      final firstCorrect = updates.entries
          .where((e) => e.value == WordStatus.correct)
          .map((e) => e.key)
          .fold<int>(-1, (a, b) => a < 0 || b < a ? b : a);
      if (firstCorrect >= 0) {
        _startResolved = true;
        final ayah = _ayahIndexOfWord(firstCorrect);
        final start = ayah > 0 ? _ayahWordStarts[ayah] : 0;
        if (start > 0 && !aligner.statuses.sublist(0, start).contains(WordStatus.correct)) {
          for (var w = 0; w < start; w++) {
            updates[w] = WordStatus.correct;
          }
          _recorder?.log('startAt', {'word': start, 'ayah': ayah});
        }
      }
    }
    // Where the session started is the only free choice. Until it is known
    // nothing is a skip; once it is, the recitation may not skip: a skipped
    // word stops the session there (a run of them, or a whole ayah, stops it
    // HARD: only reciting from that word or a help button goes on).
    var skipHold = -1;
    var skipRun = 0;
    if (!_startResolved) {
      updates.removeWhere((w, st) => st == WordStatus.skipped);
    } else if (_holdWord < 0) {
      bool flawed(int w) =>
          w >= 0 &&
          w < aligner.length &&
          aligner.statuses[w] == WordStatus.pending &&
          (updates[w] == WordStatus.skipped || updates[w] == WordStatus.mistake);
      var first = -1;
      for (final e in updates.entries) {
        if (e.value == WordStatus.skipped &&
            aligner.statuses[e.key] == WordStatus.pending &&
            (first < 0 || e.key < first)) {
          first = e.key;
        }
      }
      if (first >= 0) {
        while (flawed(first - 1)) {
          first--;
        }
        var last = first;
        while (flawed(last + 1)) {
          last++;
        }
        skipHold = first;
        skipRun = last - first + 1;
        updates.removeWhere((w, st) => w > skipHold);
        updates[skipHold] = WordStatus.mistake;
      }
    }
    if (updates.isEmpty) return;
    final heardWords = [
      for (final e in updates.entries)
        if (e.value == WordStatus.correct) aligner.expectedNormalized[e.key],
    ];
    final outcome = aligner.applyExternalVerdicts(
      updates,
      heardTokens: heardWords.isNotEmpty ? heardWords : const ['\u00b7'],
    );
    if (outcome.correct.isEmpty &&
        outcome.skipped.isEmpty &&
        outcome.mistakes.isEmpty) {
      return;
    }
    for (final w in outcome.skipped) {
      _noteError(w, 'skipped');
    }
    _recorder?.log('verdicts', {
      'settled': settled,
      'cursor': cursorWord,
      'correct': outcome.correct,
      'skipped': outcome.skipped,
      'mistakes': outcome.mistakes,
      'cursorAfter': aligner.cursor,
      'hold': _holdWord,
      'detail': [
        for (final v in verdicts)
          if (updates.containsKey(v.word))
            {
              'w': v.word,
              's': v.state.name,
              'd': double.parse(v.distance.toStringAsFixed(3)),
              'h': v.heard,
              if (v.reason.isNotEmpty) 'r': v.reason,
            },
      ],
    });
    revision.value++;

    if (skipHold >= 0) {
      final hard = skipRun >= 2;
      final ayah = _ayahIndexOfWord(skipHold);
      final wholeAyah = ayah >= 0 &&
          skipHold == _ayahWordStarts[ayah] &&
          skipHold + skipRun >= _ayahWordStarts[ayah + 1];
      _holdWord = skipHold;
      _holdHard = hard;
      _wordsPastHold = 0;
      heldWord.value = _holdWord;
      _recorder?.log('hold', {
        'word': _holdWord,
        'reason': 'skipped',
        'run': skipRun,
        'hard': hard,
        'wholeAyah': wholeAyah,
      });
      _noteError(skipHold, wholeAyah ? 'skippedAyah' : 'skipped');
      TasmeeAlert.fire();
      _setFeedback(
        RecitationFeedback(
          FeedbackKind.wrong,
          hard
              ? 'تجاوزت موضعًا — عد إلى الكلمة المظلَّلة، أو اضغط «كلمة» أو «الآية»'
              : 'تجاوزت كلمة — أعدها أو اضغط «كلمة»',
        ),
        sticky: true,
        show: true,
      );
      if (hard) _rewindTracker(skipHold, barrier: true);
      return;
    }

    // A new mistake: hold the reveal there and say exactly what was heard.
    final newMistake = wrongVerdicts
        .where((v) => outcome.mistakes.contains(v.word))
        .fold<WordVerdict?>(null, (a, b) => a == null || b.word < a.word ? b : a);
    if (newMistake != null && (_holdWord < 0 || newMistake.word < _holdWord)) {
      _holdWord = newMistake.word;
      _wordsPastHold = 0;
      heldWord.value = _holdWord;
      // Say that there is a mistake and what was heard, but never the
      // expected word itself: the reciter is testing memory. The hint
      // button reveals it on request.
      final heard = phonemesToArabic(newMistake.heard);
      final ayah = _ayahIndexOfWord(newMistake.word);
      final position = ayah < 0 ? 0 : newMistake.word - _ayahWordStarts[ayah] + 1;
      final number = ayah < 0 ? null : _page?.ayahs[ayah].ayah;
      final where = number == null ? '' : ' (الآية $number، الكلمة $position)';
      _recorder?.log('hold', {'word': _holdWord, 'reason': newMistake.reason, 'heard': newMistake.heard});
      _noteError(newMistake.word, newMistake.reason.isEmpty ? 'distance' : newMistake.reason, heard);
      TasmeeAlert.fire();
      // The bar only says THAT there is a mistake (the held word carries
      // the red tint); what was heard and why go to the log and the report.
      _recorder?.log('note', {
        'message': switch (newMistake.reason) {
          'hafs' => 'قرأت «$heard» بحفص$where',
          'word' => 'قرأت «$heard» وهي ليست الكلمة المطلوبة$where',
          'extra' => 'زدت «$heard» وليست في الآية$where',
          'haraka' => 'حركة آخر الكلمة غير صحيحة$where',
          _ => 'خطأ$where — سمعت «$heard»',
        },
      });
      _setFeedback(
        const RecitationFeedback(
          FeedbackKind.wrong,
          'خطأ في الكلمة المظلَّلة — أعدها أو اضغط «كلمة»',
        ),
        sticky: true,
        show: true,
      );
      _finishIfComplete();
      return;
    }
    _explain(outcome, heardWords.join(' '), ayahBefore, isFinal: true);
    _finishIfComplete();
  }

  /// How many words right after [word] the pending verdicts call skipped
  /// (mistakes in between count along; 0 when none is skipped).
  int _skippedRunAfter(int word, Map<int, WordStatus> updates, QuranWordAligner aligner) {
    var n = 0;
    var skipped = 0;
    for (var w = word + 1; w < aligner.length; w++) {
      final st = updates[w];
      if (aligner.statuses[w] != WordStatus.pending ||
          (st != WordStatus.skipped && st != WordStatus.mistake)) {
        break;
      }
      n++;
      if (st == WordStatus.skipped) skipped++;
    }
    return skipped == 0 ? 0 : n;
  }

  static final RegExp _marks = RegExp(
    r'[ً-ٰٟۖ-ۭؐ-ؚ࣓-ࣿ]',
  );

  /// A word of at most three letters once its marks are stripped.
  bool _isShortWord(int w) {
    if (w < 0 || w >= _expectedWords.length) return false;
    return _expectedWords[w].replaceAll(_marks, '').length <= 3;
  }

  void _releaseHold(String how) {
    if (_holdWord < 0) return;
    _recorder?.log('holdReleased', {'word': _holdWord, 'how': how, 'hard': _holdHard});
    if (feedback.value?.kind == FeedbackKind.wrong) _setFeedback(null);
    _tracker?.maxCell = null;
    _holdWord = -1;
    _holdHard = false;
    _wordsPastHold = 0;
    heldWord.value = -1;
  }

  /// Rebuilds the tracker so that it waits at [word] with nothing heard yet
  /// (repeat an ayah, go on after a help button, stop at skipped words).
  /// With [barrier] no path may leave the ayah of [word] until the hold is
  /// released, whatever is recited further down the page.
  void _rewindTracker(int word, {bool barrier = false}) {
    final reference = _reference;
    if (reference == null || _tracker == null) return;
    if (word < 0 || word >= reference.n) return;
    final tracker =
        PhonemeTracker(reference, startAnywhere: false, startWord: word);
    if (barrier) {
      final ayah = _ayahIndexOfWord(word);
      if (ayah >= 0) {
        tracker.maxCell = reference.wordStart[_ayahWordStarts[ayah + 1]];
      }
    }
    _tracker = tracker;
    _tracer = VerdictTracer(tracker, lexicon: _lexicon);
    _settledApplied = false;
    _startResolved = true;
    _recorder?.log('rewind', {'word': word, 'barrier': tracker.maxCell});
  }

  /// A drill ends once its target ayah has been recited to its last word
  /// with nothing held. Returns true when it ended the session.
  bool _checkDrillDone() {
    final drill = _drill;
    final aligner = _aligner;
    final page = _page;
    if (drill == null || aligner == null || page == null) return false;
    if (_activePage != drill.page || _holdWord >= 0) return false;
    if (status.value != MemorizationTestStatus.listening) return false;
    final idx = page.ayahs.indexWhere(
      (a) => a.surah == drill.surah && a.ayah == drill.ayah,
    );
    if (idx < 0 || aligner.cursor < _ayahWordStarts[idx + 1]) return false;
    final passed = [
      for (final t in drill.targets)
        if (!_drillMissed.contains(t.key)) t,
    ];
    final failed = [
      for (final t in drill.targets)
        if (_drillMissed.contains(t.key)) t,
    ];
    _recorder?.log('drill', {
      'passed': [for (final t in passed) t.key],
      'failed': [for (final t in failed) t.key],
    });
    _saveReport(finished: false);
    TasmeeWeakPointStore.resolve(passed.map((t) => t.key));
    drillResult.value =
        TasmeeDrillResult(drill: drill, passed: passed, failed: failed);
    status.value = MemorizationTestStatus.completed;
    _stopEngineOnly();
    return true;
  }

  /// Turns an alignment outcome into the one line the panel shows.
  void _explain(
    SegmentOutcome outcome,
    String text,
    int ayahBefore, {
    required bool isFinal,
  }) {
    if (outcome.tokens.isEmpty) return;
    final aligner = _aligner!;

    // An interim decode is cut mid-air; only its positive news is worth
    // showing. Negative verdicts wait for the final decode.
    if (!isFinal &&
        outcome.correct.isEmpty &&
        outcome.skipped.isEmpty) {
      return;
    }

    // Several finals in a row that match nothing on the page, anywhere:
    // the reciter has drifted into another surah (the Quran repeats
    // phrases across surahs, and memory follows the phrase).
    if (isFinal && outcome.alignedNothing && !outcome.repeatOfHistory) {
      _unexplainedFinals++;
    } else if (isFinal) {
      _unexplainedFinals = 0;
    }
    if (_unexplainedFinals >= 2 && !_matchesAnywhere(outcome)) {
      _setFeedback(
        const RecitationFeedback(
          FeedbackKind.wrong,
          'ما تقرؤه ليس في هذه الصفحة — عد إلى الآية المطلوبة أو اضغط «كلمة»',
        ),
        show: true,
      );
      return;
    }

    if (outcome.mistakes.isNotEmpty) {
      final w = _expectedWords[outcome.mistakes.first];
      _setFeedback(RecitationFeedback(
        FeedbackKind.wrong,
        'خطأ في «$w» — سمعت: ${_shorten(text)}',
      ));
      _maybeWrongAyah(outcome);
      return;
    }
    if (outcome.unclearIndex >= 0) {
      if (_maybeWrongAyah(outcome)) return;
      final w = _expectedWords[outcome.unclearIndex];
      _setFeedback(RecitationFeedback(
        FeedbackKind.unclear,
        'لم أتبيّن الكلمة، أعد: «$w»',
      ));
      return;
    }
    if (outcome.skipped.isNotEmpty) {
      // A jump across ayahs (the aligner resynced further down the page):
      // say which ayahs were passed over and where the reciter is now.
      final page = _page;
      final firstAyah = _ayahIndexOfWord(outcome.skipped.first);
      final lastSkippedAyah = _ayahIndexOfWord(outcome.skipped.last);
      final nowAyah = aligner.isComplete
          ? _ayahWordStarts.length - 2
          : currentAyahIndex;
      if (page != null && firstAyah >= 0 && nowAyah > firstAyah) {
        final from = page.ayahs[firstAyah].ayah;
        final to = page.ayahs[lastSkippedAyah].ayah;
        final now = page.ayahs[nowAyah].ayah;
        _setFeedback(RecitationFeedback(
          FeedbackKind.wrong,
          from == to
              ? 'تجاوزت الآية $from — أنت الآن في الآية $now'
              : 'تجاوزت الآيات $from–$to — أنت الآن في الآية $now',
        ));
        return;
      }
      final words = outcome.skipped
          .take(3)
          .map((i) => _expectedWords[i])
          .join(' ');
      _setFeedback(RecitationFeedback(
        FeedbackKind.wrong,
        outcome.skipped.length > 3
            ? 'تجاوزت ${outcome.skipped.length} كلمات: $words …'
            : 'تجاوزت: $words',
      ));
      return;
    }
    if (outcome.repeatOfHistory) return;

    // Correct words only. Announce each ayah completed by this segment.
    final ayahNow = aligner.isComplete
        ? _ayahWordStarts.length - 2
        : currentAyahIndex;
    if (ayahNow > ayahBefore || aligner.isComplete) {
      final last = aligner.isComplete ? ayahNow : ayahNow - 1;
      final done = <String>[];
      for (var i = math.max(ayahBefore, _lastAyahIndex); i <= last; i++) {
        if (i < 0 || i + 1 >= _ayahWordStarts.length) continue;
        final number = _page?.ayahs[i].ayah ?? i + 1;
        done.add(_ayahFlagged(i) ? 'الآية $number (بملاحظات)' : 'الآية $number ✓');
      }
      _lastAyahIndex = last + 1;
      if (done.isNotEmpty) {
        _setFeedback(RecitationFeedback(FeedbackKind.good, done.join('، ')));
      }
    }
  }

  /// When a segment matched nothing near the cursor, checks whether it
  /// matches some other ayah on the page well enough to say "you seem to be
  /// reading ayah N". Returns true when such feedback was shown.
  bool _maybeWrongAyah(SegmentOutcome outcome) {
    final aligner = _aligner;
    final page = _page;
    if (aligner == null || page == null) return false;
    final tokens = outcome.tokens;
    if (tokens.length < 3) return false;
    final needed = math.max(3, (tokens.length * 0.6).ceil());
    final windowStart = aligner.cursor;
    final windowEnd = math.min(aligner.length, windowStart + aligner.windowSize);

    var bestAt = -1;
    var bestMatches = 0;
    for (var at = 0; at + needed <= aligner.length; at++) {
      if (at >= windowStart && at < windowEnd) continue;
      final m = aligner.matchesAt(tokens, at);
      if (m > bestMatches) {
        bestMatches = m;
        bestAt = at;
      }
    }
    if (bestAt < 0 || bestMatches < needed) return false;

    final heardAyah = _ayahIndexOfWord(bestAt);
    final wantedAyah = currentAyahIndex;
    if (heardAyah < 0 || heardAyah == wantedAyah) return false;
    final heard = page.ayahs[heardAyah];
    final wanted = page.ayahs[wantedAyah];
    final sameSurah = heard.surah == wanted.surah;
    _recorder?.log('wrongAyah', {'heard': heardAyah, 'wanted': wantedAyah});
    _setFeedback(RecitationFeedback(
      FeedbackKind.wrong,
      sameSurah
          ? 'يبدو أنك تقرأ الآية ${heard.ayah}، والمطلوب الآية ${wanted.ayah}'
          : 'يبدو أنك تقرأ ${heard.surahName} ${heard.ayah}، والمطلوب '
              '${wanted.surahName} ${wanted.ayah}',
    ));
    return true;
  }

  /// Whether the segment's words match anywhere on the page well enough
  /// to be one of its ayahs (the "wrong ayah" test, minus the message).
  bool _matchesAnywhere(SegmentOutcome outcome) {
    final aligner = _aligner;
    if (aligner == null || outcome.tokens.length < 3) return true;
    final needed = math.max(3, (outcome.tokens.length * 0.6).ceil());
    for (var at = 0; at + needed <= aligner.length; at++) {
      if (aligner.matchesAt(outcome.tokens, at) >= needed) return true;
    }
    return false;
  }

  void _checkSilence() {
    if (status.value != MemorizationTestStatus.listening) return;
    if (!usingRealEngine.value || _silenceWarned) return;
    if (DateTime.now().difference(_lastVoiceOrSegment).inSeconds >= 8) {
      _silenceWarned = true;
      _setFeedback(
        const RecitationFeedback(
          FeedbackKind.silent,
          'لا أسمع صوتًا — اقترب من الميكروفون وارفع صوتك قليلًا',
        ),
        sticky: true,
        show: true,
      );
    }
  }

  void _finishIfComplete() {
    if (_checkDrillDone()) return;
    final aligner = _aligner;
    if (aligner == null || !aligner.isComplete) return;
    // The last word held for a mistake: the page waits for it like any other.
    if (_holdWord >= 0) return;
    // The phoneme engine flows into the next page without stopping: the
    // reciter keeps reading and only the expected text changes under it.
    if (_tracker != null &&
        _recorder != null &&
        status.value == MemorizationTestStatus.listening &&
        (_activePage ?? 602) < 602) {
      if (!_advancing) _continueToNextPage();
      return;
    }
    _finishPage();
  }

  /// Ends the page for good: summary line, engine stopped, result left on
  /// screen until the user exits or restarts.
  void _finishPage() {
    _saveReport(finished: true);
    status.value = MemorizationTestStatus.completed;
    final (clean, flagged) = summary;
    _recorder?.log('completed', {
      'clean': clean,
      'flagged': flagged,
      'statuses': [for (final st in statuses) st.name],
    });
    _setFeedback(
      RecitationFeedback(
        flagged == 0 ? FeedbackKind.good : FeedbackKind.info,
        flagged == 0
            ? 'أحسنت! اكتملت الصفحة بلا أخطاء'
            : 'اكتملت الصفحة: $clean بلا ملاحظات، $flagged بملاحظات',
      ),
      sticky: true,
      show: true,
    );
    // Stop the engine but keep aligner/regions so the overlay can keep
    // showing the final result until the user exits the mode.
    _stopEngineOnly();
  }

  /// Swaps the session onto the next page while the microphone and the
  /// recognizer keep running. What was already said past this page's last
  /// word (about a second of speech by the time that word is confirmed) is
  /// replayed into the new page's tracker, this page's log is closed and a
  /// new one opened, and [pageAdvanced] tells the page view to flip.
  Future<void> _continueToNextPage() async {
    _advancing = true;
    final token = _startToken;
    final donePage = _activePage!;
    final next = donePage + 1;
    try {
      final regions = await AyahRegionService.forPage(next);
      final wordRegions = await WordRegionService.forPage(next);
      final pages = await QuranJsonService.loadQuranPages();
      final phonemes = await PagePhonemeService.forPage(next);
      QuranPageData? page;
      for (final p in pages) {
        if (p.page == next) {
          page = p;
          break;
        }
      }
      final expectedWords = <String>[];
      final starts = <int>[];
      if (page != null) {
        for (final ayah in page.ayahs) {
          starts.add(expectedWords.length);
          expectedWords.addAll(
            ayah.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty),
          );
        }
        starts.add(expectedWords.length);
      }
      final usable = regions != null &&
          page != null &&
          phonemes != null &&
          expectedWords.isNotEmpty &&
          phonemes.words.length == expectedWords.length &&
          _regionsMatchText(regions, page);
      if (token != _startToken ||
          status.value != MemorizationTestStatus.listening) {
        return;
      }
      if (!usable) {
        _finishPage();
        return;
      }

      // Speech already heard beyond this page's last word.
      final oldTracker = _tracker!;
      final oldAligner = _aligner!;
      var from = oldTracker.heard.length;
      for (final v in _tracer!.verdicts(settled: true)) {
        if (v.word == oldAligner.length - 1 && v.spanTo >= 0) from = v.spanTo;
      }
      final carry =
          oldTracker.heard.sublist(math.min(from, oldTracker.heard.length));

      final (clean, flagged) = summary;
      _saveReport(finished: true);
      _pageStartedAt = DateTime.now();
      _recorder?.log('completed', {
        'clean': clean,
        'flagged': flagged,
        'continuedTo': next,
        'statuses': [for (final st in statuses) st.name],
      });
      final oldRecorder = _recorder;
      final newRecorder = await TasmeeSessionRecorder.begin(
        page: next,
        installId: _installId,
        info: {
          ..._recorderInfo,
          'continuedFrom': donePage,
          'ayahs': [for (final a in page.ayahs) '${a.surah}:${a.ayah}'],
          'words': expectedWords.length,
        },
      );
      if (token != _startToken ||
          status.value != MemorizationTestStatus.listening) {
        await newRecorder?.finish();
        return;
      }
      await _audioSub?.cancel();
      _recorder = newRecorder;
      final audio = _engine?.audioChunks;
      _audioSub = (audio != null && newRecorder != null)
          ? audio.listen(newRecorder.addAudio)
          : null;
      if (oldRecorder != null) {
        unawaited(oldRecorder.finish().then((_) {
          lastSessionFiles.value = [oldRecorder.audioPath, oldRecorder.logPath];
        }));
      }

      final reference =
          PhonemeReference(phonemes.collapsed(), PhonemeCostTable());
      _reference = reference;
      final tracker = PhonemeTracker(
        reference,
        startAnywhere: false, // a page the session flowed into starts at its top
      );
      _tracker = tracker;
      _tracer = VerdictTracer(tracker, lexicon: await _loadLexicon());
      _aligner = QuranWordAligner(expectedWords)
        ..onWordResolved = (_) => revision.value++;
      _regions = regions;
      _wordBoxes = _usableWordBoxes(wordRegions, page);
      _wordMarginRect = wordRegions?.marginRect;
      _page = page;
      _expectedWords = expectedWords;
      _ayahWordStarts = starts;
      _activePage = next;
      _lastAyahIndex = 0;
      _holdWord = -1;
      _holdHard = false;
      _wordsPastHold = 0;
      heldWord.value = -1;
      _settledApplied = false;
      _startResolved = true; // a continued page starts at its first word
      _recorder?.log('listening', {'carriedChars': carry.length});
      if (carry.isNotEmpty) tracker.feed(carry);
      _lastPhonemeAt = DateTime.now();
      _setFeedback(RecitationFeedback(
        flagged == 0 ? FeedbackKind.good : FeedbackKind.info,
        flagged == 0
            ? 'الصفحة $donePage ✓ — تابع'
            : 'الصفحة $donePage: $flagged آيات بملاحظات — تابع',
      ));
      // A ValueNotifier is silent when its value does not change, and the
      // same page can be flowed into twice in one run of the app (p130 ->
      // p131, back, and again): pulse through 0 so every advance fires.
      pageAdvanced.value = 0;
      pageAdvanced.value = next;
      revision.value++;
      _applyTrackerVerdicts(settled: false);
    } catch (e) {
      debugPrint('MemorizationTestService: could not continue to page $next: $e');
      if (token == _startToken) _finishPage();
    } finally {
      _advancing = false;
    }
  }

  static String _shorten(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.length <= 5) return text.trim();
    return '… ${words.sublist(words.length - 5).join(' ')}';
  }

  /// Shows [value] on the session bar when [show] is set; every message is
  /// written to the session log either way. The bar is kept quiet on
  /// purpose: it speaks up for silence, a mistake, skipped words and the
  /// end of a page; confirmations ("ayah N correct", "well done", what was
  /// heard instead of a word) go to the log and the report only.
  void _setFeedback(
    RecitationFeedback? value, {
    bool sticky = false,
    bool show = false,
  }) {
    if (value != null) {
      lastMessage.value = value;
      _recorder?.log('feedback', {
        'kind': value.kind.name,
        'message': value.message,
        'ayah': currentAyahIndex,
        'word': currentWordIndex,
        'shown': show,
      });
      if (!show) return;
    }
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    feedback.value = value;
    if (value != null && !sticky) {
      _feedbackTimer = Timer(const Duration(seconds: 5), () {
        if (feedback.value == value) feedback.value = null;
      });
    }
  }

  Future<void> _stopEngineOnly() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _trackerTimer?.cancel();
    _trackerTimer = null;
    await _segmentSub?.cancel();
    _segmentSub = null;
    await _audioSub?.cancel();
    _audioSub = null;
    final engine = _engine;
    if (engine != null) {
      if (_levelListener != null) {
        engine.audioLevel.removeListener(_levelListener!);
      }
      if (_busyListener != null) engine.busy.removeListener(_busyListener!);
      if (_decodeListener != null) {
        engine.lastDecodeMs.removeListener(_decodeListener!);
      }
      await engine.stop();
    }
    _levelListener = null;
    _busyListener = null;
    _decodeListener = null;
    _engine = null;
    audioLevel.value = 0;
    engineBusy.value = false;
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      await recorder.finish();
      lastSessionFiles.value = [recorder.audioPath, recorder.logPath];
    }
  }

  /// Ends the session and clears all state. Safe to call when idle.
  Future<void> stop() async {
    if (status.value == MemorizationTestStatus.listening) {
      _saveReport(finished: false);
    }
    if (_recorder != null && status.value == MemorizationTestStatus.listening) {
      _recorder?.log('stopped', {
        'word': currentWordIndex,
        'ayah': currentAyahIndex,
        'statuses': [for (final st in statuses) st.name],
      });
    }
    await _stopEngineOnly();
    _feedbackTimer?.cancel();
    _feedbackTimer = null;
    feedback.value = null;
    lastMessage.value = null;
    lastHeard.value = '';
    _aligner = null;
    _tracker = null;
    _tracer = null;
    _reference = null;
    _holdWord = -1;
    _holdHard = false;
    _wordsPastHold = 0;
    heldWord.value = -1;
    _drill = null;
    drillLabel.value = null;
    _regions = null;
    _wordBoxes = const [];
    _page = null;
    _expectedWords = const [];
    _ayahWordStarts = const [];
    _activePage = null;
    _lastAyahIndex = -1;
    usingRealEngine.value = false;
    stubReason.value = StubReason.none;
    if (status.value != MemorizationTestStatus.idle) {
      status.value = MemorizationTestStatus.idle;
      revision.value++;
    }
  }
}

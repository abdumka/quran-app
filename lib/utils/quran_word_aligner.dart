import 'arabic_text_normalizer.dart';

/// The recognition state of a single expected word in a memorization-test
/// session, driving what the reveal UI shows for that word's position.
enum WordStatus {
  /// Not yet recited (or not yet resolved) -- the reveal UI keeps this word
  /// masked.
  pending,

  /// Recognized (exactly, or close enough to absorb minor ASR/orthography
  /// noise) in the expected order. Reveal UI shows the real word.
  correct,

  /// The same expected word failed to align across repeated segments while
  /// something else recognizable kept landing in its place -- treated as a
  /// genuine pronunciation/word mistake, not a one-off ASR misfire. Reveal UI
  /// shows the word with a "wrong" tint so the learner sees what was missed.
  mistake,

  /// A later word matched before this one ever did, implying this word was
  /// recited too quietly/quickly to catch or genuinely dropped. Reveal UI
  /// shows the word with a "skipped" tint.
  skipped,

  /// A recognized segment didn't align with anything in the current window
  /// at all. Transient -- deliberately does *not* flag a mistake from a
  /// single failed segment (see class doc). Reveal UI should not change
  /// anything visible for `unclear`; it's an internal waiting state.
  unclear,
}

/// Aligns a live stream of recognized speech segments against a known
/// expected word sequence (a Quran passage in Qaloon orthography) and
/// decides, word by word, whether each was recited correctly, mistakenly,
/// skipped, or is still pending -- driving the "reveal words as you recite
/// them" UI.
///
/// This class has zero Flutter/plugin dependencies and only depends on the
/// plugin-free [normalizeArabicText]/[normalizedArabicWords] utilities, so
/// it is fully unit-testable without a microphone, an ASR model, or a
/// device.
///
/// ## Design
///
/// The aligner never assumes the recognizer sends one segment per word --
/// each call to [submitRecognizedSegment] may contain zero, one, or several
/// words (a VAD-detected utterance chunk can span a whole phrase). Each
/// segment is aligned, via a small bounded edit-distance alignment, against
/// only a forward-looking *window* of the still-unresolved expected words
/// (starting at the current cursor) -- never the whole remaining passage.
/// Bounding the window serves two purposes: it keeps the alignment cheap,
/// and it prevents one coincidental fuzzy match far ahead from silently
/// "skipping" everything in between. Because already-confirmed words are
/// excluded from the window entirely, a user repeating a word/phrase they
/// already said correctly simply produces tokens that match nothing in the
/// window and are ignored -- repeats never cause a false double-advance.
///
/// A word is only promoted to [WordStatus.mistake] after a *two-strike*
/// rule: it must fail to align across two consecutive segments while a
/// different, recognizable word keeps landing in its place. A single
/// failed segment -- which could just be noise, a cough, or the ASR
/// mishearing -- only ever produces a transient [WordStatus.unclear], never
/// an immediate "wrong" verdict. This mirrors advice (from evaluating this
/// feature's design against real product feedback) that false "you got it
/// wrong" verdicts erode trust in a recitation checker faster than being
/// briefly unresponsive does.
///
/// The fuzzy-match threshold and window size are tunable heuristics; the
/// values here are reasonable defaults but are expected to be calibrated
/// against real microphone recordings (not just clean reference audio)
/// once the on-device recognizer is wired up -- see the memorization-test
/// plan's device-matrix acceptance step.
class QuranWordAligner {
  QuranWordAligner(List<String> expectedWords, {this.windowSize = 6})
    : assert(expectedWords.isNotEmpty, 'expectedWords must not be empty'),
      assert(windowSize > 0, 'windowSize must be positive'),
      _expectedNormalized = List.unmodifiable(
        expectedWords.map(normalizeArabicText),
      ),
      _statuses = List.filled(
        expectedWords.length,
        WordStatus.pending,
        growable: false,
      ),
      _missStreak = List.filled(
        expectedWords.length,
        0,
        growable: false,
      );

  /// How many still-unresolved expected words (from the cursor forward) a
  /// single recognized segment is allowed to align against. Keeps the
  /// per-segment alignment cheap and stops one lucky far-ahead fuzzy match
  /// from skipping a whole run of words at once.
  final int windowSize;

  final List<String> _expectedNormalized;
  final List<WordStatus> _statuses;
  final List<int> _missStreak;

  int _cursor = 0;

  /// Called (synchronously, from within [submitRecognizedSegment]) whenever
  /// a word's status is resolved away from [WordStatus.pending], with its
  /// index into the original `expectedWords` list. The UI layer uses this
  /// to drive per-word reveal animations without re-diffing the whole
  /// [statuses] list on every update.
  void Function(int index)? onWordResolved;

  /// Current status of every expected word, in order. Do not mutate --
  /// treat as read-only (a fresh unmodifiable view is not allocated per
  /// access for performance; callers must not rely on identity across
  /// calls to [submitRecognizedSegment]/[reset]).
  List<WordStatus> get statuses => _statuses;

  /// Number of expected words, i.e. `expectedWords.length`.
  int get length => _expectedNormalized.length;

  /// Index of the first not-yet-resolved (`pending`/`unclear`) word, or
  /// [length] once every word has been resolved.
  int get cursor => _cursor;

  /// Whether every expected word has been resolved (correct/mistake/skipped
  /// -- `unclear` never counts, since it's transient by definition).
  bool get isComplete => _cursor >= length;

  /// Resets the aligner to its initial state (all words `pending`, cursor at
  /// the start) so a session can be retried without recreating the aligner.
  void reset() {
    _cursor = 0;
    for (var i = 0; i < _statuses.length; i++) {
      _statuses[i] = WordStatus.pending;
      _missStreak[i] = 0;
    }
  }

  /// Feeds one recognized speech segment (raw ASR output text, in whatever
  /// spelling convention the recognizer produces -- it is normalized
  /// internally the same way the expected words are) into the aligner.
  ///
  /// Only call this for segments the recognizer actually produced from
  /// detected speech (e.g. one call per VAD-bounded utterance). Silence
  /// detection/"the user hasn't said anything yet" is the caller's
  /// responsibility, not the aligner's -- an empty or whitespace-only
  /// segment is a no-op here.
  void submitRecognizedSegment(String rawRecognizedText) {
    if (isComplete) return;

    final tokens = normalizedArabicWords(rawRecognizedText);
    if (tokens.isEmpty) return;

    final windowEnd = (_cursor + windowSize).clamp(_cursor, length);
    final window = _expectedNormalized.sublist(_cursor, windowEnd);
    if (window.isEmpty) return;

    final alignment = _alignWindow(window, tokens);

    if (alignment.matchedUpTo < 0) {
      // Nothing in this segment aligned with anything still pending. Before
      // treating that as a sign of trouble, rule out the harmless case: the
      // user repeating a word or phrase they already recited correctly.
      // Already-resolved words are deliberately excluded from `window` (so
      // a real repeat can never match anything there), which makes a repeat
      // and genuine noise look identical to the alignment step -- so check
      // the trailing history and, if every token is explained by something
      // already passed, ignore the segment rather than penalizing the next
      // pending word for it.
      //
      // Ordering matters: this check runs only AFTER window alignment has
      // found nothing, never before. The Quran repeats words (Al-Fatihah
      // itself has عليهم in both ayah 6 and ayah 7) -- if the history check
      // ran first, a segment carrying the *second* occurrence would be
      // misread as a repeat of the first and swallowed, stranding the
      // cursor on a word the user just recited correctly.
      final historyStart = (_cursor - windowSize).clamp(0, _cursor);
      final history = _expectedNormalized.sublist(historyStart, _cursor);
      if (history.isNotEmpty && _looksLikeRepeatOfHistory(tokens, history)) {
        return;
      }

      // Genuine miss: bump the front word's miss streak; only promote to
      // `mistake` once it's failed twice in a row (see class doc for why).
      final frontIndex = _cursor;
      _missStreak[frontIndex]++;
      final promoted = _missStreak[frontIndex] >= 2;
      _setStatus(
        frontIndex,
        promoted ? WordStatus.mistake : WordStatus.unclear,
      );
      if (promoted) {
        _cursor = frontIndex + 1;
      }
      return;
    }

    for (var rel = 0; rel <= alignment.matchedUpTo; rel++) {
      final absoluteIndex = _cursor + rel;
      if (alignment.matchedRelIndices.contains(rel)) {
        _missStreak[absoluteIndex] = 0;
        _setStatus(absoluteIndex, WordStatus.correct);
      } else {
        _setStatus(absoluteIndex, WordStatus.skipped);
      }
    }
    _cursor += alignment.matchedUpTo + 1;
  }

  void _setStatus(int index, WordStatus status) {
    if (_statuses[index] == status) return;
    _statuses[index] = status;
    onWordResolved?.call(index);
  }

  /// Bounded word-level alignment of [window] (still-pending expected
  /// words, oldest first) against [tokens] (this segment's recognized
  /// words), via a small edit-distance DP -- the word-granularity analogue
  /// of classic character-level edit distance, with "equal" replaced by
  /// [_wordsClose] so minor spelling/diacritic noise doesn't count as a
  /// mismatch.
  static _WindowAlignment _alignWindow(
    List<String> window,
    List<String> tokens,
  ) {
    final n = window.length;
    final m = tokens.length;
    // dp[i][j] = min edit cost aligning window[0..i) with tokens[0..j)
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 1; i <= n; i++) {
      dp[i][0] = i;
    }
    for (var j = 1; j <= m; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final matchCost = _wordsClose(window[i - 1], tokens[j - 1]) ? 0 : 1;
        final substitute = dp[i - 1][j - 1] + matchCost;
        final deleteExpected = dp[i - 1][j] + 1; // expected word not heard
        final insertToken = dp[i][j - 1] + 1; // extra/noise token
        dp[i][j] = [
          substitute,
          deleteExpected,
          insertToken,
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    // Traceback from (n, m) to (0, 0) to recover which expected words
    // matched. When several alignments tie on cost, prefer the one that
    // matches tokens as EARLY in the window as possible: walking backward,
    // try consuming a window word as a deletion (i--) before trying a
    // diagonal match, which pushes any tied match toward lower indices.
    // This matters for repeated words -- the Quran reuses words at close
    // range (Al-Fatihah has عليهم twice, five words apart), and a
    // diagonal-first traceback would happily bind a token to the *far*
    // occurrence at equal cost, wrongly marking everything in between as
    // skipped. Walking backward, the first true match (matchCost == 0)
    // encountered is the furthest (highest-index) one, since indices only
    // decrease.
    var i = n, j = m;
    final matchedRelIndices = <int>{};
    var matchedUpTo = -1;
    while (i > 0 || j > 0) {
      if (i > 0 && dp[i][j] == dp[i - 1][j] + 1) {
        i--;
        continue;
      }
      if (i > 0 && j > 0) {
        final matchCost = _wordsClose(window[i - 1], tokens[j - 1]) ? 0 : 1;
        if (dp[i][j] == dp[i - 1][j - 1] + matchCost) {
          if (matchCost == 0) {
            matchedRelIndices.add(i - 1);
            matchedUpTo = matchedUpTo == -1 ? i - 1 : matchedUpTo;
          }
          i--;
          j--;
          continue;
        }
      }
      j--;
    }

    return _WindowAlignment(
      matchedUpTo: matchedUpTo,
      matchedRelIndices: matchedRelIndices,
    );
  }

  /// Whether every token in a recognized segment is explained by something
  /// in the trailing `history` of already-resolved expected words -- i.e.
  /// this segment looks like a harmless repeat of words already accounted
  /// for, not a new attempt at the still-pending ones.
  static bool _looksLikeRepeatOfHistory(
    List<String> tokens,
    List<String> history,
  ) {
    return tokens.every(
      (token) => history.any((word) => _wordsClose(token, word)),
    );
  }

  /// Two already-normalized words are "close enough" to count as a match if
  /// they're identical, or differ by only a small character-level edit
  /// distance relative to their length -- absorbing minor ASR noise and the
  /// kind of orthographic variance normalization alone doesn't catch,
  /// without accepting a genuinely different (but similarly short) word.
  /// Short words (<=3 chars) require an exact match: Arabic has many
  /// meaningfully-different short function words one edit apart (e.g. "من"
  /// vs "عن"), so allowing any fuzziness there would cause false matches
  /// far more often than it forgives real noise.
  static bool _wordsClose(String a, String b) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;
    final threshold = a.length <= 3
        ? 0
        : (a.length <= 7 ? 1 : 2);
    if (threshold == 0) return false;
    return _levenshtein(a, b, maxDistance: threshold) <= threshold;
  }

  /// Character-level edit distance between [a] and [b], short-circuiting
  /// (returning `maxDistance + 1`) once it's clear the result will exceed
  /// [maxDistance] -- callers only care whether the words are "close",
  /// never the exact distance beyond that.
  static int _levenshtein(String a, String b, {required int maxDistance}) {
    if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;
    var previous = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      var rowMin = current[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
        if (current[j] < rowMin) rowMin = current[j];
      }
      if (rowMin > maxDistance) return maxDistance + 1;
      previous = current;
    }
    return previous[b.length];
  }
}

class _WindowAlignment {
  const _WindowAlignment({
    required this.matchedUpTo,
    required this.matchedRelIndices,
  });

  /// Highest relative (0-based, within the window) expected-word index that
  /// matched a recognized token this segment, or -1 if none did.
  final int matchedUpTo;

  /// Relative indices (within the window) that were true matches, as
  /// opposed to being swept up as "skipped" because they fell before
  /// [matchedUpTo] without matching anything themselves.
  final Set<int> matchedRelIndices;
}

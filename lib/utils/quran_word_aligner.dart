import 'dart:math' as math;

import 'arabic_text_normalizer.dart';

/// [normalizeArabicText] with the dagger alef (U+0670) removed rather than
/// expanded to a full alef. The search normalizer expands it so "الرحمٰن"
/// is findable by typing "الرحمان", but speech recognizers spell such words
/// the everyday way -- "الرحمن", "ذلك", "هذا" -- and a 3-letter word like
/// ذلك must match exactly, so "ذالك" would never be recognised as recited.
///
/// It also drops the silent alef of a plural-waw ending ("قالوا" -> "قالو"):
/// recognizers often write "ويبسط" for وَيَبْسُطُواْ, two letters short of
/// the expected spelling, which the length-scaled fuzzy match then rejects.
String normalizeRecitationText(String text) => normalizeArabicText(
      text.replaceAll('ٰ', ''),
    ).replaceAll(RegExp(r'وا(?=\s|$)'), 'و');

/// The recognition state of a single expected word in a memorization-test
/// session, driving what the reveal UI shows for that word's position.
enum WordStatus {
  /// Not yet recited (or not yet resolved) -- the reveal UI keeps this word
  /// masked.
  pending,

  /// Recognized (exactly, or close enough to absorb minor ASR/orthography
  /// noise) in the expected order. Reveal UI shows the real word.
  correct,

  /// The same expected word failed to align across repeated final segments
  /// while something else recognizable kept landing in its place -- treated
  /// as a genuine pronunciation/word mistake, not a one-off ASR misfire.
  mistake,

  /// A later word matched before this one ever did, implying this word was
  /// recited too quietly/quickly to catch or genuinely dropped.
  skipped,

  /// A recognized segment didn't align with anything in the current window
  /// at all. Transient -- deliberately does *not* flag a mistake from a
  /// single failed segment (see class doc). It's an internal waiting state.
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
/// The recognizer sends overlapping segments: interim decodes of an
/// utterance in progress, then the authoritative final decode that
/// re-covers the same audio, and utterances themselves overlap at forced
/// splits. So a segment routinely contains words that were ALREADY
/// resolved followed by new ones. Each segment is therefore aligned, with a
/// small word-level edit-distance DP, against a *context* made of the
/// trailing already-resolved words (the history, [historySize]) followed
/// by a forward-looking *window* of still-pending words ([windowSize]).
/// Tokens that land in the history are absorbed silently; only matches in
/// the window resolve anything. Bounding the window keeps the alignment
/// cheap and stops one lucky far-ahead fuzzy match from silently skipping
/// everything in between.
///
/// Cost model: a true match is free, an unheard expected word or an extra
/// token costs 1, and a *mismatched substitution costs 2* -- the same as
/// delete + insert -- so the DP can never prefer pairing wrong words over
/// finding the real match a few words later (with cost 1 it did exactly
/// that on real recordings, marking a correctly recited word a mistake).
///
/// A word is only promoted to [WordStatus.mistake] after a *two-strike*
/// rule on FINAL segments: it must fail to align across two consecutive
/// finals while something else recognizable lands in its place. Interim
/// segments (cut mid-utterance, last word dropped) never promote; they can
/// only advance the cursor on real matches or leave a transient `unclear`.
class QuranWordAligner {
  QuranWordAligner(
    List<String> expectedWords, {
    this.windowSize = 6,
    this.historySize = 40,
    this.resyncReach = 30,
  })  : assert(expectedWords.isNotEmpty, 'expectedWords must not be empty'),
        assert(windowSize > 0, 'windowSize must be positive'),
        _expectedNormalized = List.unmodifiable(
          expectedWords.map(normalizeArabicText),
        ),
        _expectedNoDagger = List.unmodifiable(
          expectedWords.map(normalizeRecitationText),
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
  /// single recognized segment is allowed to align against.
  final int windowSize;

  /// How far past the window a final segment may resync (see
  /// [_resyncPoint]): a few ayahs, never the whole page.
  final int resyncReach;

  /// How many already-resolved words before the cursor take part in the
  /// alignment so that repeated / overlapping speech is absorbed instead of
  /// being forced onto pending words. Reciters who lose their place often
  /// restart two or three ayahs back, so this spans a few ayahs.
  final int historySize;

  final List<String> _expectedNormalized;

  /// The same words with the dagger alef DROPPED instead of expanded (see
  /// [normalizeRecitationText]); a token matches if it is close to either
  /// spelling.
  final List<String> _expectedNoDagger;
  final List<WordStatus> _statuses;
  final List<int> _missStreak;

  int _cursor = 0;

  /// Consecutive FINAL segments that carried words but resolved nothing
  /// near the cursor (and were not repeats). A resync needs two of them
  /// first: one unexplained final is usually a slip -- the reciter said
  /// the end of the next ayah instead of this one -- and must be reported,
  /// not followed.
  int _lostFinals = 0;

  /// Called (synchronously, from within [submitRecognizedSegment]) whenever
  /// a word's status is resolved away from [WordStatus.pending], with its
  /// index into the original `expectedWords` list.
  void Function(int index)? onWordResolved;

  /// Current status of every expected word, in order. Treat as read-only.
  List<WordStatus> get statuses => _statuses;

  /// Number of expected words, i.e. `expectedWords.length`.
  int get length => _expectedNormalized.length;

  /// Index of the first not-yet-resolved (`pending`/`unclear`) word, or
  /// [length] once every word has been resolved.
  int get cursor => _cursor;

  /// Whether every expected word has been resolved (correct/mistake/skipped
  /// -- `unclear` never counts, since it's transient by definition).
  bool get isComplete => _cursor >= length;

  /// Normalized expected words, in order (read-only).
  List<String> get expectedNormalized => _expectedNormalized;

  /// Resets the aligner to its initial state.
  void reset() {
    _cursor = 0;
    _lostFinals = 0;
    for (var i = 0; i < _statuses.length; i++) {
      _statuses[i] = WordStatus.pending;
      _missStreak[i] = 0;
    }
  }

  /// Resolves every still-pending word in `[start, end)` with [status]
  /// without any recognition -- the "reveal this ayah" / "skip this ayah"
  /// help buttons. The cursor jumps past [end] if it was inside the range.
  void forceResolveRange(int start, int end, WordStatus status) {
    final from = start.clamp(0, length);
    final to = end.clamp(from, length);
    for (var i = from; i < to; i++) {
      if (_statuses[i] == WordStatus.correct ||
          _statuses[i] == WordStatus.mistake ||
          _statuses[i] == WordStatus.skipped) {
        continue;
      }
      _setStatus(i, status);
    }
    if (_cursor < to) _cursor = to;
  }

  /// How many of [tokens] (already normalized) match the expected words
  /// starting at [at], position by position. Used for "wrong ayah"
  /// detection outside the window.
  int matchesAt(List<String> tokens, int at) {
    var matches = 0;
    for (var k = 0; k < tokens.length && at + k < length; k++) {
      if (_closeToExpected(at + k, tokens[k])) matches++;
    }
    return matches;
  }

  bool _closeToExpected(int index, String token, {bool lastToken = false}) =>
      _wordsClose(_expectedNormalized[index], token, lastToken: lastToken) ||
      _wordsClose(_expectedNoDagger[index], token, lastToken: lastToken);

  /// Feeds one recognized speech segment (raw ASR output text) into the
  /// aligner and reports what changed. [isFinal] is false for interim
  /// (mid-utterance) decodes, which may advance on matches but never count
  /// as a strike against the front word.
  ///
  /// [maxNewWords], when positive, bounds how many pending words this
  /// segment may resolve (correct or skipped). The engine derives it from
  /// the amount of speech heard since the previous segment: a Quran-tuned
  /// recognizer readily completes a familiar phrase it has not actually
  /// heard yet, and this keeps such guessed-ahead words masked until the
  /// audio that carries them has arrived.
  SegmentOutcome submitRecognizedSegment(
    String rawRecognizedText, {
    bool isFinal = true,
    int maxNewWords = 0,
  }) {
    if (isComplete) return const SegmentOutcome.empty();

    final tokens = normalizedArabicWords(rawRecognizedText);
    if (tokens.isEmpty) return const SegmentOutcome.empty();

    final correct = <int>[];
    final skipped = <int>[];
    var remaining = tokens;
    var anyHistoryMatch = false;
    var advanced = false;
    var budget = maxNewWords > 0 ? maxNewWords : 1 << 30;

    // A segment can carry more words than one window. Consume it window by
    // window: apply an alignment, drop the tokens it used, and align what's
    // left against the next window until nothing more matches.
    while (remaining.isNotEmpty && !isComplete && budget > 0) {
      final historyStart = (_cursor - historySize).clamp(0, _cursor);
      final windowEnd = (_cursor + windowSize).clamp(_cursor, length);
      final historyLen = _cursor - historyStart;
      var alignment = _alignContext(
        contextStart: historyStart,
        contextEnd: windowEnd,
        historyLen: historyLen,
        tokens: remaining,
      );
      if (alignment.historyMatched) anyHistoryMatch = true;
      // A final decode re-covers audio an interim only saw in part: a word
      // the interim could not hear (and so swept as skipped) now arrives
      // whole. Matching it in the history repairs the verdict.
      for (final abs in alignment.historyMatchedIndices) {
        final st = _statuses[abs];
        if (st == WordStatus.skipped || st == WordStatus.mistake) {
          _missStreak[abs] = 0;
          _setStatus(abs, WordStatus.correct);
          correct.add(abs);
          advanced = true;
        }
      }
      if (alignment.matchedUpTo < 0) {
        // Everything landed in the history. That is usually a harmless
        // repeat -- but the Quran reuses words at close range (Al-Fatihah
        // has عليهم in ayah 6 and ayah 7), and a segment carrying the
        // SECOND occurrence must not be swallowed as a repeat of the first.
        // So, as a fallback, align against the pending window alone.
        if (!alignment.historyMatched) break;
        final windowOnly = _alignContext(
          contextStart: _cursor,
          contextEnd: windowEnd,
          historyLen: 0,
          tokens: remaining,
        );
        // Accept the fallback only when it explains most of the segment;
        // one lucky word out of ten is a repeat, not a continuation.
        if (windowOnly.matchedUpTo < 0 ||
            windowOnly.matchedTokens * 2 < remaining.length) {
          break;
        }
        alignment = windowOnly;
      }

      advanced = true;
      // Never reveal more CORRECT words than the speech budget allows; the
      // words the segment carries beyond it stay pending until more audio
      // arrives. (Skipped words are not shown as recited, so they do not
      // count -- a resync over a garbled stretch must stay possible.)
      var upTo = alignment.matchedUpTo;
      var matchedSoFar = 0;
      for (var rel = 0; rel <= alignment.matchedUpTo; rel++) {
        if (alignment.matchedRelIndices.contains(rel)) {
          if (matchedSoFar >= budget) {
            upTo = rel - 1;
            break;
          }
          matchedSoFar++;
        }
      }
      budget -= matchedSoFar;
      for (var rel = 0; rel <= upTo; rel++) {
        final absoluteIndex = _cursor + rel;
        if (alignment.matchedRelIndices.contains(rel)) {
          _missStreak[absoluteIndex] = 0;
          if (_statuses[absoluteIndex] != WordStatus.correct) {
            correct.add(absoluteIndex);
          }
          _setStatus(absoluteIndex, WordStatus.correct);
        } else {
          skipped.add(absoluteIndex);
          _setStatus(absoluteIndex, WordStatus.skipped);
        }
      }
      if (upTo < 0) break; // budget exhausted before the first match
      _cursor += upTo + 1;
      if (upTo < alignment.matchedUpTo) break; // budget exhausted
      if (alignment.matchedTokenUpTo + 1 >= remaining.length) break;
      remaining = remaining.sublist(alignment.matchedTokenUpTo + 1);
    }

    if (advanced) {
      if (isFinal) _lostFinals = 0;
      return SegmentOutcome(tokens: tokens, correct: correct, skipped: skipped);
    }

    // RESYNC: nothing aligned near the cursor, but a final segment matches
    // three or more consecutive words further down the page. The stretch
    // in between was recited but garbled by the recognizer (it happens to
    // whole phrases when the voice is quiet); without this the window never
    // sees past it and the session is stuck. Jump there, marking the
    // unheard stretch skipped, and align the segment from the new place.
    // Only once the recognizer has clearly lost its place (this is at least
    // the second unexplained final in a row): on the first one the
    // caller's "you seem to be reading ayah N" feedback is the right
    // answer, and the cursor must stay put.
    if (isFinal && !anyHistoryMatch && tokens.length >= 2) _lostFinals++;
    if (isFinal &&
        !anyHistoryMatch &&
        tokens.length >= 3 &&
        _lostFinals >= 2) {
      final at = _resyncPoint(tokens);
      if (at > _cursor) {
        _lostFinals = 0;
        for (var i = _cursor; i < at; i++) {
          skipped.add(i);
          _setStatus(i, WordStatus.skipped);
        }
        _cursor = at;
        final again = submitRecognizedSegment(
          rawRecognizedText,
          isFinal: isFinal,
          maxNewWords: maxNewWords,
        );
        return SegmentOutcome(
          tokens: tokens,
          correct: again.correct,
          skipped: [...skipped, ...again.skipped],
          mistakes: again.mistakes,
          unclearIndex: again.unclearIndex,
        );
      }
    }

    // Nothing in this segment aligned with anything still pending.
    if (anyHistoryMatch) {
      // The user repeated words they already recited: harmless.
      return SegmentOutcome(tokens: tokens, repeatOfHistory: true);
    }

    // Genuine miss. Only FINAL segments count as strikes: an interim is cut
    // mid-air and routinely garbled. Promote to `mistake` on the second
    // consecutive final strike (see class doc for why not the first).
    final frontIndex = _cursor;
    if (isFinal) _missStreak[frontIndex]++;
    final promoted = _missStreak[frontIndex] >= 2;
    _setStatus(
      frontIndex,
      promoted ? WordStatus.mistake : WordStatus.unclear,
    );
    if (promoted) {
      _cursor = frontIndex + 1;
      return SegmentOutcome(tokens: tokens, mistakes: [frontIndex]);
    }
    return SegmentOutcome(tokens: tokens, unclearIndex: frontIndex);
  }

  /// Where a segment that matched nothing near the cursor lines up further
  /// ahead: the first position past the window (within [resyncReach]
  /// words) at which the segment's leading tokens -- allowing up to two
  /// garbled ones in front -- match at least three consecutive expected
  /// words. Returns -1 when there is no such place.
  int _resyncPoint(List<String> tokens) {
    final from = _cursor + windowSize;
    final to = math.min(length, _cursor + resyncReach);
    for (var lead = 0; lead <= 2; lead++) {
      if (tokens.length - lead < 3) break;
      for (var at = from; at + 3 <= to; at++) {
        var run = 0;
        for (var k = lead; k < tokens.length && at + k - lead < length; k++) {
          if (!_closeToExpected(at + k - lead, tokens[k])) break;
          run++;
        }
        if (run >= 3) return at;
      }
    }
    return -1;
  }

  void _setStatus(int index, WordStatus status) {
    if (_statuses[index] == status) return;
    _statuses[index] = status;
    onWordResolved?.call(index);
  }

  /// Word-level alignment of the expected words in
  /// `[contextStart, contextEnd)` -- the first [historyLen] of them already
  /// resolved, the rest the pending window -- against [tokens], via a small
  /// edit-distance DP with "equal" replaced by [_wordsClose]. Reports which
  /// WINDOW words matched (relative to the window start) and the last token
  /// that took part in a window match.
  _ContextAlignment _alignContext({
    required int contextStart,
    required int contextEnd,
    required int historyLen,
    required List<String> tokens,
  }) {
    final n = contextEnd - contextStart;
    final m = tokens.length;
    const mismatch = 2;
    bool close(int i, int j) => _closeToExpected(
          contextStart + i - 1,
          tokens[j - 1],
          lastToken: j == m,
        );

    // Leaving a HISTORY word unmatched is free -- it was already resolved
    // and the segment simply may not repeat it -- while leaving a pending
    // window word unmatched costs 1 (it would be "skipped"). Without this,
    // placing a repeated phrase in the history or in the window tied on
    // cost and the tie-break wrongly favoured the history, skipping the
    // window's copy (e.g. every "وَأَمَّا إِن كَانَ مِنَ" of Al-Waqi'ah).
    int deleteCost(int i) => i - 1 < historyLen ? 0 : 1;

    // dp[i][j] = min cost aligning context[0..i) with tokens[0..j).
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 1; i <= n; i++) {
      dp[i][0] = dp[i - 1][0] + deleteCost(i);
    }
    for (var j = 1; j <= m; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final substitute = dp[i - 1][j - 1] + (close(i, j) ? 0 : mismatch);
        final deleteExpected = dp[i - 1][j] + deleteCost(i); // not heard
        final insertToken = dp[i][j - 1] + 1; // extra/noise token
        var best = substitute;
        if (deleteExpected < best) best = deleteExpected;
        if (insertToken < best) best = insertToken;
        dp[i][j] = best;
      }
    }

    // Traceback from (n, m). On ties prefer consuming a context word as a
    // deletion before a diagonal, which pushes tied matches toward LOWER
    // indices (earlier words -- and history before window): the Quran
    // reuses words at close range (Al-Fatihah has عليهم twice, five words
    // apart) and binding a token to the far occurrence would wrongly skip
    // everything in between. Walking backward, the first true match seen
    // is the furthest one, since indices only decrease.
    // Semi-global end: the segment need not reach the end of the window --
    // pending words after the last match simply have not been recited yet
    // and cost nothing. Without this, a lucky fuzzy hit six words ahead was
    // cheaper than stopping, and words got skipped.
    var endI = historyLen;
    var bestCost = dp[historyLen][m];
    for (var i = historyLen + 1; i <= n; i++) {
      // On ties prefer the later end: it explains more of what was heard
      // (a genuinely skipped ayah costs the same as unexplained words, and
      // the reciter really did say those words).
      if (dp[i][m] <= bestCost) {
        bestCost = dp[i][m];
        endI = i;
      }
    }

    var i = endI, j = m;
    final matchedRelIndices = <int>{};
    final historyMatchedIndices = <int>[];
    var matchedUpTo = -1;
    var matchedTokenUpTo = -1;
    var matchedTokens = 0;
    var historyMatched = false;
    while (i > 0 || j > 0) {
      if (i > 0 && dp[i][j] == dp[i - 1][j] + deleteCost(i)) {
        i--;
        continue;
      }
      if (i > 0 && j > 0) {
        final isMatch = close(i, j);
        if (dp[i][j] == dp[i - 1][j - 1] + (isMatch ? 0 : mismatch)) {
          if (isMatch) {
            matchedTokens++;
            if (i - 1 >= historyLen) {
              final rel = i - 1 - historyLen;
              matchedRelIndices.add(rel);
              if (matchedUpTo == -1) matchedUpTo = rel;
              if (matchedTokenUpTo == -1) matchedTokenUpTo = j - 1;
            } else {
              historyMatched = true;
              historyMatchedIndices.add(contextStart + i - 1);
            }
          }
          i--;
          j--;
          continue;
        }
      }
      j--;
    }

    return _ContextAlignment(
      matchedUpTo: matchedUpTo,
      matchedTokenUpTo: matchedTokenUpTo,
      matchedRelIndices: matchedRelIndices,
      matchedTokens: matchedTokens,
      historyMatched: historyMatched,
      historyMatchedIndices: historyMatchedIndices,
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
  ///
  /// [lastToken] marks the final word of a recognized segment: audio is
  /// cut at segment ends, so that word may be truncated ("المؤ" for
  /// "المؤمنون"). A truncation of at least 3 letters that is a prefix of the
  /// expected word then counts as a match.
  static bool _wordsClose(String a, String b, {bool lastToken = false}) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;
    if (lastToken && b.length >= 3 && a.length > b.length && a.startsWith(b)) {
      return true;
    }
    final threshold = a.length <= 3 ? 0 : (a.length <= 7 ? 1 : 2);
    if (threshold == 0) return false;
    return _levenshtein(a, b, maxDistance: threshold) <= threshold;
  }

  /// Character-level edit distance between [a] and [b], short-circuiting
  /// (returning `maxDistance + 1`) once it's clear the result will exceed
  /// [maxDistance].
  static int _levenshtein(String a, String b, {required int maxDistance}) {
    if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;
    var previous = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      var rowMin = current[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var best = previous[j] + 1;
        if (current[j - 1] + 1 < best) best = current[j - 1] + 1;
        if (previous[j - 1] + cost < best) best = previous[j - 1] + cost;
        current[j] = best;
        if (current[j] < rowMin) rowMin = current[j];
      }
      if (rowMin > maxDistance) return maxDistance + 1;
      previous = current;
    }
    return previous[b.length];
  }
}

/// What one [QuranWordAligner.submitRecognizedSegment] call did, so the UI
/// can explain itself ("didn't catch that", "wrong word", "skipped ...").
class SegmentOutcome {
  const SegmentOutcome({
    this.tokens = const [],
    this.correct = const [],
    this.skipped = const [],
    this.mistakes = const [],
    this.unclearIndex = -1,
    this.repeatOfHistory = false,
  });

  const SegmentOutcome.empty() : this();

  /// The segment's normalized words (empty when the segment was blank).
  final List<String> tokens;

  /// Expected-word indices newly resolved `correct` by this segment.
  final List<int> correct;

  /// Expected-word indices swept as `skipped` by this segment.
  final List<int> skipped;

  /// Expected-word indices promoted to `mistake` by this segment.
  final List<int> mistakes;

  /// The front word left `unclear` (a strike, or an interim miss), or -1.
  final int unclearIndex;

  /// The segment only repeated already-recited words and was ignored.
  final bool repeatOfHistory;

  /// Nothing in the segment aligned with the pending window.
  bool get alignedNothing =>
      tokens.isNotEmpty && correct.isEmpty && skipped.isEmpty;
}

class _ContextAlignment {
  const _ContextAlignment({
    required this.matchedUpTo,
    required this.matchedTokenUpTo,
    required this.matchedRelIndices,
    required this.matchedTokens,
    required this.historyMatched,
    required this.historyMatchedIndices,
  });

  /// How many tokens took part in a true match (history or window).
  final int matchedTokens;

  /// Absolute expected-word indices matched inside the history.
  final List<int> historyMatchedIndices;

  /// Highest window-relative expected-word index that matched a token, or
  /// -1 if none did.
  final int matchedUpTo;

  /// Index of the last recognized token that took part in a window match,
  /// or -1. Tokens after it were not explained by this window.
  final int matchedTokenUpTo;

  /// Window-relative indices that were true matches, as opposed to being
  /// swept up as "skipped" because they fell before [matchedUpTo].
  final Set<int> matchedRelIndices;

  /// Whether any token matched an already-resolved (history) word.
  final bool historyMatched;
}

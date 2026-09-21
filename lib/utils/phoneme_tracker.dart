import 'dart:math' as math;
import 'dart:typed_data';

/// Online phoneme tracker for streaming CTC recitation recognition.
///
/// The recognizer (a streaming Zipformer2-CTC model with a 251-token
/// Quranic phoneme vocabulary) emits phoneme tokens a few hundred
/// milliseconds after they are spoken. This tracker follows those phonemes
/// through the expected phoneme string of the page with an online
/// edit-distance DP (one column per heard character), keeps a cursor, and
/// judges every word the cursor has passed: `ok`, `unsure`, `wrong`,
/// `skipped`, or still `pending`.
///
/// It is a Dart port of the clean-room TypeScript engine in the Tilawa
/// project (`packages/core/src/recitation/{tracker,verdicts,alignment,
/// phonemeCost}.ts`, MIT), validated against a Python port replayed on the
/// owner's recorded sessions (see `tasmee_work/zipformer/eval_session.py`).
/// Pure Dart: no Flutter, no plugins, fully unit-testable.
enum VerdictState { ok, unsure, wrong, skipped, pending }

/// One expected word of the page: its Quran-phonetic-script string (the
/// recognizer's alphabet), the mushaf word, and where it sits in its ayah.
class PhonemeWord {
  const PhonemeWord({
    required this.phon,
    required this.text,
    required this.ayah,
    required this.wordInAyah,
    required this.ayahWords,
    this.tanween = '',
    this.taMarbuta = false,
    this.hafsAlt = '',
    this.wasl = false,
    this.alts = const [],
    this.accept = const [],
  });

  /// Other phoneme forms that are equally correct for this word: what the
  /// recognizer is known to produce for a CORRECT Qalun reading when it
  /// cannot hear the Qalun feature (wa-hwa comes out as wa-huwa even from a
  /// Qalun sheikh), and readings Qalun allows both ways.
  final List<String> accept;

  /// Phonemes of the words the Quran has at this spot in its look-alike
  /// passages (mutashabihat: the same neighbours, another word). Hearing one
  /// of them is a substitution even when it sounds close to the expected
  /// word.
  final List<String> alts;

  /// The Hafs reading's phonemes when Qalun reads the word differently
  /// (مَلِكِ vs مَاالِكِ); hearing this form is a habit error, flagged even
  /// though it is acoustically close. Empty when the readings agree.
  final String hafsAlt;

  /// The word begins with hamzat al-wasl: connected to the previous word its
  /// leading hamza and vowel are not pronounced.
  final bool wasl;

  /// Expected phonemes (madd runs already collapsed when the reference was
  /// built with [collapseMadd]).
  final String phon;

  /// The mushaf word as printed (Qalun orthography).
  final String text;

  /// Ayah id within the reference (0-based, contiguous).
  final int ayah;
  final int wordInAyah;
  final int ayahWords;

  /// Tanween the word carries in Hafs orthography (`ً`, `ٌ`, `ٍ` or empty)
  /// and whether it ends in ta marbuta -- both drive the pausal form.
  final String tanween;
  final bool taMarbuta;
}

/// A heard phoneme character with the CTC frame (25 Hz) it was emitted at.
class HeardChar {
  const HeardChar(this.ch, this.frame, {this.margin = 1.0});
  final String ch;
  final int frame;
  final double margin;
}

class WordVerdict {
  const WordVerdict({
    required this.word,
    required this.state,
    required this.distance,
    required this.heardRatio,
    required this.margin,
    this.heard = '',
    this.spanFrom = -1,
    this.spanTo = -1,
    this.reason = '',
  });
  final int word;
  final VerdictState state;
  final double distance;
  final double heardRatio;
  final double margin;
  final String heard;
  final int spanFrom;
  final int spanTo;

  /// Why a `wrong` verdict was given beyond distance: `hafs` when the heard
  /// form matched the Hafs reading of a word Qalun reads differently.
  final String reason;
}

/// Tunables (Tilawa defaults). Frames are CTC frames of 40 ms.
class TrackerConfig {
  const TrackerConfig({
    this.jumpCost = 12,
    this.repeatCost = 10,
    this.ayahJumpCost = 14,
    this.farJumpCost = 28,
    this.startAyahCost = 6,
    this.lexiconDistance = 0.12,
    this.commitDwell = 6,
    this.okDistance = 0.15,
    this.unsureDistance = 0.4,
    this.minHeardFraction = 0.34,
    this.minMargin = 0.35,
    this.lostWindow = 120,
    this.lostRate = 0.35,
    this.settleFrames = 25,
  });
  /// Cost of starting at any word (the session's first phonemes) and, once
  /// under way, of the DP jumping to an arbitrary word.
  final double jumpCost;
  final double repeatCost;

  /// Jumping to the first word of the next or the previous ayah: a reciter
  /// who blanks and moves on, or goes back an ayah to regain the flow.
  final double ayahJumpCost;

  /// Any other jump (into the middle of an ayah, several ayahs away): only
  /// when the recitation has strayed for a long stretch. Keeps a phrase
  /// that happens to match the end of the next ayah (لبئس ما كانوا يصنعون
  /// said for يعملون) from being followed there.
  final double farJumpCost;

  /// Cost of the first phonemes landing on an ayah start: a session may
  /// begin at any ayah of the page.
  final double startAyahCost;

  /// A heard slice this close to some other Quran word is a substitution
  /// (الفاسقون for الظالمون), even when it lies in the unsure band.
  final double lexiconDistance;
  final int commitDwell;
  final double okDistance;
  final double unsureDistance;
  final double minHeardFraction;
  final double minMargin;
  final int lostWindow;
  final double lostRate;
  final int settleFrames;
}

final RegExp _maddRun = RegExp('(ا{3,}|ۥ{3,}|ۦ{3,})');

/// Collapses every madd run (alef / small waw / small yeh repeated) to two
/// symbols. Free-choice madd lengths (munfasil, aared) are unreliable in
/// the token stream and Qalun reads munfasil short anyway, so run length
/// is ignored on both sides of the comparison.
String collapseMadd(String s) =>
    s.replaceAllMapped(_maddRun, (m) => m.group(0)!.substring(0, 2));

// ---------------------------------------------------------------------------
// Cost table (phonemeCost.ts)
// ---------------------------------------------------------------------------

const String _alphabet =
    'ءابتثجحخدذرزسشصضطظعغفقكلمنهويۥۦں۾ٲأإآؤئٱىَُِڇؙۣ۪ٞۜـ';

class PhonemeCostTable {
  PhonemeCostTable() {
    final chars = _alphabet.runes.map(String.fromCharCode).toList();
    _size = chars.length + 1;
    _unknown = chars.length;
    for (var i = 0; i < chars.length; i++) {
      _ids[chars[i]] = i;
    }
    _matrix = Float32List(_size * _size);
    for (var i = 0; i < _size; i++) {
      for (var j = 0; j < _size; j++) {
        _matrix[i * _size + j] = (i == _unknown || j == _unknown)
            ? 1.0
            : _charCost(chars[i], chars[j]);
      }
    }
  }

  late final int _size;
  late final int _unknown;
  final Map<String, int> _ids = {};
  late final Float32List _matrix;

  int get unknownId => _unknown;

  /// Short vowels, sukun-like and tajweed marks (not letters).
  static bool isMark(String ch) => _marks.contains(ch);

  int id(String ch) => _ids[ch] ?? _unknown;

  Int32List encode(String s) {
    final runes = s.runes.toList();
    final out = Int32List(runes.length);
    for (var i = 0; i < runes.length; i++) {
      out[i] = id(String.fromCharCode(runes[i]));
    }
    return out;
  }

  double cost(int heard, int expected) => _matrix[heard * _size + expected];

  static const Map<String, String> _canonical = {
    'ۦ': 'ي',
    'ۥ': 'و',
    'ں': 'ن',
    '۾': 'م',
    'ٱ': 'ا',
    'ى': 'ي',
  };
  static final Set<String> _hamza = 'ءأإآاؤئٲ'.runes.map(String.fromCharCode).toSet();
  static final Set<String> _shortVowels = 'َُِ'.runes.map(String.fromCharCode).toSet();
  static final Set<String> _marks = 'َُِڇؙۣ۪ٞۜـ'.runes.map(String.fromCharCode).toSet();
  static final Set<String> _neighbors = _buildNeighbors();

  static Set<String> _buildNeighbors() {
    const groups = ['ذدضتط', 'ظزذصسث', 'جزش', 'ةهت', 'قكغ', 'فبم'];
    const pairs = [
      ['ه', 'ح'],
      ['غ', 'خ'],
      ['ء', 'ع'],
      ['ن', 'م'],
      ['ن', 'ل'],
      ['ظ', 'ض'],
    ];
    final s = <String>{};
    String key(String a, String b) => a.compareTo(b) < 0 ? '$a\u0000$b' : '$b\u0000$a';
    for (final g in groups) {
      final cs = g.runes.map(String.fromCharCode).toList();
      for (var i = 0; i < cs.length; i++) {
        for (var j = i + 1; j < cs.length; j++) {
          s.add(key(cs[i], cs[j]));
        }
      }
    }
    for (final p in pairs) {
      s.add(key(p[0], p[1]));
    }
    return s;
  }

  static double _charCost(String h, String e) {
    if (h == e) return 0;
    final ch = _canonical[h] ?? h;
    final ce = _canonical[e] ?? e;
    if (ch == ce) return 0;
    final hm = _marks.contains(h);
    final em = _marks.contains(e);
    if (hm || em) {
      if (hm && em) {
        return _shortVowels.contains(h) && _shortVowels.contains(e) ? 0.1 : 0.25;
      }
      return 1;
    }
    if (_hamza.contains(ch) && _hamza.contains(ce)) return 0.1;
    final k = ch.compareTo(ce) < 0 ? '$ch\u0000$ce' : '$ce\u0000$ch';
    if (_neighbors.contains(k)) return 0.25;
    return 1;
  }
}

// ---------------------------------------------------------------------------
// Alignment (alignment.ts)
// ---------------------------------------------------------------------------

double weightedLevenshtein(Int32List a, Int32List b, PhonemeCostTable t) {
  final n = a.length;
  final m = b.length;
  if (n == 0 && m == 0) return 0;
  var prev = Float32List(m + 1);
  var cur = Float32List(m + 1);
  for (var j = 0; j <= m; j++) {
    prev[j] = j.toDouble();
  }
  for (var i = 1; i <= n; i++) {
    cur[0] = i.toDouble();
    final ha = a[i - 1];
    for (var j = 1; j <= m; j++) {
      var c = prev[j - 1] + t.cost(ha, b[j - 1]);
      final up = prev[j] + 1;
      final left = cur[j - 1] + 1;
      if (up < c) c = up;
      if (left < c) c = left;
      cur[j] = c;
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[m];
}

double normalizedDistance(Int32List a, Int32List b, PhonemeCostTable t) {
  if (a.isEmpty && b.isEmpty) return 0;
  if (a.isEmpty || b.isEmpty) return 1;
  return weightedLevenshtein(a, b, t) / math.max(a.length, b.length);
}

/// Global alignment of [heard] against `ref[from, to)`; returns, per heard
/// char, the ref index it pairs with or -1.
Int32List alignGlobal(
  Int32List heard,
  Int32List ref,
  int from,
  int to,
  PhonemeCostTable t,
) {
  final n = heard.length;
  final m = to - from;
  final assign = Int32List(n);
  if (n == 0) return assign;
  if (m <= 0) {
    assign.fillRange(0, n, -1);
    return assign;
  }
  final cols = m + 1;
  final c = Float32List((n + 1) * cols);
  final tr = Uint8List((n + 1) * cols);
  for (var j = 0; j <= m; j++) {
    c[j] = j.toDouble();
  }
  for (var i = 1; i <= n; i++) {
    c[i * cols] = i.toDouble();
  }
  for (var i = 1; i <= n; i++) {
    final ha = heard[i - 1];
    final row = i * cols;
    final prev = (i - 1) * cols;
    for (var j = 1; j <= m; j++) {
      var v = c[prev + j - 1] + t.cost(ha, ref[from + j - 1]);
      var k = 0;
      final up = c[prev + j] + 1;
      if (up < v) {
        v = up;
        k = 1;
      }
      final left = c[row + j - 1] + 1;
      if (left < v) {
        v = left;
        k = 2;
      }
      c[row + j] = v;
      tr[row + j] = k;
    }
  }
  var i = n;
  var j = m;
  assign.fillRange(0, n, -1);
  while (i > 0 || j > 0) {
    if (i == 0) {
      j--;
      continue;
    }
    if (j == 0) {
      assign[i - 1] = -1;
      i--;
      continue;
    }
    final k = tr[i * cols + j];
    if (k == 0) {
      assign[i - 1] = from + j - 1;
      i--;
      j--;
    } else if (k == 1) {
      assign[i - 1] = -1;
      i--;
    } else {
      j--;
    }
  }
  return assign;
}

// ---------------------------------------------------------------------------
// Reference (the page's expected phoneme string)
// ---------------------------------------------------------------------------

class PhonemeReference {
  PhonemeReference(this.words, this.table) {
    final buf = StringBuffer();
    wordStart = List<int>.filled(words.length + 1, 0);
    var off = 0;
    for (var i = 0; i < words.length; i++) {
      wordStart[i] = off;
      buf.write(words[i].phon);
      off += words[i].phon.runes.length;
    }
    wordStart[words.length] = off;
    text = buf.toString();
    ref = table.encode(text);
    length = ref.length;
    localWordOfPos = Int32List(length);
    for (var i = 0; i < words.length; i++) {
      for (var p = wordStart[i]; p < wordStart[i + 1]; p++) {
        localWordOfPos[p] = i;
      }
    }
  }

  final List<PhonemeWord> words;
  final PhonemeCostTable table;
  late final List<int> wordStart;
  late final String text;
  late final Int32List ref;
  late final int length;
  late final Int32List localWordOfPos;

  int get n => words.length;

  String wordPhonemes(int i) => words[i].phon;
}

// ---------------------------------------------------------------------------
// Tracker (tracker.ts)
// ---------------------------------------------------------------------------

class PhonemeTracker {
  PhonemeTracker(
    this.reference, {
    this.cfg = const TrackerConfig(),
    this.startAnywhere = true,
    this.startWord = 0,
  })  : table = reference.table,
        len = reference.length {
    _resetColumn();
  }

  final PhonemeReference reference;
  final PhonemeCostTable table;
  final TrackerConfig cfg;
  final int len;

  /// Whether the first phonemes may land on any ayah of the page (a session
  /// opened by the user) or only on its first word (a page the session
  /// flowed into from the previous one).
  final bool startAnywhere;

  /// With [startAnywhere] false, the only word the recitation may start on
  /// (an ayah the reciter was sent back to, the first ayah of a drill).
  final int startWord;

  /// Barrier: no path may be in a cell past this one (null: none). Set while
  /// the session is stopped at skipped words, so that whatever is recited
  /// further down the page cannot carry the cursor on.
  int? maxCell;

  late Float32List column;

  /// For every DP cell, where the best path into it last restarted: the
  /// index of the first heard char after the jump/repeat transition and the
  /// word-start cell it landed on. The verdict tracer cuts runs at that
  /// exact point rather than at the (later) char where the restarted path
  /// overtook the old one, so the words a reciter goes back to are judged
  /// again from their first phoneme.
  late Int32List originHeard;
  late Int32List originCell;
  int cursorCell = 0;
  int cursorLocalWord = -1;
  double cursorCost = 0;
  int revision = 0;
  final List<int> trail = [];

  /// Per heard char: the origin (see [originHeard] / [originCell]) of the
  /// best path at that char.
  final List<int> originHeardTrail = [];
  final List<int> originCellTrail = [];
  final List<double> costs = [];
  final List<HeardChar> heard = [];
  bool lost = false;

  static const int _rateMinN = 24;

  /// Index of the word the reciter is currently in (0 when nothing heard).
  int get cursorWord => math.max(0, cursorLocalWord);

  bool get reachedEnd => cursorCell >= len - 1;

  void _resetColumn() {
    final jump = cfg.jumpCost;
    column = Float32List(len + 1);
    column.fillRange(0, len + 1, double.infinity);
    originHeard = Int32List(len + 1);
    originCell = Int32List(len + 1);
    for (var i = 0; i < reference.n; i++) {
      final m = reference.wordStart[i];
      if (!startAnywhere) {
        column[m] = i == startWord ? 0 : double.infinity;
      } else {
        column[m] = m == 0
            ? 0
            : (reference.words[i].wordInAyah == 0 ? cfg.startAyahCost : jump);
      }
      originCell[m] = m;
    }
    for (var m = 1; m <= len; m++) {
      if (column[m - 1] + 1 < column[m]) {
        column[m] = column[m - 1] + 1;
        originCell[m] = originCell[m - 1];
      }
    }
    cursorCell = startAnywhere ? 0 : reference.wordStart[startWord];
    cursorLocalWord = -1;
    cursorCost = 0;
    lost = false;
  }

  /// Cost of restarting the path at word [i]: a repeat inside the current
  /// ayah, a move to the first word of the next or previous ayah, or a far
  /// jump anywhere else. Before the first phoneme every ayah start is cheap.
  double _restartCost(int i, int cursorAyah, int cursorPos, double repeat,
      double ayahJump, double jump) {
    final w = reference.words[i];
    final m = reference.wordStart[i];
    if (cursorAyah < 0) {
      if (!startAnywhere) return i == startWord ? repeat : double.infinity;
      return w.wordInAyah == 0 ? ayahJump : jump;
    }
    // Once under way the recitation never jumps FORWARD: where it starts is
    // the only free choice (the start options live on in the DP column).
    // A similar phrase further down the page is an error here, not a move.
    if (m > cursorPos) return double.infinity;
    if (w.ayah == cursorAyah) return repeat;
    if (w.wordInAyah == 0 && w.ayah == cursorAyah - 1) return ayahJump;
    return jump;
  }

  double? costRate([int? window]) {
    final w0 = window ?? cfg.lostWindow;
    final n = costs.length;
    if (n < _rateMinN) return null;
    final w = math.min(w0, n);
    final before = n - w > 0 ? costs[n - w - 1] : 0.0;
    return (costs[n - 1] - before) / w;
  }

  void feed(Iterable<HeardChar> chars) {
    for (final h in chars) {
      feedOne(h);
    }
  }

  void feedOne(HeardChar h) {
    final prev = column;
    final L = len;
    var colMin = prev[0];
    for (var m = 1; m <= L; m++) {
      if (prev[m] < colMin) colMin = prev[m];
    }
    final started = cursorLocalWord >= 0 && heard.isNotEmpty;
    final jump = colMin + (started ? cfg.farJumpCost : cfg.jumpCost);
    final ayahJump = colMin + (started ? cfg.ayahJumpCost : cfg.startAyahCost);
    final repeat = colMin + cfg.repeatCost;
    final cursorAyah =
        cursorLocalWord < 0 ? -1 : reference.words[cursorLocalWord].ayah;
    final cursorPos = cursorCell;
    final hid = table.id(h.ch);
    final ref = reference.ref;
    final g = heard.length;
    final prevOH = originHeard;
    final prevOC = originCell;
    final next = Float32List(L + 1);
    final nextOH = Int32List(L + 1);
    final nextOC = Int32List(L + 1);
    next[0] = prev[0] + 1;
    // A path still sitting on the cell it started (or restarted) on has
    // matched nothing yet: what it heard so far is noise BEFORE its run (the
    // ayah recited further down the page while the session waits at a
    // skipped one), so the run begins after it.
    nextOH[0] = prevOC[0] == 0 ? g + 1 : prevOH[0];
    nextOC[0] = prevOC[0];
    if (reference.wordStart[0] == 0) {
      final r = _restartCost(0, cursorAyah, cursorPos, repeat, ayahJump, jump);
      if (r < next[0]) {
        next[0] = r;
        nextOH[0] = g;
        nextOC[0] = 0;
      }
    }
    for (var m = 1; m <= L; m++) {
      var v = prev[m - 1] + table.cost(hid, ref[m - 1]);
      var oh = prevOH[m - 1];
      var oc = prevOC[m - 1];
      final ins = prev[m] + 1;
      if (ins < v) {
        v = ins;
        oc = prevOC[m];
        oh = oc == m ? g + 1 : prevOH[m];
      }
      final del = next[m - 1] + 1;
      if (del < v) {
        v = del;
        oh = nextOH[m - 1];
        oc = nextOC[m - 1];
      }
      next[m] = v;
      nextOH[m] = oh;
      nextOC[m] = oc;
    }
    for (var i = 0; i < reference.n; i++) {
      final m = reference.wordStart[i];
      final restart = _restartCost(i, cursorAyah, cursorPos, repeat, ayahJump, jump);
      if (restart < next[m]) {
        next[m] = restart;
        nextOH[m] = g;
        nextOC[m] = m;
        for (var j = m + 1; j <= L && next[j - 1] + 1 < next[j]; j++) {
          next[j] = next[j - 1] + 1;
          nextOH[j] = nextOH[j - 1];
          nextOC[j] = nextOC[j - 1];
        }
      }
    }
    final cap = maxCell;
    if (cap != null) {
      for (var m = cap + 1; m <= L; m++) {
        next[m] = double.infinity;
      }
    }
    var bestCell = 0;
    var bestCost = next[0];
    var bestDist = (0 - cursorPos).abs();
    for (var m = 1; m <= L; m++) {
      final c = next[m];
      final d = (m - cursorPos).abs();
      if (c < bestCost || (c == bestCost && d < bestDist)) {
        bestCost = c;
        bestCell = m;
        bestDist = d;
      }
    }
    column = next;
    originHeard = nextOH;
    originCell = nextOC;
    cursorCell = bestCell;
    cursorLocalWord = bestCell == 0
        ? 0
        : reference.localWordOfPos[math.min(bestCell, L) - 1];
    cursorCost = bestCost;
    trail.add(bestCell);
    originHeardTrail.add(nextOH[bestCell]);
    originCellTrail.add(nextOC[bestCell]);
    costs.add(bestCost);
    heard.add(h);
    final rate = costRate(cfg.lostWindow);
    lost = rate != null && rate >= cfg.lostRate;
  }
}

// ---------------------------------------------------------------------------
// Verdicts (verdicts.ts)
// ---------------------------------------------------------------------------

class _Segment {
  _Segment({
    required this.heardFrom,
    required this.heardTo,
    required this.refFrom,
    required this.refTo,
    required this.run,
    required this.contextFrom,
  });
  final int heardFrom;
  final int heardTo;
  final int refFrom;
  final int refTo;
  final int run;
  final int contextFrom;
}

class _Span {
  _Span(this.from, this.to, this.run);
  final int from;
  final int to;
  final int run;
}

/// The pausal (waqf) form of a word's phonemes when a reciter stops on it
/// mid-ayah: tanween becomes a plain vowel or a fathatan alef, a final short
/// vowel drops. Null when there is no distinct pausal form.
String? pausalPhonemes(String ph, PhonemeWord w, bool atAyahEnd) {
  if (atAyahEnd) return null;
  final chars = ph.runes.map(String.fromCharCode).toList();
  if (chars.length < 2) return null;
  const cluster = {'ن', 'ں', 'م', '۾', 'و', 'ۥ', 'ي', 'ۦ', 'ل', 'ر'};
  const shortVowels = {'َ', 'ُ', 'ِ'};
  const tanweenVowel = {'ً': 'َ', 'ٌ': 'ُ', 'ٍ': 'ِ'};
  String? result;
  if (w.tanween.isNotEmpty) {
    var stem = List<String>.of(chars);
    if (stem.isNotEmpty) {
      final last = stem.last;
      if (cluster.contains(last)) {
        var i = stem.length - 1;
        while (i >= 0 && stem[i] == last) {
          i--;
        }
        stem = stem.sublist(0, i + 1);
      }
    }
    final vowel = tanweenVowel[w.tanween];
    if (vowel == null || stem.isEmpty || stem.last != vowel) return null;
    if (w.tanween == 'ً' && !w.taMarbuta) {
      result = '${stem.join()}اا';
    } else {
      result = stem.sublist(0, stem.length - 1).join();
    }
  } else if (shortVowels.contains(chars.last)) {
    result = chars.sublist(0, chars.length - 1).join();
  }
  if (result == null || result.isEmpty || result == ph) return null;
  return result;
}

/// Fatha, damma, kasra: the recognizer's short-vowel tokens.
const Set<String> _shortVowels = {'َ', 'ُ', 'ِ'};

class VerdictTracer {
  VerdictTracer(this.tracker, {TrackerConfig? cfg, this.lexicon})
      : table = tracker.table,
        cfg = cfg ?? tracker.cfg;

  final PhonemeTracker tracker;
  final PhonemeLexicon? lexicon;
  final PhonemeCostTable table;
  final TrackerConfig cfg;
  final Map<String, Map<int, _Span>> _cache = {};
  int _cacheRevision = -1;

  static const int _segmentCut = 300;
  static const int _contextChars = 6;

  List<WordVerdict> verdicts({bool settled = false}) {
    final t = tracker;
    if (_cacheRevision != t.revision) {
      _cache.clear();
      _cacheRevision = t.revision;
    }
    final segs = _segment(t.trail);
    final spans = <int, _Span>{};
    for (var s = 0; s < segs.length; s++) {
      final seg = segs[s];
      final open = s == segs.length - 1;
      Map<int, _Span> got;
      if (!open) {
        final key = '${seg.contextFrom}:${seg.heardTo}:${seg.refFrom}:${seg.refTo}';
        got = _cache[key] ??= _alignSegment(seg);
      } else {
        got = _alignSegment(seg);
      }
      spans.addAll(got);
    }
    return _judge(spans, settled, segs.isEmpty ? 0 : segs.last.run);
  }

  /// Cuts the heard stream into runs, one per restart of the best path,
  /// and each run into segments of at most [_segmentCut] chars.
  ///
  /// The tracker records, for every heard char, where the best path at that
  /// char last restarted (a jump or a repeat) and the word start it landed
  /// on. Walking those origins back from the last char gives the exact
  /// restart points. Cutting at the char where the trail moved backwards
  /// instead (the old way) missed the first words of every repeat: the
  /// restarted path only overtakes the old one after its restart cost has
  /// been paid off, two or three words in, so the words the reciter went
  /// back to correct kept their stale verdicts.
  List<_Segment> _segment(List<int> trail) {
    final n = trail.length;
    if (n == 0) return const [];
    final t = tracker;
    final runStarts = <int>[];
    final runCells = <int>[];
    var end = n;
    while (end > 0) {
      var o = t.originHeardTrail[end - 1];
      if (o < 0) o = 0;
      if (o >= end) o = end - 1;
      runStarts.add(o);
      runCells.add(t.originCellTrail[end - 1]);
      end = o;
    }
    final segs = <_Segment>[];
    final runs = runStarts.length;
    for (var run = 0; run < runs; run++) {
      final k = runs - 1 - run;
      final runStart = runStarts[k];
      final runEnd = k == 0 ? n : runStarts[k - 1];
      var segStart = runStart;
      var prevSegStart = runStart;
      for (var g = runStart + 1; g <= runEnd; g++) {
        if (g - segStart < _segmentCut && g != runEnd) continue;
        final firstOfRun = segStart == runStart;
        final int refFrom;
        if (firstOfRun) {
          refFrom = runCells[k];
        } else {
          final cell = trail[segStart];
          refFrom = cell <= 0
              ? 0
              : t.reference.wordStart[t.reference.localWordOfPos[cell - 1]];
        }
        final contextFrom = firstOfRun
            ? segStart
            : math.max(prevSegStart, segStart - _contextChars);
        segs.add(_Segment(
          heardFrom: segStart,
          heardTo: g,
          refFrom: refFrom,
          refTo: trail[g - 1],
          run: run,
          contextFrom: contextFrom,
        ));
        prevSegStart = segStart;
        segStart = g;
      }
    }
    return segs;
  }

  Map<int, _Span> _alignSegment(_Segment seg) {
    final t = tracker;
    final ids = Int32List(seg.heardTo - seg.contextFrom);
    for (var i = 0; i < ids.length; i++) {
      ids[i] = table.id(t.heard[seg.contextFrom + i].ch);
    }
    final assign = alignGlobal(ids, t.reference.ref, seg.refFrom, seg.refTo, table);
    final first = <int, int>{};
    final last = <int, int>{};
    for (var i = 0; i < assign.length; i++) {
      final refIndex = assign[i];
      if (refIndex < 0) continue;
      final lw = t.reference.localWordOfPos[refIndex];
      final gi = seg.contextFrom + i;
      first.putIfAbsent(lw, () => gi);
      last[lw] = gi;
    }
    return {
      for (final e in first.entries) e.key: _Span(e.value, last[e.key]! + 1, seg.run),
    };
  }

  static int _stopBoundary(List<HeardChar> heard, int from, int to, int settle) {
    final end = math.min(heard.length, to + 4);
    for (var i = from + 1; i <= end; i++) {
      if (i == heard.length) return i;
      if (heard[i].frame - heard[i - 1].frame >= settle) return i;
    }
    return -1;
  }

  /// Whether the reciter read straight on from word [w] into the next one:
  /// only then is the word's final short vowel pronounced and heard. At a
  /// pause (a waqf sign, a breath) the vowel is silent and the recognizer
  /// tends to invent one; and when the next word begins with the letter this
  /// one ends on (kadhdhaba bi-) the two merge and the vowel is lost.
  bool _readOn(Map<int, _Span> spans, int w, _Span span, String exp) {
    final t = tracker;
    final next = spans[w + 1];
    if (next == null || next.run != span.run) return false;
    if (span.to <= 0 || next.from >= t.heard.length || next.from < span.to) return false;
    final gapFrames = t.heard[next.from].frame - t.heard[span.to - 1].frame;
    if (gapFrames > 8) return false;
    final nextExp = t.reference.words[w + 1].phon;
    final stem = _skeleton(exp);
    final nextStem = _skeleton(nextExp);
    if (stem.isEmpty || nextStem.isEmpty) return false;
    final a = table.encode(stem[stem.length - 1]);
    final b = table.encode(nextStem[0]);
    if (table.cost(a[0], b[0]) == 0) return false;
    return true;
  }

  /// Nasal-assimilation symbols as plain letters, doubled letters single.
  /// A final nasal counts as one sound whatever it assimilated to (min
  /// before ba is heard as mim).
  static String _foldNasal(String s) {
    const nasals = 'منں۾';
    final endsNasal = s.isNotEmpty && nasals.contains(s[s.length - 1]);
    var x = s.replaceAll('ں', 'ن').replaceAll('۾', 'ن');
    while (x.isNotEmpty && (x.endsWith('م') || x.endsWith('ن'))) {
      x = x.substring(0, x.length - 1);
    }
    if (endsNasal) x = '$xن';
    final b = StringBuffer();
    String? last;
    for (final r in x.runes) {
      final c = String.fromCharCode(r);
      if (c != last) b.write(c);
      last = c;
    }
    return b.toString();
  }

  /// The consonants of a phoneme string (short vowels and marks dropped).
  static String _skeleton(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      if (!PhonemeCostTable.isMark(c)) b.write(c);
    }
    return b.toString();
  }

  /// The short vowel the mushaf word ends on, or '' (sukun, tanween, a long
  /// vowel, or a pause form where none is written).
  static String _finalVowel(String text) {
    for (var i = text.length - 1; i >= 0; i--) {
      final c = text[i];
      if (_shortVowels.contains(c)) return c;
      final u = c.codeUnitAt(0);
      final isMark = (u >= 0x064B && u <= 0x065F) || u == 0x0670 || (u >= 0x06D6 && u <= 0x06ED);
      if (!isMark) return '';
      if (u >= 0x064B && u <= 0x064D) return ''; // tanween
      if (u == 0x0652 || u == 0x06E1) return ''; // sukun
    }
    return '';
  }

  /// Heard chars after [w]'s span that the alignment gave to no word, up to
  /// the next word's span (same run, already settled). Empty when there is
  /// no next span yet or the two spans touch.
  String _gapAfter(Map<int, _Span> spans, int w, _Span span, int heardLen, int dwell) {
    final next = spans[w + 1];
    if (next == null || next.run != span.run) return '';
    if (next.from <= span.to || next.to > heardLen - dwell) return '';
    if (next.from - span.to > 14) return '';
    return _slice(span.to, next.from);
  }

  /// The same word in another nasal/assimilation form (مِن / مِںںں,
  /// بَينَهُم / بَينَهُ۾۾۾) is not a substitution.
  bool _sameWordFolded(String a, String b) {
    String fold(String x) {
      final f = x.replaceAll('ں', 'ن').replaceAll('۾', 'م');
      final out = StringBuffer();
      var prev = '';
      for (final r in f.runes) {
        final c = String.fromCharCode(r);
        if (c != prev) out.write(c);
        prev = c;
      }
      return out.toString();
    }

    return normalizedDistance(table.encode(fold(a)), table.encode(fold(b)), table) <= 0.2;
  }

  /// [hit] is the expected word minus its first letters (لَاا of عَلَاا, ءِذ
  /// of وَءِذ) and that first consonant was heard just before the span: the
  /// recognizer glued it to the previous word, nothing was omitted.
  bool _prefixHeardBefore(String hit, String exp, int from) {
    if (!exp.endsWith(hit) || hit.length >= exp.length) return false;
    final missing = exp.substring(0, exp.length - hit.length);
    final before = _slice(math.max(0, from - missing.length - 2), from);
    return before.contains(missing[0]);
  }

  String _slice(int from, int to) {
    final h = tracker.heard;
    final b = StringBuffer();
    for (var i = from; i < to && i < h.length; i++) {
      b.write(h[i].ch);
    }
    return b.toString();
  }

  List<WordVerdict> _judge(Map<int, _Span> spans, bool settled, int lastRun) {
    final t = tracker;
    if (spans.isEmpty) return const [];
    var minW = 1 << 30;
    var maxW = -1;
    for (final w in spans.keys) {
      if (w < minW) minW = w;
      if (w > maxW) maxW = w;
    }
    final cursorWord = t.cursorWord;
    final cursorPending = !t.reachedEnd && !settled;
    final dwell = settled ? 0 : cfg.commitDwell;
    final heardLen = t.heard.length;
    final out = <WordVerdict>[];
    for (var w = minW; w <= maxW; w++) {
      final span = spans[w];
      final wd = t.reference.words[w];
      final exp = wd.phon;
      final expLen = exp.runes.length;
      final pending = (w == cursorWord && cursorPending) ||
          (span != null && span.to > heardLen - dwell) ||
          (span != null && span.run < lastRun && w >= cursorWord);
      final heardCount = span == null ? 0 : span.to - span.from;
      if (!pending && heardCount < cfg.minHeardFraction * expLen) {
        // Skipped only once the cursor has passed it: a gap between the
        // cursor and an abandoned excursion further down the page is not
        // a skip, those words are simply not reached yet.
        if (minW < w && w < maxW && w < cursorWord) {
          out.add(WordVerdict(
            word: w,
            state: VerdictState.skipped,
            distance: 1,
            heardRatio: expLen > 0 ? heardCount / expLen : 0,
            margin: 0,
          ));
        }
        continue;
      }
      if (span == null) continue;
      final from = span.from;
      var to = span.to;
      var heardSlice = _slice(from, to);
      var distance = normalizedDistance(
        table.encode(heardSlice),
        table.encode(exp),
        table,
      );
      var reason = '';
      // Connected to the previous word, a hamzat-al-wasl word drops its
      // leading hamza and vowel.
      if (wd.wasl && expLen > 2 && exp.startsWith('ء')) {
        final rest = String.fromCharCodes(exp.runes.skip(2));
        final dWasl = normalizedDistance(
          table.encode(heardSlice),
          table.encode(rest),
          table,
        );
        if (dWasl < distance) distance = dWasl;
      }
      final atAyahEnd = wd.wordInAyah == wd.ayahWords - 1;
      final pausal = pausalPhonemes(exp, wd, atAyahEnd);
      if (distance > cfg.okDistance && pausal != null) {
        final stop = _stopBoundary(t.heard, from, to, cfg.settleFrames);
        if (stop >= 0) {
          if (stop != to) {
            to = stop;
            heardSlice = _slice(from, to);
          }
          final d2 = normalizedDistance(
            table.encode(heardSlice),
            table.encode(pausal),
            table,
          );
          distance = math.min(distance, d2);
        }
      }
      var margin = 0.0;
      final spanHeard = span.to - span.from;
      if (spanHeard > 0) {
        for (var i = span.from; i < span.to && i < heardLen; i++) {
          margin += t.heard[i].margin;
        }
        margin /= spanHeard;
      }
      final heardRatio = expLen > 0 ? spanHeard / expLen : 0.0;
      // The Hafs reading of a word Qalun reads differently: a habit error,
      // flagged even when it is within the ok band.
      if (!pending && wd.hafsAlt.isNotEmpty) {
        final altEnc = table.encode(wd.hafsAlt);
        var dExp = distance;
        var dAlt = normalizedDistance(table.encode(heardSlice), altEnc, table);
        // A final short vowel that the Hafs form carries and the Qalun form
        // does not (فَيَغْفِرُ / فَيَغْفِرْ) lands just past this word's span,
        // unassigned or on the next word. No word begins with a short
        // vowel, so it is this word's: judge the alt on the extended slice.
        if (to < heardLen) {
          final nextCh = t.heard[to].ch;
          if (_shortVowels.contains(nextCh) && wd.hafsAlt.endsWith(nextCh)) {
            final ext = table.encode(heardSlice + nextCh);
            final dAltExt = normalizedDistance(ext, altEnc, table);
            if (dAltExt < dAlt) {
              dAlt = dAltExt;
              dExp = normalizedDistance(ext, table.encode(exp), table);
            }
          }
        }
        if (dAlt < dExp && dAlt <= cfg.okDistance) reason = 'hafs';
      }
      // An equally correct form (see [PhonemeWord.accept]).
      var accepted = false;
      for (final a in wd.accept) {
        final dA = normalizedDistance(table.encode(heardSlice), table.encode(a), table);
        if (dA < distance) distance = dA;
        if (dA <= cfg.okDistance) accepted = true;
      }
      // A heard form that is not this word but IS another Quran word
      // (الفاسقون for الظالمون, يفقهون for يعقلون, وإذا for وترى) is a
      // substitution, however close the two happen to be acoustically.
      String substitute = '';
      if (!pending && !accepted && reason.isEmpty && distance > cfg.okDistance && lexicon != null) {
        final hit = lexicon!.nearest(heardSlice, cfg.lexiconDistance, table);
        // A truncated or pausal form of the expected word itself (قَبلِ of
        // قَبلِكُم, مَكَانَ of مَكَانًا) is not another word.
        if (hit != null &&
            !exp.startsWith(hit) &&
            !hit.startsWith(exp) &&
            !_sameWordFolded(hit, exp) &&
            !_prefixHeardBefore(hit, exp, from) &&
            normalizedDistance(table.encode(hit), table.encode(exp), table) > cfg.okDistance &&
            (wd.hafsAlt.isEmpty ||
                normalizedDistance(table.encode(hit), table.encode(wd.hafsAlt), table) > cfg.okDistance)) {
          reason = 'word';
          substitute = hit;
        }
      }
      // Inside the ok band too, when what was heard is EXACTLY another
      // Quran word that differs in a consonant (yahshuruhum for nahshuruhum):
      // one cheap substitution in a long word stays under the ok distance.
      if (!pending &&
          !accepted &&
          reason.isEmpty &&
          distance > 0 &&
          distance <= cfg.okDistance &&
          lexicon != null &&
          heardSlice.runes.length >= 3 &&
          heardSlice != exp &&
          heardSlice != pausal &&
          lexicon!.contains(heardSlice) &&
          !exp.startsWith(heardSlice) &&
          !heardSlice.startsWith(exp) &&
          _foldNasal(heardSlice) != _foldNasal(exp) &&
          !_prefixHeardBefore(heardSlice, exp, from) &&
          _skeleton(heardSlice) != _skeleton(exp) &&
          heardSlice != wd.hafsAlt) {
        reason = 'word';
        substitute = heardSlice;
      }
      // Look-alike passages: the word another ayah has at this very spot.
      if (!pending && !accepted && reason.isEmpty && wd.alts.isNotEmpty && heardSlice != exp) {
        final enc = table.encode(heardSlice);
        for (final alt in wd.alts) {
          final dAlt = normalizedDistance(enc, table.encode(alt), table);
          if (dAlt < 1e-6 || (dAlt <= 0.2 && dAlt + 0.1 <= distance)) {
            reason = 'word';
            substitute = alt;
            break;
          }
        }
      }
      // The vowel a word ends on (i'rab): everything else matches exactly
      // and only the final short vowel differs (والنورِ for والنورَ). At a
      // stop the vowel is silent and nothing can be said; read on, it is
      // the first sound after the word.
      if (!pending && !accepted && reason.isEmpty && _readOn(spans, w, span, exp)) {
        final want = _finalVowel(wd.text);
        // (The expected phonemes must end on that very vowel: where the text
        // and the phonemes disagree the fault is the phonetizer's.)
        if (want.isNotEmpty &&
            !(_shortVowels.contains(exp[exp.length - 1]) && !exp.endsWith(want))) {
          String got = '';
          var stem = heardSlice;
          if (heardSlice.isNotEmpty && _shortVowels.contains(heardSlice[heardSlice.length - 1])) {
            got = heardSlice[heardSlice.length - 1];
            stem = heardSlice.substring(0, heardSlice.length - 1);
          } else if (to < heardLen && _shortVowels.contains(t.heard[to].ch)) {
            got = t.heard[to].ch;
          }
          final expStem = _shortVowels.contains(exp[exp.length - 1])
              ? exp.substring(0, exp.length - 1)
              : exp;
          if (got.isNotEmpty && got != want && stem == expStem) {
            reason = 'haraka';
            substitute = heardSlice == stem ? '$stem$got' : heardSlice;
          }
        }
      }
      // What was heard BETWEEN this word and the next (assigned to neither):
      // a few sounds that complete another Quran word (قالوا for قال, ذلكم
      // for ذلك), or a whole extra word (رزقنا «به» من قبل).
      if (!pending && reason.isEmpty && lexicon != null) {
        var gap = _gapAfter(spans, w, span, heardLen, dwell);
        // Sounds that belong to the next word's doubled first letter (hal
        // lana, in ya'fu) or that complete an accepted form are no gap.
        if (gap.isNotEmpty && w + 1 < t.reference.n) {
          final nextFirst = table.encode(t.reference.words[w + 1].phon);
          if (nextFirst.isNotEmpty &&
              table.encode(gap).every((c) => table.cost(c, nextFirst[0]) == 0)) {
            gap = '';
          }
        }
        if (gap.isNotEmpty) {
          final joined = table.encode(heardSlice + gap);
          for (final a in wd.accept) {
            if (normalizedDistance(joined, table.encode(a), table) <= 0.06) gap = '';
          }
        }
        if (gap.isNotEmpty) {
          final n = gap.runes.length;
          if (n <= 4) {
            final hit = lexicon!.nearest(heardSlice + gap, 0.06, table);
            if (hit != null &&
                hit.runes.length > exp.runes.length &&
                !_sameWordFolded(hit, exp) &&
                normalizedDistance(table.encode(hit), table.encode(exp), table) > 0.1) {
              reason = 'word';
              substitute = hit;
            }
          }
          if (reason.isEmpty && n >= 3) {
            final hit = lexicon!.nearest(gap, cfg.lexiconDistance, table);
            if (hit != null && hit.runes.length >= 3) {
              reason = 'extra';
              substitute = hit;
            }
          }
        }
      }
      final VerdictState state;
      if (pending) {
        state = VerdictState.pending;
      } else if (reason == 'hafs' || reason == 'word' || reason == 'extra' || reason == 'haraka') {
        state = VerdictState.wrong;
      } else if (distance <= cfg.okDistance) {
        state = VerdictState.ok;
      } else if (distance <= cfg.unsureDistance || margin < cfg.minMargin) {
        // Much more was said than the word holds and it is not close: some
        // other words were recited over it (akhadhnahum heard for fa-idha).
        state = heardRatio >= 1.4 && distance > 0.3
            ? VerdictState.wrong
            : VerdictState.unsure;
      } else if (heardCutShort(heardSlice, exp)) {
        state = VerdictState.unsure;
      } else {
        state = VerdictState.wrong;
      }
      out.add(WordVerdict(
        word: w,
        state: state,
        distance: distance,
        heardRatio: heardRatio,
        margin: margin,
        heard: substitute.isNotEmpty ? substitute : heardSlice,
        spanFrom: from,
        spanTo: to,
        reason: reason,
      ));
    }
    return out;
  }
}

/// Whether [heard] is a short word's opening heard exactly, with only its
/// held ending missing: the nasal of an ikhfa or an idgham (كُن فَيَكُونُ heard
/// كُ, مِن وَّرَقَةٍ heard مِ) or a long vowel (مَا heard مَ, فِے heard فِ). The
/// model hands that ending to the next word, and in a word of two letters
/// its loss alone is a distance of 0.6: phone logs show correct readings
/// stopped there for up to a minute. Such a word is `unsure`, not `wrong`.
/// A missing letter (قَا for قَالَ) or a wrong sound (كَ for كُن) is no match.
bool heardCutShort(String heard, String expected) {
  final h = heard.runes.toList();
  final e = expected.runes.toList();
  if (h.length < 2 || h.length > 3 || e.length <= h.length) return false;
  for (var i = 0; i < h.length; i++) {
    if (h[i] != e[i]) return false;
  }
  final first = e[h.length];
  for (var i = h.length; i < e.length; i++) {
    if (e[i] != first) return false;
  }
  final tail = e.length - h.length;
  final c = String.fromCharCode(first);
  if ('اۥۦں۾'.contains(c)) return true;
  // A doubled consonant with no vowel only ends a word through idgham.
  return tail >= 2 && 'ويمنلر'.contains(c);
}

/// Every distinct phoneme string of the mushaf's words (context and pausal
/// forms), for the substitution check: is what was heard some *other* word?
class PhonemeLexicon {
  PhonemeLexicon(Iterable<String> entries) {
    for (final e in entries) {
      (_byLength[e.runes.length] ??= []).add(e);
    }
  }

  final Map<int, List<String>> _byLength = {};
  Set<String>? _all;

  /// Whether [s] is exactly a lexicon entry.
  bool contains(String s) =>
      (_all ??= {for (final b in _byLength.values) ...b}).contains(s);

  /// The lexicon entry within [maxDistance] of [heard] with the smallest
  /// distance, or null. Only entries of a similar length are tried.
  String? nearest(String heard, double maxDistance, PhonemeCostTable table) {
    // Verdicts are recomputed ten times a second; a slice is looked up once.
    if (_cache.containsKey(heard)) return _cache[heard];
    return _cache[heard] = _nearest(heard, maxDistance, table);
  }

  final Map<String, String?> _cache = {};

  String? _nearest(String heard, double maxDistance, PhonemeCostTable table) {
    final n = heard.runes.length;
    if (n < 2) return null;
    final enc = table.encode(heard);
    String? best;
    var bestD = maxDistance;
    final slack = (n * maxDistance).ceil();
    for (var len = n - slack; len <= n + slack; len++) {
      final bucket = _byLength[len];
      if (bucket == null) continue;
      for (final e in bucket) {
        final d = normalizedDistance(enc, table.encode(e), table);
        if (d <= bestD) {
          bestD = d;
          best = e;
        }
      }
    }
    return best;
  }
}

/// Renders a phoneme string as readable pointed Arabic for feedback lines:
/// long-vowel and nasal symbols become letters, tajweed markers are dropped,
/// madd runs shrink to one letter.
String phonemesToArabic(String ph) {
  final collapsed = collapseMadd(ph)
      .replaceAll('اا', 'ا')
      .replaceAll('ۥۥ', 'و')
      .replaceAll('ۦۦ', 'ي');
  final b = StringBuffer();
  for (final r in collapsed.runes) {
    final c = String.fromCharCode(r);
    switch (c) {
      case 'ۥ':
        b.write('و');
      case 'ۦ':
        b.write('ي');
      case 'ں':
        b.write('ن');
      case '۾':
        b.write('م');
      case 'ڇ':
      case 'ۜ':
      case '۪':
      case 'ؙ':
      case 'ٲ':
      case 'ـ':
        break;
      default:
        b.write(c);
    }
  }
  // Ghunnah and idgham runs (ننن, ممم, يييَ) read as one letter.
  return b.toString().replaceAllMapped(
        RegExp(r'([ء-ي])\1{2,}'),
        (m) => m.group(1)!,
      );
}

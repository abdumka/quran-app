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
  });

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
  PhonemeTracker(this.reference, {this.cfg = const TrackerConfig()})
      : table = reference.table,
        len = reference.length {
    _resetColumn();
  }

  final PhonemeReference reference;
  final PhonemeCostTable table;
  final TrackerConfig cfg;
  final int len;

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
      column[m] = m == 0
          ? 0
          : (reference.words[i].wordInAyah == 0 ? cfg.startAyahCost : jump);
      originCell[m] = m;
    }
    for (var m = 1; m <= len; m++) {
      if (column[m - 1] + 1 < column[m]) {
        column[m] = column[m - 1] + 1;
        originCell[m] = originCell[m - 1];
      }
    }
    cursorCell = 0;
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
    if (cursorAyah < 0) return w.wordInAyah == 0 ? ayahJump : jump;
    if (w.ayah == cursorAyah && m <= cursorPos) return repeat;
    if (w.wordInAyah == 0 && (w.ayah == cursorAyah + 1 || w.ayah == cursorAyah - 1)) {
      return ayahJump;
    }
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
    nextOH[0] = prevOH[0];
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
        oh = prevOH[m];
        oc = prevOC[m];
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
      // A heard form that is not this word but IS another Quran word
      // (الفاسقون for الظالمون, يفقهون for يعقلون, وإذا for وترى) is a
      // substitution, however close the two happen to be acoustically.
      String substitute = '';
      if (!pending && reason.isEmpty && distance > cfg.okDistance && lexicon != null) {
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
      final VerdictState state;
      if (pending) {
        state = VerdictState.pending;
      } else if (reason == 'hafs' || reason == 'word') {
        state = VerdictState.wrong;
      } else if (distance <= cfg.okDistance) {
        state = VerdictState.ok;
      } else if (distance <= cfg.unsureDistance || margin < cfg.minMargin) {
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

/// Every distinct phoneme string of the mushaf's words (context and pausal
/// forms), for the substitution check: is what was heard some *other* word?
class PhonemeLexicon {
  PhonemeLexicon(Iterable<String> entries) {
    for (final e in entries) {
      (_byLength[e.runes.length] ??= []).add(e);
    }
  }

  final Map<int, List<String>> _byLength = {};

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

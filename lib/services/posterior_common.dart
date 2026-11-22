// The plain-Dart half of the posterior verify: the query, the verdict, the
// token table and the CTC aligner. Split out of zipformer_posterior.dart
// (2026-11-21) so the web build, which has no dart:ffi, can compile the
// Tasmee service against a stub engine (zipformer_posterior_web.dart).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// What the service asks about one stop: the accepted phoneme forms of the
/// disputed word, its neighbours, and the frame (40 ms, window-relative)
/// before which a match does not count (an earlier occurrence of the same
/// word inside the window is not this one).
class PosteriorQuery {
  const PosteriorQuery({
    required this.forms,
    required this.prevPhon,
    required this.nextPhon,
    required this.minEndFrame,
  });

  final List<String> forms;
  final String prevPhon;
  final String nextPhon;
  final int minEndFrame;

  /// The a=3, c=3 rule of the 2026-11-06 study: total alignment cost of the
  /// word (relative to the greedy path) and the worst token's best frame.
  static const double scoreFloor = 3.0;
  static const double weakestFloor = 3.0;
}

class PosteriorVerdict {
  const PosteriorVerdict(this.tokens, this.score, this.weakest, this.cleared, this.candidate);

  /// Greedy tokens of the fresh decode (identical to sherpa's).
  final List<String> tokens;
  final double? score;
  final double? weakest;
  final bool cleared;
  final String? candidate;
}

/// Log posteriors, frames x vocab, row-major.
class LogProbs {
  LogProbs(this.frames, this.vocab, this.data, this.blank);
  final int frames;
  final int vocab;
  final Float32List data;
  final int blank;

  double at(int t, int k) => data[t * vocab + k];

  int argmax(int t) {
    var best = 0;
    var bv = data[t * vocab];
    for (var k = 1; k < vocab; k++) {
      final v = data[t * vocab + k];
      if (v > bv) {
        bv = v;
        best = k;
      }
    }
    return best;
  }

  /// Greedy CTC decode: collapse repeats, drop blanks.
  List<String> greedy(TokenTable tokens) {
    final out = <String>[];
    var prev = -1;
    for (var t = 0; t < frames; t++) {
      final i = argmax(t);
      if (i != prev && i != blank) out.add(tokens.text(i));
      prev = i;
    }
    return out;
  }
}

/// The model's token table (`zipformer-tokens.txt`: `<token> <id>` lines).
class TokenTable {
  TokenTable(this._idToText) {
    for (final e in _idToText.entries) {
      if (e.value == '<blank>') {
        blank = e.key;
      } else {
        _textToId[e.value] = e.key;
        if (e.value.runes.length > maxLen) maxLen = e.value.runes.length;
      }
    }
    for (final c in const ['ا', 'ۥ', 'ۦ']) {
      _maddClass[c] = {
        for (final e in _textToId.entries)
          if (e.key.isNotEmpty && e.key.runes.every((r) => String.fromCharCode(r) == c)) e.value
      };
    }
  }

  factory TokenTable.fromFile(String path) {
    final map = <int, String>{};
    for (final line in File(path).readAsLinesSync()) {
      final s = line.trimRight();
      final cut = s.lastIndexOf(' ');
      if (cut <= 0) continue;
      map[int.parse(s.substring(cut + 1))] = s.substring(0, cut);
    }
    return TokenTable(map);
  }

  final Map<int, String> _idToText;
  final Map<String, int> _textToId = {};
  final Map<String, Set<int>> _maddClass = {};
  int blank = 0;
  int maxLen = 1;

  String text(int id) => _idToText[id] ?? '';
  int? id(String text) => _textToId[text];

  /// All lengths of a madd letter's token (a collapsed «اا» stands for any
  /// run), or null when [piece] is not a pure madd run.
  Set<int>? maddClass(String piece) {
    final runes = piece.runes.toList();
    if (runes.isEmpty) return null;
    final c = String.fromCharCode(runes.first);
    if (!_maddClass.containsKey(c)) return null;
    for (final r in runes) {
      if (r != runes.first) return null;
    }
    return _maddClass[c];
  }

  /// Longest-match cut of a phoneme string into model tokens.
  List<String> tokensOf(String s) {
    final r = s.runes.toList();
    final out = <String>[];
    var i = 0;
    while (i < r.length) {
      var matched = false;
      for (var len = math.min(maxLen, r.length - i); len > 0; len--) {
        final piece = String.fromCharCodes(r.sublist(i, i + len));
        if (_textToId.containsKey(piece)) {
          out.add(piece);
          i += len;
          matched = true;
          break;
        }
      }
      if (!matched) i++;
    }
    return out;
  }
}

/// One way the expected word may appear in the window, anchored on a
/// neighbour ([nextAnchored] when the anchor is the word after).
class Candidate {
  const Candidate(this.text, this.nextAnchored);
  final String text;
  final bool nextAnchored;
}

class Alignment {
  Alignment(this.score, this.weakest, this.start, this.end, this.text);
  final double score;
  final double weakest;
  final int start;
  final int end;
  final String text;
}

/// CTC forced alignment of a phoneme string anywhere in a window, scored
/// relative to each frame's best token (the greedy path costs 0).
class Aligner {
  static const double _neg = -1e9;
  static const Set<String> _particles = {'وَ', 'فَ', 'لَ', 'لِ', 'بِ', 'كَ'};
  static const String _vowels = 'َُِ';

  /// `score_lib.candidates`: each form with the last two tokens of the word
  /// before (also without its final vowel: a reciter who paused dropped it)
  /// or the first two tokens of the word after (also past a hamzat al-wasl).
  static List<Candidate> candidates(
      TokenTable tokens, List<String> forms, String prev, String next) {
    String tail(String ph) {
      final t = tokens.tokensOf(ph);
      return t.sublist(math.max(0, t.length - 2)).join();
    }
    String head(String ph) {
      final t = tokens.tokensOf(ph);
      return t.sublist(0, math.min(2, t.length)).join();
    }
    final out = <Candidate>[];
    final seen = <String>{};
    void add(String s, bool nextAnchored) {
      if (s.isNotEmpty && seen.add('${nextAnchored ? 1 : 0}$s')) out.add(Candidate(s, nextAnchored));
    }
    for (final f in forms) {
      if (f.isEmpty) continue;
      if (prev.isNotEmpty) {
        add(tail(prev) + f, false);
        final last = String.fromCharCode(prev.runes.last);
        if (_vowels.contains(last)) {
          add(tail(String.fromCharCodes(prev.runes.toList()..removeLast())) + f, false);
        }
      }
      if (next.isNotEmpty) {
        add(f + head(next), true);
        if (next.startsWith('ء') && next.runes.length > 2) {
          add(f + head(String.fromCharCodes(next.runes.skip(2))), true);
        }
      }
    }
    return out;
  }

  /// The best-scoring candidate, refusing a next-anchored match that has a
  /// particle the page does not have right before it («وما» said for «ما»).
  static Alignment? guardedScore(LogProbs lp, TokenTable tokens, List<Candidate> cands,
      String prevPhon, int minEnd) {
    Alignment? best;
    for (final c in cands) {
      final r = align(lp, tokens, c.text, minEnd);
      if (r == null) continue;
      if (c.nextAnchored && _particleBefore(lp, tokens, r.start, prevPhon)) continue;
      if (best == null || r.score > best.score) best = r;
    }
    return best;
  }

  static bool _particleBefore(LogProbs lp, TokenTable tokens, int start, String prevPhon,
      {int look = 8}) {
    for (var t = start - 1; t >= math.max(0, start - look); t--) {
      final i = lp.argmax(t);
      if (i == lp.blank) continue;
      final tok = tokens.text(i);
      return _particles.contains(tok) && !prevPhon.endsWith(tok);
    }
    return false;
  }

  /// `own_ctc.align`: Viterbi over the edges that cut [s] into model tokens
  /// (a madd run accepts any length of its letter). The match must end at
  /// frame [minEnd] or later. Returns null when [s] has no tokenisation or
  /// the window is empty.
  static Alignment? align(LogProbs lp, TokenTable tokens, String s, int minEnd) {
    final runes = s.runes.toList();
    final n = runes.length;
    if (n == 0 || lp.frames == 0) return null;
    // Edges: (from, to, token ids).
    final eFrom = <int>[];
    final eTo = <int>[];
    final eIds = <List<int>>[];
    final seen = <String>{};
    for (var i = 0; i < n; i++) {
      for (var len = 1; len <= math.min(tokens.maxLen, n - i); len++) {
        final piece = String.fromCharCodes(runes.sublist(i, i + len));
        final id = tokens.id(piece);
        if (id == null) continue;
        final madd = tokens.maddClass(piece);
        final ids = madd != null && madd.isNotEmpty ? (madd.toList()..sort()) : [id];
        final key = '$i:${i + len}:${ids.join(",")}';
        if (!seen.add(key)) continue;
        eFrom.add(i);
        eTo.add(i + len);
        eIds.add(ids);
      }
    }
    final e = eFrom.length;
    if (e == 0) return null;
    final into = List<List<int>>.generate(n + 1, (_) => []);
    for (var k = 0; k < e; k++) {
      into[eTo[k]].add(k);
    }
    final frames = lp.frames;
    final vocab = lp.vocab;
    // Per-frame relative log-probs for each edge and for blank.
    final rowMax = Float32List(frames);
    for (var t = 0; t < frames; t++) {
      var m = lp.data[t * vocab];
      for (var k = 1; k < vocab; k++) {
        final v = lp.data[t * vocab + k];
        if (v > m) m = v;
      }
      rowMax[t] = m;
    }
    double emit(int k, int t) {
      final ids = eIds[k];
      var best = lp.data[t * vocab + ids[0]];
      for (var j = 1; j < ids.length; j++) {
        final v = lp.data[t * vocab + ids[j]];
        if (v > best) best = v;
      }
      return best - rowMax[t];
    }
    bool sameIds(int a, int b) {
      final x = eIds[a], y = eIds[b];
      if (x.length != y.length) return false;
      for (var j = 0; j < x.length; j++) {
        if (x[j] != y[j]) return false;
      }
      return true;
    }
    var sc = Float64List(e)..fillRange(0, e, _neg);
    var wk = Float64List(e);
    var cur = Float64List(e)..fillRange(0, e, _neg);
    var st = Int32List(e);
    var bsc = Float64List(n + 1)..fillRange(0, n + 1, _neg);
    var bwk = Float64List(n + 1);
    var bst = Int32List(n + 1);
    Alignment? best;
    for (var t = 0; t < frames; t++) {
      final nsc = Float64List(e)..fillRange(0, e, _neg);
      final nwk = Float64List(e);
      final ncur = Float64List(e)..fillRange(0, e, _neg);
      final nst = Int32List(e);
      final nb = Float64List(n + 1)..fillRange(0, n + 1, _neg);
      final nbw = Float64List(n + 1);
      final nbs = Int32List(n + 1);
      for (var k = 0; k < e; k++) {
        final em = emit(k, t);
        var v = _neg, w = 0.0, c = _neg;
        var s0 = t;
        if (sc[k] > _neg / 2) {
          v = sc[k];
          w = wk[k];
          c = cur[k];
          s0 = st[k];
        }
        final i = eFrom[k];
        if (i == 0 && v < 0.0) {
          v = 0.0;
          w = 0.0;
          c = _neg;
          s0 = t;
        }
        if (bsc[i] > v) {
          v = bsc[i];
          w = bwk[i];
          c = _neg;
          s0 = bst[i];
        }
        for (final f in into[i]) {
          if (sc[f] > v && !sameIds(f, k)) {
            v = sc[f];
            w = math.min(wk[f], cur[f]);
            c = _neg;
            s0 = st[f];
          }
        }
        if (v <= _neg / 2) continue;
        nsc[k] = v + em;
        nwk[k] = w;
        ncur[k] = math.max(c, em);
        nst[k] = s0;
      }
      final be = lp.data[t * vocab + lp.blank] - rowMax[t];
      for (var i = 1; i <= n; i++) {
        var v = bsc[i], w = bwk[i];
        var s0 = bst[i];
        for (final f in into[i]) {
          if (sc[f] > v) {
            v = sc[f];
            w = math.min(wk[f], cur[f]);
            s0 = st[f];
          }
        }
        if (v > _neg / 2) {
          nb[i] = v + be;
          nbw[i] = w;
          nbs[i] = s0;
        }
      }
      sc = nsc;
      wk = nwk;
      cur = ncur;
      st = nst;
      bsc = nb;
      bwk = nbw;
      bst = nbs;
      if (t < minEnd) continue;
      for (final k in into[n]) {
        if (sc[k] > _neg / 2 && (best == null || sc[k] > best.score)) {
          best = Alignment(sc[k], math.min(wk[k], cur[k]), st[k], t, s);
        }
      }
    }
    return best;
  }
}

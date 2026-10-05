import 'dart:typed_data';

import '../services/page_phoneme_service.dart';
import 'phoneme_tracker.dart';

/// Where in the mushaf a run of heard phonemes was found.
class QuranLocation {
  const QuranLocation({
    required this.page,
    required this.wordOnPage,
    required this.ayahOnPage,
    required this.distance,
  });

  final int page;

  /// Index of the first matched word among the page's words.
  final int wordOnPage;

  /// Index of that word's ayah among the page's ayahs.
  final int ayahOnPage;

  /// Edit cost of the match per heard phoneme (0 = exact).
  final double distance;

  @override
  String toString() => 'p$page w$wordOnPage a$ayahOnPage d${distance.toStringAsFixed(2)}';
}

/// Finds the first place in the whole mushaf that sounds like a run of
/// heard phonemes («التسميع من أي موضع»). The expected phonemes of every
/// page are laid end to end; the places sharing phoneme 4-grams with the
/// heard run are the candidates, and the heard run is aligned against a
/// window at each with the tracker's own phoneme costs, free to start and
/// end anywhere in the window. Of the places that match equally well the
/// earliest in the mushaf wins.
class QuranPhonemeLocator {
  QuranPhonemeLocator(Map<int, PagePhonemes> pages, {PhonemeCostTable? table})
      : table = table ?? PhonemeCostTable() {
    final ids = <int>[];
    final wordStart = <int>[];
    final pageOf = <int>[];
    final localOf = <int>[];
    final ayahOf = <int>[];
    final numbers = pages.keys.toList()..sort();
    for (final n in numbers) {
      final words = pages[n]!.collapsed();
      for (var i = 0; i < words.length; i++) {
        wordStart.add(ids.length);
        ids.addAll(this.table.encode(words[i].phon));
        pageOf.add(n);
        localOf.add(i);
        ayahOf.add(words[i].ayah);
      }
    }
    _text = Int32List.fromList(ids);
    _wordPage = Int32List.fromList(pageOf);
    _wordLocal = Int32List.fromList(localOf);
    _wordAyah = Int32List.fromList(ayahOf);
    _wordOfPos = Int32List(_text.length);
    for (var w = 0; w < wordStart.length; w++) {
      final end = w + 1 < wordStart.length ? wordStart[w + 1] : _text.length;
      for (var pos = wordStart[w]; pos < end; pos++) {
        _wordOfPos[pos] = w;
      }
    }
    // Every position of every 4-gram, for seeding the search.
    final lists = <int, List<int>>{};
    for (var p = 0; p + _gram <= _text.length; p++) {
      (lists[_key(_text, p)] ??= []).add(p);
    }
    _grams = {for (final e in lists.entries) e.key: Int32List.fromList(e.value)};
  }

  final PhonemeCostTable table;
  late final Int32List _text;
  late final Int32List _wordPage;
  late final Int32List _wordLocal;
  late final Int32List _wordAyah;
  late final Int32List _wordOfPos;
  late final Map<int, Int32List> _grams;

  static const int _gram = 4;

  /// A 4-gram packed into one int (phoneme ids are below 64).
  static int _key(Int32List s, int p) =>
      (s[p] << 18) | (s[p + 1] << 12) | (s[p + 2] << 6) | s[p + 3];

  /// Number of phonemes in the whole mushaf.
  int get length => _text.length;

  static QuranPhonemeLocator? _shared;
  static Future<QuranPhonemeLocator>? _building;

  /// The locator over the app's own page phonemes, built once.
  static Future<QuranPhonemeLocator> shared() {
    final s = _shared;
    if (s != null) return Future.value(s);
    return _building ??= () async {
      final pages = await PagePhonemeService.loadAll();
      return _shared = QuranPhonemeLocator(pages);
    }();
  }

  /// The earliest place in the mushaf that [heard] (a run of phoneme
  /// characters, madd runs collapsed) fits within [maxPerChar] edit cost per
  /// heard phoneme. Places within [tie] of the best cost count as equally
  /// good, and the earliest of them is returned. Null when nothing fits.
  QuranLocation? locate(
    String heard, {
    double maxPerChar = 0.25,
    double tie = 0.5,
    int candidates = 48,
  }) {
    final q = table.encode(collapseMadd(heard));
    final m = q.length;
    final n = _text.length;
    if (m < _gram || n == 0) return null;

    // Seeds: every text position that shares a 4-gram with the heard run,
    // voted by the start position it implies.
    final votes = <int, int>{};
    for (var o = 0; o + _gram <= m; o++) {
      final hits = _grams[_key(q, o)];
      if (hits == null || hits.length > 20000) continue;
      for (final p in hits) {
        final c = p - o;
        votes[c] = (votes[c] ?? 0) + 1;
      }
    }
    if (votes.isEmpty) return null;
    final starts = votes.keys.toList()
      ..sort((a, b) {
        final d = votes[b]! - votes[a]!;
        return d != 0 ? d : a - b;
      });
    // The best-supported starts, neighbours folded into the stronger one.
    final chosen = <int>[];
    for (final c in starts) {
      if (chosen.length >= candidates) break;
      if (chosen.any((d) => (d - c).abs() <= 3)) continue;
      chosen.add(c);
    }

    double bestCost = double.infinity;
    var bestStart = -1;
    for (final c in chosen) {
      final lo = (c - 6).clamp(0, n);
      final hi = (c + m + 6).clamp(0, n);
      if (hi - lo < _gram) continue;
      final r = _align(q, lo, hi, tie);
      if (r == null) continue;
      final (cost, start) = r;
      if (cost < bestCost - tie || (cost <= bestCost + tie && start < bestStart)) {
        if (cost < bestCost) bestCost = cost;
        bestStart = start;
      }
    }
    if (bestStart < 0 || bestCost > maxPerChar * m) return null;
    final w = _wordOfPos[bestStart.clamp(0, n - 1)];
    return QuranLocation(
      page: _wordPage[w],
      wordOnPage: _wordLocal[w],
      ayahOnPage: _wordAyah[w],
      distance: bestCost / m,
    );
  }

  /// Semi-global alignment of [q] against the text window [lo, hi): the
  /// match may begin and end anywhere in it, every heard phoneme counts.
  /// Returns the best cost and, of the ends within [tie] of it, the
  /// earliest start.
  (double, int)? _align(Int32List q, int lo, int hi, double tie) {
    final m = q.length;
    final n = hi - lo;
    var prev = Float64List(n + 1);
    var cur = Float64List(n + 1);
    var prevStart = Int32List(n + 1);
    var curStart = Int32List(n + 1);
    for (var j = 0; j <= n; j++) {
      prevStart[j] = lo + j;
    }
    final text = _text;
    for (var i = 1; i <= m; i++) {
      final qi = q[i - 1];
      cur[0] = i.toDouble();
      curStart[0] = lo;
      for (var j = 1; j <= n; j++) {
        var best = prev[j - 1] + table.cost(qi, text[lo + j - 1]);
        var start = prevStart[j - 1];
        final del = prev[j] + 1;
        if (del < best) {
          best = del;
          start = prevStart[j];
        }
        final ins = cur[j - 1] + 1;
        if (ins < best) {
          best = ins;
          start = curStart[j - 1];
        }
        cur[j] = best;
        curStart[j] = start;
      }
      final t = prev;
      prev = cur;
      cur = t;
      final ts = prevStart;
      prevStart = curStart;
      curStart = ts;
    }
    var min = double.infinity;
    for (var j = 1; j <= n; j++) {
      if (prev[j] < min) min = prev[j];
    }
    if (min == double.infinity) return null;
    var start = -1;
    for (var j = 1; j <= n; j++) {
      if (prev[j] <= min + tie && (start < 0 || prevStart[j] < start)) {
        start = prevStart[j];
      }
    }
    return (min, start);
  }
}

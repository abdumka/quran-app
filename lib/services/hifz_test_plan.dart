import 'dart:math';

import '../models/quran_page_data.dart';
import '../surah_data.dart';
import '../thumn_data.dart';
import 'tasmee_weak_point_store.dart';

/// Where the questions of a memorization test come from.
enum HifzTestSource { mistakes, random, both }

/// What part of the mushaf a test draws its questions from.
enum HifzRangeKind { all, surahs, hizbs, pages }

/// A stretch of the mushaf: the whole of it, surahs [from]..[to], hizbs
/// [from]..[to] or pages [from]..[to] (all inclusive, 1-based).
class HifzRange {
  const HifzRange(this.kind, {this.from = 1, this.to = 1});

  const HifzRange.all() : this(HifzRangeKind.all);

  final HifzRangeKind kind;
  final int from;
  final int to;

  /// Number of items of this kind in the mushaf (surahs, hizbs or pages).
  static int maxOf(HifzRangeKind kind) => switch (kind) {
        HifzRangeKind.all => 1,
        HifzRangeKind.surahs => 114,
        HifzRangeKind.hizbs => 60,
        HifzRangeKind.pages => 602,
      };

  /// The same range with [from] and [to] inside the mushaf and in order.
  HifzRange normalized() {
    final max = maxOf(kind);
    var a = from.clamp(1, max);
    var b = to.clamp(1, max);
    if (a > b) {
      final t = a;
      a = b;
      b = t;
    }
    return HifzRange(kind, from: a, to: b);
  }

  static String surahName(int number) {
    for (final s in surahList) {
      if (s['number'] == number) return s['name'] as String;
    }
    return '$number';
  }

  /// Short Arabic description («سورة البقرة», «الأحزاب ٣–٥», ...).
  String get label {
    final r = normalized();
    switch (r.kind) {
      case HifzRangeKind.all:
        return 'المصحف كله';
      case HifzRangeKind.surahs:
        return r.from == r.to
            ? 'سورة ${surahName(r.from)}'
            : 'من سورة ${surahName(r.from)} إلى سورة ${surahName(r.to)}';
      case HifzRangeKind.hizbs:
        return r.from == r.to
            ? 'الحزب ${r.from}'
            : 'الأحزاب ${r.from} إلى ${r.to}';
      case HifzRangeKind.pages:
        return r.from == r.to
            ? 'الصفحة ${r.from}'
            : 'الصفحات ${r.from} إلى ${r.to}';
    }
  }

  Map<String, Object?> toJson() => {'kind': kind.name, 'from': from, 'to': to};

  factory HifzRange.fromJson(Map<String, dynamic> j) {
    final kind = HifzRangeKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => HifzRangeKind.all,
    );
    return HifzRange(
      kind,
      from: j['from'] as int? ?? 1,
      to: j['to'] as int? ?? 1,
    ).normalized();
  }
}

/// Everything the user chose on the setup sheet.
class HifzTestConfig {
  const HifzTestConfig({
    this.source = HifzTestSource.random,
    this.range = const HifzRange.all(),
    this.questions = 5,
    this.ayahsPerQuestion = 3,
  });

  final HifzTestSource source;
  final HifzRange range;

  /// How many questions the test asks.
  final int questions;

  /// How many ayahs one question covers (from its start to its end).
  final int ayahsPerQuestion;

  HifzTestConfig copyWith({
    HifzTestSource? source,
    HifzRange? range,
    int? questions,
    int? ayahsPerQuestion,
  }) =>
      HifzTestConfig(
        source: source ?? this.source,
        range: range ?? this.range,
        questions: questions ?? this.questions,
        ayahsPerQuestion: ayahsPerQuestion ?? this.ayahsPerQuestion,
      );

  Map<String, Object?> toJson() => {
        'source': source.name,
        'range': range.toJson(),
        'questions': questions,
        'ayahsPerQuestion': ayahsPerQuestion,
      };

  factory HifzTestConfig.fromJson(Map<String, dynamic> j) => HifzTestConfig(
        source: HifzTestSource.values.firstWhere(
          (s) => s.name == j['source'],
          orElse: () => HifzTestSource.random,
        ),
        range: j['range'] is Map<String, dynamic>
            ? HifzRange.fromJson(j['range'] as Map<String, dynamic>)
            : const HifzRange.all(),
        questions: (j['questions'] as int? ?? 5).clamp(1, 50),
        ayahsPerQuestion: (j['ayahsPerQuestion'] as int? ?? 3).clamp(1, 10),
      );
}

/// One ayah of the mushaf, with where it is printed.
class AyahRef {
  const AyahRef({
    required this.page,
    required this.indexOnPage,
    required this.surah,
    required this.surahName,
    required this.ayah,
    required this.text,
  });

  /// 1-based mushaf page the ayah is listed on (an ayah printed across a
  /// page break is listed on the page it ends on).
  final int page;

  /// Position of the ayah among the page's ayahs (0-based), as the Tasmee
  /// session counts them.
  final int indexOnPage;
  final int surah;
  final String surahName;
  final int ayah;
  final String text;

  String get key => '$surah:$ayah';
}

/// The mushaf as one flat list of ayahs in reading order, so a range of
/// surahs, hizbs or pages becomes a span of indices.
class QuranAyahIndex {
  QuranAyahIndex(this.ayahs) {
    for (var i = 0; i < ayahs.length; i++) {
      _byKey[ayahs[i].key] = i;
    }
  }

  factory QuranAyahIndex.fromPages(List<QuranPageData> pages) {
    final sorted = List<QuranPageData>.of(pages)
      ..sort((a, b) => a.page.compareTo(b.page));
    final out = <AyahRef>[];
    for (final p in sorted) {
      for (var i = 0; i < p.ayahs.length; i++) {
        final a = p.ayahs[i];
        out.add(AyahRef(
          page: p.page,
          indexOnPage: i,
          surah: a.surah,
          surahName: a.surahName,
          ayah: a.ayah,
          text: a.text,
        ));
      }
    }
    return QuranAyahIndex(out);
  }

  final List<AyahRef> ayahs;
  final Map<String, int> _byKey = {};

  int get length => ayahs.length;

  /// Flat index of `surah:ayah`, or null when the mushaf has no such ayah.
  int? indexOf(int surah, int ayah) => _byKey['$surah:$ayah'];

  /// The ayah before [i] in reading order, or null at the very start.
  AyahRef? before(int i) => i > 0 ? ayahs[i - 1] : null;

  /// Inclusive span of flat indices [range] covers, or null when the range
  /// holds no ayah.
  (int, int)? spanOf(HifzRange range) {
    final r = range.normalized();
    if (ayahs.isEmpty) return null;
    switch (r.kind) {
      case HifzRangeKind.all:
        return (0, ayahs.length - 1);
      case HifzRangeKind.surahs:
        final lo = ayahs.indexWhere((a) => a.surah == r.from);
        final hi = ayahs.lastIndexWhere((a) => a.surah == r.to);
        if (lo < 0 || hi < 0 || hi < lo) return null;
        return (lo, hi);
      case HifzRangeKind.pages:
        final lo = ayahs.indexWhere((a) => a.page >= r.from);
        final hi = ayahs.lastIndexWhere((a) => a.page <= r.to);
        if (lo < 0 || hi < 0 || hi < lo) return null;
        return (lo, hi);
      case HifzRangeKind.hizbs:
        final lo = _hizbStart(r.from);
        if (lo == null) return null;
        final next = _hizbStart(r.to + 1);
        final hi = next == null ? ayahs.length - 1 : next - 1;
        if (hi < lo) return null;
        return (lo, hi);
    }
  }

  /// Flat index of the first ayah of hizb [h] (1..60); null past the end.
  int? _hizbStart(int h) {
    for (final t in thumnEntries) {
      if (t.hizb == h) return indexOf(t.startSurah, t.startAyah);
    }
    return null;
  }
}

/// One question of a test: recite from [start] to [end] (same surah).
class HifzTestQuestion {
  const HifzTestQuestion({
    required this.start,
    required this.end,
    required this.before,
    this.targets = const [],
  });

  final AyahRef start;
  final AyahRef end;

  /// The ayah just before [start] (its ending is the cue), or null when the
  /// question opens a surah.
  final AyahRef? before;

  /// Weak points inside the question when it was built from the reciter's
  /// mistakes; empty for a random question.
  final List<TasmeeWeakPoint> targets;

  bool get fromMistakes => targets.isNotEmpty;

  int get ayahCount => end.ayah - start.ayah + 1;

  /// Words the cue quotes from the end of [before] (a long ayah is not
  /// quoted whole).
  static const int cueWords = 7;

  /// The end of the ayah before the start, as a teacher would say it:
  /// «... وَإِيَّاكَ نَسْتَعِينُ». Empty when the question opens a surah.
  String get cueTail {
    final b = before;
    if (b == null) return '';
    final words = b.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= cueWords) return words.join(' ');
    return '… ${words.sublist(words.length - cueWords).join(' ')}';
  }

  /// Where to start, as told to the reciter: the surah and ayah, and the
  /// words to continue from.
  String get where => start.ayah == 1
      ? 'سورة ${start.surahName} من أولها'
      : 'سورة ${start.surahName}، من الآية ${start.ayah}';

  /// How much to recite: «آية واحدة», «٣ آيات (٢٥–٢٧)».
  String get extent {
    final n = ayahCount;
    if (n == 1) return 'آية واحدة';
    final count = n == 2 ? 'آيتان' : '$n آيات';
    return '$count (${start.ayah}–${end.ayah})';
  }

  /// Short name for lists: «سورة البقرة، الآيات ٢٥–٢٧».
  String get title => ayahCount == 1
      ? 'سورة ${start.surahName}، الآية ${start.ayah}'
      : 'سورة ${start.surahName}، الآيات ${start.ayah}–${end.ayah}';

  /// What the page shows while the question runs (see [TasmeeDrill.cue]).
  String get cue {
    final b = before;
    return b == null
        ? '$where — $extent'
        : '$where — $extent\nبعد قوله تعالى: ﴿$cueTail﴾';
  }

  /// The question as a Tasmee session runs it: start on [start]'s page at
  /// its ayah, end once [end] is recited.
  TasmeeDrill toDrill(int index, int total) => TasmeeDrill(
        page: end.page,
        surah: end.surah,
        ayah: end.ayah,
        targets: targets,
        index: index,
        total: total,
        title: 'اختبار',
        cue: cue,
        startPage: start.page,
        startAyahIndex: start.indexOnPage,
      );
}

/// A test under way: its questions and the outcome of those answered.
class HifzTestRun {
  HifzTestRun(this.config, this.questions);

  final HifzTestConfig config;
  final List<HifzTestQuestion> questions;
  final List<TasmeeDrillResult> results = [];

  int get answered => results.length;
  int get correct => results.where((r) => r.clean).length;
}

/// Builds the questions of a test from the reciter's mistakes, at random,
/// or both.
class HifzTestPlanner {
  /// How many draws to try before giving up on filling the random part.
  static const int _tries = 200;

  static List<HifzTestQuestion> plan({
    required QuranAyahIndex index,
    required HifzTestConfig config,
    required List<TasmeeWeakPoint> pool,
    Random? random,
  }) {
    final span = index.spanOf(config.range);
    if (span == null) return const [];
    final (lo, hi) = span;
    final n = config.ayahsPerQuestion.clamp(1, 10);
    final want = config.questions.clamp(1, 50);
    final rng = random ?? Random();

    final out = <HifzTestQuestion>[];
    final used = <String>{};

    if (config.source != HifzTestSource.random) {
      final groups = _mistakeGroups(index, pool, lo, hi);
      final take = config.source == HifzTestSource.mistakes
          ? want
          : min(groups.length, (want + 1) ~/ 2);
      for (final g in groups) {
        if (out.length >= take) break;
        final t = index.indexOf(g.first.surah, g.first.ayah)!;
        final q = _questionEndingAt(index, t, n, lo, targets: g);
        if (used.add(q.start.key)) out.add(q);
      }
      if (config.source == HifzTestSource.mistakes) return out;
    }

    // Random questions fill the rest; starts are not repeated.
    var tries = 0;
    while (out.length < want && tries++ < _tries) {
      final s = lo + rng.nextInt(hi - lo + 1);
      final q = _questionStartingAt(index, s, n, hi);
      if (used.add(q.start.key)) out.add(q);
    }
    if (config.source == HifzTestSource.both) out.shuffle(rng);
    return out;
  }

  /// Weak points inside [lo]..[hi] grouped by ayah, the most-missed ayah
  /// first, then the one missed longest ago (as the drills order them).
  static List<List<TasmeeWeakPoint>> _mistakeGroups(
    QuranAyahIndex index,
    List<TasmeeWeakPoint> pool,
    int lo,
    int hi,
  ) {
    final groups = <String, List<TasmeeWeakPoint>>{};
    for (final p in pool) {
      final i = index.indexOf(p.surah, p.ayah);
      if (i == null || i < lo || i > hi) continue;
      (groups['${p.surah}:${p.ayah}'] ??= []).add(p);
    }
    final list = groups.values.toList()
      ..sort((a, b) {
        int weight(List<TasmeeWeakPoint> g) => g.fold(0, (s, p) => s + p.count);
        final w = weight(b).compareTo(weight(a));
        if (w != 0) return w;
        DateTime oldest(List<TasmeeWeakPoint> g) =>
            g.map((p) => p.lastAt).reduce((x, y) => x.isBefore(y) ? x : y);
        return oldest(a).compareTo(oldest(b));
      });
    for (final g in list) {
      g.sort((a, b) => a.word.compareTo(b.word));
    }
    return list;
  }

  /// A question of up to [n] ayahs that ends at flat index [t]: it runs up
  /// to the target from a few ayahs before it, inside the same surah and
  /// the range.
  static HifzTestQuestion _questionEndingAt(
    QuranAyahIndex index,
    int t,
    int n,
    int lo, {
    required List<TasmeeWeakPoint> targets,
  }) {
    var s = t;
    while (s - 1 >= lo &&
        index.ayahs[s - 1].surah == index.ayahs[t].surah &&
        t - s + 1 < n) {
      s--;
    }
    return HifzTestQuestion(
      start: index.ayahs[s],
      end: index.ayahs[t],
      before: _before(index, s),
      targets: targets,
    );
  }

  /// A question of up to [n] ayahs from flat index [s] on, inside the same
  /// surah and the range.
  static HifzTestQuestion _questionStartingAt(
    QuranAyahIndex index,
    int s,
    int n,
    int hi,
  ) {
    var e = s;
    while (e + 1 <= hi &&
        index.ayahs[e + 1].surah == index.ayahs[s].surah &&
        e - s + 1 < n) {
      e++;
    }
    return HifzTestQuestion(
      start: index.ayahs[s],
      end: index.ayahs[e],
      before: _before(index, s),
    );
  }

  /// The ayah before [s] when it is of the same surah (a question that
  /// opens a surah has no cue ayah).
  static AyahRef? _before(QuranAyahIndex index, int s) {
    final b = index.before(s);
    if (b == null || b.surah != index.ayahs[s].surah) return null;
    return b;
  }
}

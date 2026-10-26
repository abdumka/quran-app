import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart'
    show ValueNotifier, compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'content_update_service.dart';

/// «تنزيلات ومتشابهات»: the reader's two choices. Colouring is on by default
/// (owner's decision after the tester review); so is a colour per count.
class TanzilatSetting {
  static const String _enabledKey = 'tanzilatColorEnabled';
  static const String _byCountKey = 'tanzilatColorByCount';

  /// Colour the tanzilat words on the page.
  static final ValueNotifier<bool> enabled = ValueNotifier(true);

  /// One colour per count (غريبة, 2, 3, 4, then one colour for 5 and more), so
  /// the reader learns the count from the colour; off = everything red.
  static final ValueNotifier<bool> colorByCount = ValueNotifier(true);

  /// Testers' switch in «أدوات الاختبار»: a double tap on an ayah opens its
  /// tanzilat straight away (the long press keeps the usual options).
  static final ValueNotifier<bool> doubleTapOpensTanzilat = ValueNotifier(
    false,
  );
  static const String _doubleTapKey = 'tanzilatDoubleTapDirect';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledKey) ?? true;
    colorByCount.value = prefs.getBool(_byCountKey) ?? true;
    doubleTapOpensTanzilat.value = prefs.getBool(_doubleTapKey) ?? false;
  }

  static Future<void> setDoubleTapOpensTanzilat(bool value) async {
    doubleTapOpensTanzilat.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_doubleTapKey, value);
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  static Future<void> setColorByCount(bool value) async {
    colorByCount.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_byCountKey, value);
  }
}

/// One place of a tanzilah: the words (indices into the ayah's text split on
/// spaces, the order of `word_masks.json`) to colour in one ayah.
class TanzilahPlace {
  final int surah;
  final int ayah;
  final List<int> words;

  const TanzilahPlace(this.surah, this.ayah, this.words);
}

/// One row of «مذكرة التنزيل». Most rows are one place; a [rule] row is a
/// spelling written the same way wherever it occurs («متكررة»), so it holds
/// every place of that word.
class TanzilahRow {
  /// The memo's word, kept for [rule] rows (their title in the sheet).
  final String? word;
  final bool rule;
  final List<TanzilahPlace> places;

  /// الدنفاسي's verse about a [rule] row (a spelling rule has its own card).
  final List<DanfasiVerse> danfasi;

  const TanzilahRow({
    this.word,
    this.rule = false,
    required this.places,
    this.danfasi = const [],
  });
}

/// A verse of الدنفاسي's poem, from «دليل الناسي». It is shown on a card only
/// when the rule's own places and its word match the card's (see
/// danfasi_relink.py; sharing an ayah is not enough).
class DanfasiVerse {
  final String title;
  final List<String> lines;

  const DanfasiVerse(this.title, this.lines);
}

/// One tanzilah of the memo: its stated count and its rows.
class TanzilahGroup {
  final int id;

  /// The memo's count column: «غ» (غريبة, a single place) or a number.
  final String label;
  final List<TanzilahRow> rows;
  final List<DanfasiVerse> danfasi;

  const TanzilahGroup({
    required this.id,
    required this.label,
    required this.rows,
    this.danfasi = const [],
  });

  bool get isGharibah => label == 'غ';

  /// The memo's count as a number (1 for غريبة, 0 when unreadable).
  int get count => isGharibah ? 1 : int.tryParse(label) ?? 0;
}

/// Where one coloured word comes from.
class TanzilahHit {
  final TanzilahGroup group;
  final TanzilahRow row;

  const TanzilahHit(this.group, this.row);

  /// The count the colour stands for: the group's count, but a spelling rule
  /// counts its own places (its group's number counts words, not places).
  int get count => row.rule ? row.places.length : group.count;

  /// الدنفاسي's verses on this hit's card: a spelling rule's own, else the
  /// group's.
  List<DanfasiVerse> get danfasi => row.rule ? row.danfasi : group.danfasi;
}

/// The colour bucket of a count: 0 = غريبة, 1..3 = 2..4, 4 = five or more.
int tanzilahBucket(int count) => count <= 1 ? 0 : (count >= 5 ? 4 : count - 1);

/// Loads `assets/data/tanzilat.json` (built offline by
/// build_tanzilat_data.py from the memo, the Tanzil-app data and the tester
/// decisions) and indexes it by ayah.
class TanzilatService {
  TanzilatService._() {
    ContentUpdateService.instance.registerItem(
      'tanzilat',
      apply: reload,
      isLoaded: () => _loaded || _loading != null,
    );
  }
  static final TanzilatService instance = TanzilatService._();

  static const String _assetPath = 'assets/data/tanzilat.json';

  List<TanzilahGroup> _groups = const [];
  Map<(int, int), List<TanzilahHit>> _byAyah = const {};
  Map<(int, int), Map<int, TanzilahHit>> _words = const {};
  Map<(int, int, int), List<Rect>> _noPaint = const {};
  Future<void>? _loading;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<TanzilahGroup> get groups => _groups;

  /// Bumped when the data is swapped live (a server update), so widgets that
  /// cached anything derived from it rebuild.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  /// Re-reads the data (the downloaded file when one is newer than the
  /// asset) and swaps it in; the server-update service calls this.
  Future<void> reload() async {
    // Not loaded yet: the first load will read the new file anyway.
    if (!_loaded && _loading == null) return;
    await load();
    await _load();
    revision.value++;
  }

  Future<void> _load() async {
    try {
      // A newer file fetched from our server replaces the bundled asset.
      final jsonString =
          await ContentUpdateService.instance.readFor('tanzilat') ??
          await rootBundle.loadString(_assetPath);
      _noPaint = await compute(parseNoPaint, jsonString);
      setGroups(await compute(parseTanzilat, jsonString));
    } catch (error) {
      debugPrint('TanzilatService: failed to load $_assetPath: $error');
      setGroups(const []);
    }
  }

  /// Installs [groups] and rebuilds the indexes (the loader, and tests).
  void setGroups(List<TanzilahGroup> groups) {
    final byAyah = <(int, int), List<TanzilahHit>>{};
    final words = <(int, int), Map<int, TanzilahHit>>{};
    for (final g in groups) {
      for (final r in g.rows) {
        for (final p in r.places) {
          final key = (p.surah, p.ayah);
          final hits = byAyah.putIfAbsent(key, () => []);
          if (!hits.any((h) => h.group == g && h.row == r)) {
            hits.add(TanzilahHit(g, r));
          }
          final w = words.putIfAbsent(key, () => {});
          // A word in two groups keeps the smaller count's colour: the rarer
          // tanzilah is the one worth noticing.
          final hit = TanzilahHit(g, r);
          for (final i in p.words) {
            final old = w[i];
            if (old == null || hit.count < old.count) w[i] = hit;
          }
        }
      }
    }
    _groups = groups;
    _byAyah = byAyah;
    _words = words;
    _loaded = true;
  }

  /// The tanzilat touching one ayah (one entry per group and row), in the
  /// memo's order.
  List<TanzilahHit> forAyah(int surah, int ayah) =>
      _byAyah[(surah, ayah)] ?? const [];

  /// The coloured words of one ayah: word index -> its tanzilah.
  Map<int, TanzilahHit> wordsOf(int surah, int ayah) =>
      _words[(surah, ayah)] ?? const {};

  /// Parts of a coloured word's box that are never coloured: the «صه» stop
  /// mark above it (ratios of the 720x1640 page image, like the word boxes).
  List<Rect> noPaintOf(int surah, int ayah, int word) =>
      _noPaint[(surah, ayah, word)] ?? const [];

  /// Installs the stop-mark rectangles (the loader, and tests).
  void setNoPaint(Map<(int, int, int), List<Rect>> noPaint) =>
      _noPaint = noPaint;
}

/// The asset's `nopaint`: "s:a:i" -> [[x, y, w, h], …] in 720x1640 px — the
/// «صه» stop marks found above coloured words (find_stop_marks.py keeps only
/// the sure ones), as ratios of the page image.
Map<(int, int, int), List<Rect>> parseNoPaint(String jsonString) {
  final decoded = json.decode(jsonString) as Map<String, dynamic>;
  final out = <(int, int, int), List<Rect>>{};
  ((decoded['nopaint'] as Map<String, dynamic>?) ?? const {}).forEach((k, v) {
    final p = k.split(':').map(int.parse).toList();
    out[(p[0], p[1], p[2])] = [
      for (final r in v as List<dynamic>)
        Rect.fromLTWH(
          ((r as List<dynamic>)[0] as num) / 720,
          (r[1] as num) / 1640,
          (r[2] as num) / 720,
          (r[3] as num) / 1640,
        ),
    ];
  });
  return out;
}

/// Parses the asset (top level so it can run in a background isolate).
List<TanzilahGroup> parseTanzilat(String jsonString) {
  final decoded = json.decode(jsonString) as Map<String, dynamic>;
  // The verses once, by rule id; groups and rule rows list the ids they show.
  final verses = <String, DanfasiVerse>{
    for (final e
        in ((decoded['dan'] as Map<String, dynamic>?) ?? const {}).entries)
      e.key: DanfasiVerse((e.value as Map<String, dynamic>)['t'] as String, [
        for (final l in e.value['v'] as List<dynamic>) l as String,
      ]),
  };
  List<DanfasiVerse> versesOf(Map<String, dynamic> holder) => [
    for (final id in (holder['d'] as List<dynamic>?) ?? const [])
      ?verses[id as String],
  ];
  return [
    for (final g in decoded['groups'] as List<dynamic>)
      _group(g as Map<String, dynamic>, versesOf),
  ];
}

TanzilahGroup _group(
  Map<String, dynamic> g,
  List<DanfasiVerse> Function(Map<String, dynamic>) versesOf,
) => TanzilahGroup(
  id: g['id'] as int,
  label: g['n'] as String,
  rows: [
    for (final r in g['rows'] as List<dynamic>)
      TanzilahRow(
        word: (r as Map<String, dynamic>)['w'] as String?,
        rule: r['list'] == 1,
        danfasi: versesOf(r),
        places: [
          for (final p in r['p'] as List<dynamic>)
            TanzilahPlace((p as List<dynamic>)[0] as int, p[1] as int, [
              for (final i in p[2] as List<dynamic>) i as int,
            ]),
        ],
      ),
  ],
  danfasi: versesOf(g),
);

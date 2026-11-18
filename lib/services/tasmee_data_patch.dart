import 'dart:convert';

/// Corrections to the Tasmee pronunciation data that arrive from our server
/// after a build shipped (the `tasmee_data` item of `ContentUpdateService`,
/// built by `tools/build_tasmee_data_patch.py`):
///
///     {"ver": 2,
///      "ayahs": [{"page": 6, "key": "2:30", "w": [[text, phon, …], …]}],
///      "lexiconAdd": ["…"], "lexiconRemove": ["…"]}
///
/// `ayahs` replaces the words of whole ayat of `assets/data/page_phonemes.json`
/// (each word exactly as in that file); `lexiconAdd` / `lexiconRemove` change
/// `assets/data/phoneme_lexicon.json`. The lists are cumulative against the
/// bundles of every build that reads this item.
///
/// An ayah is replaced only on the page the bundle has it on and only when
/// the replacement has the same number of words: the page text, the word
/// boxes, the stored mistakes and the tracker all count an ayah's words the
/// same way. Anything else is left as bundled. A file that breaks a rule of
/// shape is refused as a whole ([parse]), at download and again at load.
///
/// Applied when the data is first loaded (the first Tasmee session of a
/// run), so a session never changes under the reciter.
class TasmeeDataPatch {
  const TasmeeDataPatch({
    required this.ver,
    required this.ayahs,
    required this.lexiconAdd,
    required this.lexiconRemove,
  });

  final int ver;

  /// (page, "surah:ayah") -> the ayah's words, each as in the bundle.
  final Map<(int, String), List<List<dynamic>>> ayahs;
  final Set<String> lexiconAdd;
  final Set<String> lexiconRemove;

  static const int maxAyahs = 6236;
  static const int maxLexiconChanges = 30000;
  static final RegExp _key = RegExp(r'^([1-9][0-9]{0,2}):([1-9][0-9]{0,2})$');

  /// Reads and checks a patch file. Throws [FormatException] when anything is
  /// out of shape: a half-good file is refused, never applied in part.
  static TasmeeDataPatch parse(String source) {
    final decoded = json.decode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('tasmee_data: not an object');
    }
    final ver = decoded['ver'];
    if (ver is! int) throw const FormatException('tasmee_data: no ver');
    final rawAyahs = decoded['ayahs'] ?? const [];
    if (rawAyahs is! List || rawAyahs.length > maxAyahs) {
      throw const FormatException('tasmee_data: bad ayahs');
    }
    final ayahs = <(int, String), List<List<dynamic>>>{};
    for (final a in rawAyahs) {
      if (a is! Map) throw const FormatException('tasmee_data: bad ayah');
      final page = a['page'];
      final key = a['key'];
      final words = a['w'];
      if (page is! int || page < 1 || page > 604) {
        throw const FormatException('tasmee_data: bad page');
      }
      if (key is! String || !_validKey(key)) {
        throw FormatException('tasmee_data: bad key $key');
      }
      if (words is! List || words.isEmpty) {
        throw FormatException('tasmee_data: $key has no words');
      }
      for (final w in words) {
        if (!validWord(w)) {
          throw FormatException('tasmee_data: $key has a bad word');
        }
      }
      if (ayahs.containsKey((page, key))) {
        throw FormatException('tasmee_data: $key listed twice');
      }
      ayahs[(page, key)] = [for (final w in words) List<dynamic>.of(w as List)];
    }
    Set<String> strings(Object? v, String name) {
      v ??= const [];
      if (v is! List || v.length > maxLexiconChanges) {
        throw FormatException('tasmee_data: bad $name');
      }
      final out = <String>{};
      for (final s in v) {
        if (s is! String || s.isEmpty || s.length > 64) {
          throw FormatException('tasmee_data: bad $name entry');
        }
        out.add(s);
      }
      return out;
    }

    final add = strings(decoded['lexiconAdd'], 'lexiconAdd');
    final remove = strings(decoded['lexiconRemove'], 'lexiconRemove');
    if (add.intersection(remove).isNotEmpty) {
      throw const FormatException('tasmee_data: added and removed at once');
    }
    return TasmeeDataPatch(
      ver: ver,
      ayahs: ayahs,
      lexiconAdd: add,
      lexiconRemove: remove,
    );
  }

  static bool _validKey(String key) {
    final m = _key.firstMatch(key);
    if (m == null) return false;
    final s = int.parse(m.group(1)!);
    final a = int.parse(m.group(2)!);
    return s >= 1 && s <= 114 && a >= 1 && a <= 286;
  }

  /// One word as `page_phonemes.json` stores it:
  /// `[text, phon, tanween, taMarbuta 0/1, hafsAlt, wasl 0/1, alts?, accept?]`.
  static bool validWord(Object? w) {
    if (w is! List || w.length < 6 || w.length > 8) return false;
    bool str(Object? v, {bool nonEmpty = false}) =>
        v is String && v.length <= 64 && (!nonEmpty || v.isNotEmpty);
    bool bit(Object? v) => v == 0 || v == 1;
    bool strings(Object? v) =>
        v is List && v.length <= 32 && v.every((s) => str(s, nonEmpty: true));
    if (!str(w[0], nonEmpty: true) || !str(w[1], nonEmpty: true)) return false;
    if (!str(w[2]) || !bit(w[3]) || !str(w[4]) || !bit(w[5])) return false;
    if (w.length > 6 && !strings(w[6])) return false;
    if (w.length > 7 && !strings(w[7])) return false;
    return true;
  }

  /// Lays the ayah replacements over the decoded `page_phonemes.json` (a
  /// list of `{"page", "ayahs": [{"key", "w"}]}`), in place. Returns how many
  /// ayat were replaced.
  int applyToPages(List<dynamic> pages) {
    if (ayahs.isEmpty) return 0;
    var applied = 0;
    for (final item in pages) {
      if (item is! Map<String, dynamic>) continue;
      final page = item['page'];
      final list = item['ayahs'];
      if (page is! int || list is! List) continue;
      for (final ay in list) {
        if (ay is! Map<String, dynamic>) continue;
        final key = ay['key'];
        final words = ay['w'];
        if (key is! String || words is! List) continue;
        final fix = ayahs[(page, key)];
        if (fix == null || fix.length != words.length) continue;
        ay['w'] = fix;
        applied++;
      }
    }
    return applied;
  }

  /// The lexicon entries with this patch applied.
  List<String> applyToLexicon(Iterable<String> entries) {
    final out = <String>[
      for (final e in entries)
        if (!lexiconRemove.contains(e)) e,
    ];
    final have = out.toSet();
    for (final e in lexiconAdd) {
      if (have.add(e)) out.add(e);
    }
    return out;
  }
}

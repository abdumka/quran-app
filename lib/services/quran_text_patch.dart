import 'dart:convert';

/// Spelling corrections to the Qur'an text of `assets/data/output.json` that
/// arrive from our server after a build shipped (the `quran_text` item of
/// `ContentUpdateService`, built by `tools/build_quran_text_patch.py`):
///
///     {"ver": 2, "patches": [
///       {"surah": 20, "ayah": 62,
///        "text": "<the whole corrected ayah>",
///        "from": ["<the ayah as a build we shipped carries it>", ...]}]}
///
/// The list is cumulative. It may only change the letters and marks inside
/// words, never how many words an ayah has: the word boxes, the tanzilat
/// colours, the Tasmee phonemes and the paint pictures all count the words of
/// an ayah the same way, so one word more or less would shift all of them.
/// Changes to the page layout, the ayah numbering or the pronunciation need a
/// store release.
///
/// Safety, in order of what it protects:
///   * a file that breaks any rule is refused as a whole, at download and
///     again at load ([parse]); the bundled text is used instead;
///   * an ayah is replaced only when the build's own text is one of the
///     `from` texts the fix was written against; any other text (a newer
///     build that already carries the fix, or a different one) is left
///     exactly as bundled ([apply]);
///   * whether an ayah opens with the basmala cannot change (Tasmee treats
///     such words differently), nor can anything outside the Arabic letters
///     and Qur'an marks the mushaf text already uses.
class QuranTextPatch {
  QuranTextPatch._();

  /// More than this many ayat is not a list of spelling fixes.
  static const int maxEntries = 1000;

  /// The basmala as `MemorizationTestService.embeddedBasmalaLength` compares
  /// it (a test keeps the two in step).
  static const List<String> basmalaWords = ['بسم', 'الله', 'الرحمن', 'الرحيم'];
  static final RegExp _tashkeel = RegExp(r'[ؐ-ًؚ-ٰٟۖ-ۭـ]');

  /// The characters an ayah may contain: a space between words, the Arabic
  /// letters and harakat, superscript alef, the Qur'an annotation marks.
  /// Never digits (Eastern or Western), the ayah-end sign U+06DD, the hizb
  /// sign U+06DE, punctuation, control or direction characters.
  static bool allowedChar(int u) =>
      u == 0x20 ||
      (u >= 0x0621 && u <= 0x065F) ||
      u == 0x0670 ||
      u == 0x06D2 ||
      (u >= 0x06D6 && u <= 0x06DC) ||
      (u >= 0x06DF && u <= 0x06ED);

  /// Words separated by exactly one space, no space at either end, only
  /// [allowedChar] characters. Then splitting on ' ' and on `\s+` give the
  /// same words, as every reader of the text expects.
  static bool wellFormed(String text) {
    if (text.isEmpty || text.startsWith(' ') || text.endsWith(' ')) {
      return false;
    }
    if (text.contains('  ')) return false;
    for (final u in text.runes) {
      if (!allowedChar(u)) return false;
    }
    return true;
  }

  static int wordCount(String text) => text.split(' ').length;

  /// True when [text] begins with the four words of the basmala.
  static bool opensWithBasmala(String text) {
    final words = text.split(' ');
    if (words.length < basmalaWords.length) return false;
    for (var i = 0; i < basmalaWords.length; i++) {
      final bare = words[i].replaceAll(_tashkeel, '').replaceAll('ٱ', 'ا');
      if (bare != basmalaWords[i]) return false;
    }
    return true;
  }

  /// Reads and checks a patch file. Throws [FormatException] when any entry
  /// breaks a rule: a half-good file is refused, never applied in part.
  static List<QuranTextFix> parse(String source) {
    final decoded = json.decode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('quran_text: not an object');
    }
    if (decoded['ver'] is! int) {
      throw const FormatException('quran_text: no ver');
    }
    final patches = decoded['patches'];
    if (patches is! List) {
      throw const FormatException('quran_text: no patches');
    }
    if (patches.length > maxEntries) {
      throw const FormatException('quran_text: too many patches');
    }
    final fixes = <QuranTextFix>[];
    final seen = <(int, int)>{};
    for (final p in patches) {
      if (p is! Map) throw const FormatException('quran_text: bad patch');
      final surah = p['surah'];
      final ayah = p['ayah'];
      final text = p['text'];
      final from = p['from'];
      if (surah is! int || surah < 1 || surah > 114) {
        throw const FormatException('quran_text: bad surah');
      }
      if (ayah is! int || ayah < 1 || ayah > 286) {
        throw const FormatException('quran_text: bad ayah');
      }
      final where = '$surah:$ayah';
      if (!seen.add((surah, ayah))) {
        throw FormatException('quran_text: $where listed twice');
      }
      if (text is! String || !wellFormed(text)) {
        throw FormatException('quran_text: $where bad text');
      }
      if (from is! List || from.isEmpty) {
        throw FormatException('quran_text: $where has no "from"');
      }
      final words = wordCount(text);
      final basmala = opensWithBasmala(text);
      final olds = <String>[];
      for (final old in from) {
        if (old is! String || !wellFormed(old) || old == text) {
          throw FormatException('quran_text: $where bad "from"');
        }
        if (wordCount(old) != words) {
          throw FormatException('quran_text: $where changes the word count');
        }
        if (opensWithBasmala(old) != basmala) {
          throw FormatException('quran_text: $where changes the basmala');
        }
        olds.add(old);
      }
      fixes.add(QuranTextFix(surah: surah, ayah: ayah, text: text, from: olds));
    }
    return fixes;
  }

  /// Lays [fixes] over the decoded pages of `output.json` (a list of
  /// `{"page", "ayahs": [{"surah", "ayah", "text", ...}]}` maps), in place.
  /// Only the `text` of a matching ayah changes, and only when its bundled
  /// text is one of the fix's `from` texts. Every change is decided before
  /// the first one is made.
  static QuranTextPatchStats apply(
    List<dynamic> pages,
    List<QuranTextFix> fixes,
  ) {
    final byKey = {for (final f in fixes) (f.surah, f.ayah): f};
    final changes = <(Map<String, dynamic>, String)>[];
    var already = 0;
    var skipped = 0;
    final found = <(int, int)>{};
    for (final page in pages) {
      if (page is! Map<String, dynamic>) continue;
      final ayahs = page['ayahs'];
      if (ayahs is! List) continue;
      for (final a in ayahs) {
        if (a is! Map<String, dynamic>) continue;
        final key = (a['surah'], a['ayah']);
        final fix = byKey[key];
        if (fix == null) continue;
        found.add((fix.surah, fix.ayah));
        final current = a['text'];
        if (current is! String) {
          skipped++;
        } else if (current == fix.text) {
          already++;
        } else if (fix.from.contains(current) &&
            wordCount(current) == wordCount(fix.text)) {
          changes.add((a, fix.text));
        } else {
          skipped++;
        }
      }
    }
    for (final (ayah, text) in changes) {
      ayah['text'] = text;
    }
    return QuranTextPatchStats(
      applied: changes.length,
      already: already,
      skipped: skipped + (fixes.length - found.length),
    );
  }
}

class QuranTextFix {
  const QuranTextFix({
    required this.surah,
    required this.ayah,
    required this.text,
    required this.from,
  });

  final int surah;
  final int ayah;
  final String text;
  final List<String> from;
}

class QuranTextPatchStats {
  const QuranTextPatchStats({
    required this.applied,
    required this.already,
    required this.skipped,
  });

  /// Ayat whose text was replaced.
  final int applied;

  /// Ayat this build already carries in the corrected form.
  final int already;

  /// Ayat left as bundled: not found, or a text the fix was not written for.
  final int skipped;

  @override
  String toString() => 'applied $applied, already $already, skipped $skipped';
}

/// Lets search ignore whether a phrase is written joined or separated.
///
/// The Uthmani rasm joins some word pairs in one place and separates the
/// same pair in another (أَيْنَمَا / أَيْنَ مَا, مِمَّا / مِن مَّا,
/// كُلَّمَا / كُلَّ مَا), and it attaches the vocative يا to its noun
/// (يَٰقَوْمِ, يَٰٓأَيُّهَا). Someone typing «يا قوم» or «أينما» should not
/// have to know which form a given ayah uses.
///
/// Both sides are brought to the separated form. [splitText] rewrites an
/// ayah and can read its diacritics, so «أَلَّا» ("that … not") splits into
/// «أن لا» while «إِلَّا» ("except") stays. [splitQuery] rewrites what was
/// typed, which has no diacritics, so it only splits forms that can mean one
/// thing. The search page uses these for whole-phrase matches only, never for
/// its fuzzy word scoring, so «من ما» does not pull in every ayah that merely
/// contains من and ما.
///
/// Every function takes and returns text in the search page's normalized
/// form (no diacritics, one alef, ي for ى/ئ, و for ؤ).
library;

/// Joined forms whose letters can only mean one thing, with their separated
/// spelling.
const Map<String, String> _joinedForms = {
  'اينما': 'اين ما',
  'كلما': 'كل ما',
  'بيسما': 'بيس ما',
  'فيما': 'في ما',
  'حيثما': 'حيث ما',
  'انما': 'ان ما',
  'مما': 'من ما',
  'عما': 'عن ما',
  'عمن': 'عن من',
  'ممن': 'من من',
  'لكيلا': 'لكي لا',
  'نعما': 'نعم ما',
  'ويكان': 'وي كان',
  'ويكانه': 'وي كانه',
  'يبنوم': 'يا ابن ام', // يَبْنَؤُمَّ (20:92)
};

/// Joined forms that need the ayah's diacritics to be told apart from a
/// look-alike: أَلَّا vs إِلَّا, أَمَّن vs ءَامَنَ, فَإِلَّمْ vs فَأَلَمْ.
const Map<String, String> _markedJoinedForms = {
  'الا': 'ان لا',
  'الن': 'ان لن',
  'امن': 'ام من',
  'الم': 'ان لم',
};

/// Conjunctions that may sit in front of a joined form (وَمِمَّا, فَأَيْنَمَا).
const List<String> _prefixes = ['', 'و', 'ف'];

/// The vocative يا written onto its noun: ي + fatha + dagger alef, with an
/// optional maddah, after an optional و/ف.
final RegExp _attachedVocative = RegExp(
  '^([وف]َ?)?يَٰٓ?',
);

String? _splitJoined(String word) {
  for (final prefix in _prefixes) {
    if (!word.startsWith(prefix)) continue;
    final split = _joinedForms[word.substring(prefix.length)];
    if (split != null) return '$prefix$split';
  }
  return null;
}

String? _splitMarked(String original, String word) {
  if (!original.contains('ّ')) return null; // every one carries a shadda
  for (final prefix in _prefixes) {
    if (!word.startsWith(prefix)) continue;
    final rest = word.substring(prefix.length);
    final split = _markedJoinedForms[rest];
    if (split == null) continue;
    // أَلَّا / أَلَّن / أَمَّن start with hamza on alef; فَإِلَّمْ with hamza under.
    final hamza = rest == 'الم' ? 'إ' : 'أ';
    if (original.contains(hamza)) return '$prefix$split';
  }
  return null;
}

String? _splitVocative(String original, String Function(String) normalize) {
  final match = _attachedVocative.firstMatch(original);
  if (match == null) return null;
  final rest = normalize(original.substring(match.end));
  if (rest.isEmpty) return null;
  // Built by hand: normalizing «يَٰ» alone would drop its final dagger alef.
  final prefix = match.group(1)?.substring(0, 1) ?? '';
  const vocative = 'يا';
  return '$prefix$vocative $rest';
}

/// [text] (an ayah, with its diacritics) normalized word by word with
/// [normalize], with every joined form written separated.
String splitText(String text, String Function(String) normalize) {
  final words = <String>[];
  for (final original in text.split(RegExp(r'\s+'))) {
    final word = normalize(original);
    if (word.isEmpty) continue;
    words.add(
      _splitVocative(original, normalize) ??
          _splitMarked(original, word) ??
          _splitJoined(word) ??
          word,
    );
  }
  return words.join(' ');
}

/// A normalized [query] with its unambiguous joined forms written separated.
String splitQuery(String query) => query
    .split(' ')
    .where((word) => word.isNotEmpty)
    .map((word) => _splitJoined(word) ?? word)
    .join(' ');

/// A normalized [query] with separated pairs written joined, the reverse of
/// [splitQuery] (also for the forms only [splitText] produces). Used to find
/// what to highlight in an ayah that spells the phrase joined.
String joinQuery(String query) {
  var joined = ' $query ';
  for (final forms in [_joinedForms, _markedJoinedForms]) {
    forms.forEach((join, split) {
      for (final prefix in _prefixes) {
        joined = joined.replaceAll(' $prefix$split ', ' $prefix$join ');
      }
    });
  }
  return joined.trim();
}

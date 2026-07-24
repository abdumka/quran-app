/// Shared Arabic text normalization for comparing Qur'an text across
/// different spelling/diacritic conventions -- e.g. this app's Qaloon mushaf
/// orthography vs. a generic Arabic speech-recognition model's output, or a
/// user's raw search query vs. the mushaf text. Strips diacritics/quranic
/// annotation marks and unifies letter variants (alef forms, ya forms, waw
/// hamza, ta marbuta) so two spellings of "the same" word compare equal.
///
/// Extracted from `search_page.dart`'s original `_normalizeText`/
/// `_normalizeChar` (which now delegate here) so other features -- notably
/// the memorization-test recitation aligner -- can reuse the exact same
/// rules without duplicating them.
///
/// Uses `\uXXXX` escapes (rather than literal Arabic characters) throughout
/// for the character-class regex and switch cases, so the exact code points
/// are unambiguous in source.
library;

final RegExp _diacriticsPattern = RegExp(
  r'[\u0610-\u061A\u064B-\u065F\u06D6-\u06ED]',
);

/// Normalizes a full string: strips diacritics/quranic symbols, unifies
/// alef/ya/waw/ta-marbuta variants, removes tatweel/standalone hamza/commas,
/// and collapses whitespace.
String normalizeArabicText(String text) {
  return text
      // Normalize Alef Wasla (U+0671)
      .replaceAll('ٱ', 'ا')
      // Normalize Small/dagger Alef (U+0670) to regular Alef
      .replaceAll('ٰ', 'ا')
      // Remove all diacritics and quranic symbols
      .replaceAll(_diacriticsPattern, '')
      // Remove Tatweel (U+0640)
      .replaceAll('ـ', '')
      // Normalize Alef variations (hamza-above U+0623, hamza-below U+0625,
      // madda-above U+0622) to plain Alef (U+0627)
      .replaceAll(RegExp('[أإآ]'), 'ا')
      // Normalize Ya variations (alef maksura U+0649, yeh barree U+06D2,
      // yeh with hamza U+0626) to plain Ya (U+064A)
      .replaceAll(RegExp('[ىےئ]'), 'ي')
      // Normalize Waw with Hamza (U+0624) to plain Waw (U+0648)
      .replaceAll('ؤ', 'و')
      // Normalize Ta Marbuta (U+0629) to Ha (U+0647)
      .replaceAll('ة', 'ه')
      // Remove standalone Hamza (U+0621)
      .replaceAll('ء', '')
      // Remove Arabic comma (U+060C)
      .replaceAll('،', '')
      // Remove extra spaces
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Normalizes a single character using the same rules as
/// [normalizeArabicText]. Returns `null` when the character should be
/// dropped entirely (diacritics, tatweel, standalone hamza, commas), `' '`
/// for whitespace, or the normalized replacement character otherwise.
String? normalizeArabicChar(String char) {
  if (char.trim().isEmpty) return ' ';

  final code = char.codeUnitAt(0);
  if (code == 0x0670) return 'ا'; // Small/dagger Alef

  final isDiacritic =
      (code >= 0x0610 && code <= 0x061A) ||
      (code >= 0x064B && code <= 0x065F) ||
      (code >= 0x06D6 && code <= 0x06ED);
  if (isDiacritic) return null;

  switch (code) {
    case 0x0640: // Tatweel
    case 0x060C: // Arabic comma
    case 0x0621: // Standalone Hamza
      return null; // Ignore these entirely
    case 0x0623: // Alef with Hamza above
    case 0x0625: // Alef with Hamza below
    case 0x0622: // Alef with Madda above
    case 0x0671: // Alef Wasla
      return 'ا'; // Alef
    case 0x0649: // Alef Maksura
    case 0x06D2: // Yeh Barree
    case 0x0626: // Yeh with Hamza above
      return 'ي'; // Ya
    case 0x0624: // Waw with Hamza above
      return 'و'; // Waw
    case 0x0629: // Ta Marbuta
      return 'ه'; // Ha
    default:
      return char;
  }
}

/// Normalizes [text] and splits it into non-empty words. Convenience used by
/// callers that just want a word list (e.g. the recitation aligner) rather
/// than the normalized string itself.
List<String> normalizedArabicWords(String text) => normalizeArabicText(
  text,
).split(' ').where((word) => word.isNotEmpty).toList();

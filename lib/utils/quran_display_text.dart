/// Makes the app's Qaloon text (`assets/data/output.json`) render correctly
/// in ordinary fonts.
///
/// The text is in the KFGQPC encoding, which only the KFGQPC mushaf font
/// draws as intended. Every system font (Android, iOS, TV, browsers) draws the
/// real Unicode glyphs instead, so these come out wrong:
///
/// * Open (successive) tanween, stored as
///   U+0657 ARABIC INVERTED DAMMA      → fathatan (looks like "6"),
///   U+065E ARABIC FATHA WITH TWO DOTS → dammatan (looks like "%"),
///   U+0656 ARABIC SUBSCRIPT ALEF      → kasratan (a stray stroke).
/// * Alef maqsura, stored as a dotted ya U+064A: عِيسَي، عَلَيٰ، هُديٗ.
/// * A real ya that carries no vowel of its own, stored as
///   U+06D2 YEH BARREE (the Urdu "ے"): فِے، شَےْءٍ.
///
/// So any plain-text display of Qur'an text — search results, the tafsir
/// sheet, copied/shared text, Tasmee messages — goes through
/// [quranDisplayText] first. Every replacement is 1:1, so string length and
/// character offsets are unchanged. Only *display* strings should be
/// converted: Tasmee matches words against `page_phonemes.json`, which keeps
/// the original encoding.
///
/// Tanween maps to the standard marks rather than U+08F0–08F2 (the proper
/// open-tanween code points): iOS and older Android fonts don't reliably
/// cover those, and a missing mark shows as a dotted circle.
library;

final RegExp _openTanween = RegExp('[\u0656\u0657\u065E]');

// Marks an alef maqsura may carry without being a real ya: dagger alef,
// madda, fathatan (standard and open) and the Quranic annotation marks.
const String _maqsuraMarks = '\u0670\u0653\u064B\u0657\u06D6-\u06ED';

// What may not follow those marks at the end of a word: a letter or any
// other mark (a vowel on the ya makes it a real ya: عَلَيَّ، هُدِيَ، إِنِّيَ).
const String _letterOrMark = '\u0621-\u065F\u0670-\u06D3\u06D6-\u06ED\u06FA-\u06FF';

/// A dotted ya that is really an alef maqsura:
/// * after a fatha, with no vowel of its own, at the end of the word
///   (عَلَي، مُوسَيٰ، ٱلْقَتْلَيۖ) or carrying a dagger alef mid-word
///   (سَوَّيٰهُنَّ، ٱلتَّوْرَيٰةَ); or
/// * carrying fathatan at the end of the word (هُديٗ، مُّسَمّيٗ).
/// Real final ya after a fatha always has a vowel or sukun here (يَدَےْ uses
/// the yeh barree), so it is never matched. Checked against every ayah:
/// 2,910 words converted, none of them a real ya.
final RegExp _maqsura = RegExp(
  '(?<=\u064E\u0651?)\u064A(?=\u0670|[$_maqsuraMarks]*(?![$_letterOrMark]))'
  '|\u064A(?=[\u064B\u0657][$_maqsuraMarks]*(?![$_letterOrMark]))',
);

// A yeh barree, plus the hamza-below it takes in اِمْرِےٕ — which, on a
// normal ya, reads as the ordinary ئ (hamza above).
final RegExp _yehBarree = RegExp('\u06D2\u0655?');

/// A count with its noun in the right Arabic form: «سؤال واحد», «سؤالان»,
/// «3 أسئلة» (3–10, plural) and «11 سؤالًا» (11 and up, singular accusative).
/// [one] and [two] are whole phrases; [few] is the plural; [many] the
/// accusative singular. Zero reads like the plural («0 أسئلة»).
String arabicCount(int n, {required String one, required String two, required String few, required String many}) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n >= 3 && n <= 10) return '$n $few';
  if (n == 0) return '$n $few';
  return '$n $many';
}

String questionsCount(int n) =>
    arabicCount(n, one: 'سؤال واحد', two: 'سؤالان', few: 'أسئلة', many: 'سؤالًا');
String ayatCount(int n) =>
    arabicCount(n, one: 'آية واحدة', two: 'آيتان', few: 'آيات', many: 'آية');
String athmanCount(int n) =>
    arabicCount(n, one: 'ثمن واحد', two: 'ثمنان', few: 'أثمان', many: 'ثمنًا');
String pagesCount(int n) =>
    arabicCount(n, one: 'صفحة واحدة', two: 'صفحتان', few: 'صفحات', many: 'صفحة');
String notesCount(int n) =>
    arabicCount(n, one: 'ملاحظة واحدة', two: 'ملاحظتان', few: 'ملاحظات', many: 'ملاحظة');
String placesCount(int n) =>
    arabicCount(n, one: 'موضع واحد', two: 'موضعان', few: 'مواضع', many: 'موضعًا');

String quranDisplayText(String text) {
  return fixOpenTanween(text)
      .replaceAll(_maqsura, '\u0649')
      .replaceAllMapped(
        _yehBarree,
        (m) => m[0]!.length == 1 ? '\u064A' : '\u064A\u0654',
      );
}

// A few alef-maqsura typos in the tafsir sources, fixed only as whole,
// undiacritized words: موسي بن عقبة (al-Tabari), يونس بن متي (al-Qurtubi),
// قال تعالي (al-Sa'di, Zad al-Masir), حتي… A vowelled تَعَالَيْ is a real
// imperative and never matches (its marks break the word).
final RegExp _tafsirMaqsuraTypos = RegExp(
  '(?<![\u0621-\u065F\u0670])(موس|عيس|حت|مت)ي(?![\u0621-\u065F\u0670])'
  '|(?<=(?:قال|قوله|الله|سبحانه|بين) )(تعال)ي(?![\u0621-\u065F\u0670])',
);

/// Tafsir text for display: [fixOpenTanween] plus the typo fixes above. The
/// full [quranDisplayText] must not run on prose — its alef-maqsura rule is
/// for the vowelled mushaf text only.
String tafsirDisplayText(String text) {
  return fixOpenTanween(text).replaceAllMapped(
    _tafsirMaqsuraTypos,
    (m) => '${m[1] ?? m[2]}\u0649',
  );
}

/// Only the tanween part of [quranDisplayText], for text that is not in the
/// KFGQPC encoding throughout — e.g. tafsir prose that quotes a few ayat in
/// it (al-Muyassar).
String fixOpenTanween(String text) {
  if (!_openTanween.hasMatch(text)) return text;
  return text.replaceAllMapped(_openTanween, (m) {
    switch (m[0]!.codeUnitAt(0)) {
      case 0x0657:
        return '\u064B'; // fathatan
      case 0x065E:
        return '\u064C'; // dammatan
      default:
        return '\u064D'; // kasratan
    }
  });
}

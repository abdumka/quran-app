/// Makes the app's Qaloon text (`assets/data/output.json`) render correctly
/// in ordinary fonts.
///
/// The text is in the KFGQPC encoding, which stores the "open" (successive)
/// tanween as code points that only the KFGQPC mushaf font draws as tanween:
///
///   U+0657 ARABIC INVERTED DAMMA        → open fathatan  (looks like "6")
///   U+065E ARABIC FATHA WITH TWO DOTS   → open dammatan  (looks like "%")
///   U+0656 ARABIC SUBSCRIPT ALEF        → open kasratan  (a stray stroke)
///
/// Every system font (Android, iOS, TV, browsers) draws their real Unicode
/// glyphs instead, so any plain-text display of Qur'an text — search results,
/// the tafsir sheet, copied/shared text, Tasmee messages — goes through
/// [quranDisplayText] first. They map to the standard tanween marks, which
/// every font renders. (U+08F0–08F2, the proper open-tanween code points, are
/// not reliably covered by iOS or older Android fonts, and a missing mark
/// shows as a dotted circle, which is worse.)
///
/// The mapping is 1:1, so string length and character offsets are unchanged
/// (search highlighting relies on that). Only *display* strings should be
/// converted: Tasmee matches words against `page_phonemes.json`, which keeps
/// the original encoding.
library;

final RegExp _openTanween = RegExp('[\u0656\u0657\u065E]');

String quranDisplayText(String text) {
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

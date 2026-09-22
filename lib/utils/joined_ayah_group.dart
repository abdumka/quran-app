import '../models/quran_page_data.dart';

/// The ayat one clip recites: [head] plus the ayat right after it that have
/// no audio of their own because the reciter joins them to it in one breath
/// (الوقف الهبطي: Doukali, Qaniwah, Abu Sneineh...). Used to highlight the
/// whole group while its single clip plays, instead of leaving the highlight
/// on the first ayah while the voice has moved on.
///
/// [following] is what comes after [head] in reading order (it may run over
/// page turns) and [joinedToPrevious] says whether an ayah is recited inside
/// the clip before it. The walk is deliberately timid, because a wrong
/// highlight is worse than a short one. It stops:
///  * at the first ayah that is not joined,
///  * at the end of the surah (a breath never carries over a basmala),
///  * at any gap in the numbering (unexpected data),
///  * after [maxLength] ayat.
/// An ayah printed across a page turn is listed on both pages; the repeat is
/// skipped.
List<QuranAyahData> joinedAyahGroup(
  QuranAyahData head,
  Iterable<QuranAyahData> following,
  bool Function(QuranAyahData ayah) joinedToPrevious, {
  int maxLength = 40,
}) {
  final group = <QuranAyahData>[head];
  for (final next in following) {
    final last = group.last;
    if (next.surah == last.surah && next.ayah == last.ayah) continue;
    if (next.surah != head.surah || next.ayah != last.ayah + 1) break;
    if (group.length >= maxLength || !joinedToPrevious(next)) break;
    group.add(next);
  }
  return group;
}

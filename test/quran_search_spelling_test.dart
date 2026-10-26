import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/search_page.dart';
import 'package:islamic_dawah_mushaf/services/quran_json_service.dart';
import 'package:islamic_dawah_mushaf/utils/quran_search_spelling.dart';

/// Search treats joined and separated spellings alike (أينما / أين ما,
/// مما / من ما, يَٰقَوْمِ / يا قوم), and output.json writes the four
/// disputed joinings the way the printed Libyan mushaf does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> texts; // "s:a" -> original ayah text

  setUpAll(() async {
    texts = {
      for (final page in await QuranJsonService.loadQuranPages())
        for (final ayah in page.ayahs) '${ayah.surah}:${ayah.ayah}': ayah.text,
    };
  });

  String exact(String text) => normalizeSearchText(text, exact: true);

  bool containsWholeWord(String text, String query) {
    var start = 0;
    while (true) {
      final i = text.indexOf(query, start);
      if (i == -1) return false;
      final end = i + query.length;
      if ((i == 0 || text[i - 1] == ' ') &&
          (end == text.length || text[end] == ' ')) {
        return true;
      }
      start = i + 1;
    }
  }

  /// The ayat the search page lists as full-phrase matches for [typed].
  Set<String> hits(String typed) {
    final query = exact(typed);
    final split = splitQuery(query);
    return {
      for (final entry in texts.entries)
        if ([exact(entry.value), splitText(entry.value, exact)].any(
          (text) => [query, split].any((q) => containsWholeWord(text, q)),
        ))
          entry.key,
    };
  }

  test('the four joinings follow the print', () {
    // Compared normalized: the KFGQPC text writes ئ as ي + hamza above.
    expect(exact(texts['2:92']!), contains('قل بيس ما يامركم'));
    expect(exact(texts['4:77']!), startsWith('اين ما تكونوا'));
    expect(exact(texts['23:44']!), contains('كلما جا'));
    expect(exact(texts['33:61']!), contains('اين ما ثقفوا'));
  });

  test('أين ما and أينما find the same ayat', () {
    final separated = hits('أين ما');
    expect(separated, hits('أينما'));
    expect(separated, containsAll(['4:77', '16:76', '26:92', '33:61']));
    expect(separated, hasLength(11)); // 2:114 is فأينما, a different word
  });

  test('assimilated pairs match both ways', () {
    expect(hits('من ما'), containsAll(['30:27', '4:11', '63:10']));
    expect(hits('مما'), containsAll(['30:27', '63:10']));
    expect(hits('عما'), contains('7:166')); // عَن مَّا نُهُواْ
    expect(hits('أم من يجيب'), contains('27:64')); // أَمَّنْ يُجِيبُ
    expect(hits('فإن لم يستجيبوا'), containsAll(['11:14', '28:50']));
    expect(hits('أن لا'), contains('2:227')); // أَلَّا يُقِيمَا
    expect(hits('كل ما'), containsAll(['4:90', '23:44', '5:66']));
    expect(hits('قل بئسما'), contains('2:92'));
  });

  test('the attached vocative يا is found as typed', () {
    expect(hits('يا قوم'), contains('2:53'));
    expect(hits('يا أيها الذين ءامنوا'), contains('2:103'));
    expect(hits('يا آدم'), contains('2:32'));
    expect(hits('يا ابن أم'), contains('20:92')); // يَبْنَؤُمَّ
  });

  test('إلا does not pick up ألّا through its diacritics', () {
    // Only a typed «أن لا» reaches ألّا through the spelling forms; إلا's
    // own matches are the plain ones, unchanged.
    final query = exact('إلا');
    expect(splitQuery(query), query);
    expect(splitText('إِلَّا', exact), 'الا');
    expect(splitText('أَلَّا', exact), 'ان لا');
  });

  test('query spelling helpers', () {
    expect(splitQuery('فاينما توجهوا'), 'فاين ما توجهوا');
    expect(joinQuery('من ما'), 'مما');
    expect(joinQuery('فاين ما'), 'فاينما');
    expect(joinQuery('ان لا'), 'الا');
  });
}

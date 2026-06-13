import 'dart:convert';
import 'dart:io';

void main() async {
  final qalonFile = File('assets/data/output.json');
  final qalonJsonStr = await qalonFile.readAsString();
  final qalonDecoded = jsonDecode(qalonJsonStr);

  final List<dynamic> qalonData = [];
  for (final item in qalonDecoded) {
    if (item is List) qalonData.addAll(item);
    else qalonData.add(item);
  }

  List<String> qalonAyahs = [];
  for (var page in qalonData) {
    for (var ayah in page['ayahs']) {
      if (ayah['surah'] == 27) {
        qalonAyahs.add(ayah['text']);
      }
    }
  }

  final url = Uri.parse('http://api.alquran.cloud/v1/surah/27');
  final request = await HttpClient().getUrl(url);
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  final hafsDecoded = jsonDecode(responseBody);
  
  List<String> hafsAyahs = [];
  for (var a in hafsDecoded['data']['ayahs']) {
    hafsAyahs.add(a['text']);
  }

  String normalize(String text) {
    // Remove diacritics (tashkeel) and spaces
    return text.replaceAll(RegExp(r'[\u0617-\u061A\u064B-\u0652\s]'), '');
  }

  int q = 0;
  int h = 0;
  while (q < qalonAyahs.length && h < hafsAyahs.length) {
    String qText = normalize(qalonAyahs[q]);
    String hText = normalize(hafsAyahs[h]);
    
    if (h == 0 && hText.startsWith("بِسْمِٱللَّهِٱلرَّحْمَٰنِٱلرَّحِيمِ".replaceAll(RegExp(r'[\u0617-\u061A\u064B-\u0652\s]'), ''))) {
      hText = hText.substring("بِسْمِٱللَّهِٱلرَّحْمَٰنِٱلرَّحِيمِ".replaceAll(RegExp(r'[\u0617-\u061A\u064B-\u0652\s]'), '').length);
    }
    
    // Quick heuristic: length comparison
    if ((qText.length - hText.length).abs() < 10) {
      // Roughly equal length -> Match
      q++; h++;
    } else if (qText.length < hText.length - 10) {
      // Qalon is much shorter -> Split
      print("SPLIT: Qalon ${q + 1} and ${q + 2} = Hafs ${h + 1}");
      q += 2;
      h += 1;
    } else if (hText.length < qText.length - 10) {
      // Hafs is much shorter -> Merge
      print("MERGE: Qalon ${q + 1} = Hafs ${h + 1} and ${h + 2}");
      q += 1;
      h += 2;
    } else {
      q++; h++;
    }
  }
}

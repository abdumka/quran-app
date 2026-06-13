import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void checkSurah(int surahNum, List<dynamic> flattened, Map<int, String> allHafs) {
  final qalonAyahs = <int, String>{};
  for (final page in flattened) {
    for (final a in (page['ayahs'] as List)) {
      if (a['surah'] == surahNum) {
        qalonAyahs[a['ayah'] as int] = a['text'] as String;
      }
    }
  }

  final hafsAyahs = <int, String>{};
  for (int i = 1; i <= 300; i++) {
     if (allHafs.containsKey(surahNum * 1000 + i)) {
         hafsAyahs[i] = allHafs[surahNum * 1000 + i]!;
     }
  }

  print("\n--- Surah $surahNum (Qalon: ${qalonAyahs.length}, Hafs: ${hafsAyahs.length}) ---");
  int q = 1;
  int h = 1;
  while (q <= qalonAyahs.length && h <= hafsAyahs.length) {
    int qLen = qalonAyahs[q]!.length;
    int hLen = hafsAyahs[h]!.length;
    
    if ((qLen - hLen).abs() > 20) {
      bool resolved = false;
      
      // Try Merge
      if (h < hafsAyahs.length) {
         int hNextLen = hafsAyahs[h+1]!.length;
         if ((qLen - (hLen + hNextLen)).abs() < 20) {
             print("  => Merge: Qalon $q matches Hafs $h + ${h+1}");
             q++; h += 2; resolved = true;
         }
      }
      
      // Try Split
      if (!resolved && q < qalonAyahs.length) {
          int qNextLen = qalonAyahs[q+1]!.length;
          if ((hLen - (qLen + qNextLen)).abs() < 20) {
             print("  => Split: Hafs $h matches Qalon $q + ${q+1}");
             q += 2; h++; resolved = true;
          }
      }
      
      // Try Merge 3
      if (!resolved && h < hafsAyahs.length - 1) {
         int hNextLen = hafsAyahs[h+1]!.length;
         int hNext2Len = hafsAyahs[h+2]!.length;
         if ((qLen - (hLen + hNextLen + hNext2Len)).abs() < 20) {
             print("  => Merge 3: Qalon $q matches Hafs $h + ${h+1} + ${h+2}");
             q++; h += 3; resolved = true;
         }
      }

      if (!resolved) {
          print('  [!] Unresolved at Qalon $q, Hafs $h');
          q++; h++;
      }
    } else {
      q++; h++;
    }
  }
}

void main() async {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  final flattened = <dynamic>[];
  for (final item in data) {
    if (item is List) { flattened.addAll(item); } else { flattened.add(item); }
  }

  final response = await http.get(Uri.parse('https://api.alquran.cloud/v1/quran/quran-uthmani'));
  final hafsData = json.decode(response.body);
  final allHafs = <int, String>{};
  for (final surah in hafsData['data']['surahs']) {
      for (final ayah in surah['ayahs']) {
          allHafs[surah['number'] * 1000 + ayah['numberInSurah']] = ayah['text'];
      }
  }

  checkSurah(24, flattened, allHafs);
  checkSurah(38, flattened, allHafs);
}

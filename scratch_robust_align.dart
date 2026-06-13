import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

String normalize(String text) {
  return text
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06E5\u06E6\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED]'), '') // Remove diacritics
      .replaceAll(RegExp(r'[أإآ]'), 'ا') // Normalize Alifs
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ے', 'ي')
      .replaceAll('ئ', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll(RegExp(r'\s+'), '') // Remove all whitespace to compare pure characters
      .replaceAll('ۖ', '').replaceAll('ۗ', '').replaceAll('ۘ', '').replaceAll('ۙ', '').replaceAll('ۚ', '').replaceAll('ۛ', '');
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
  final allHafs = <int, List<String>>{};
  for (final surah in hafsData['data']['surahs']) {
      List<String> ayahs = [];
      for (final ayah in surah['ayahs']) {
          ayahs.add(normalize(ayah['text']));
      }
      // Handle Basmalah
      if (surah['number'] != 1 && surah['number'] != 9 && ayahs[0].startsWith(normalize('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ'))) {
          ayahs[0] = ayahs[0].substring(normalize('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ').length);
      }
      allHafs[surah['number']] = ayahs;
  }

  final qalonCounts = {
      2:285, 5:122, 6:167, 8:76, 9:130, 13:44, 14:54, 23:119, 27:95, 37:181,
      39:72, 40:84, 41:53, 42:50, 44:56, 45:36, 46:34, 47:39, 52:47, 53:61,
      55:77, 56:99, 57:28, 71:30, 75:39, 79:45, 80:41, 81:28, 86:16, 89:32,
      91:16, 96:20, 101:10, 106:5, 107:6
  };

  for (final surahNum in qalonCounts.keys) {
      final qalonAyahs = <String>[];
      for (final page in flattened) {
        for (final a in (page['ayahs'] as List)) {
          if (a['surah'] == surahNum) {
            qalonAyahs.add(normalize(a['text'] as String));
          }
        }
      }

      final hafsAyahs = allHafs[surahNum]!;
      
      print('\n--- Surah $surahNum (Qalon: \${qalonAyahs.length}, Hafs: \${hafsAyahs.length}) ---');
      
      int q = 0;
      int h = 0;
      while (q < qalonAyahs.length && h < hafsAyahs.length) {
          String qStr = qalonAyahs[q];
          String hStr = hafsAyahs[h];
          
          if ((qStr.length - hStr.length).abs() < 5) { // Basically equal
              q++; h++; continue;
          }
          
          // Try Merge: Qalon combines Hafs[h] + Hafs[h+1]
          if (h + 1 < hafsAyahs.length) {
              String combinedH = hStr + hafsAyahs[h+1];
              if ((qStr.length - combinedH.length).abs() < 5) {
                  print('  => Merge: Qalon ${q+1} = Hafs ${h+1} + ${h+2}');
                  q++; h += 2; continue;
              }
              // Try Merge 3
              if (h + 2 < hafsAyahs.length) {
                  String combinedH3 = combinedH + hafsAyahs[h+2];
                  if ((qStr.length - combinedH3.length).abs() < 5) {
                      print('  => Merge 3: Qalon ${q+1} = Hafs ${h+1} + ${h+2} + ${h+3}');
                      q++; h += 3; continue;
                  }
              }
          }
          
          // Try Split: Hafs combines Qalon[q] + Qalon[q+1]
          if (q + 1 < qalonAyahs.length) {
              String combinedQ = qStr + qalonAyahs[q+1];
              if ((combinedQ.length - hStr.length).abs() < 5) {
                  print('  => Split: Hafs ${h+1} = Qalon ${q+1} + ${q+2}');
                  q += 2; h++; continue;
              }
          }
          
          print('  [!] Unresolved at Qalon ${q+1}, Hafs ${h+1} (QLen: ${qStr.length}, HLen: ${hStr.length})');
          q++; h++;
      }
  }
}

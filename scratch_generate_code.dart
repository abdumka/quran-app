import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void generateLogic(int surahNum, List<dynamic> flattened, Map<int, String> allHafs) {
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

  if (qalonAyahs.length == hafsAyahs.length) return; // Skip if equal

  // Known ones that are already perfect or complex:
  if ([11, 17, 18, 19, 21, 22, 24, 38].contains(surahNum)) return;

  String logic = "    if (s == $surahNum) {\n";
  
  int q = 1;
  int h = 1;
  int currentOffset = 0; // audio ayah = qalon ayah + currentOffset
  
  while (q <= qalonAyahs.length && h <= hafsAyahs.length) {
    int qLen = qalonAyahs[q]!.length;
    int hLen = hafsAyahs[h]!.length;
    
    if ((qLen - hLen).abs() > 20) {
      bool resolved = false;
      
      // Try Merge 2
      if (h < hafsAyahs.length) {
         int hNextLen = hafsAyahs[h+1]!.length;
         if ((qLen - (hLen + hNextLen)).abs() < 25) {
             logic += "      if (a < $q) return ['\${surahStr}\${(a + $currentOffset).toString().padLeft(3, '0')}.mp3'];\n";
             logic += "      if (a == $q) return ['\${surahStr}${(h).toString().padLeft(3, '0')}.mp3', '\${surahStr}${(h+1).toString().padLeft(3, '0')}.mp3'];\n";
             currentOffset++;
             q++; h += 2; resolved = true;
         }
      }
      
      // Try Merge 3
      if (!resolved && h < hafsAyahs.length - 1) {
         int hNextLen = hafsAyahs[h+1]!.length;
         int hNext2Len = hafsAyahs[h+2]!.length;
         if ((qLen - (hLen + hNextLen + hNext2Len)).abs() < 25) {
             logic += "      if (a < $q) return ['\${surahStr}\${(a + $currentOffset).toString().padLeft(3, '0')}.mp3'];\n";
             logic += "      if (a == $q) return ['\${surahStr}${(h).toString().padLeft(3, '0')}.mp3', '\${surahStr}${(h+1).toString().padLeft(3, '0')}.mp3', '\${surahStr}${(h+2).toString().padLeft(3, '0')}.mp3'];\n";
             currentOffset += 2;
             q++; h += 3; resolved = true;
         }
      }

      // Try Split 2
      if (!resolved && q < qalonAyahs.length) {
          int qNextLen = qalonAyahs[q+1]!.length;
          if ((hLen - (qLen + qNextLen)).abs() < 25) {
             logic += "      if (a < $q) return ['\${surahStr}\${(a + $currentOffset).toString().padLeft(3, '0')}.mp3'];\n";
             logic += "      if (a == $q) return ['\${surahStr}${(h).toString().padLeft(3, '0')}.mp3'];\n";
             logic += "      if (a == ${q+1}) return [];\n";
             currentOffset--;
             q += 2; h++; resolved = true;
         }
      }

      if (!resolved) {
          q++; h++;
      }
    } else {
      q++; h++;
    }
  }
  
  if (currentOffset != 0) {
      logic += "      return ['\${surahStr}\${(a + $currentOffset).toString().padLeft(3, '0')}.mp3'];\n";
  } else {
      logic += "      return ['\${surahStr}\${a.toString().padLeft(3, '0')}.mp3'];\n";
  }
  logic += "    }\n";
  
  print(logic);
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

  for (int i = 1; i <= 114; i++) {
     generateLogic(i, flattened, allHafs);
  }
}

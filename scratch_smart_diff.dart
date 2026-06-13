import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

String clean(String text) {
  return text
      .replaceAll(RegExp(r'[^\u0621-\u064A]'), '')
      .replaceAll('ي', 'ی')
      .replaceAll('ے', 'ی')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه');
}

void main() async {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  final flattened = <dynamic>[];
  for (final item in data) {
    if (item is List) { flattened.addAll(item); } else { flattened.add(item); }
  }
  
  final qalonAyahs = <int, String>{};
  for (final page in flattened) {
    for (final a in (page['ayahs'] as List)) {
      if (a['surah'] == 21) {
        qalonAyahs[a['ayah'] as int] = clean(a['text'] as String);
      }
    }
  }

  final response = await http.get(Uri.parse('https://api.alquran.cloud/v1/surah/21'));
  final hafsData = json.decode(response.body);
  final hafsAyahs = <int, String>{};
  for (final a in hafsData['data']['ayahs']) {
    hafsAyahs[a['numberInSurah'] as int] = clean(a['text'] as String);
  }

  if (hafsAyahs[1]!.startsWith('بسماللهالرحمنالرحیم')) {
    hafsAyahs[1] = hafsAyahs[1]!.substring('بسماللهالرحمنالرحیم'.length);
  }

  int q = 1;
  int h = 1;
  final merges = <int>[];
  
  while (q <= qalonAyahs.length && h <= hafsAyahs.length) {
    if (qalonAyahs[q] == hafsAyahs[h]) {
      q++; h++; continue;
    }
    
    if (h < hafsAyahs.length) {
      String combined = hafsAyahs[h]! + hafsAyahs[h+1]!;
      if ((qalonAyahs[q]!.length - combined.length).abs() < 10) {
        merges.add(q);
        q++; h += 2; continue;
      }
    }
    
    if (h < hafsAyahs.length - 1) {
      String combined = hafsAyahs[h]! + hafsAyahs[h+1]! + hafsAyahs[h+2]!;
      if ((qalonAyahs[q]!.length - combined.length).abs() < 10) {
        merges.add(q);
        q++; h += 3; continue;
      }
    }
    
    // Check if Hafs combines Q and Q+1 (split in Qalon)
    if (q < qalonAyahs.length) {
      String combinedQ = qalonAyahs[q]! + qalonAyahs[q+1]!;
      if ((combinedQ.length - hafsAyahs[h]!.length).abs() < 10) {
        print('SPLIT FOUND: Hafs $h is split into Qalon $q and ${q+1}');
        q += 2; h++; continue;
      }
    }
    
    print('Failed to match at Q=$q H=$h');
    q++; h++;
  }
  
  print('Merges found at Qalon Ayah numbers: \$merges');
}

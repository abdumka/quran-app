import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  // Get Qalon ayahs
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  final flattened = <dynamic>[];
  for (final item in data) {
    if (item is List) { flattened.addAll(item); } else { flattened.add(item); }
  }
  
  final qalonAyahs = <int, String>{};
  for (final page in flattened) {
    for (final a in (page['ayahs'] as List)) {
      if (a['surah'] == 18) {
        qalonAyahs[a['ayah'] as int] = a['text'] as String;
      }
    }
  }

  // Get Hafs ayahs
  final response = await http.get(Uri.parse('https://api.alquran.cloud/v1/surah/18'));
  final hafsData = json.decode(response.body);
  final hafsAyahs = <int, String>{};
  for (final a in hafsData['data']['ayahs']) {
    hafsAyahs[a['numberInSurah'] as int] = a['text'] as String;
  }

  // Compare
  print('Qalon count: ${qalonAyahs.length}, Hafs count: ${hafsAyahs.length}');
  
  int qOffset = 0;
  for (int h = 1; h <= hafsAyahs.length; h++) {
    int q = h - qOffset;
    if (!qalonAyahs.containsKey(q)) break;
    
    // Normalize text for basic length comparison (ignoring diacritics)
    final hText = hafsAyahs[h]!.replaceAll(RegExp(r'[^\u0621-\u064A]'), '');
    final qText = qalonAyahs[q]!.replaceAll(RegExp(r'[^\u0621-\u064A]'), '');
    
    // If length difference is huge, they probably combined/split
    if ((hText.length - qText.length).abs() > 30) {
      print('MISMATCH at Hafs $h / Qalon $q');
      print('  Hafs: ${hafsAyahs[h]}');
      print('  Qalo: ${qalonAyahs[q]}');
      
      // Let's check if Qalon combined this and next Hafs ayah
      if (h < hafsAyahs.length) {
        final hNextText = hafsAyahs[h+1]!.replaceAll(RegExp(r'[^\u0621-\u064A]'), '');
        final combinedHafs = hText + hNextText;
        if ((combinedHafs.length - qText.length).abs() < 30) {
          print('  => Qalon $q seems to combine Hafs $h and ${h+1}');
          qOffset++; // Hafs is ahead by 1 now
        }
      }
    }
  }
}

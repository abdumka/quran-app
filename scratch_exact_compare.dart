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
  int qIndex = 1;
  int hIndex = 1;
  while (qIndex <= qalonAyahs.length && hIndex <= hafsAyahs.length) {
    String qText = qalonAyahs[qIndex]!.replaceAll(RegExp(r'[^\u0621-\u064A]'), '');
    String hText = hafsAyahs[hIndex]!.replaceAll(RegExp(r'[^\u0621-\u064A]'), '');
    
    // Strip basmalah if present at the beginning of ayah 1
    if (hIndex == 1) {
      hText = hText.replaceFirst(RegExp(r'^.*الحمدلله'), 'الحمدلله');
    }
    
    // If they match perfectly
    if (qText == hText) {
      qIndex++;
      hIndex++;
      continue;
    }
    
    // If Qalon contains Hafs + next Hafs
    if (hIndex < hafsAyahs.length) {
      String hTextNext = hafsAyahs[hIndex+1]!.replaceAll(RegExp(r'[^\u0621-\u064A]'), '');
      if (qText == hText + hTextNext) {
        print('FOUND MERGE: Qalon $qIndex combines Hafs $hIndex and ${hIndex+1}');
        qIndex++;
        hIndex += 2;
        continue;
      }
      
      // What if it combines 3 ayahs?
      if (hIndex < hafsAyahs.length - 1) {
        String hTextNext2 = hafsAyahs[hIndex+2]!.replaceAll(RegExp(r'[^\u0621-\u064A]'), '');
        if (qText == hText + hTextNext + hTextNext2) {
          print('FOUND MERGE 3: Qalon $qIndex combines Hafs $hIndex, ${hIndex+1}, ${hIndex+2}');
          qIndex++;
          hIndex += 3;
          continue;
        }
      }
    }
    
    print('COULD NOT RESOLVE at Qalon $qIndex, Hafs $hIndex');
    print('Q: ${qalonAyahs[qIndex]}');
    print('H: ${hafsAyahs[hIndex]}');
    break;
  }
}

import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  
  final flattened = <dynamic>[];
  for (final item in data) {
    if (item is List) {
      flattened.addAll(item);
    } else {
      flattened.add(item);
    }
  }

  print("Total pages: ${flattened.length}");
  
  Map<int, int> counts = {};

  for (int i = 0; i < flattened.length; i++) {
    var pageObj = flattened[i];
    if (pageObj is! Map) continue;
    var ayahs = pageObj['ayahs'] as List<dynamic>;
    for (var a in ayahs) {
      int s = a['surah'];
      int ayahNum = a['ayah'];
      if (!counts.containsKey(s) || ayahNum > counts[s]!) {
        counts[s] = ayahNum;
      }
    }
  }
  
  print('Found surahs: ' + counts.keys.toList().join(', '));
  print('Surah 4 ayahs: ' + counts[4].toString());
}

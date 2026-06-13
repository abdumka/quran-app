import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  print("Total pages: ${data.length}");
  
  Map<int, int> counts = {};

  for (int i = 0; i < data.length; i++) {
    var pageObj = data[i];
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
  
  print("Found surahs: ${counts.keys.toList().join(', ')}");
}

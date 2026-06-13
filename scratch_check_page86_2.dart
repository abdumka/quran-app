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

  for (int i = 0; i < flattened.length; i++) {
    var pageObj = flattened[i];
    if (pageObj is! Map) continue;
    if (pageObj['page'] == 85 || pageObj['page'] == 86 || pageObj['page'] == 87) {
      print('Page ' + pageObj['page'].toString() + ':');
      var ayahs = pageObj['ayahs'] as List<dynamic>;
      for (var a in ayahs) {
        String t = a['text'].toString();
        if (t.length > 30) t = t.substring(0, 30);
        print('  Surah ' + a['surah'].toString() + ' Ayah ' + a['ayah'].toString() + ': ' + t + '...');
      }
    }
  }
}

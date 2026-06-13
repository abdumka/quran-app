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
    if (pageObj['page'] == 85 || pageObj['page'] == 86) {
      print("Page ${pageObj['page']}:");
      var ayahs = pageObj['ayahs'] as List<dynamic>;
      for (var a in ayahs) {
        print("  Surah ${a['surah']} Ayah ${a['ayah']}: ${a['text'].substring(0, 30)}...");
      }
    }
  }
}

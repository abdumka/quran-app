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

  for (final page in flattened) {
    if (page['page'] == 85 || page['page'] == 86) {
      print('=== PAGE ${page['page']} ===');
      final ayahs = page['ayahs'] as List<dynamic>;
      for (final ayah in ayahs) {
        print('Surah ${ayah['surah']} Ayah ${ayah['ayah']}: ${ayah['text']}');
      }
    }
  }
}

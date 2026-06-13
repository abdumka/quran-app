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
    final ayahs = page['ayahs'] as List<dynamic>;
    for (final ayah in ayahs) {
      if (ayah['surah'] == 1) {
        print('Surah 1 Ayah ${ayah['ayah']}: ${ayah['text']}');
      }
    }
  }
}

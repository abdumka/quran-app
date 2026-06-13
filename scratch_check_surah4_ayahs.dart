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
      if (ayah['surah'] == 4 && (ayah['ayah'] <= 5 || ayah['ayah'] >= 45 && ayah['ayah'] <= 55)) {
        print("Surah 4 Ayah ${ayah['ayah']}: ${ayah['text'].substring(0, 30)}...");
      }
    }
  }
}

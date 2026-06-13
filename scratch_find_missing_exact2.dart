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
      if (ayah['surah'] == 4) {
        final text = ayah['text'].toString();
        if (text.contains('يَشْتَرُونَ') || text.contains('يشترون') || text.contains('الضلالة') || text.contains('ضلالة') || text.contains('اَ۬لضَّلَٰلَةَ')) {
          print('Found in Surah ${ayah['surah']} Ayah ${ayah['ayah']}: ${ayah['text']}');
        }
      }
    }
  }
}

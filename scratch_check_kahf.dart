import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  final flattened = <dynamic>[];
  for (final item in data) {
    if (item is List) { flattened.addAll(item); } else { flattened.add(item); }
  }
  
  print('=== SURAH AL-KAHF (18) ===');
  for (final page in flattened) {
    bool hasSurah = false;
    for (final a in (page['ayahs'] as List)) {
      if (a['surah'] == 18) {
        if (!hasSurah) {
          print('\n--- PAGE ${page['page']} ---');
          hasSurah = true;
        }
        final text = a['text'] as String;
        final preview = text.length > 40 ? '${text.substring(0, 20)}...${text.substring(text.length - 20)}' : text;
        print('  Ayah ${a['ayah']}: $preview');
      }
    }
  }
}

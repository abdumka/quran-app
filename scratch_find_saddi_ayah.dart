import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/ar.saddi.json');
  final data = json.decode(file.readAsStringSync())['data']['surahs'];
  
  for (final surah in data) {
    if (surah['number'] == 4) {
      for (final ayah in surah['ayahs']) {
        if (ayah['text'].contains('يَشْتَرُونَ الضَّلَالَةَ') || ayah['text'].contains('يشترون') || ayah['text'].contains('تَضِلُّواْ')) {
          print('Found in ar.saddi.json - Surah 4 Ayah ${ayah['numberInSurah']}: ${ayah['text']}');
        }
      }
    }
  }
}

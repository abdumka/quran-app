import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = jsonDecode(file.readAsStringSync());
  
  for (var page in data) {
    if (page is List) {
      for (var p in page) {
        if (p['page'] == 144 || p['page'] == 145) {
          for (var ayah in p['ayahs']) {
            if (ayah['surah'] == 6 && (ayah['ayah'] >= 130 && ayah['ayah'] <= 132)) {
              print('Page: ' + p['page'].toString() + ', Surah: ' + ayah['surah'].toString() + ', Ayah: ' + ayah['ayah'].toString());
              print(ayah['text']);
            }
          }
        }
      }
    } else {
      if (page['page'] == 144 || page['page'] == 145) {
        for (var ayah in page['ayahs']) {
          if (ayah['surah'] == 6 && (ayah['ayah'] >= 130 && ayah['ayah'] <= 132)) {
            print('Page: ' + page['page'].toString() + ', Surah: ' + ayah['surah'].toString() + ', Ayah: ' + ayah['ayah'].toString());
            print(ayah['text']);
          }
        }
      }
    }
  }
}

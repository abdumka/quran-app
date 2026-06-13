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

  bool found = false;
  for (int i = 0; i < flattened.length; i++) {
    var pageObj = flattened[i];
    if (pageObj is! Map) continue;
    var ayahs = pageObj['ayahs'] as List<dynamic>;
    for (var a in ayahs) {
      if (a['text'].contains('أَلَمْ تَرَ إِلَي اَ۬لذِينَ أُوتُواْ نَصِيباٗ مِّنَ اَ۬لْكِتَٰبِ')) {
        print('FOUND ON PAGE ' + pageObj['page'].toString() + ' SURAH ' + a['surah'].toString() + ' AYAH ' + a['ayah'].toString());
        found = true;
      }
    }
  }
  if (!found) {
    print('NOT FOUND AT ALL IN ORIGINAL JSON!');
  }
}

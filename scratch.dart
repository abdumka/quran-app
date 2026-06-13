import 'dart:convert';
import 'dart:io';

void main() async {
  final file = File('assets/data/output.json');
  final jsonStr = await file.readAsString();
  final decoded = jsonDecode(jsonStr);

  final List<dynamic> data = [];
  for (final item in decoded) {
    if (item is List) {
      data.addAll(item);
    } else {
      data.add(item);
    }
  }

  for (var page in data) {
    for (var ayah in page['ayahs']) {
      if (ayah['surah'] == 27) {
        int qalonAyah = ayah['ayah'];
        print('Qalon ${qalonAyah}: ${ayah['text'].substring(0, ayah['text'].length > 40 ? 40 : ayah['text'].length)}...');
      }
    }
  }
}

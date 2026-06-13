import 'dart:io';
import 'dart:convert';

void main() async {
  final jsonString = await File('assets/data/output.json').readAsString();
  final data = jsonDecode(jsonString) as List;

  Map<int, int> qalonCounts = {};
  for (var i = 0; i < data.length; i++) {
    var page = data[i];
    if (page is Map && page.containsKey('ayahs')) {
      var ayahs = page['ayahs'] as List;
      for (var j = 0; j < ayahs.length; j++) {
        var ayah = ayahs[j];
        if (ayah is Map) {
          int surah = ayah['surah'] as int;
          qalonCounts[surah] = (qalonCounts[surah] ?? 0) + 1;
        }
      }
    }
  }

  for (var i=1; i<=114; i++) {
    if ((qalonCounts[i] ?? 0) == 0) {
      print('Surah $i is MISSING from output.json!');
    }
  }
}

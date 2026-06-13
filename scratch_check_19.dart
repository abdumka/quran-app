import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  final flattened = <dynamic>[];
  for (final item in data) {
    if (item is List) { flattened.addAll(item); } else { flattened.add(item); }
  }
  
  final qalonCounts = <int, int>{};
  for (final page in flattened) {
    for (final a in (page['ayahs'] as List)) {
      int s = a['surah'] as int;
      qalonCounts[s] = (qalonCounts[s] ?? 0) + 1;
    }
  }

  final response = await http.get(Uri.parse('https://api.alquran.cloud/v1/meta'));
  final hafsData = json.decode(response.body);
  final hafsCounts = <int, int>{};
  for (final s in hafsData['data']['surahs']['references']) {
    hafsCounts[s['number'] as int] = s['numberOfAyahs'] as int;
  }

  print('Surah 19: Qalon=${qalonCounts[19]} Hafs=${hafsCounts[19]}');
}

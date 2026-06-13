import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  
  var lastPage = data.last;
  print('Last page: ' + lastPage['page'].toString());
  var ayahs = lastPage['ayahs'] as List<dynamic>;
  for (var a in ayahs) {
    print('Surah ' + a['surah'].toString() + ' Ayah ' + a['ayah'].toString() + ': ' + a['text']);
  }
}

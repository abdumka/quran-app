import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  
  bool patched = false;

  for (int i = 0; i < data.length; i++) {
    var pageObj = data[i];
    if (pageObj is! Map) continue;
    
    if (pageObj['page'] == 86) {
      var ayahs = pageObj['ayahs'] as List<dynamic>;
      for (var a in ayahs) {
        if (a['surah'] == 4 && a['ayah'] == 51) {
          a['text'] = "أَلَمْ تَرَ إِلَي اَ۬لذِينَ أُوتُواْ نَصِيباٗ مِّنَ اَ۬لْكِتَٰبِ يُومِنُونَ بِالْجِبْتِ وَالطَّٰغُوتِ وَيَقُولُونَ لِلذِينَ كَفَرُواْ هَٰٓؤُلَآءِ أَهْدَيٰ مِنَ اَ۬لذِينَ ءَامَنُواْ سَبِيلاًۖ";
          patched = true;
          print('Fixed Ayah 51 on Page 86');
        }
      }
    }
  }

  if (patched) {
    file.writeAsStringSync(json.encode(data));
    print('Successfully patched output.json!');
  } else {
    print('Not found.');
  }
}

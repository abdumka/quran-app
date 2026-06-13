import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  
  bool patched = false;

  for (int i = 0; i < data.length; i++) {
    var pageObj = data[i];
    if (pageObj is! Map) continue;
    
    if (pageObj['page'] == 85) {
      // Add the missing ayah 44 to the end of Page 85
      var ayahs = pageObj['ayahs'] as List<dynamic>;
      bool has44 = false;
      for (var a in ayahs) {
        if (a['surah'] == 4 && a['ayah'] == 44) has44 = true;
      }
      if (!has44) {
        ayahs.add({
          "surah": 4,
          "surahName": "النساء",
          "ayah": 44,
          "text": "أَلَمْ تَرَ إِلَي اَ۬لذِينَ أُوتُواْ نَصِيباٗ مِّنَ اَ۬لْكِتَٰبِ يَشْتَرُونَ اَ۬لضَّلَٰلَةَ وَيُرِيدُونَ أَن تَضِلُّواْ اَ۬لسَّبِيلَۖ"
        });
        patched = true;
        print('Added Ayah 44 to Page 85');
      }
    }
    
    if (pageObj['page'] >= 86) {
      // Shift all subsequent ayahs in Surah 4 by +1
      var ayahs = pageObj['ayahs'] as List<dynamic>;
      for (var a in ayahs) {
        if (a['surah'] == 4) {
          // If the text is Wallahu A'lamu, it's currently Ayah 44, we need to make it 45.
          a['ayah'] = a['ayah'] + 1;
        }
      }
    }
  }

  if (patched) {
    file.writeAsStringSync(json.encode(data));
    print('Successfully patched output.json!');
  } else {
    print('Already patched or not found.');
  }
}

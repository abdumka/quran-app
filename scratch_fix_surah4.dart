import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  
  bool patched = false;

  for (int i = 0; i < data.length; i++) {
    var pageObj = data[i];
    if (pageObj is! Map) continue;
    
    // Fix Page 85
    if (pageObj['page'] == 85) {
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
    
    // Fix Page 86 and subsequent pages by shifting numbering, then fixing text
    if (pageObj['page'] >= 86) {
      var ayahs = pageObj['ayahs'] as List<dynamic>;
      for (var a in ayahs) {
        if (a['surah'] == 4) {
          a['ayah'] = a['ayah'] + 1; // Shift number
          if (a['ayah'] == 51 && pageObj['page'] == 86) {
            // Replace the wrong text with the correct Hafs 51 text
            a['text'] = "أَلَمْ تَرَ إِلَي اَ۬لذِينَ أُوتُواْ نَصِيباٗ مِّنَ اَ۬لْكِتَٰبِ يُومِنُونَ بِالْجِبْتِ وَالطَّٰغُوتِ وَيَقُولُونَ لِلذِينَ كَفَرُواْ هَٰٓؤُلَآءِ أَهْدَيٰ مِنَ اَ۬لذِينَ ءَامَنُواْ سَبِيلاًۖ";
            print('Fixed Ayah 51 text on Page 86');
          }
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

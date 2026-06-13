import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = jsonDecode(file.readAsStringSync());
  
  Map<String, dynamic>? page144;
  Map<String, dynamic>? page145;
  
  for (var page in data) {
    var p = page is List ? page[0] : page;
    if (p['page'] == 144) page144 = p;
    if (p['page'] == 145) page145 = p;
  }
  
  if (page144 != null && page145 != null) {
    // Find Surah 6 Ayah 132 in page 145
    var ayahs145 = List<dynamic>.from(page145['ayahs']);
    var targetAyahIndex = ayahs145.indexWhere((a) => a['surah'] == 6 && a['ayah'] == 132);
    
    if (targetAyahIndex != -1) {
      var targetAyah = ayahs145.removeAt(targetAyahIndex);
      page145['ayahs'] = ayahs145;
      
      var ayahs144 = List<dynamic>.from(page144['ayahs']);
      ayahs144.add(targetAyah);
      page144['ayahs'] = ayahs144;
      
      file.writeAsStringSync(jsonEncode(data));
      print('Successfully moved Surah 6 Ayah 132 from Page 145 to Page 144.');
    } else {
      print('Ayah not found in Page 145.');
    }
  }
}

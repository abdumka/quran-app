import 'dart:io';
import 'dart:convert';

void main() {
  final file = File('assets/data/output.json');
  final json = jsonDecode(file.readAsStringSync());
  
  List<dynamic> pages = [];
  if (json is List) {
    for (var item in json) {
      if (item is List) {
        pages.addAll(item);
      } else {
        pages.add(item);
      }
    }
  } else if (json is Map && json['pages'] != null) {
    pages = json['pages'];
  }
  
  for(var p in pages) {
    if(p['page'] == 355) {
      print('Page 355 Ayahs:');
      for(var a in p['ayahs']) {
        print('${a['surahName']} - ${a['ayah']}');
      }
    }
    if(p['page'] == 356) {
      print('Page 356 Ayahs:');
      for(var a in p['ayahs']) {
        print('${a['surahName']} - ${a['ayah']}');
      }
    }
  }
}

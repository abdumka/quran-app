import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/ar.saddi.json');
  final data = json.decode(file.readAsStringSync());
  if (data is Map) {
    print('Keys: ' + data.keys.take(10).join(', '));
    // Let's print the first ayah of Surah 114
    var quran = data['quran'] ?? data['data'];
    if (quran != null) {
      print('Found quran array/object');
    }
  } else if (data is List) {
    print('It is a list of length ' + data.length.toString());
  }
}

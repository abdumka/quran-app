import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/ar.saddi.json'); // Let's check the other JSON
  final text = file.readAsStringSync();
  if (text.contains('يَشْتَرُونَ الضَّلَالَةَ') || text.contains('يشترون')) {
    print('Found the missing ayah in ar.saddi.json!');
  } else {
    print('Not found in ar.saddi.json either');
  }
}

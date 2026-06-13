import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/ar.saddi.json');
  final jsonString = file.readAsStringSync();
  print('Read saddi. Length: ' + jsonString.length.toString());
}

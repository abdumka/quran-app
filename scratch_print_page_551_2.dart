import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  
  print('Length: ' + data.length.toString());
  var lastObj = data.last;
  print('Type of last object: ' + lastObj.runtimeType.toString());
  if (lastObj is Map) {
    print('Keys: ' + lastObj.keys.join(', '));
  } else {
    print('Value: ' + lastObj.toString());
  }
}

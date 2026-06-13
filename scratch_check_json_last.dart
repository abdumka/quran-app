import 'dart:io';
import 'dart:convert';

void main() {
  try {
    final d = jsonDecode(File('assets/data/output.json').readAsStringSync()) as List;
    final lastItem = d.last as List;
    print('Last element is a List with ${lastItem.length} items');
    int maps = 0;
    for (var item in lastItem) {
      if (item is Map) maps++;
    }
    print('Maps inside the List: $maps');
    if (maps > 0) {
      var firstMap = lastItem.firstWhere((e) => e is Map, orElse: () => null);
      if (firstMap != null) {
        print('First Map in the list has keys: ${firstMap.keys.toList()}');
        if (firstMap.containsKey('page')) {
          print('First page inside list: ${firstMap['page']}');
        }
      }
      var lastMap = lastItem.lastWhere((e) => e is Map, orElse: () => null);
      if (lastMap != null && lastMap.containsKey('page')) {
        print('Last page inside list: ${lastMap['page']}');
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}

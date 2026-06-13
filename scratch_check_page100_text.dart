import 'dart:convert';
import 'dart:io';

void main() async {
  var url = Uri.parse('http://api.alquran.cloud/v1/page/100/quran-uthmani');
  var response = await HttpClient().getUrl(url);
  var res = await response.close();
  var body = await res.transform(utf8.decoder).join();
  if (res.statusCode == 200) {
    var ayahs = json.decode(body)['data']['ayahs'] as List<dynamic>;
    print('Madinah Page 100 starts with text: ' + ayahs.first['text'].substring(0, 30));
    
    final file = File('assets/data/output.json');
    final data = json.decode(file.readAsStringSync()) as List<dynamic>;
    final flattened = <dynamic>[];
    for (final item in data) {
      if (item is List) flattened.addAll(item);
      else flattened.add(item);
    }
    
    for (int i = 0; i < flattened.length; i++) {
      var pageObj = flattened[i];
      if (pageObj is! Map) continue;
      if (pageObj['page'] == 100) {
        var ayahsJson = pageObj['ayahs'] as List<dynamic>;
        print('JSON Page 100 starts with text: ' + ayahsJson.first['text'].toString().substring(0, 30));
        break;
      }
    }
  } else {
    print('FAILED');
  }
}

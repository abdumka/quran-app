import 'dart:convert';
import 'dart:io';

void main() async {
  var url = Uri.parse('http://api.alquran.cloud/v1/page/86/quran-uthmani');
  var response = await HttpClient().getUrl(url);
  var res = await response.close();
  var body = await res.transform(utf8.decoder).join();
  if (res.statusCode == 200) {
    var ayahs = json.decode(body)['data']['ayahs'] as List<dynamic>;
    print('Madinah Page 86 starts with: Surah ' + ayahs.first['surah']['number'].toString() + ' Ayah ' + ayahs.first['numberInSurah'].toString());
  } else {
    print('FAILED');
  }
}

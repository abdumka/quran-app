import 'dart:convert';
import 'dart:io';

void main() async {
  var url = Uri.parse('http://api.alquran.cloud/v1/page/85/quran-uthmani');
  var response = await HttpClient().getUrl(url);
  var res = await response.close();
  var body = await res.transform(utf8.decoder).join();
  if (res.statusCode == 200) {
    var ayahs = json.decode(body)['data']['ayahs'] as List<dynamic>;
    print('Madinah Page 85 starts with: Surah ' + ayahs.first['surah']['number'].toString() + ' Ayah ' + ayahs.first['numberInSurah'].toString() + ' Text: ' + ayahs.first['text'].substring(0, 30));
    print('Madinah Page 85 ends with: Surah ' + ayahs.last['surah']['number'].toString() + ' Ayah ' + ayahs.last['numberInSurah'].toString() + ' Text: ' + ayahs.last['text'].substring(0, 30));
  } else {
    print('FAILED');
  }
}

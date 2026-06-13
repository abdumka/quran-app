import 'dart:convert';
import 'dart:io';

void main() async {
  var url = Uri.parse('http://api.alquran.cloud/v1/surah/4/quran-qalon');
  var response = await HttpClient().getUrl(url);
  var res = await response.close();
  var body = await res.transform(utf8.decoder).join();
  if (res.statusCode == 200) {
    var data = json.decode(body)['data']['ayahs'] as List<dynamic>;
    for (int i = 40; i <= 44; i++) {
      print("Ayah ${data[i]['numberInSurah']}: ${data[i]['text'].substring(0, 50)}...");
    }
  } else {
    print('FAILED');
  }
}

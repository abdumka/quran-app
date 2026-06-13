import 'dart:convert';
import 'dart:io';

void main() async {
  var url = Uri.parse('http://api.alquran.cloud/v1/page/552/quran-uthmani');
  var response = await HttpClient().getUrl(url);
  var res = await response.close();
  var body = await res.transform(utf8.decoder).join();
  print(body.substring(0, 500));
}

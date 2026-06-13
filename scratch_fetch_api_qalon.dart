import 'dart:convert';
import 'dart:io';

void main() async {
  var url = Uri.parse('http://api.alquran.cloud/v1/page/552/quran-qalon');
  var response = await HttpClient().getUrl(url);
  var res = await response.close();
  var body = await res.transform(utf8.decoder).join();
  if (res.statusCode == 200) {
    print('SUCCESS');
    print(body.substring(0, 500));
  } else {
    print('FAILED \${res.statusCode}');
  }
}

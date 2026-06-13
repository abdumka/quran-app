import 'dart:io';

void main() async {
  final url1 = 'https://raw.githubusercontent.com/quran-by-verses/alhosary-qaloon-32/main/001001.mp3';
  final url2 = 'https://raw.githubusercontent.com/quran-by-verses/alhosary-qaloon-32/master/001001.mp3';
  
  try {
    final client = HttpClient();
    final req1 = await client.headUrl(Uri.parse(url1));
    final res1 = await req1.close();
    print('main branch: ${res1.statusCode}');
    
    final req2 = await client.headUrl(Uri.parse(url2));
    final res2 = await req2.close();
    print('master branch: ${res2.statusCode}');
  } catch(e) {
    print(e);
  }
}

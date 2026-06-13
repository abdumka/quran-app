import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final url = 'https://github.com/mahfodqr/quran-app-files/releases/download/v1.1.0/hawamesh.zip';
  print('Testing URL: $url');
  try {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);
    print('Status: ${response.statusCode}');
    print('Content-Length: ${response.contentLength}');
    
    // Just read a few bytes to see if it starts
    int bytes = 0;
    await for (final chunk in response.stream) {
      bytes += chunk.length;
      if (bytes > 1024) {
         print('Successfully read 1KB data.');
         break;
      }
    }
    client.close();
  } catch (e) {
    print('Error: $e');
  }
}

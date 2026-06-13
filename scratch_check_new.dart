import 'dart:io';
import 'dart:convert';

void main() async {
  final dir = Directory(r'C:\Users\Mr WaGdI\Downloads\Compressed\New folder (2)\New folder');
  if (!dir.existsSync()) {
    print('Dir not found');
    return;
  }
  final files = dir.listSync().whereType<File>().toList();
  Map<int, int> counts = {};
  for (var f in files) {
    final name = f.uri.pathSegments.last;
    if (name.endsWith('.mp3') && name.length >= 6) {
      final s = int.tryParse(name.substring(0,3));
      if (s != null) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
    }
  }

  final jsonString = await File('assets/data/output.json').readAsString();
  final data = jsonDecode(jsonString) as List;

  Map<int, int> qalonCounts = {};
  for (var i = 0; i < data.length; i++) {
    var page = data[i];
    if (page is Map && page.containsKey('ayahs')) {
      var ayahs = page['ayahs'] as List;
      for (var j = 0; j < ayahs.length; j++) {
        var ayah = ayahs[j];
        if (ayah is Map) {
          int surah = ayah['surah'] as int;
          qalonCounts[surah] = (qalonCounts[surah] ?? 0) + 1;
        }
      }
    }
  }

  print('================= مقارنة السور المضافة حديثاً =================');
  
  List<int> newSurahs = [6, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114];
  for (var s in newSurahs) {
    int qCount = qalonCounts[s] ?? 0;
    int aCount = counts[s] ?? 0;
    print('سورة $s: في التطبيق ($qCount) | في الصوت ($aCount)');
    if (aCount < qCount) {
      List<int> merged = [];
      for (int i = aCount; i <= qCount; i++) merged.add(i);
      print('  -> استنتاج: الملف $aCount يحتوي على الآيات المدمجة: ${merged.join(', ')}');
    } else if (aCount > qCount) {
      List<int> extras = [];
      for (int i = qCount + 1; i <= aCount; i++) extras.add(i);
      print('  -> استنتاج: الملفات الزائدة هي: ${extras.join(', ')}');
    } else {
      print('  -> استنتاج: تطابق تام 100%');
    }
  }
}

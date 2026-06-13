import 'dart:convert';
import 'dart:io';

void main() async {
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

  final audioCounts = {
    1: 7, 2: 285, 3: 200, 4: 176, 5: 120, 7: 206, 8: 75, 9: 129, 10: 109,
    11: 123, 12: 111, 13: 43, 14: 52, 15: 99, 16: 128, 17: 111, 18: 105, 19: 98,
    20: 135, 21: 112, 22: 78, 23: 118, 24: 64, 25: 77, 26: 227, 27: 93, 28: 88,
    29: 69, 30: 60, 31: 34, 32: 30, 33: 73, 34: 54, 35: 45, 36: 83, 37: 182,
    38: 88, 39: 75, 40: 85, 41: 54, 42: 53, 43: 89, 44: 59, 45: 37, 46: 35,
    47: 38, 48: 29, 49: 18, 50: 45, 51: 60, 52: 49, 53: 62, 54: 55, 55: 78,
    56: 96, 57: 29, 58: 22, 59: 24, 60: 13, 61: 14, 62: 11, 63: 11, 64: 18,
    65: 12, 66: 12, 67: 30, 68: 52, 69: 52, 70: 44, 71: 28, 72: 28, 73: 20,
    74: 56, 75: 40, 76: 31, 77: 50, 78: 40, 79: 46, 80: 42, 81: 29, 82: 19,
    83: 36, 84: 25, 85: 22, 86: 17, 87: 19, 88: 26, 89: 30, 90: 20, 91: 15,
    92: 21, 93: 11, 94: 8, 95: 8, 96: 19, 97: 5, 98: 8, 99: 8, 100: 11,
    101: 11, 102: 8, 103: 3, 104: 9
  };

  print('================= الزوائد المكتشفة (أطوالها 1 ثانية) =================');
  for (var entry in qalonCounts.entries) {
    int surah = entry.key;
    int qCount = entry.value;
    if (audioCounts.containsKey(surah)) {
      int aCount = audioCounts[surah]!;
      if (aCount > qCount) {
        // Here we have extra padding files
        List<int> extras = [];
        for (int i = qCount + 1; i <= aCount; i++) {
          extras.add(i);
        }
        print('- سورة ${surah}: الآيات الزائدة هي (${extras.join(', ')})');
      }
    }
  }

  print('\\n================= الآيات المدمجة في آخر ملف (حسب القاعدة الجديدة) =================');
  for (var entry in qalonCounts.entries) {
    int surah = entry.key;
    int qCount = entry.value;
    if (audioCounts.containsKey(surah)) {
      int aCount = audioCounts[surah]!;
      if (qCount > aCount) {
        // Here we have missing files, meaning they are merged in the last file
        List<int> merged = [];
        for (int i = aCount; i <= qCount; i++) {
          merged.add(i);
        }
        print('- سورة ${surah}: الملف الأخير ${aCount.toString().padLeft(3, '0')} يحتوي على الآيات المدمجة (${merged.join(', ')})');
      }
    }
  }
}

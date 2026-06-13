import 'dart:io';

void main() {
  final hafs = {
    1: 7, 2: 286, 3: 200, 4: 176, 5: 120, 6: 165, 7: 206, 8: 75, 9: 129, 10: 109,
    11: 123, 12: 111, 13: 43, 14: 52, 15: 99, 16: 128, 17: 111, 18: 110, 19: 98,
    20: 135, 21: 112, 22: 78, 23: 118, 24: 64, 25: 77, 26: 227, 27: 93, 28: 88,
    29: 69, 30: 60, 31: 34, 32: 30, 33: 73, 34: 54, 35: 45, 36: 83, 37: 182,
    38: 88, 39: 75, 40: 85, 41: 54, 42: 53, 43: 89, 44: 59, 45: 37, 46: 35,
    47: 38, 48: 29, 49: 18, 50: 45, 51: 60, 52: 49, 53: 62, 54: 55, 55: 78,
    56: 96, 57: 29, 58: 22, 59: 24, 60: 13, 61: 14, 62: 11, 63: 11, 64: 18,
    65: 12, 66: 12, 67: 30, 68: 52, 69: 52, 70: 44, 71: 28, 72: 28, 73: 20,
    74: 56, 75: 40, 76: 31, 77: 50, 78: 40, 79: 46, 80: 42, 81: 29, 82: 19,
    83: 36, 84: 25, 85: 22, 86: 17, 87: 19, 88: 26, 89: 30, 90: 20, 91: 15,
    92: 21, 93: 11, 94: 8, 95: 8, 96: 19, 97: 5, 98: 8, 99: 8, 100: 11,
    101: 11, 102: 8, 103: 3, 104: 9, 105: 5, 106: 4, 107: 7, 108: 3, 109: 6,
    110: 3, 111: 5, 112: 4, 113: 5, 114: 6
  };

  final qalon = Map<int, int>.from(hafs);
  qalon[5] = 122; qalon[6] = 167; qalon[8] = 76; qalon[9] = 130; qalon[11] = 122;
  qalon[13] = 44; qalon[14] = 54; qalon[17] = 110; qalon[18] = 105; qalon[20] = 134;
  qalon[21] = 111; qalon[22] = 76; qalon[23] = 119; qalon[24] = 62; qalon[27] = 95;
  qalon[31] = 33; qalon[36] = 82; qalon[37] = 181; qalon[38] = 86; qalon[39] = 72;
  qalon[40] = 84; qalon[41] = 53; qalon[42] = 50; qalon[44] = 56; qalon[45] = 36;
  qalon[46] = 34; qalon[47] = 39; qalon[52] = 47; qalon[53] = 61; qalon[55] = 77;
  qalon[56] = 99; qalon[57] = 28; qalon[71] = 30; qalon[75] = 39; qalon[79] = 45;
  qalon[80] = 41; qalon[81] = 28; qalon[86] = 16; qalon[89] = 32; qalon[91] = 16;
  qalon[96] = 20; qalon[101] = 10; qalon[106] = 5; qalon[107] = 6;
  
  // Custom adjustments based on what user has in audio currently:
  // Surah 2 has 285 in Qalon (they deleted 002286.mp3 previously)
  qalon[2] = 285;
  // Surah 4 has 175 in Qalon (Hafs is 176)
  qalon[4] = 175;
  
  final dir = Directory(r'C:\Users\Mr WaGdI\Downloads\Compressed\New folder (2)\New folder');
  final files = dir.listSync().whereType<File>().toList();
  Map<int, int> audioCounts = {};
  for (var f in files) {
    final name = f.uri.pathSegments.last;
    if (name.endsWith('.mp3') && name.length >= 6) {
      final s = int.tryParse(name.substring(0,3));
      if (s != null) {
        audioCounts[s] = (audioCounts[s] ?? 0) + 1;
      }
    }
  }

  print('================= الزوائد =================');
  for (int s = 1; s <= 114; s++) {
    int qCount = qalon[s]!;
    int aCount = audioCounts[s] ?? 0;
    if (aCount > qCount) {
      print('سورة $s: تطبيق ($qCount) | صوت ($aCount) -> زيادة ${aCount - qCount}');
    }
  }

  print('\\n================= النواقص (المدمجة) =================');
  for (int s = 1; s <= 114; s++) {
    int qCount = qalon[s]!;
    int aCount = audioCounts[s] ?? 0;
    if (qCount > aCount) {
      List<int> merged = [];
      for (int i = aCount; i <= qCount; i++) merged.add(i);
      print('سورة $s: تطبيق ($qCount) | صوت ($aCount) -> مدمجة (${merged.join(', ')})');
    }
  }
}

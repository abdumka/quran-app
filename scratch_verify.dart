import 'dart:convert';
import 'dart:io';

void main() async {
  // 1. Count ayahs per surah from output.json
  final file = File('assets/data/output.json');
  final json = jsonDecode(await file.readAsString());
  final List data = [];
  for (final item in json) {
    if (item is List) data.addAll(item);
    else data.add(item);
  }

  Map<int, int> textCount = {};
  Map<int, String> names = {};
  for (var page in data) {
    for (var ayah in page['ayahs']) {
      int s = ayah['surah'];
      int a = ayah['ayah'];
      names[s] = ayah['surahName'] ?? '';
      if (!textCount.containsKey(s) || a > textCount[s]!) textCount[s] = a;
    }
  }

  // 2. Count audio files per surah from GitHub repo listing
  //    We know files are named SSSAAA.mp3 and we have the audio_service code
  //    that references specific file numbers. Instead, check the last file for each surah.
  //    Use the GitHub raw URL to check existence of the last expected file.
  
  print('');
  print('| # | السورة | آيات_النص | آيات_الصوت | الفرق | مُعالَج؟ | الحالة |');
  print('|---|--------|-----------|------------|-------|---------|--------|');

  // Known audio file counts per surah (from Hafs standard numbering)
  // These are well-known: https://en.wikipedia.org/wiki/List_of_surahs_in_the_Quran
  final Map<int, int> hafsAyahCount = {
    1: 7, 2: 286, 3: 200, 4: 176, 5: 120, 6: 165, 7: 206, 8: 75,
    9: 129, 10: 109, 11: 123, 12: 111, 13: 43, 14: 52, 15: 99, 16: 128,
    17: 111, 18: 110, 19: 98, 20: 135, 21: 112, 22: 78, 23: 118, 24: 64,
    25: 77, 26: 227, 27: 93, 28: 88, 29: 69, 30: 60, 31: 34, 32: 30,
    33: 73, 34: 54, 35: 45, 36: 83, 37: 182, 38: 88, 39: 75, 40: 85,
    41: 54, 42: 53, 43: 89, 44: 59, 45: 37, 46: 35, 47: 38, 48: 29,
    49: 18, 50: 45, 51: 60, 52: 49, 53: 62, 54: 55, 55: 78, 56: 96,
    57: 29, 58: 22, 59: 24, 60: 13, 61: 14, 62: 11, 63: 11, 64: 18,
    65: 12, 66: 12, 67: 30, 68: 52, 69: 52, 70: 44, 71: 28, 72: 28,
    73: 20, 74: 56, 75: 40, 76: 31, 77: 50, 78: 40, 79: 46, 80: 42,
    81: 29, 82: 19, 83: 36, 84: 25, 85: 22, 86: 17, 87: 19, 88: 26,
    89: 30, 90: 20, 91: 15, 92: 21, 93: 11, 94: 8, 95: 8, 96: 19,
    97: 5, 98: 8, 99: 8, 100: 11, 101: 11, 102: 8, 103: 3, 104: 9,
    105: 5, 106: 4, 107: 7, 108: 3, 109: 6, 110: 3, 111: 5, 112: 4,
    113: 5, 114: 6,
  };

  // Surahs that already have mapping in audio_service.dart
  final Set<int> handledSurahs = {
    1, 2, 3, // Original mappings
    5, 6, 8, 9, 11, 13, 14, 17, 18, 19, 20, 21, 22, // Restored mappings
    23, 24,   // Al-Mu'minun, An-Nur  
    27, 31, 36, 37, 38, 39, 40, 41, 42, // Batch 1
    44, 45, 46, 47, 52, 53, 55, 56, 57, // Batch 2
    71, 75, 79, 80, 81, 86, 89, 91, 96, 99, 101, 106, 107, // Batch 3
  };

  int ok = 0, handled = 0, needsFix = 0;
  for (int s = 1; s <= 114; s++) {
    final tc = textCount[s] ?? 0;
    final ac = hafsAyahCount[s] ?? 0;
    final diff = tc - ac;
    final n = names[s] ?? '';

    if (diff == 0) {
      ok++;
      // Don't print matching ones to keep table short
    } else {
      final d = diff > 0 ? '+$diff' : '$diff';
      final isHandled = handledSurahs.contains(s);
      if (isHandled) {
        handled++;
      } else {
        needsFix++;
      }
      final status = isHandled ? '✅ مُعالَج' : '❌ يحتاج إصلاح';
      print('| $s | $n | $tc | $ac | $d | ${isHandled ? "نعم" : "لا"} | $status |');
    }
  }

  print('');
  print('---');
  print('✅ متطابقة (لا تحتاج تعديل): $ok سورة');
  print('✅ مختلفة ومُعالَجة: $handled سورة');
  print('❌ مختلفة وتحتاج إصلاح: $needsFix سورة');
}

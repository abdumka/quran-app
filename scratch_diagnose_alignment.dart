import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;

  final flattened = <dynamic>[];
  for (final item in data) {
    if (item is List) {
      flattened.addAll(item);
    } else {
      flattened.add(item);
    }
  }

  // 1) Show pages 106-108 (around Surah Al-Ma'idah start)
  print('========================================');
  print('PAGES 106-108 (Surah Al-Ma\'idah area)');
  print('========================================');
  for (final page in flattened) {
    final pNum = page['page'] as int;
    if (pNum >= 106 && pNum <= 108) {
      print('\n--- PAGE $pNum ---');
      final ayahs = page['ayahs'] as List<dynamic>;
      for (final a in ayahs) {
        print('  Surah ${a['surah']} Ayah ${a['ayah']}');
      }
    }
  }

  // 2) Check ALL surah boundaries - does each surah start on the right page?
  // surah_data says surah 5 starts on page 106
  final surahStartPages = {
    1:1, 2:2, 3:50, 4:77, 5:106, 6:128, 7:151, 8:177, 9:187, 10:208,
    11:221, 12:235, 13:249, 14:255, 15:262, 16:267, 17:282, 18:293,
    19:305, 20:312, 21:322, 22:332, 23:342, 24:350, 25:359, 26:367,
    27:377, 28:385, 29:396, 30:404, 31:411, 32:415, 33:418, 34:428,
    35:434, 36:440, 37:446, 38:452, 39:457, 40:466, 41:476, 42:482,
    43:488, 44:495, 45:498, 46:501, 47:505, 48:509, 49:513, 50:515,
    51:517, 52:520, 53:523, 54:525, 55:528, 56:531, 57:534, 58:539,
    59:542, 60:546, 61:548, 62:550, 63:551, 64:553, 65:555, 66:557,
    67:559, 68:561, 69:563, 70:565, 71:567, 72:569, 73:571, 74:572,
    75:574, 76:575, 77:577, 78:579, 79:580, 80:582, 81:583, 82:584,
    83:585, 84:586, 85:587, 86:588, 87:589, 88:589, 89:590, 90:591,
    91:592, 92:593, 93:593, 94:594, 95:594, 96:595, 97:596, 98:596,
    99:597, 100:597, 101:598, 102:598, 103:599, 104:599, 105:599,
    106:600, 107:600, 108:600, 109:601, 110:601, 111:601, 112:602,
    113:602, 114:602,
  };

  // Standard ayah counts
  final surahAyahCounts = {
    1:7, 2:286, 3:200, 4:176, 5:120, 6:165, 7:206, 8:75, 9:129, 10:109,
    11:123, 12:111, 13:43, 14:52, 15:99, 16:128, 17:111, 18:110, 19:98,
    20:135, 21:112, 22:78, 23:118, 24:64, 25:77, 26:227, 27:93, 28:88,
    29:69, 30:60, 31:34, 32:30, 33:73, 34:54, 35:45, 36:83, 37:182,
    38:88, 39:75, 40:85, 41:54, 42:53, 43:89, 44:59, 45:37, 46:35,
    47:38, 48:29, 49:18, 50:45, 51:60, 52:49, 53:62, 54:55, 55:78,
    56:96, 57:29, 58:22, 59:24, 60:13, 61:14, 62:11, 63:11, 64:18,
    65:12, 66:12, 67:30, 68:52, 69:52, 70:44, 71:28, 72:28, 73:20,
    74:56, 75:40, 76:31, 77:50, 78:40, 79:46, 80:42, 81:29, 82:19,
    83:36, 84:25, 85:22, 86:17, 87:19, 88:26, 89:30, 90:20, 91:15,
    92:21, 93:11, 94:8, 95:8, 96:19, 97:5, 98:8, 99:8, 100:11, 101:11,
    102:8, 103:3, 104:9, 105:5, 106:4, 107:7, 108:3, 109:6, 110:3,
    111:5, 112:4, 113:5, 114:6,
  };

  // 3) Build a map: for each page, list its ayahs
  final pageAyahMap = <int, List<Map<String, dynamic>>>{};
  for (final page in flattened) {
    final pNum = page['page'] as int;
    final ayahs = page['ayahs'] as List<dynamic>;
    pageAyahMap[pNum] = ayahs.cast<Map<String, dynamic>>().toList();
  }

  // 4) Check each surah: verify ayah 1 exists on its start page
  print('\n\n========================================');
  print('SURAH BOUNDARY CHECKS');
  print('========================================');
  int errors = 0;
  for (int s = 1; s <= 114; s++) {
    final startPage = surahStartPages[s]!;
    final pageAyahs = pageAyahMap[startPage] ?? [];
    
    bool found = pageAyahs.any((a) => a['surah'] == s && a['ayah'] == 1);
    if (!found) {
      print('❌ Surah $s: Ayah 1 NOT found on expected page $startPage');
      // Search where it actually is
      for (int p = 1; p <= 604; p++) {
        final pa = pageAyahMap[p] ?? [];
        if (pa.any((a) => a['surah'] == s && a['ayah'] == 1)) {
          print('   → Actually found on page $p');
          break;
        }
      }
      errors++;
    }
  }
  if (errors == 0) print('✅ All surah starts are on correct pages');

  // 5) Check ayah continuity within each surah
  print('\n\n========================================');
  print('AYAH CONTINUITY CHECKS');
  print('========================================');
  
  // Collect all ayahs per surah across all pages
  final surahAyahs = <int, List<int>>{};
  for (final page in flattened) {
    final ayahs = page['ayahs'] as List<dynamic>;
    for (final a in ayahs) {
      final s = a['surah'] as int;
      final ay = a['ayah'] as int;
      surahAyahs.putIfAbsent(s, () => []);
      surahAyahs[s]!.add(ay);
    }
  }

  int contErrors = 0;
  for (int s = 1; s <= 114; s++) {
    final ayahs = surahAyahs[s] ?? [];
    final expectedCount = surahAyahCounts[s] ?? 0;
    
    if (ayahs.isEmpty) {
      print('❌ Surah $s: NO ayahs found at all!');
      contErrors++;
      continue;
    }
    
    // Check for duplicates
    final dupes = <int>[];
    final seen = <int>{};
    for (final a in ayahs) {
      if (seen.contains(a)) dupes.add(a);
      seen.add(a);
    }
    
    // Check for missing
    final missing = <int>[];
    for (int a = 1; a <= expectedCount; a++) {
      if (!seen.contains(a)) missing.add(a);
    }
    
    // Check for extra
    final extra = <int>[];
    for (final a in seen) {
      if (a > expectedCount || a < 1) extra.add(a);
    }
    
    if (dupes.isNotEmpty || missing.isNotEmpty || extra.isNotEmpty) {
      print('❌ Surah $s (expected $expectedCount ayahs, found ${seen.length}):');
      if (missing.isNotEmpty) print('   Missing: $missing');
      if (dupes.isNotEmpty) print('   Duplicates: $dupes');
      if (extra.isNotEmpty) print('   Extra/Out-of-range: $extra');
      contErrors++;
    }
  }
  if (contErrors == 0) print('✅ All surahs have correct ayah sequences');

  // 6) Check page boundaries for surahs 4-10 in detail
  print('\n\n========================================');
  print('DETAILED PAGE BOUNDARIES (Surahs 4-10)');
  print('========================================');
  for (int s = 4; s <= 10; s++) {
    final startP = surahStartPages[s]!;
    final nextSurahStartP = s < 114 ? surahStartPages[s + 1]! : 605;
    
    print('\n--- Surah $s (pages $startP to ${nextSurahStartP - 1}) ---');
    for (int p = startP; p < nextSurahStartP && p <= 604; p++) {
      final ayahs = pageAyahMap[p] ?? [];
      final surahAyahsOnPage = ayahs.where((a) => a['surah'] == s).toList();
      if (surahAyahsOnPage.isNotEmpty) {
        final first = surahAyahsOnPage.first['ayah'];
        final last = surahAyahsOnPage.last['ayah'];
        print('  Page $p: Ayah $first - $last (${surahAyahsOnPage.length} ayahs)');
      }
    }
  }
}

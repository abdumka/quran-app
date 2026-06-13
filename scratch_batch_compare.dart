import 'dart:convert';
import 'dart:io';

/// Fetches Hafs text from API for a specific surah and compares with Qalon
/// to find exact merge/split points.
void main() async {
  final qalonFile = File('assets/data/output.json');
  final qalonJsonStr = await qalonFile.readAsString();
  final qalonDecoded = jsonDecode(qalonJsonStr);

  final List<dynamic> qalonData = [];
  for (final item in qalonDecoded) {
    if (item is List) qalonData.addAll(item);
    else qalonData.add(item);
  }

  // Surahs to check (from 25 onwards)
  final surahs = [27, 31, 36, 37, 38, 39, 40, 41, 42, 44, 45, 46, 47, 52, 53, 55, 56, 57, 71, 75, 79, 80, 81, 86, 89, 91, 96, 99, 101, 106, 107];

  for (final surahNum in surahs) {
    // Get Qalon ayahs
    List<String> qalonAyahs = [];
    for (var page in qalonData) {
      for (var ayah in page['ayahs']) {
        if (ayah['surah'] == surahNum) {
          int ayahNum = ayah['ayah'];
          if (qalonAyahs.length < ayahNum) {
            qalonAyahs.add(ayah['text']);
          }
        }
      }
    }

    // Get Hafs ayahs from API
    try {
      final url = Uri.parse('http://api.alquran.cloud/v1/surah/$surahNum/quran-simple');
      final request = await HttpClient().getUrl(url);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final hafsDecoded = jsonDecode(responseBody);
      
      List<String> hafsAyahs = [];
      for (var a in hafsDecoded['data']['ayahs']) {
        hafsAyahs.add(a['text']);
      }

      final diff = qalonAyahs.length - hafsAyahs.length;
      final sign = diff > 0 ? '+' : '';
      print('\n${'=' * 60}');
      print('SURAH $surahNum: Qalon=${qalonAyahs.length}, Hafs=${hafsAyahs.length} ($sign$diff)');
      print('${'=' * 60}');

      // Normalize text for comparison
      String norm(String text) {
        return text
          .replaceAll(RegExp(r'[\u0617-\u061A\u064B-\u0652\u0670\u06D6-\u06ED]'), '') // Remove tashkeel
          .replaceAll(RegExp(r'[ٱ]'), 'ا')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      }

      // Walk through both arrays simultaneously to find divergence points
      int q = 0; // Qalon index
      int h = 0; // Hafs index

      while (q < qalonAyahs.length && h < hafsAyahs.length) {
        String qNorm = norm(qalonAyahs[q]);
        String hNorm = norm(hafsAyahs[h]);

        // Check if they're roughly the same length (within 15 chars)
        if ((qNorm.length - hNorm.length).abs() <= 15) {
          // Likely a match
          q++; h++;
          continue;
        }

        if (qNorm.length < hNorm.length * 0.7) {
          // Qalon is much shorter -> SPLIT: Two Qalon ayahs = one Hafs ayah
          print('  SPLIT at Qalon ${q+1} + ${q+2} = Hafs ${h+1}');
          print('    Q${q+1}: ${qalonAyahs[q].substring(0, qalonAyahs[q].length.clamp(0, 40))}...');
          if (q + 1 < qalonAyahs.length) {
            print('    Q${q+2}: ${qalonAyahs[q+1].substring(0, qalonAyahs[q+1].length.clamp(0, 40))}...');
          }
          print('    H${h+1}: ${hafsAyahs[h].substring(0, hafsAyahs[h].length.clamp(0, 60))}...');
          q += 2;
          h += 1;
        } else if (hNorm.length < qNorm.length * 0.7) {
          // Hafs is much shorter -> MERGE: One Qalon ayah = two Hafs ayahs
          print('  MERGE at Qalon ${q+1} = Hafs ${h+1} + ${h+2}');
          print('    Q${q+1}: ${qalonAyahs[q].substring(0, qalonAyahs[q].length.clamp(0, 60))}...');
          print('    H${h+1}: ${hafsAyahs[h].substring(0, hafsAyahs[h].length.clamp(0, 40))}...');
          if (h + 1 < hafsAyahs.length) {
            print('    H${h+2}: ${hafsAyahs[h+1].substring(0, hafsAyahs[h+1].length.clamp(0, 40))}...');
          }
          q += 1;
          h += 2;
        } else {
          // Close but not exact, could be slight variations
          // Try checking if next Qalon ayah is very short (indicating split)
          if (q + 1 < qalonAyahs.length) {
            String nextQNorm = norm(qalonAyahs[q + 1]);
            String combined = qNorm + ' ' + nextQNorm;
            if ((combined.length - hNorm.length).abs() < combined.length * 0.3) {
              print('  SPLIT at Qalon ${q+1} + ${q+2} = Hafs ${h+1}');
              print('    Q${q+1}: ${qalonAyahs[q].substring(0, qalonAyahs[q].length.clamp(0, 40))}...');
              print('    Q${q+2}: ${qalonAyahs[q+1].substring(0, qalonAyahs[q+1].length.clamp(0, 40))}...');
              q += 2;
              h += 1;
              continue;
            }
          }
          // Try merge
          if (h + 1 < hafsAyahs.length) {
            String nextHNorm = norm(hafsAyahs[h + 1]);
            String combined = hNorm + ' ' + nextHNorm;
            if ((combined.length - qNorm.length).abs() < combined.length * 0.3) {
              print('  MERGE at Qalon ${q+1} = Hafs ${h+1} + ${h+2}');
              print('    Q${q+1}: ${qalonAyahs[q].substring(0, qalonAyahs[q].length.clamp(0, 60))}...');
              q += 1;
              h += 2;
              continue;
            }
          }
          // Give up, move both forward
          print('  UNKNOWN MISMATCH at Q${q+1}/H${h+1} (qLen=${qNorm.length}, hLen=${hNorm.length})');
          print('    Q${q+1}: ${qalonAyahs[q].substring(0, qalonAyahs[q].length.clamp(0, 50))}...');
          print('    H${h+1}: ${hafsAyahs[h].substring(0, hafsAyahs[h].length.clamp(0, 50))}...');
          q++; h++;
        }
      }

      // If there are remaining ayahs in either
      if (q < qalonAyahs.length) {
        print('  REMAINING: ${qalonAyahs.length - q} extra Qalon ayahs from Q${q+1}');
      }
      if (h < hafsAyahs.length) {
        print('  REMAINING: ${hafsAyahs.length - h} extra Hafs ayahs from H${h+1}');
      }
    } catch (e) {
      print('ERROR fetching Surah $surahNum: $e');
    }
  }
}

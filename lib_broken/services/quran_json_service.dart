import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/quran_page_data.dart';

class QuranJsonService {
  static List<QuranPageData>? _cache;

  static Future<List<QuranPageData>> loadQuranPages() async {
    if (_cache != null) return _cache!;

    final jsonString = await rootBundle.loadString('assets/data/output.json');
    final decoded = json.decode(jsonString);

    if (decoded is! List) {
      throw Exception('JSON root must be a List');
    }

    final flattened = _flattenIfNeeded(decoded);

    final pages = flattened
        .map((e) => QuranPageData.fromJson(e as Map<String, dynamic>))
        .toList();

    // Inject spanning ayahs to fix synchronization issues
    _injectSpannedAyah(pages, 354, 355, 24, 36); // Surah 24 Ayah 36
    _injectSpannedAyah(pages, 355, 356, 24, 42); // Surah 24 Ayah 42

    _cache = pages;
    return pages;
  }

  /// Dynamically inject a spanning ayah into the first page if it's missing.
  static void _injectSpannedAyah(List<QuranPageData> pages, int fromPage, int toPage, int surah, int ayah) {
    final fromIndex = pages.indexWhere((p) => p.page == fromPage);
    if (fromIndex != -1) {
      final fromP = pages[fromIndex];
      if (!fromP.ayahs.any((a) => a.surah == surah && a.ayah == ayah)) {
        // Find the ayah data from the target page
        final toIndex = pages.indexWhere((p) => p.page == toPage);
        if (toIndex != -1) {
          final toP = pages[toIndex];
          final ayahData = toP.ayahs.firstWhere(
            (a) => a.surah == surah && a.ayah == ayah,
            orElse: () => QuranAyahData(
              surah: surah,
              surahName: '',
              ayah: ayah,
              text: '',
            ),
          );
          fromP.ayahs.add(ayahData);
        }
      }
    }
  }

  static List<dynamic> _flattenIfNeeded(List<dynamic> input) {
    final result = <dynamic>[];

    for (final item in input) {
      if (item is List) {
        result.addAll(item);
      } else {
        result.add(item);
      }
    }

    return result;
  }
}
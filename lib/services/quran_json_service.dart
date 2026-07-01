import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import '../models/quran_page_data.dart';

class QuranJsonService {
  static List<QuranPageData>? _cache;
  static Future<List<QuranPageData>>? _loading;

  static Future<List<QuranPageData>> loadQuranPages() {
    if (_cache != null) return Future.value(_cache!);
    // Coalesce concurrent callers (reader, audio, search) into one load;
    // clear the in-flight future when done so a failed load can be retried.
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<List<QuranPageData>> _load() async {
    final jsonString = await rootBundle.loadString('assets/data/output.json');

    // Parsing ~1.7 MB of JSON takes long enough to drop frames, so decode and
    // build the models on a background isolate instead of the UI thread.
    final pages = await compute(_parsePages, jsonString);

    // Inject spanning ayahs to fix synchronization issues
    _injectSpannedAyah(pages, 354, 355, 24, 36); // Surah 24 Ayah 36
    _injectSpannedAyah(pages, 355, 356, 24, 42); // Surah 24 Ayah 42

    _cache = pages;
    return pages;
  }

  static List<QuranPageData> _parsePages(String jsonString) {
    final decoded = json.decode(jsonString);

    if (decoded is! List) {
      throw Exception('JSON root must be a List');
    }

    final flattened = _flattenIfNeeded(decoded);

    return flattened
        .map((e) => QuranPageData.fromJson(e as Map<String, dynamic>))
        .toList();
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
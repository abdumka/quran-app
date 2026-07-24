import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/word_position_data.dart';
import '../utils/arabic_text_normalizer.dart';

/// Loads the word-level bounding boxes (`assets/data/word_positions.json`)
/// used by the memorization-test reveal overlay.
///
/// Mirrors `AyahPositionService`'s asset-load-and-cache shape, but
/// deliberately without that service's local-override/SharedPreferences
/// layers -- those exist to support an in-app ayah-position *editor*, which
/// word positions don't have (they're hand-calibrated offline by
/// `tools/generate_word_positions_page1.py`).
class WordPositionService {
  static const String _assetPath = 'assets/data/word_positions.json';
  static Map<int, WordPositionPageData>? _cache;

  /// Loads and caches all word positions, keyed by page number. Returns an
  /// empty map if the asset is missing/corrupt (callers treat "no data for
  /// this page" as "feature unavailable here", never as an error).
  static Future<Map<int, WordPositionPageData>> loadWordPositions() async {
    if (_cache != null) return _cache!;
    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      final decoded = json.decode(jsonString) as List<dynamic>;
      _cache = {
        for (final item in decoded)
          (item as Map<String, dynamic>)['page'] as int:
              WordPositionPageData.fromJson(item),
      };
    } catch (error) {
      debugPrint('WordPositionService: failed to load $_assetPath: $error');
      _cache = const {};
    }
    return _cache!;
  }

  /// Word positions for one page, or null when the page has no word data
  /// (currently everything except page 1 -- the memorization-test POC).
  static Future<WordPositionPageData?> forPage(int page) async {
    final all = await loadWordPositions();
    return all[page];
  }

  /// Sanity-checks a page's word boxes against the live expected words from
  /// `output.json` (the runtime source of truth). Returns a list of
  /// human-readable problems -- empty means consistent. Logs (but does not
  /// throw) on mismatch, per the plan's "warn, don't crash, on drift".
  static List<String> validateAgainstExpectedWords(
    WordPositionPageData pageData,
    Map<int, List<String>> expectedWordsByAyah,
  ) {
    final problems = <String>[];
    for (final ayah in pageData.ayahs) {
      final expected = expectedWordsByAyah[ayah.ayah];
      if (expected == null) {
        problems.add(
          'ayah ${ayah.ayah}: no expected words found in output.json',
        );
        continue;
      }
      if (expected.length != ayah.words.length) {
        problems.add(
          'ayah ${ayah.ayah}: ${ayah.words.length} word boxes but '
          '${expected.length} words in output.json',
        );
        continue;
      }
      for (var i = 0; i < expected.length; i++) {
        if (normalizeArabicText(ayah.words[i].text) !=
            normalizeArabicText(expected[i])) {
          problems.add(
            'ayah ${ayah.ayah} word $i: box text "${ayah.words[i].text}" != '
            'output.json "${expected[i]}"',
          );
        }
      }
    }
    for (final problem in problems) {
      debugPrint('WordPositionService: DRIFT WARNING: $problem');
    }
    return problems;
  }
}

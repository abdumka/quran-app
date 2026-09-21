import 'dart:convert';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/word_region_data.dart';

/// Loads `assets/data/word_masks.json`: for every word of every page the
/// small rectangles that cover exactly its ink, generated offline by
/// `tools/generate_word_masks.py` from the bundled page images and the ayah
/// line rects, plus each page's placement inside the margin-view image.
/// Lets the memorization test reveal the page word by word.
class WordRegionService {
  static const String _assetPath = 'assets/data/word_masks.json';
  static Map<int, WordRegionPageData>? _cache;
  static Future<Map<int, WordRegionPageData>>? _loading;

  static Future<Map<int, WordRegionPageData>> loadAll() {
    if (_cache != null) return Future.value(_cache!);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<Map<int, WordRegionPageData>> _load() async {
    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      _cache = await compute(_parse, jsonString);
    } catch (error) {
      debugPrint('WordRegionService: failed to load $_assetPath: $error');
      _cache = const {};
    }
    return _cache!;
  }

  static Map<int, WordRegionPageData> _parse(String jsonString) {
    final decoded = json.decode(jsonString) as List<dynamic>;
    return {
      for (final item in decoded)
        (item as Map<String, dynamic>)['page'] as int:
            WordRegionPageData.fromJson(item),
    };
  }

  /// Word boxes for one 1-based mushaf page, or null when unavailable.
  static Future<WordRegionPageData?> forPage(int page) async =>
      (await loadAll())[page];
}

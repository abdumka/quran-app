import 'dart:convert';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/word_region_data.dart';
import 'content_update_service.dart';

/// Loads `assets/data/word_masks.json`: for every word of every page the
/// small rectangles that cover exactly its ink, generated offline by
/// `tools/generate_word_masks.py` from the bundled page images and the ayah
/// line rects, plus each page's placement inside the margin-view image.
/// Lets the memorization test reveal the page word by word.
///
/// Corrections published after this build shipped (a word whose boxes sat on
/// its neighbour, a letter left out) arrive as a patch file through
/// [ContentUpdateService]: a list of ayat whose `words` replace the bundled
/// ones. It is applied here, at load, so every reader of the boxes — the
/// Tasmee masks, the playing-ayah tint, the tanzilat colours — sees the same
/// corrected page.
class WordRegionService {
  static const String _assetPath = 'assets/data/word_masks.json';
  static Map<int, WordRegionPageData>? _cache;
  static Future<Map<int, WordRegionPageData>>? _loading;

  static Future<Map<int, WordRegionPageData>> loadAll() {
    if (_cache != null) return Future.value(_cache!);
    if (_loading == null) {
      // A patch landing after this point shows at the next launch.
      ContentUpdateService.instance.registerItem(
        'word_masks',
        isLoaded: () => _cache != null || _loading != null,
      );
    }
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<Map<int, WordRegionPageData>> _load() async {
    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      final patch = await ContentUpdateService.instance.readFor('word_masks');
      _cache = await compute(parseWordMasks, (jsonString, patch));
    } catch (error) {
      debugPrint('WordRegionService: failed to load $_assetPath: $error');
      _cache = const {};
    }
    return _cache!;
  }

  /// Word boxes for one 1-based mushaf page, or null when unavailable.
  static Future<WordRegionPageData?> forPage(int page) async =>
      (await loadAll())[page];
}

/// Parses the asset and lays [patch] (`{"patches":[{"page","surah","ayah",
/// "words"}]}`, or null) over it. Top level so it can run in an isolate.
Map<int, WordRegionPageData> parseWordMasks((String, String?) input) {
  final (jsonString, patch) = input;
  final decoded = json.decode(jsonString) as List<dynamic>;
  final pages = <int, Map<String, dynamic>>{
    for (final item in decoded)
      (item as Map<String, dynamic>)['page'] as int: item,
  };
  if (patch != null) {
    try {
      final patches =
          (json.decode(patch) as Map<String, dynamic>)['patches']
              as List<dynamic>;
      for (final p in patches) {
        final m = p as Map<String, dynamic>;
        final page = pages[m['page'] as int];
        if (page == null) continue;
        // `"cont": true` = the opening words of an ayah that runs onto the
        // next page (the page's `cont` entry)
        if (m['cont'] == true) {
          final c = page['cont'];
          if (c is Map<String, dynamic> &&
              c['surah'] == m['surah'] &&
              c['ayah'] == m['ayah']) {
            c['words'] = m['words'];
          } else {
            page['cont'] = {
              'surah': m['surah'],
              'ayah': m['ayah'],
              'words': m['words'],
            };
          }
          continue;
        }
        for (final ayah in page['ayahs'] as List<dynamic>) {
          final a = ayah as Map<String, dynamic>;
          if (a['surah'] == m['surah'] && a['ayah'] == m['ayah']) {
            a['words'] = m['words'];
          }
        }
      }
    } catch (error) {
      debugPrint('WordRegionService: bad patch ignored: $error');
    }
  }
  return {
    for (final e in pages.entries) e.key: WordRegionPageData.fromJson(e.value),
  };
}

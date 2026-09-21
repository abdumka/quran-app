import 'dart:convert';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/ayah_region_data.dart';

/// Loads `assets/data/ayah_regions.json`: per-ayah line rects and marker
/// boxes for all 602 pages, generated offline by
/// `tools/generate_ayah_regions.py` from the bundled page images.
class AyahRegionService {
  static const String _assetPath = 'assets/data/ayah_regions.json';
  static Map<int, AyahRegionPageData>? _cache;
  static Future<Map<int, AyahRegionPageData>>? _loading;

  static Future<Map<int, AyahRegionPageData>> loadAll() {
    if (_cache != null) return Future.value(_cache!);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<Map<int, AyahRegionPageData>> _load() async {
    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      // ~1.4 MB of JSON; keep the decode off the UI thread.
      _cache = await compute(_parse, jsonString);
    } catch (error) {
      debugPrint('AyahRegionService: failed to load $_assetPath: $error');
      _cache = const {};
    }
    return _cache!;
  }

  static Map<int, AyahRegionPageData> _parse(String jsonString) {
    final decoded = json.decode(jsonString) as List<dynamic>;
    return {
      for (final item in decoded)
        (item as Map<String, dynamic>)['page'] as int:
            AyahRegionPageData.fromJson(item),
    };
  }

  /// Regions for one 1-based mushaf page, or null when unavailable.
  static Future<AyahRegionPageData?> forPage(int page) async =>
      (await loadAll())[page];
}

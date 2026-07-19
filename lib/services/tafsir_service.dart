import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/quran_page_data.dart';
import '../models/tafsir_edition.dart';
import 'quran_json_service.dart';
import 'tafsir_cache_service.dart';
import 'tafsir_edition_service.dart';

class TafsirService {
  /// Decoded data for each **bundled** edition, keyed by edition id. Shape:
  /// `List<surah> of List<hafsAyah> of String`. Kept per-edition so switching
  /// back and forth doesn't re-decode.
  static final Map<String, List<dynamic>> _bundledData = {};

  static List<QuranPageData>? _quranPages;

  /// Maps the app's Qalun (Madani) ayah numbering to the Hafs (Kufi) numbering
  /// used by the source tafaseer. Shape: { "surah": { "qalunAyah": hafsAyah |
  /// [start,end] } }. Only ayahs whose number differs are listed; anything
  /// missing is 1:1. Generated and content-verified by generate_narration_map.py.
  static Map<String, dynamic>? _narrationMap;

  /// Loads the Qalun→Hafs map (used only by the bundled editions; the online
  /// editions bake the mapping into their per-page files at build time).
  static Future<void> _loadNarrationMap() async {
    if (_narrationMap != null) return;
    try {
      final mapString =
          await rootBundle.loadString('assets/data/narration_map.json');
      final decoded = json.decode(mapString);
      _narrationMap =
          (decoded['qalun_to_hafs'] as Map?)?.cast<String, dynamic>() ?? {};
    } catch (_) {
      // Missing/invalid map → fall back to a pure 1:1 mapping.
      _narrationMap = {};
    }
  }

  static Future<void> _loadQuranPages() async {
    _quranPages ??= await QuranJsonService.loadQuranPages();
  }

  /// Loads (and caches) a bundled edition's `assets/data/<edition>.json`.
  /// The file is a few MB, so it's decoded on a background isolate to keep the
  /// UI thread free when the sheet first opens.
  static Future<List<dynamic>> _loadBundled(TafsirEdition edition) async {
    final cached = _bundledData[edition.id];
    if (cached != null) return cached;
    final jsonString = await rootBundle.loadString(edition.assetPath!);
    final decoded = await compute(json.decode, jsonString);
    final data = (decoded['tafsir'] as List<dynamic>?) ?? const [];
    _bundledData[edition.id] = data;
    return data;
  }

  /// Returns the Hafs ayah number(s) that a Qalun ayah corresponds to. Usually
  /// a single number; a list (range) when one Qalun ayah spans several Hafs
  /// ayahs (e.g. a verse opening with the muqatta'at letters).
  static List<int> _hafsAyahsFor(int surah, int qalunAyah) {
    final surahMap = _narrationMap?['$surah'];
    if (surahMap is Map) {
      final value = surahMap['$qalunAyah'];
      if (value is int) return [value];
      if (value is List && value.length == 2) {
        final start = (value[0] as num).toInt();
        final end = (value[1] as num).toInt();
        if (end >= start) {
          return [for (var h = start; h <= end; h++) h];
        }
      }
    }
    return [qalunAyah]; // 1:1 fallback
  }

  static String _tafsirForHafsAyah(
    List<dynamic> data,
    int surahIdx,
    int hafsAyah,
  ) {
    final ayahIdx = hafsAyah - 1;
    if (surahIdx >= 0 &&
        surahIdx < data.length &&
        ayahIdx >= 0 &&
        ayahIdx < data[surahIdx].length) {
      return data[surahIdx][ayahIdx].toString();
    }
    return '';
  }

  static QuranPageData? _pageDataFor(int pageNumber) {
    return _quranPages?.firstWhere(
      (p) => p.page == pageNumber,
      orElse: () => QuranPageData(page: pageNumber, ayahs: []),
    );
  }

  /// Returns the tafsir rows for a page (one per ayah on the page) for the
  /// currently selected edition. Bundled editions read their asset + translate
  /// Qalun→Hafs at runtime; online editions fetch/cache a pre-baked per-page
  /// file (mapping already applied).
  static Future<List<Map<String, dynamic>>> getTafsirForPage(
    int pageIndex,
  ) async {
    await _loadQuranPages();

    final edition = TafsirEditionService.instance.selected.value;
    final int pageNumber = pageIndex + 1;
    final pageData = _pageDataFor(pageNumber);
    if (pageData == null || pageData.ayahs.isEmpty) return [];

    return edition.isBundled
        ? _bundledPage(edition, pageData)
        : _onlinePage(edition, pageNumber, pageData);
  }

  // ── Bundled editions (Sa'di, Muyassar) ────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _bundledPage(
    TafsirEdition edition,
    QuranPageData pageData,
  ) async {
    await _loadNarrationMap();
    final data = await _loadBundled(edition);

    final tafsirList = <Map<String, dynamic>>[];
    for (final ayah in pageData.ayahs) {
      // The app's surah/ayah are Qalun-numbered; translate to Hafs before the
      // lookup, joining the text when a verse spans several Hafs ayahs so
      // nothing is dropped.
      final surahIdx = ayah.surah - 1;
      final hafsAyahs = _hafsAyahsFor(ayah.surah, ayah.ayah);

      String tafsirText = 'تفسير غير متوفر';
      try {
        final parts = <String>[];
        for (final hafsAyah in hafsAyahs) {
          final part = _tafsirForHafsAyah(data, surahIdx, hafsAyah);
          // When one Qalun ayah spans several Hafs ayahs that share a single
          // grouped commentary block, those Hafs slots hold identical text —
          // collapse consecutive duplicates so it isn't shown twice, while
          // still joining genuinely distinct commentary.
          if (part.trim().isNotEmpty &&
              (parts.isEmpty || parts.last != part)) {
            parts.add(part);
          }
        }
        if (parts.isNotEmpty) tafsirText = parts.join('\n\n');
      } catch (_) {
        // Fallback text stays.
      }

      tafsirList.add({
        'surahName': ayah.surahName,
        'ayahNumber': ayah.ayah,
        'ayahText': ayah.text,
        'tafsir': tafsirText,
      });
    }
    return tafsirList;
  }

  // ── Online editions (Ibn Kathir, Tabari, Qurtubi, Zad al-Masir) ───────────

  static Future<List<Map<String, dynamic>>> _onlinePage(
    TafsirEdition edition,
    int pageNumber,
    QuranPageData pageData,
  ) async {
    // 1) cached page, else 2) fetch + cache. The per-page file already holds the
    // final text per app (Qalun) ayah — the Qalun→Hafs mapping and multi-ayah
    // joining were baked in at build time (tools/build_tafsir_pages.py).
    String? jsonStr =
        await TafsirCacheService.instance.readPage(edition, pageNumber);
    if (jsonStr == null) {
      try {
        final response =
            await http.get(Uri.parse(edition.pageUrl(pageNumber)));
        if (response.statusCode == 200) {
          jsonStr = utf8.decode(response.bodyBytes);
          await TafsirCacheService.instance
              .writePage(edition, pageNumber, jsonStr);
        }
      } catch (_) {
        // No network and nothing cached → handled below.
      }
    }

    final byKey = <String, String>{};
    if (jsonStr != null) {
      try {
        final decoded = json.decode(jsonStr);
        final list =
            (decoded is Map ? decoded['ayat'] : decoded) as List? ?? const [];
        for (final e in list) {
          if (e is Map) {
            byKey['${e['surah']}:${e['ayah']}'] = (e['text'] ?? '').toString();
          }
        }
      } catch (_) {
        // Corrupt cache → treat as unavailable for this page.
      }
    }

    final unavailable = jsonStr == null;
    final tafsirList = <Map<String, dynamic>>[];
    for (final ayah in pageData.ayahs) {
      String tafsirText;
      if (unavailable) {
        tafsirText = 'يتطلب اتصالاً بالإنترنت لعرض هذا التفسير لأول مرة';
      } else {
        final text = byKey['${ayah.surah}:${ayah.ayah}'];
        tafsirText =
            (text != null && text.trim().isNotEmpty) ? text : 'تفسير غير متوفر';
      }
      tafsirList.add({
        'surahName': ayah.surahName,
        'ayahNumber': ayah.ayah,
        'ayahText': ayah.text,
        'tafsir': tafsirText,
      });
    }
    return tafsirList;
  }
}

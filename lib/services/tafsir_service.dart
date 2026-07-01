import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import '../models/quran_page_data.dart';
import 'quran_json_service.dart';

class TafsirService {
  static List<dynamic>? _tafsirData;
  static List<QuranPageData>? _quranPages;

  /// Maps the app's Qalun (Madani) ayah numbering to the Hafs (Kufi) numbering
  /// used by the Sa'di tafsir. Shape: { "surah": { "qalunAyah": hafsAyah | [start,end] } }.
  /// Only ayahs whose number differs are listed; anything missing is 1:1.
  /// Generated and content-verified by generate_narration_map.py (repo root).
  static Map<String, dynamic>? _narrationMap;

  static Future<void> loadData() async {
    if (_tafsirData == null) {
      final jsonString = await rootBundle.loadString('assets/data/ar.saddi.json');
      // ~5.8 MB of JSON — decode on a background isolate so opening the
      // tafsir panel for the first time doesn't freeze the UI.
      final decoded = await compute(json.decode, jsonString);
      _tafsirData = decoded['tafsir'];
    }

    if (_narrationMap == null) {
      try {
        final mapString =
            await rootBundle.loadString('assets/data/narration_map.json');
        final decoded = json.decode(mapString);
        _narrationMap = (decoded['qalun_to_hafs'] as Map?)?.cast<String, dynamic>() ?? {};
      } catch (_) {
        // Missing/invalid map → fall back to a pure 1:1 mapping.
        _narrationMap = {};
      }
    }

    _quranPages ??= await QuranJsonService.loadQuranPages();
  }

  /// Returns the Hafs ayah number(s) that a Qalun ayah corresponds to.
  /// Usually a single number; a list (range) when one Qalun ayah spans several
  /// Hafs ayahs (e.g. a verse that opens with the muqatta'at letters).
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

  static String _tafsirForHafsAyah(int surahIdx, int hafsAyah) {
    final ayahIdx = hafsAyah - 1;
    if (_tafsirData != null &&
        surahIdx >= 0 &&
        surahIdx < _tafsirData!.length &&
        ayahIdx >= 0 &&
        ayahIdx < _tafsirData![surahIdx].length) {
      return _tafsirData![surahIdx][ayahIdx].toString();
    }
    return '';
  }

  static Future<List<Map<String, dynamic>>> getTafsirForPage(int pageIndex) async {
    await loadData();

    final int pageNumber = pageIndex + 1;
    final pageData = _quranPages?.firstWhere(
      (p) => p.page == pageNumber,
      orElse: () => QuranPageData(page: pageNumber, ayahs: []),
    );

    if (pageData == null || pageData.ayahs.isEmpty) {
      return [];
    }

    List<Map<String, dynamic>> tafsirList = [];
    for (var ayah in pageData.ayahs) {
      // The app's surah/ayah are Qalun-numbered; translate to Hafs before
      // looking up the tafsir, joining the text when a verse spans several
      // Hafs ayahs so nothing is dropped.
      final surahIdx = ayah.surah - 1;
      final hafsAyahs = _hafsAyahsFor(ayah.surah, ayah.ayah);

      String tafsirText = 'تفسير غير متوفر';
      try {
        final parts = <String>[];
        for (final hafsAyah in hafsAyahs) {
          final part = _tafsirForHafsAyah(surahIdx, hafsAyah);
          if (part.trim().isNotEmpty) parts.add(part);
        }
        if (parts.isNotEmpty) {
          tafsirText = parts.join('\n\n');
        }
      } catch (e) {
        // Fallback
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

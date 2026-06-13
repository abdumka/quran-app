import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/quran_page_data.dart';
import 'quran_json_service.dart';

class TafsirService {
  static List<dynamic>? _tafsirData;
  static List<QuranPageData>? _quranPages;

  static Future<void> loadData() async {
    if (_tafsirData == null) {
      final jsonString = await rootBundle.loadString('assets/data/ar.saddi.json');
      final decoded = json.decode(jsonString);
      _tafsirData = decoded['tafsir'];
    }
    
    if (_quranPages == null) {
      _quranPages = await QuranJsonService.loadQuranPages();
    }
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
      // surah and ayah are 1-indexed in output.json
      final surahIdx = ayah.surah - 1;
      final ayahIdx = ayah.ayah - 1;
      
      String tafsirText = 'تفسير غير متوفر';
      try {
        if (_tafsirData != null && 
            surahIdx >= 0 && surahIdx < _tafsirData!.length &&
            ayahIdx >= 0 && ayahIdx < _tafsirData![surahIdx].length) {
          tafsirText = _tafsirData![surahIdx][ayahIdx].toString();
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

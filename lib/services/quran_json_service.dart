import 'dart:convert';
import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import '../models/quran_page_data.dart';
import 'content_update_service.dart';
import 'quran_text_patch.dart';

class QuranJsonService {
  static List<QuranPageData>? _cache;
  static Future<List<QuranPageData>>? _loading;

  static Future<List<QuranPageData>> loadQuranPages() {
    if (_cache != null) return Future.value(_cache!);
    if (_loading == null) {
      // Text corrections from the server apply only here, at load: one that
      // lands later shows at the next launch, so the text under a running
      // recitation, Tasmee session or search never changes.
      ContentUpdateService.instance.registerItem(
        'quran_text',
        isLoaded: () => _cache != null || _loading != null,
      );
    }
    // Coalesce concurrent callers (reader, audio, search) into one load;
    // clear the in-flight future when done so a failed load can be retried.
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<List<QuranPageData>> _load() async {
    final results = await Future.wait<String?>([
      rootBundle.loadString('assets/data/output.json'),
      _readPatch(),
    ]);

    // Parsing ~1.7 MB of JSON takes long enough to drop frames, so decode and
    // build the models on a background isolate instead of the UI thread.
    final pages = await compute(parsePages, (results[0]!, results[1]));

    _cache = pages;
    return pages;
  }

  /// Tests only: forget the loaded text, as a new launch would.
  @visibleForTesting
  static void debugReset() {
    _cache = null;
    _loading = null;
  }

  /// The downloaded text corrections, or null. Never throws: without them
  /// the bundled text is used.
  static Future<String?> _readPatch() async {
    try {
      return await ContentUpdateService.instance.readFor('quran_text');
    } catch (e) {
      debugPrint('QuranJsonService: text corrections not read: $e');
      return null;
    }
  }

  /// Parses `output.json` and lays the server's text corrections ([patch],
  /// or null) over it. A patch that breaks any rule of [QuranTextPatch] is
  /// ignored as a whole. Top level of the isolate, so it must stay static.
  @visibleForTesting
  static List<QuranPageData> parsePages((String, String?) input) {
    final (jsonString, patch) = input;
    final decoded = json.decode(jsonString);

    if (decoded is! List) {
      throw Exception('JSON root must be a List');
    }

    final flattened = _flattenIfNeeded(decoded);

    if (patch != null) {
      try {
        final stats = QuranTextPatch.apply(
          flattened,
          QuranTextPatch.parse(patch),
        );
        debugPrint('QuranJsonService: text corrections $stats');
      } catch (e) {
        debugPrint('QuranJsonService: text corrections ignored: $e');
      }
    }

    return flattened
        .map((e) => QuranPageData.fromJson(e as Map<String, dynamic>))
        .toList();
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

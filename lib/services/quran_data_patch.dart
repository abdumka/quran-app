import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'content_update_service.dart';

/// Corrections to the smaller bundled data sets that arrive from our server
/// after a build shipped (the `quran_data` item of `ContentUpdateService`,
/// from `tools/content_updates/quran_data.json`). Every section is optional:
///
///     {"ver": 2,
///      "ayahRegions": {"35": {"ayahs": [...], "continues": {...}}},
///      "audioAyahMap": {"20": {"24": [25]}},
///      "breathData": {"assets/data/qaniwah_continuations.json":
///                       {"continuations": {"2": [5]}, "basmala_in_ayah1": [1]}},
///      "narrationMap": {"2": {"1": [1, 2], "2": 3}},
///      "tafsirFixes": [{"edition": "saddi", "surah": 2, "ayah": 5,
///                       "text": "…"}]}
///
///   * `ayahRegions`: whole pages of `assets/data/ayah_regions.json` (the
///     highlight and Tasmee masks of each ayah), each exactly as in that
///     file. A page is replaced only when it lists the same ayat in the same
///     order as the bundle: moving an ayah to another page is a layout change
///     and needs a release.
///   * `audioAyahMap` / `narrationMap`: the whole `map` / `qalun_to_hafs`
///     table of `audio_ayah_map.json` / `narration_map.json`.
///   * `breathData`: the whole الوقف الهبطي file of a bundled reciter, keyed
///     by its asset path.
///   * `tafsirFixes`: one ayah's text of a bundled tafsir (Hafs numbering, as
///     in that edition's file).
///
/// A file that breaks a rule of shape is refused as a whole ([parse]), at
/// download and again at load; the bundled data is then used. Read once per
/// run, when the first of those data sets loads.
class QuranDataPatch {
  QuranDataPatch._({
    required this.ver,
    required this.ayahRegions,
    required this.audioAyahMap,
    required this.breathData,
    required this.narrationMap,
    required this.tafsirFixes,
  });

  final int ver;

  /// Page -> the page's entry as in `ayah_regions.json` (with `page` set).
  final Map<int, Map<String, dynamic>> ayahRegions;
  final Map<int, Map<int, List<int>>>? audioAyahMap;
  final Map<String, Map<String, dynamic>> breathData;
  final Map<String, dynamic>? narrationMap;

  /// edition id -> "surah:ayah" -> text.
  final Map<String, Map<String, String>> tafsirFixes;

  static const Set<String> tafsirEditions = {'saddi', 'muyassar', 'jalalayn'};

  static Future<QuranDataPatch?>? _loading;

  /// The downloaded patch, or null (none, or refused). Read once per run.
  static Future<QuranDataPatch?> load() => _loading ??= _load();

  static Future<QuranDataPatch?> _load() async {
    // Read once per run: a newer file downloaded later waits for the next.
    ContentUpdateService.instance.registerItem('quran_data', isLoaded: () => true);
    try {
      final text = await ContentUpdateService.instance.readFor('quran_data');
      if (text == null) return null;
      final patch = parse(text);
      debugPrint('QuranDataPatch: v${patch.ver}');
      return patch;
    } catch (e) {
      debugPrint('QuranDataPatch: ignored: $e');
      return null;
    }
  }

  @visibleForTesting
  static void debugReset() => _loading = null;

  static int? _int(String s, int min, int max) {
    final n = int.tryParse(s);
    return n != null && n >= min && n <= max ? n : null;
  }

  /// Page-relative 0..1, with the small overhang the bundle itself has (an
  /// end marker at the very edge sits at x = -0.004).
  static bool _ratio(Object? v) =>
      v is num && v.isFinite && v >= -0.05 && v <= 1.05;

  static bool _rect(Object? r) {
    if (r is! Map) return false;
    final x = r['x'], y = r['y'], w = r['width'], h = r['height'];
    if (!_ratio(x) || !_ratio(y) || !_ratio(w) || !_ratio(h)) return false;
    return (w as num) > 0 &&
        (h as num) > 0 &&
        (x as num) + w <= 1.05 &&
        (y as num) + h <= 1.05;
  }

  static bool _region(Object? a) {
    if (a is! Map) return false;
    final s = a['surah'], n = a['ayah'], rects = a['rects'], m = a['marker'];
    if (s is! int || s < 1 || s > 114 || n is! int || n < 1 || n > 286) {
      return false;
    }
    if (rects is! List || rects.isEmpty || !rects.every(_rect)) return false;
    return m == null || _rect(m);
  }

  /// Reads and checks a patch file. Throws [FormatException] when anything is
  /// out of shape.
  static QuranDataPatch parse(String source) {
    final d = json.decode(source);
    if (d is! Map<String, dynamic>) {
      throw const FormatException('quran_data: not an object');
    }
    final ver = d['ver'];
    if (ver is! int) throw const FormatException('quran_data: no ver');

    final regions = <int, Map<String, dynamic>>{};
    final rawRegions = d['ayahRegions'];
    if (rawRegions != null) {
      if (rawRegions is! Map<String, dynamic>) {
        throw const FormatException('quran_data: bad ayahRegions');
      }
      rawRegions.forEach((k, v) {
        final page = _int(k, 1, 604);
        if (page == null || v is! Map<String, dynamic>) {
          throw FormatException('quran_data: bad region page $k');
        }
        final ayahs = v['ayahs'];
        if (ayahs is! List || ayahs.isEmpty || !ayahs.every(_region)) {
          throw FormatException('quran_data: bad regions on page $k');
        }
        final cont = v['continues'];
        if (cont != null && !_region(cont)) {
          throw FormatException('quran_data: bad continues on page $k');
        }
        regions[page] = {...v, 'page': page};
      });
    }

    Map<int, Map<int, List<int>>>? audioMap;
    final rawAudio = d['audioAyahMap'];
    if (rawAudio != null) {
      if (rawAudio is! Map<String, dynamic>) {
        throw const FormatException('quran_data: bad audioAyahMap');
      }
      audioMap = {};
      rawAudio.forEach((sk, ayahs) {
        final s = _int(sk, 1, 114);
        if (s == null || ayahs is! Map<String, dynamic>) {
          throw FormatException('quran_data: bad audio surah $sk');
        }
        final inner = <int, List<int>>{};
        ayahs.forEach((ak, files) {
          final a = _int(ak, 1, 286);
          if (a == null ||
              files is! List ||
              !files.every((f) => f is int && f >= 0 && f <= 286)) {
            throw FormatException('quran_data: bad audio ayah $sk:$ak');
          }
          inner[a] = files.cast<int>();
        });
        audioMap![s] = inner;
      });
    }

    final breath = <String, Map<String, dynamic>>{};
    final rawBreath = d['breathData'];
    if (rawBreath != null) {
      if (rawBreath is! Map<String, dynamic>) {
        throw const FormatException('quran_data: bad breathData');
      }
      rawBreath.forEach((asset, v) {
        if (!asset.startsWith('assets/data/') ||
            !asset.endsWith('.json') ||
            asset.contains('..') ||
            v is! Map<String, dynamic>) {
          throw FormatException('quran_data: bad breath asset $asset');
        }
        final cont = v['continuations'];
        if (cont is! Map<String, dynamic>) {
          throw FormatException('quran_data: $asset has no continuations');
        }
        cont.forEach((sk, ayat) {
          if (_int(sk, 1, 114) == null ||
              ayat is! List ||
              !ayat.every((a) => a is int && a >= 1 && a <= 286)) {
            throw FormatException('quran_data: bad breath surah $sk');
          }
        });
        final basmala = v['basmala_in_ayah1'] ?? const [];
        if (basmala is! List ||
            !basmala.every((s) => s is int && s >= 1 && s <= 114)) {
          throw FormatException('quran_data: bad basmala list in $asset');
        }
        breath[asset] = v;
      });
    }

    Map<String, dynamic>? narration;
    final rawNarration = d['narrationMap'];
    if (rawNarration != null) {
      if (rawNarration is! Map<String, dynamic>) {
        throw const FormatException('quran_data: bad narrationMap');
      }
      bool hafs(Object? v) =>
          (v is int && v >= 1 && v <= 286) ||
          (v is List &&
              v.length == 2 &&
              v.every((n) => n is int && n >= 1 && n <= 286) &&
              (v[0] as int) <= (v[1] as int));
      rawNarration.forEach((sk, ayahs) {
        if (_int(sk, 1, 114) == null || ayahs is! Map<String, dynamic>) {
          throw FormatException('quran_data: bad narration surah $sk');
        }
        ayahs.forEach((ak, v) {
          if (_int(ak, 1, 286) == null || !hafs(v)) {
            throw FormatException('quran_data: bad narration $sk:$ak');
          }
        });
      });
      narration = rawNarration;
    }

    final fixes = <String, Map<String, String>>{};
    final rawFixes = d['tafsirFixes'];
    if (rawFixes != null) {
      if (rawFixes is! List || rawFixes.length > 10000) {
        throw const FormatException('quran_data: bad tafsirFixes');
      }
      for (final f in rawFixes) {
        if (f is! Map) throw const FormatException('quran_data: bad fix');
        final e = f['edition'], s = f['surah'], a = f['ayah'], t = f['text'];
        if (e is! String ||
            !tafsirEditions.contains(e) ||
            s is! int ||
            s < 1 ||
            s > 114 ||
            a is! int ||
            a < 1 ||
            a > 286 ||
            t is! String ||
            t.trim().isEmpty) {
          throw const FormatException('quran_data: bad tafsir fix');
        }
        (fixes[e] ??= {})['$s:$a'] = t;
      }
    }

    return QuranDataPatch._(
      ver: ver,
      ayahRegions: regions,
      audioAyahMap: audioMap,
      breathData: breath,
      narrationMap: narration,
      tafsirFixes: fixes,
    );
  }

  /// Lays [ayahRegions] over the decoded `ayah_regions.json`, in place. A
  /// page is replaced only when its ayat (surah, ayah, in order) are the
  /// bundled page's. Returns how many pages were replaced.
  int applyToRegions(List<dynamic> pages) =>
      applyRegionFixes(pages, ayahRegions);

  /// [applyToRegions] for a bare page table (what crosses to the isolate).
  static int applyRegionFixes(
    List<dynamic> pages,
    Map<int, Map<String, dynamic>> ayahRegions,
  ) {
    if (ayahRegions.isEmpty) return 0;
    List<(Object?, Object?)> keys(Object? ayahs) => [
      for (final a in (ayahs as List? ?? const []))
        if (a is Map) (a['surah'], a['ayah']),
    ];
    var applied = 0;
    for (var i = 0; i < pages.length; i++) {
      final item = pages[i];
      if (item is! Map<String, dynamic>) continue;
      final page = item['page'];
      if (page is! int) continue;
      final fix = ayahRegions[page];
      if (fix == null) continue;
      if (!listEquals(keys(item['ayahs']), keys(fix['ayahs']))) {
        debugPrint('QuranDataPatch: page $page lists other ayat, kept');
        continue;
      }
      pages[i] = fix;
      applied++;
    }
    return applied;
  }

  static bool listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

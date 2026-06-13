import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ayah_position_data.dart';

class AyahPositionService {
  static const String _assetPath = 'assets/data/ayah_positions.json';
  static const String _localFileName = 'ayah_positions.local.json';
  static const String _prefsKey = 'ayah_positions.local.json';
  static Map<int, List<AyahPositionData>>? _cache;

  static Future<Map<int, List<AyahPositionData>>> loadAyahPositions() async {
    if (_cache != null) return _cache!;

    try {
      final jsonString = await rootBundle.loadString(_assetPath);
      _cache = _decodePositions(jsonString);
      return _cache!;

      final localFile = await _localOverrideFile();
      if (await localFile.exists()) {
        final localJson = await localFile.readAsString();
        _cache = _decodePositions(localJson);
        return _cache!;
      }

      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_prefsKey);
      if (savedJson != null && savedJson.trim().isNotEmpty) {
        _cache = _decodePositions(savedJson);
        return _cache!;
      }
    } catch (_) {
      try {
        final localFile = await _localOverrideFile();
        if (await localFile.exists()) {
          final localJson = await localFile.readAsString();
          _cache = _decodePositions(localJson);
          return _cache!;
        }

        final prefs = await SharedPreferences.getInstance();
        final savedJson = prefs.getString(_prefsKey);
        if (savedJson != null && savedJson.trim().isNotEmpty) {
          _cache = _decodePositions(savedJson);
          return _cache!;
        }
      } catch (_) {}

      _cache = _fallbackPageOnePositions();
    }

    return _cache!;
  }

  static Future<void> saveAyahPositions(
    Map<int, List<AyahPositionData>> positions,
  ) async {
    final encoded = const JsonEncoder.withIndent('  ').convert(
      _sortedPagesFromMap(positions).map((page) => page.toJson()).toList(),
    );
    Object? lastError;

    try {
      final file = await _localOverrideFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded, flush: true);
    } catch (error) {
      lastError = error;
    }

    var prefsSaved = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      prefsSaved = await prefs.setString(_prefsKey, encoded);
    } catch (error) {
      lastError ??= error;
    }

    if (!prefsSaved) {
      final file = await _localOverrideFile();
      if (!await file.exists()) {
        throw lastError ?? Exception('Failed to persist ayah positions');
      }
    }

    _cache = _immutableMap(positions);
  }

  static Future<String> getLocalOverridePath() async {
    final file = await _localOverrideFile();
    return file.path;
  }

  static Future<String> exportAyahPositionsToProjectAsset(
    Map<int, List<AyahPositionData>> positions,
  ) async {
    final assetFile = await _projectAssetFile();
    await assetFile.parent.create(recursive: true);
    final encoded = const JsonEncoder.withIndent('  ').convert(
      _sortedPagesFromMap(positions).map((page) => page.toJson()).toList(),
    );
    await assetFile.writeAsString(encoded, flush: true);
    return assetFile.path;
  }

  static void clearCache() {
    _cache = null;
  }

  static Map<int, List<AyahPositionData>> _decodePositions(String jsonString) {
    final decoded = json.decode(jsonString);

    if (decoded is! List) {
      throw Exception('Ayah positions JSON root must be a List');
    }

    final pages = decoded
        .map(
          (item) => AyahPagePositionData.fromJson(item as Map<String, dynamic>),
        )
        .toList();

    return _immutableMap(<int, List<AyahPositionData>>{
      for (final page in pages) page.page: page.ayahs,
    });
  }

  static Map<int, List<AyahPositionData>> _immutableMap(
    Map<int, List<AyahPositionData>> positions,
  ) {
    return <int, List<AyahPositionData>>{
      for (final entry in positions.entries)
        entry.key: List<AyahPositionData>.unmodifiable(entry.value),
    };
  }

  static List<AyahPagePositionData> _sortedPagesFromMap(
    Map<int, List<AyahPositionData>> positions,
  ) {
    final pageNumbers = positions.keys.toList()..sort();
    return pageNumbers
        .map(
          (pageNumber) => AyahPagePositionData(
            page: pageNumber,
            ayahs: positions[pageNumber] ?? const <AyahPositionData>[],
          ),
        )
        .toList();
  }

  static Future<File> _localOverrideFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_localFileName');
  }

  static Future<File> _projectAssetFile() async {
    var current = Directory.current.absolute;

    for (int i = 0; i < 8; i++) {
      final candidate = File(
        '${current.path}${Platform.pathSeparator}assets${Platform.pathSeparator}data${Platform.pathSeparator}ayah_positions.json',
      );
      final pubspec = File(
        '${current.path}${Platform.pathSeparator}pubspec.yaml',
      );

      if (await candidate.exists() && await pubspec.exists()) {
        return candidate;
      }

      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }

    throw Exception('Could not locate project assets/data/ayah_positions.json');
  }

  static Map<int, List<AyahPositionData>> _fallbackPageOnePositions() {
    return <int, List<AyahPositionData>>{
      1: <AyahPositionData>[
        const AyahPositionData(
          surah: 1,
          ayah: 1,
          rects: <AyahHighlightRect>[
            AyahHighlightRect(x: 0.14, y: 0.365, width: 0.73, height: 0.067),
          ],
        ),
        const AyahPositionData(
          surah: 1,
          ayah: 2,
          rects: <AyahHighlightRect>[
            AyahHighlightRect(x: 0.41, y: 0.445, width: 0.52, height: 0.074),
          ],
        ),
        const AyahPositionData(
          surah: 1,
          ayah: 3,
          rects: <AyahHighlightRect>[
            AyahHighlightRect(x: 0.06, y: 0.445, width: 0.31, height: 0.074),
          ],
        ),
        const AyahPositionData(
          surah: 1,
          ayah: 4,
          rects: <AyahHighlightRect>[
            AyahHighlightRect(x: 0.42, y: 0.525, width: 0.44, height: 0.072),
          ],
        ),
        const AyahPositionData(
          surah: 1,
          ayah: 5,
          rects: <AyahHighlightRect>[
            AyahHighlightRect(x: 0.06, y: 0.525, width: 0.33, height: 0.072),
          ],
        ),
        const AyahPositionData(
          surah: 1,
          ayah: 6,
          rects: <AyahHighlightRect>[
            AyahHighlightRect(x: 0.31, y: 0.608, width: 0.56, height: 0.075),
          ],
        ),
        const AyahPositionData(
          surah: 1,
          ayah: 7,
          rects: <AyahHighlightRect>[
            AyahHighlightRect(x: 0.09, y: 0.692, width: 0.72, height: 0.074),
            AyahHighlightRect(x: 0.06, y: 0.772, width: 0.80, height: 0.071),
          ],
        ),
      ],
    };
  }
}

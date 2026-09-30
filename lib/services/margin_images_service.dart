import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class MarginImagesState {
  final bool isEnabled;

  const MarginImagesState({required this.isEnabled});

  const MarginImagesState.initial() : isEnabled = false;
}

/// The "عرض الهوامش" preference.
///
/// The bundled page images are the full هوامش scans, so the margin view is
/// always available and this is purely a toggle: on, the reader shows the
/// whole scan; off, it shows only the frame interior (see `PageImageCrop`).
///
/// Until 1.5.2 the margin pages were a separate 144 MB download unpacked into
/// app support; [deleteLegacyDownloads] clears what those versions left
/// behind. The preference key is unchanged so an upgrade keeps the user's
/// choice.
class MarginImagesService {
  MarginImagesService._();

  static final MarginImagesService instance = MarginImagesService._();

  static const String _enabledPrefKey = 'marginImagesEnabled';

  /// Files the pre-1.5.3 download models left under app support: the margin
  /// pack, the "high-fidelity" pack (now the bundled set itself), and their
  /// partially-downloaded zips.
  static const List<String> _legacyEntries = [
    'margin_images',
    'margin_images.zip',
    'high_quality_images',
    'high_quality_images.zip',
  ];

  final ValueNotifier<MarginImagesState> state =
      ValueNotifier<MarginImagesState>(const MarginImagesState.initial());

  Future<void>? _initialized;

  /// Reads the stored preference. Cheap (SharedPreferences is already in
  /// memory by the time the reader asks), so the splash awaits it and the
  /// first frame renders in the right view.
  Future<void> initialize() => _initialized ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // Off by default on every platform; the user opts in from the settings.
    state.value = MarginImagesState(
      isEnabled: prefs.getBool(_enabledPrefKey) ?? false,
    );
  }

  Future<void> setEnabled(bool value) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPrefKey, value);
    state.value = MarginImagesState(isEnabled: value);
  }

  /// Removes the downloaded packs older versions stored on the device. Safe
  /// to call on every launch (a no-op once they are gone) and off the launch
  /// path: nothing reads those folders any more, so a failed or partial
  /// delete costs disk space only.
  static Future<void> deleteLegacyDownloads() async {
    if (kIsWeb) return;
    try {
      final supportDir = await getApplicationSupportDirectory();
      for (final name in _legacyEntries) {
        final path = p.join(supportDir.path, name);
        final type = FileSystemEntity.typeSync(path, followLinks: false);
        if (type == FileSystemEntityType.notFound) continue;
        try {
          if (type == FileSystemEntityType.directory) {
            await Directory(path).delete(recursive: true);
          } else {
            await File(path).delete();
          }
          debugPrint('MarginImagesService: removed legacy $name');
        } catch (e) {
          debugPrint('MarginImagesService: could not remove $name: $e');
        }
      }
    } catch (e) {
      debugPrint('MarginImagesService: legacy cleanup skipped: $e');
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preference: allow pinch-to-zoom on Quran pages in the paged (flip)
/// reader. When off, pages only fit the screen and page-flipping is never
/// locked by a zoom gesture.
class PageZoomService {
  PageZoomService._();
  static final PageZoomService instance = PageZoomService._();

  static const String _prefKey = 'pageZoomEnabled';

  /// Whether pinch-to-zoom is available. Listen to rebuild the settings
  /// toggle. Defaults to on unless the user explicitly turns it off.
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_prefKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    if (enabled.value == value) return;
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }
}

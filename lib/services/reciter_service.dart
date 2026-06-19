import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reciter.dart';

/// Holds the currently selected reciter and persists the choice.
///
/// The audio layer ([AudioService], [AudioDownloadService]) listens to
/// [selected] and re-points itself (base URL + cache folder) whenever it
/// changes, so the rest of the app never has to know which reciter is active.
class ReciterService {
  ReciterService._();
  static final ReciterService instance = ReciterService._();

  static const String _prefKey = 'selectedReciterId';

  /// Every reciter the user can pick from.
  final List<Reciter> reciters = Reciter.all;

  /// The active reciter. Listen to rebuild UI / re-point the audio layer.
  final ValueNotifier<Reciter> selected =
      ValueNotifier<Reciter>(Reciter.fallback);

  bool _loaded = false;

  /// Loads the persisted selection. Safe to call multiple times.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    selected.value = Reciter.byId(prefs.getString(_prefKey));
  }

  /// Selects [reciter] and persists it. No-op if already selected.
  Future<void> select(Reciter reciter) async {
    if (selected.value.id == reciter.id) return;
    selected.value = reciter;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, reciter.id);
  }
}

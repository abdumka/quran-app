import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tafsir_edition.dart';

/// Holds the currently selected tafsir edition and persists the choice.
///
/// [TafsirService] reads [selected] to decide which edition to load (bundled
/// asset vs online per-page fetch), and the tafsir sheet listens to it so the
/// reader can switch editions live. Mirrors [ReciterService].
class TafsirEditionService {
  TafsirEditionService._();
  static final TafsirEditionService instance = TafsirEditionService._();

  static const String _prefKey = 'selectedTafsirId';

  /// Every edition the user can pick from.
  final List<TafsirEdition> editions = TafsirEdition.all;

  /// The active edition. Listen to rebuild the tafsir sheet.
  final ValueNotifier<TafsirEdition> selected =
      ValueNotifier<TafsirEdition>(TafsirEdition.fallback);

  bool _loaded = false;

  /// Loads the persisted selection (a single SharedPreferences read). Safe to
  /// call multiple times.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    selected.value = TafsirEdition.byId(prefs.getString(_prefKey));
  }

  /// Selects [edition] and persists it. No-op if already selected.
  Future<void> select(TafsirEdition edition) async {
    if (selected.value.id == edition.id) return;
    selected.value = edition;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, edition.id);
  }
}

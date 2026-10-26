import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reciter.dart';
import '../page_turn_cues.dart';
import 'content_update_service.dart';

/// Holds the currently selected reciter and persists the choice.
///
/// The audio layer ([AudioService], [AudioDownloadService]) listens to
/// [selected] and re-points itself (base URL + cache folder) whenever it
/// changes, so the rest of the app never has to know which reciter is active.
class ReciterService {
  ReciterService._();
  static final ReciterService instance = ReciterService._();

  static const String _prefKey = 'selectedReciterId';

  /// Every reciter the user can pick from: the bundled ones, then any a
  /// server update added (see [applyRemote]). Read it when building a
  /// picker; [revision] ticks when the list changes.
  List<Reciter> get reciters => Reciter.offered;

  /// Bumped when [reciters] changes under a running app.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Height cap for a reciter picker's menu: six and a half rows plus the
  /// menu's own padding, so the list scrolls (half a row peeking out says
  /// there is more) instead of growing to fill the screen as reciters are
  /// added. Flutter opens the capped menu scrolled to the selected reciter.
  static double pickerMenuMaxHeight(double itemHeight) => 6.5 * itemHeight + 16;

  /// The active reciter. Listen to rebuild UI / re-point the audio layer.
  final ValueNotifier<Reciter> selected = ValueNotifier<Reciter>(
    Reciter.fallback,
  );

  bool _loaded = false;

  /// Loads the persisted selection. Safe to call multiple times.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    // The saved choice may be a server-added reciter, so read that file
    // first (prefs + one small file; no network).
    await applyRemote();
    ContentUpdateService.instance.registerItem('reciters', apply: applyRemote);
    final prefs = await SharedPreferences.getInstance();
    selected.value = Reciter.byId(prefs.getString(_prefKey));
  }

  /// Installs the downloaded `reciters_v<N>.json` (if any) into
  /// [Reciter.remote] and the page-turn cues it carries. Called at load and
  /// again by the update service when a newer file lands.
  Future<void> applyRemote() async {
    try {
      final text = await ContentUpdateService.instance.readFor('reciters');
      if (text == null) return;
      final decoded = json.decode(text);
      if (decoded is! Map<String, dynamic>) return;
      Reciter.installRemote(decoded);
      remotePageTurnCues = parseRemotePageTurnCues(decoded);
      // The selected reciter may have gained an override (timings revision).
      final current = selected.value;
      selected.value = Reciter.byId(current.id);
      revision.value++;
    } catch (e) {
      debugPrint('ReciterService: remote reciters ignored: $e');
    }
  }

  /// `{"reciters":[{"id":…, "pageTurnCues":{"35":{"surah":2,"ayah":218,
  /// "file":"002.mp3","ms":5044020}, …}}]}` -> id -> page -> cue. A reciter
  /// without cues gets none (the audio layer then estimates the turn).
  static Map<String, Map<int, PageTurnCue>> parseRemotePageTurnCues(
    Map<String, dynamic> json,
  ) {
    final out = <String, Map<int, PageTurnCue>>{};
    for (final item in (json['reciters'] as List<dynamic>? ?? const [])) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'];
      final cues = item['pageTurnCues'];
      if (id is! String || cues is! Map<String, dynamic>) continue;
      final parsed = <int, PageTurnCue>{};
      cues.forEach((page, c) {
        final p = int.tryParse(page);
        if (p == null || c is! Map<String, dynamic>) return;
        final s = c['surah'], a = c['ayah'], f = c['file'], ms = c['ms'];
        if (s is! int || a is! int || f is! String || ms is! int) return;
        parsed[p] = PageTurnCue(s, a, f, ms);
      });
      if (parsed.isNotEmpty) out[id] = parsed;
    }
    return out;
  }

  /// Selects [reciter] and persists it. No-op if already selected.
  Future<void> select(Reciter reciter) async {
    if (selected.value.id == reciter.id) return;
    selected.value = reciter;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, reciter.id);
  }
}

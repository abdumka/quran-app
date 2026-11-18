import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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

  /// What the reciters file said about the bundled reciters when this run
  /// started. A file that lands later adds its new reciters at once, but its
  /// overrides (labels, hiding, order, a replaced recording) wait for the
  /// next launch, so nothing changes under a recitation or a download.
  Object? _launchOverrides;
  Object? _launchOrder;
  bool _launchCaptured = false;

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
    final retired = Reciter.retiredCacheFolders;
    if (retired.isNotEmpty) {
      // Well after the first frame: nothing on the launch path waits on it.
      Future<void>.delayed(
        const Duration(seconds: 40),
        () => deleteRetiredFolders(retired),
      );
    }
  }

  /// Installs the downloaded `reciters_v<N>.json` (if any) into
  /// [Reciter.remote] and the page-turn cues it carries. Called at load and
  /// again by the update service when a newer file lands.
  Future<void> applyRemote() async {
    try {
      final text = await ContentUpdateService.instance.readFor('reciters');
      final decoded = text == null ? null : json.decode(text);
      final file = decoded is Map<String, dynamic> ? decoded : null;
      if (!_launchCaptured) {
        _launchCaptured = true;
        _launchOverrides = file?['overrides'];
        _launchOrder = file?['order'];
      }
      if (file == null) return;
      Reciter.installRemote(
        file,
        overrides: _launchOverrides,
        order: _launchOrder,
      );
      remotePageTurnCues = parseRemotePageTurnCues(file);
      overridePageTurnCues = parseOverridePageTurnCues(_launchOverrides);
      compiledCuesRetired = {
        for (final r in Reciter.all)
          if (Reciter.recordingReplaced(r.id)) r.id,
      };
      // Re-point the selection only when what it plays changed (or it is no
      // longer offered): a new object for the same audio would make the audio
      // layer restart the ayah and cancel a download.
      final current = selected.value;
      final next = Reciter.byId(current.id);
      if (!next.samePlaybackAs(current)) selected.value = next;
      revision.value++;
    } catch (e) {
      debugPrint('ReciterService: remote reciters ignored: $e');
    }
  }

  /// Deletes the audio of recordings a server override replaced (see
  /// [Reciter.retiredCacheFolders]). Only folders directly under the app's
  /// support directory, and only names a bundled reciter used.
  static Future<void> deleteRetiredFolders(Set<String> folders) async {
    try {
      final support = await getApplicationSupportDirectory();
      final bundled = {for (final r in Reciter.all) r.cacheFolder};
      for (final name in folders) {
        // A bundled reciter's own folder name, never a path.
        if (!bundled.contains(name)) continue;
        // Still in use after all (the override was withdrawn meanwhile)?
        if (!Reciter.retiredCacheFolders.contains(name)) continue;
        final dir = Directory('${support.path}${Platform.pathSeparator}$name');
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('ReciterService: retired audio not removed: $e');
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
      final parsed = _parseCues(cues, timed: true);
      if (parsed.isNotEmpty) out[id] = parsed;
    }
    return out;
  }

  /// The `pageTurnCues` of the overrides for bundled reciters, as
  /// [Reciter.installRemote] accepted them: a cue must name a file of the
  /// recording the reciter now plays (`SSS.mp3` under the timed scheme,
  /// `SSSAAA.mp3` otherwise), or it is dropped.
  static Map<String, Map<int, PageTurnCue>> parseOverridePageTurnCues(
    Object? overrides,
  ) {
    final out = <String, Map<int, PageTurnCue>>{};
    if (overrides is! Map<String, dynamic>) return out;
    for (final r in Reciter.all) {
      final o = overrides[r.id];
      if (o is! Map<String, dynamic>) continue;
      final cues = o['pageTurnCues'];
      if (cues is! Map<String, dynamic>) continue;
      final now = Reciter.byIdIncludingHidden(r.id);
      final parsed = _parseCues(
        cues,
        timed: now.scheme == AudioScheme.timedSurah,
      );
      if (parsed.isNotEmpty) out[r.id] = parsed;
    }
    return out;
  }

  static final RegExp _surahFile = RegExp(r'^\d{3}\.mp3$');
  static final RegExp _ayahFile = RegExp(r'^\d{6}\.mp3$');

  static Map<int, PageTurnCue> _parseCues(
    Map<String, dynamic> cues, {
    required bool timed,
  }) {
    final parsed = <int, PageTurnCue>{};
    cues.forEach((page, c) {
      final p = int.tryParse(page);
      if (p == null || p < 1 || p > 604 || c is! Map<String, dynamic>) return;
      final s = c['surah'], a = c['ayah'], f = c['file'], ms = c['ms'];
      if (s is! int || a is! int || f is! String || ms is! int || ms < 0) {
        return;
      }
      if (!(timed ? _surahFile : _ayahFile).hasMatch(f)) return;
      parsed[p] = PageTurnCue(s, a, f, ms);
    });
    return parsed;
  }

  /// Tests only: forget what the reciters file said at "launch".
  @visibleForTesting
  void debugForgetLaunch() {
    _launchCaptured = false;
    _launchOverrides = null;
    _launchOrder = null;
  }

  /// Selects [reciter] and persists it. No-op if already selected.
  Future<void> select(Reciter reciter) async {
    if (selected.value.id == reciter.id) return;
    selected.value = reciter;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, reciter.id);
  }
}

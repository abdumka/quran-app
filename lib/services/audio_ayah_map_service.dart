import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Maps the app's displayed ayah number (output.json) to the recitation audio's
/// own Qalun ayah file number(s).
///
/// The page text/numbering (output.json) and the recitation audio use slightly
/// different Qalun ayah divisions (different عدّ): they agree on surah totals in
/// most surahs but split/merge a few verses differently (e.g. output.json counts
/// An-Nisa as 176 ayahs vs the audio's 175; the audio keeps Ayat al-Kursi as one
/// file while output.json splits it). Without this map, tapping an ayah plays a
/// drifted recitation. Built offline by tools/build_audio_map.py and shipped as
/// assets/data/audio_ayah_map.json. Only non-identity entries are listed.
class AudioAyahMapService {
  AudioAyahMapService._();
  static final AudioAyahMapService instance = AudioAyahMapService._();

  // surah -> (ayah -> list of audio file ayah numbers)
  Map<int, Map<int, List<int>>> _map = const {};
  // surah -> set of audio ayah numbers that merely repeat the previous breath
  // (قنيوه's الوقف الهبطي) and must be skipped during playback.
  Map<int, Set<int>> _qaniwahContinuations = const {};
  // قنيوه surahs whose ayah-1 file already contains the basmala, so the app must
  // NOT prepend the separate basmala file 000 (else basmala plays twice).
  Set<int> _qaniwahBasmalaInAyah1 = const {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _map = await _loadAyahMap();
    await _loadQaniwahData();
  }

  Future<Map<int, Map<int, List<int>>>> _loadAyahMap() async {
    try {
      final raw = await rootBundle.loadString('assets/data/audio_ayah_map.json');
      final m = (json.decode(raw) as Map<String, dynamic>)['map'] as Map<String, dynamic>;
      final out = <int, Map<int, List<int>>>{};
      m.forEach((surah, ayahs) {
        final inner = <int, List<int>>{};
        (ayahs as Map<String, dynamic>).forEach((ayah, files) {
          inner[int.parse(ayah)] = (files as List).map((e) => e as int).toList();
        });
        out[int.parse(surah)] = inner;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _loadQaniwahData() async {
    try {
      final raw = await rootBundle.loadString('assets/data/qaniwah_continuations.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final c = decoded['continuations'] as Map<String, dynamic>;
      final out = <int, Set<int>>{};
      c.forEach((surah, ayat) {
        out[int.parse(surah)] = (ayat as List).map((e) => e as int).toSet();
      });
      _qaniwahContinuations = out;
      _qaniwahBasmalaInAyah1 =
          (decoded['basmala_in_ayah1'] as List? ?? const []).map((e) => e as int).toSet();
    } catch (_) {
      _qaniwahContinuations = const {};
      _qaniwahBasmalaInAyah1 = const {};
    }
  }

  /// Returns the audio file ayah number(s) for a displayed (surah, ayah), or
  /// null when the mapping is identity (play file with the same number).
  List<int>? lookup(int surah, int ayah) => _map[surah]?[ayah];

  /// قنيوه only: whether this audio ayah file just repeats the previous breath
  /// (so it should not be played — see [Reciter.breathCombining]).
  bool isQaniwahContinuation(int surah, int ayah) =>
      _qaniwahContinuations[surah]?.contains(ayah) ?? false;

  /// قنيوه only: whether this surah's ayah-1 file already contains the basmala,
  /// so the separate basmala file 000 must NOT be prepended.
  bool qaniwahBasmalaInAyah1(int surah) =>
      _qaniwahBasmalaInAyah1.contains(surah);
}

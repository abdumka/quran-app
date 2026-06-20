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
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await rootBundle.loadString('assets/data/audio_ayah_map.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final m = decoded['map'] as Map<String, dynamic>;
      final out = <int, Map<int, List<int>>>{};
      m.forEach((surah, ayahs) {
        final inner = <int, List<int>>{};
        (ayahs as Map<String, dynamic>).forEach((ayah, files) {
          inner[int.parse(ayah)] =
              (files as List).map((e) => e as int).toList();
        });
        out[int.parse(surah)] = inner;
      });
      _map = out;
    } catch (_) {
      _map = const {};
    }
  }

  /// Returns the audio file ayah number(s) for a displayed (surah, ayah), or
  /// null when the mapping is identity (play file with the same number).
  List<int>? lookup(int surah, int ayah) => _map[surah]?[ayah];
}

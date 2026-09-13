import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/reciter.dart';

/// One reciter's الوقف الهبطي data: which ayat merely repeat the breath that
/// already played, and which surahs recite the basmala inside the ayah-1 file.
class BreathData {
  /// surah -> audio ayah numbers that repeat the previous breath.
  final Map<int, Set<int>> continuations;

  /// Surahs whose ayah-1 file already contains the basmala, so the separate
  /// basmala file 000 must NOT be prepended (it would play twice).
  final Set<int> basmalaInAyah1;

  const BreathData(this.continuations, this.basmalaInAyah1);

  static const BreathData empty = BreathData({}, {});
}

/// Maps the app's displayed ayah number (output.json) to the recitation audio's
/// own Qalun ayah file number(s).
///
/// The page text/numbering (output.json) and the recitation audio use slightly
/// different Qalun ayah divisions (different عدّ): they now agree on surah totals
/// for every surah but split/merge a few verses differently (e.g. the audio keeps
/// Ayat al-Kursi as one file while output.json splits it). Without this map,
/// tapping an ayah plays a drifted recitation. Built offline by
/// tools/build_audio_map.py and shipped as assets/data/audio_ayah_map.json.
/// Only non-identity entries are listed.
class AudioAyahMapService {
  AudioAyahMapService._();
  static final AudioAyahMapService instance = AudioAyahMapService._();

  // surah -> (ayah -> list of audio file ayah numbers)
  Map<int, Map<int, List<int>>> _map = const {};
  // asset path -> that reciter's الوقف الهبطي data. Keyed per reciter because the
  // breath groups describe how *he* recites, so they can never be shared.
  final Map<String, BreathData> _breath = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _map = await _loadAyahMap();
    for (final reciter in Reciter.allDefined) {
      final asset = reciter.continuationsAsset;
      if (asset != null && !_breath.containsKey(asset)) {
        _breath[asset] = await _loadBreathData(asset);
      }
    }
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

  Future<BreathData> _loadBreathData(String asset) async {
    try {
      final decoded = json.decode(await rootBundle.loadString(asset))
          as Map<String, dynamic>;
      final continuations = <int, Set<int>>{};
      (decoded['continuations'] as Map<String, dynamic>).forEach((surah, ayat) {
        continuations[int.parse(surah)] =
            (ayat as List).map((e) => e as int).toSet();
      });
      final basmala = (decoded['basmala_in_ayah1'] as List? ?? const [])
          .map((e) => e as int)
          .toSet();
      return BreathData(continuations, basmala);
    } catch (_) {
      return BreathData.empty;
    }
  }

  /// Returns the audio file ayah number(s) for a displayed (surah, ayah), or
  /// null when the mapping is identity (play file with the same number).
  List<int>? lookup(int surah, int ayah) => _map[surah]?[ayah];

  /// The الوقف الهبطي data for [reciter], or empty for a reciter that doesn't
  /// combine breaths (or whose asset failed to load).
  BreathData breathDataFor(Reciter reciter) {
    final asset = reciter.continuationsAsset;
    if (asset == null) return BreathData.empty;
    return _breath[asset] ?? BreathData.empty;
  }

  /// Whether this audio ayah file just repeats [reciter]'s previous breath (so
  /// it should not be played — see [Reciter.breathCombining]).
  bool isContinuation(Reciter reciter, int surah, int ayah) =>
      breathDataFor(reciter).continuations[surah]?.contains(ayah) ?? false;

  /// Whether this surah's ayah-1 file already contains the basmala for
  /// [reciter], so the separate basmala file 000 must NOT be prepended.
  bool basmalaInAyah1(Reciter reciter, int surah) =>
      breathDataFor(reciter).basmalaInAyah1.contains(surah);
}

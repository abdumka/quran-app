import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/services/audio_ayah_map_service.dart';

/// قنيوه's files are numbered exactly as the app displays the ayat, in every
/// surah: file 014023.mp3 is the five-word «وما ذلك على الله بعزيز» (5.9 s, as
/// in every other mirror), and around every ayah the old map remapped (surahs
/// 2, 3, 11, 14, 18, 20, 30, 39, 40, 44, 56, 65, 71, 73, 80, 91, 103) file N
/// decodes as displayed ayah N, or as the breath group that starts at N. The
/// map built on 2026-07-14 from quran-meta's Qalun division shifted those
/// ayat one file back: the highlight ran an ayah ahead of the voice (30:55-60
/// was reported) and the last file of 11, 30, 73 and 91 never played.
/// Removed 2026-10-08; keep it out.
///
/// The one entry left: 020024.mp3 is a silent placeholder upstream, and he
/// recites 20:24 at the start of 020025.mp3 (the 24-29 breath).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => AudioAyahMapService.instance.load());

  test('قنيوه plays file for file, except 20:24', () {
    for (var surah = 1; surah <= 114; surah++) {
      final count = Reciter.madaniAyahCounts[surah - 1];
      for (var ayah = 1; ayah <= count; ayah++) {
        if (surah == 20 && ayah == 24) continue;
        expect(
          AudioAyahMapService.instance.lookup(surah, ayah),
          isNull,
          reason:
              '$surah:$ayah must play '
              '${surah.toString().padLeft(3, '0')}'
              '${ayah.toString().padLeft(3, '0')}.mp3',
        );
      }
    }
  });

  test('20:24 plays the 24-29 breath in 020025.mp3', () {
    expect(AudioAyahMapService.instance.lookup(20, 24), [25]);
  });

  test('the web player resolves the same way', () {
    final overrides =
        (json.decode(
                  File(
                    'web-player/data/overrides_qaniwah.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)['overrides']
            as Map<String, dynamic>;
    String reason(String key) =>
        '$key is remapped in web-player/data — rerun '
        'tools/build_web_player_data.py';
    // Ayat that are neither ayah 1 nor a breath continuation have no override
    // under a file-for-file map. These are the ones the old map shifted.
    for (final key in [
      '14-23', '14-24', '14-25', '14-26', '14-27', //
      '30-56', '30-57', '30-58', '30-59', '30-60', //
      '11-122', '73-19', '73-20', '91-16', '2-197', '3-92', '65-3',
    ]) {
      expect(overrides.containsKey(key), isFalse, reason: reason(key));
    }
    expect(overrides['20-24'], {
      'f': ['020025'],
      'cov': null,
    });
  });
}

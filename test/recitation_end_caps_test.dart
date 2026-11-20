import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/data/recitation_end_caps.dart';
import 'package:islamic_dawah_mushaf/models/athkar.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/services/athkar_audio.dart';
import 'package:islamic_dawah_mushaf/services/audio_ayah_map_service.dart';
import 'package:islamic_dawah_mushaf/services/audio_service.dart';

/// «صدق الله العظيم» is never played (owner, 2026-11-20).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every cap is inside its file and only per-ayah reciters have one '
      'so far', () {
    for (final e in recitationEndCaps.entries) {
      final r = Reciter.all.firstWhere((x) => x.id == e.key);
      expect(r.scheme, isNot(AudioScheme.timedSurah), reason: e.key);
      for (final cap in e.value.values) {
        expect(cap, greaterThan(1));
      }
    }
  });

  test('الدوكالي\'s an-Nas and al-Husary\'s 114:6 stop before the phrase; '
      'other files stay whole', () async {
    await AudioAyahMapService.instance.load();
    final nas = AudioService.instance.clipsForAyahOf(
      Reciter.doukaliQaloun,
      114,
      1,
    );
    expect(nas.single.file, '114001.mp3');
    expect(nas.single.start, isNull);
    expect(nas.single.end, const Duration(milliseconds: 29650));
    // a per-ayah file cut short is not a timed surah slice
    expect(nas.single.isSurahSlice, isFalse);
    expect(nas.single.isClipped, isTrue);

    final husary = AudioService.instance.clipsForAyahOf(
      Reciter.husaryQaloun,
      114,
      6,
    );
    expect(husary.last.end, const Duration(milliseconds: 6470));

    final other = AudioService.instance.clipsForAyahOf(
      Reciter.doukaliQaloun,
      112,
      1,
    );
    expect(other.every((c) => !c.isClipped), isTrue);
  });

  test('the athkar\'s Quls in الدوكالي end there too', () async {
    await AudioAyahMapService.instance.load();
    AthkarAudio.instance.cacheClips = false;
    final quls = AthkarData.parse(
      json.encode({
        'sections': [
          {
            'id': 1,
            'name': 'أذكار النوم',
            'items': [
              {
                'id': 94,
                't': 'قل هو الله أحد',
                'n': 3,
                'q': [
                  [112, 1, 4],
                  [113, 1, 5],
                  [114, 1, 6],
                ],
              },
            ],
          },
        ],
      }),
    ).item(94)!;
    final sources = await AthkarAudio.instance.quranSources(
      Reciter.doukaliQaloun,
      quls,
    );
    final nas = sources!.firstWhere(
      (s) => s.uri.path.endsWith('114001.mp3'),
    );
    expect(nas.start, isNull);
    expect(nas.end, const Duration(milliseconds: 29650));
  });

  test('the server can add caps without a release; junk is ignored', () {
    addTearDown(() => Reciter.installRemote(const {}));
    expect(Reciter.endCapFor('hudaifi_qaloun', '114006.mp3'), isNull);
    Reciter.installRemote({
      'endCaps': {
        'hudaifi_qaloun': {'114006.mp3': 5.5, 'bad.mp3': 3, '002255.mp3': -1},
        'naihi_qaloun': {'114.mp3': 61.2},
        'x': 'not a map',
      },
    });
    expect(Reciter.endCapFor('hudaifi_qaloun', '114006.mp3'), 5.5);
    expect(Reciter.endCapFor('hudaifi_qaloun', 'bad.mp3'), isNull);
    expect(Reciter.endCapFor('hudaifi_qaloun', '002255.mp3'), isNull);
    expect(Reciter.endCapFor('naihi_qaloun', '114.mp3'), 61.2);
    // the bundled ones still hold
    expect(Reciter.endCapFor('doukali_qaloun', '114001.mp3'), 29.65);
  });
}

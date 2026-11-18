import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/page_turn_cues.dart';
import 'package:islamic_dawah_mushaf/services/reciter_service.dart';

/// Server overrides for the BUNDLED reciters (`overrides` / `order` in
/// `reciters_v<N>.json`): labels, hiding, order, cues and a replaced
/// recording. Old builds read only `timingsRevision` from the same file.
void main() {
  tearDown(() {
    Reciter.installRemote(const {'reciters': []});
    remotePageTurnCues = {};
    overridePageTurnCues = {};
    compiledCuesRetired = {};
  });

  const husaryTimed = {
    'audioBaseUrl': 'https://audio.mushaf-qaloon.com/husary_timed/',
    'timingsBaseUrl':
        'https://quran-content.mushaf-qaloon.com/timings/husary_timed/',
    'cacheFolder': 'audio_cache_husary_timed',
    'timingsRevision': 2,
  };

  Reciter offered(String id) =>
      Reciter.offered.singleWhere((r) => r.id == id);

  test('no overrides: exactly the bundled list, in the bundled order', () {
    Reciter.installRemote(const {'reciters': []});
    expect(Reciter.offered.map((r) => r.id), Reciter.all.map((r) => r.id));
    for (final r in Reciter.all) {
      expect(identical(offered(r.id), r), isTrue, reason: r.id);
    }
  });

  test('labels: name, shortName and riwaya, each checked on its own', () {
    Reciter.installRemote({
      'reciters': [],
      'overrides': {
        'trabulsi_qaloun': {'riwaya': 'رواية قالون بتقليل التوراة'},
        'zarrouq_qaloun': {
          'riwaya': '  ',
          'shortName': 'اسم قصير جدا جدا جدا جدا',
          'name': 'محمد خليل الزروق الجديد',
        },
        'rajab_qaloun': {'shortName': 'رجب'},
      },
    });
    final t = offered('trabulsi_qaloun');
    expect(t.riwaya, 'رواية قالون بتقليل التوراة');
    expect(t.name, Reciter.trabulsiQaloun.name);
    expect(t.shortName, Reciter.trabulsiQaloun.shortName);
    expect(t.samePlaybackAs(Reciter.trabulsiQaloun), isTrue);

    final z = offered('zarrouq_qaloun');
    expect(z.riwaya, Reciter.zarrouqQaloun.riwaya, reason: 'blank ignored');
    expect(z.name, 'محمد خليل الزروق الجديد');
    // Too long a short name is ignored; the new full name stands in.
    expect(z.shortName, 'محمد خليل الزروق الجديد');

    final r = offered('rajab_qaloun');
    expect(r.shortName, 'رجب');
    expect(r.name, Reciter.rajabQaloun.name);
  });

  test('timingsRevision still only rises (old builds read the same key)', () {
    Reciter.installRemote({
      'reciters': [],
      'overrides': {
        'zarrouq_qaloun': {'timingsRevision': 0},
        'almislati_qaloun': {'timingsRevision': 9},
      },
    });
    expect(
      offered('zarrouq_qaloun').timingsRevision,
      Reciter.zarrouqQaloun.timingsRevision,
    );
    expect(offered('almislati_qaloun').timingsRevision, 9);
  });

  test('hidden reciters leave the picker; their id falls back', () {
    Reciter.installRemote({
      'reciters': [],
      'overrides': {
        'doukali_qaloun': {'hidden': true},
        'rajab_qaloun': {'hidden': 'yes'},
      },
    });
    final ids = Reciter.offered.map((r) => r.id).toList();
    expect(ids, isNot(contains('doukali_qaloun')));
    expect(ids, contains('rajab_qaloun'), reason: 'only true hides');
    expect(Reciter.byId('doukali_qaloun').id, Reciter.fallback.id);
    expect(Reciter.byId('rajab_qaloun').id, 'rajab_qaloun');
  });

  test('hiding the fallback resolves unknown ids to the first offered', () {
    Reciter.installRemote({
      'reciters': [],
      'overrides': {
        Reciter.fallback.id: {'hidden': true},
      },
    });
    expect(Reciter.byId('nobody').id, Reciter.offered.first.id);
    expect(Reciter.byId('nobody').id, isNot(Reciter.fallback.id));
  });

  test('every reciter hidden: nothing is hidden', () {
    Reciter.installRemote({
      'reciters': [],
      'overrides': {
        for (final r in Reciter.all) r.id: {'hidden': true},
      },
    });
    expect(Reciter.offered.length, Reciter.all.length);
  });

  test('order: named ids first, the rest keep their place after them', () {
    Reciter.installRemote({
      'reciters': [
        {
          'id': 'tester_qaloun',
          'name': 'قارئ تجريبي',
          'scheme': 'timedSurah',
          'audioBaseUrl': 'https://audio.mushaf-qaloon.com/tester/',
          'timingsBaseUrl':
              'https://quran-content.mushaf-qaloon.com/timings/tester/',
        },
      ],
      'order': ['zarrouq_qaloun', 'tester_qaloun', 'nobody', 7, 'zarrouq_qaloun'],
    });
    final ids = Reciter.offered.map((r) => r.id).toList();
    expect(ids.take(2), ['zarrouq_qaloun', 'tester_qaloun']);
    expect(ids.skip(2), [
      for (final r in Reciter.all)
        if (r.id != 'zarrouq_qaloun') r.id,
    ]);
  });

  group('a replaced recording', () {
    test('a valid one plays the new audio under the same id', () {
      Reciter.installRemote({
        'reciters': [],
        'overrides': {
          'husary_qaloun': {'recording': husaryTimed},
        },
      });
      final h = offered('husary_qaloun');
      expect(h.scheme, AudioScheme.timedSurah);
      expect(h.audioBaseUrl, husaryTimed['audioBaseUrl']);
      expect(h.timingsBaseUrl, husaryTimed['timingsBaseUrl']);
      expect(h.cacheFolder, 'audio_cache_husary_timed');
      expect(h.timingsRevision, 2);
      expect(h.name, Reciter.husaryQaloun.name);
      expect(h.breathCombining, isFalse);
      expect(h.coveredAyat, isEmpty);
      expect(h.samePlaybackAs(Reciter.husaryQaloun), isFalse);
      expect(Reciter.recordingReplaced('husary_qaloun'), isTrue);
      expect(Reciter.retiredCacheFolders, {'audio_cache'});
    });

    test('a label in the same override is kept', () {
      Reciter.installRemote({
        'reciters': [],
        'overrides': {
          'husary_qaloun': {'recording': husaryTimed, 'riwaya': 'جديد'},
        },
      });
      expect(offered('husary_qaloun').riwaya, 'جديد');
      expect(offered('husary_qaloun').scheme, AudioScheme.timedSurah);
    });

    test('anything unsafe keeps the bundled recording', () {
      for (final bad in <Map<String, dynamic>>[
        {...husaryTimed, 'audioBaseUrl': 'https://example.com/x/'},
        {...husaryTimed, 'timingsBaseUrl': 'http://quran-content.mushaf-qaloon.com/t/'},
        {...husaryTimed, 'cacheFolder': '../audio_cache'},
        {...husaryTimed, 'cacheFolder': 'audio_cache'},
        // Another reciter's folder: its files are different audio.
        {...husaryTimed, 'cacheFolder': 'audio_cache_zarrouq'},
        {...husaryTimed}..remove('cacheFolder'),
        {...husaryTimed, 'audioBaseUrl': Reciter.husaryQaloun.audioBaseUrl},
      ]) {
        Reciter.installRemote({
          'reciters': [],
          'overrides': {
            'husary_qaloun': {'recording': bad},
          },
        });
        expect(
          identical(offered('husary_qaloun'), Reciter.husaryQaloun),
          isTrue,
          reason: '$bad',
        );
        expect(Reciter.recordingReplaced('husary_qaloun'), isFalse);
        expect(Reciter.retiredCacheFolders, isEmpty);
      }
    });

    test('two recordings may not share a new folder', () {
      Reciter.installRemote({
        'reciters': [],
        'overrides': {
          'husary_qaloun': {'recording': husaryTimed},
          'hudaifi_qaloun': {
            'recording': {
              ...husaryTimed,
              'audioBaseUrl': 'https://audio.mushaf-qaloon.com/hudaifi_timed/',
            },
          },
        },
      });
      expect(Reciter.recordingReplaced('husary_qaloun'), isTrue);
      expect(Reciter.recordingReplaced('hudaifi_qaloun'), isFalse);
    });

    test('a hidden replaced reciter still retires only its old folder', () {
      Reciter.installRemote({
        'reciters': [],
        'overrides': {
          'husary_qaloun': {'recording': husaryTimed, 'hidden': true},
          'doukali_qaloun': {'hidden': true},
        },
      });
      expect(Reciter.retiredCacheFolders, {'audio_cache'});
    });
  });

  group('page-turn cues', () {
    test('an override cue wins over the compiled table', () {
      final cues = ReciterService.parseOverridePageTurnCues({
        'rajab_qaloun': {
          'pageTurnCues': {
            '35': {'surah': 2, 'ayah': 218, 'file': '002.mp3', 'ms': 42},
            '36': {'surah': 2, 'ayah': 218, 'file': '002218.mp3', 'ms': 1},
            '999': {'surah': 2, 'ayah': 218, 'file': '002.mp3', 'ms': 1},
          },
        },
      });
      expect(cues['rajab_qaloun']!.keys, [35], reason: 'timed: SSS.mp3 only');
      overridePageTurnCues = cues;
      expect(pageTurnCuesFor('rajab_qaloun')![35]!.atMs, 42);
    });

    test('a per-ayah reciter takes only SSSAAA.mp3 cues', () {
      final cues = ReciterService.parseOverridePageTurnCues({
        'hudaifi_qaloun': {
          'pageTurnCues': {
            '35': {'surah': 2, 'ayah': 218, 'file': '002.mp3', 'ms': 1},
            '36': {'surah': 2, 'ayah': 218, 'file': '002218.mp3', 'ms': 2},
          },
        },
      });
      expect(cues['hudaifi_qaloun']!.keys, [36]);
    });

    test('a replaced recording never uses the compiled cues', () {
      Reciter.installRemote({
        'reciters': [],
        'overrides': {
          'husary_qaloun': {'recording': husaryTimed},
        },
      });
      compiledCuesRetired = {'husary_qaloun'};
      expect(pageTurnCues['husary_qaloun'], isNotNull);
      expect(pageTurnCuesFor('husary_qaloun'), isNull, reason: 'estimate');
      // Cues measured on the new recording are taken.
      overridePageTurnCues = ReciterService.parseOverridePageTurnCues({
        'husary_qaloun': {
          'recording': husaryTimed,
          'pageTurnCues': {
            '35': {'surah': 2, 'ayah': 218, 'file': '002.mp3', 'ms': 7},
          },
        },
      });
      expect(pageTurnCuesFor('husary_qaloun')![35]!.atMs, 7);
    });
  });

  group('per-ayah tables', () {
    test('coveredAyat (covered scheme only) and missingAyat replace whole', () {
      Reciter.installRemote({
        'reciters': [],
        'overrides': {
          'doukali_qaloun': {
            'coveredAyat': {'23': [46]},
            'missingAyat': {'5': [34]},
          },
          // Not on the covered scheme: coveredAyat is ignored.
          'husary_qaloun': {
            'coveredAyat': {'23': [46]},
          },
          // Timed: its gaps live in the timing files.
          'rajab_qaloun': {
            'missingAyat': {'2': [1]},
          },
        },
      });
      final d = offered('doukali_qaloun');
      expect(d.coveredAyat, {23: {46}});
      expect(d.missingAyat, {5: {34}});
      expect(d.isMissing(5, 34), isTrue);
      expect(d.samePlaybackAs(Reciter.doukaliQaloun), isTrue);
      expect(identical(offered('husary_qaloun'), Reciter.husaryQaloun), isTrue);
      expect(identical(offered('rajab_qaloun'), Reciter.rajabQaloun), isTrue);
    });

    test('a bad table is ignored, an empty one clears', () {
      Reciter.installRemote({
        'reciters': [],
        'overrides': {
          'doukali_qaloun': {
            'coveredAyat': {'23': [999]},
            'missingAyat': {},
          },
        },
      });
      final d = offered('doukali_qaloun');
      expect(d.coveredAyat, Reciter.doukaliQaloun.coveredAyat);
      expect(d.missingAyat, isEmpty);
    });
  });
}

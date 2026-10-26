import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/page_turn_cues.dart';
import 'package:islamic_dawah_mushaf/services/app_update_service.dart';
import 'package:islamic_dawah_mushaf/services/content_update_service.dart';
import 'package:islamic_dawah_mushaf/services/reciter_service.dart';
import 'package:islamic_dawah_mushaf/services/word_region_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A manifest offering [files] (name -> body) at the given versions.
String manifestFor(
  Map<String, (int, String)> files, {
  Map<String, int> minBuild = const {},
  Map<String, String> badSha = const {},
}) {
  final items = <String, dynamic>{};
  files.forEach((name, v) {
    final (ver, body) = v;
    final bytes = utf8.encode(body);
    items[name] = {
      'ver': ver,
      'url': 'data/$name/${name}_v$ver.json',
      'sha256': badSha[name] ?? sha256.convert(bytes).toString(),
      'bytes': bytes.length,
      if (minBuild[name] != null) 'minBuild': minBuild[name],
    };
  });
  return json.encode({'v': 1, 'items': items});
}

MockClient clientFor(String manifest, Map<String, String> bodies) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path == '/data/manifest.json') return http.Response(manifest, 200);
    for (final e in bodies.entries) {
      if (path.endsWith(e.key)) {
        return http.Response.bytes(utf8.encode(e.value), 200);
      }
    }
    return http.Response('not found', 404);
  });
}

void main() {
  const tanzilatV2 = '{"v":2,"ver":2,"dan":{},"groups":[],"nopaint":{}}';
  late Directory dir;
  final service = ContentUpdateService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('content_update_');
    service.debugReset(dir: dir);
    AppUpdateService.instance.currentBuild = 0;
  });

  tearDown(() async {
    service.debugReset();
    await dir.delete(recursive: true);
  });

  test('the bundled tanzilat version matches the asset', () {
    final asset =
        json.decode(File('assets/data/tanzilat.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(asset['ver'], ContentUpdateService.bundledVersions['tanzilat']);
  });

  test('manifest: good entries parsed, bad ones dropped', () {
    final m = ContentManifest.parse(
      json.encode({
        'v': 1,
        'items': {
          'tanzilat': {
            'ver': 3,
            'url': 'data/tanzilat/tanzilat_v3.json',
            'sha256': 'a' * 64,
            'bytes': 10,
            'minBuild': 130,
          },
          'word_masks': {'ver': 0, 'url': 'x', 'sha256': 'b' * 64, 'bytes': 1},
          'reciters': {'ver': 1, 'url': '../x', 'sha256': 'c' * 64, 'bytes': 1},
          'future_thing': {
            'ver': 1,
            'url': 'y',
            'sha256': 'd' * 64,
            'bytes': 1,
          },
          'junk': 'no',
        },
      }),
    );
    expect(m.items.keys, ['tanzilat', 'future_thing']);
    expect(m.items['tanzilat']!.minBuild, 130);
    expect(() => ContentManifest.parse('[]'), throwsFormatException);
    expect(() => ContentManifest.parse('{"v":1}'), throwsFormatException);
  });

  test('a newer tanzilat is downloaded, verified, applied and kept', () async {
    var applied = 0;
    service.registerItem('tanzilat', apply: () async => applied++);
    final manifest = manifestFor({'tanzilat': (2, tanzilatV2)});
    final client = clientFor(manifest, {'tanzilat_v2.json': tanzilatV2});
    final result = await service.check(manual: true, client: client);
    expect(result.updated, ['tanzilat']);
    expect(result.pendingRestart, isEmpty);
    expect(result.message, 'تم تحديث التنزيلات.');
    expect(applied, 1);
    expect(service.versionOf('tanzilat'), 2);
    expect(await service.readFor('tanzilat'), tanzilatV2);
    expect(File('${dir.path}/tanzilat_v2.json').existsSync(), isTrue);
    expect(service.revision.value, greaterThan(0));
    // Nothing is fetched again within the day unless asked by hand.
    final again = await service.check(client: client);
    expect(again.skipped, isTrue);
    final byHand = await service.check(manual: true, client: client);
    expect(byHand.updated, isEmpty);
    expect(byHand.skipped, isFalse);
  });

  test(
    'a wrong checksum, an old version or a too-new file is refused',
    () async {
      final manifest = manifestFor(
        {'tanzilat': (2, tanzilatV2)},
        badSha: {'tanzilat': 'f' * 64},
      );
      var result = await service.check(
        manual: true,
        client: clientFor(manifest, {'tanzilat_v2.json': tanzilatV2}),
      );
      expect(result.updated, isEmpty);
      expect(result.failed, isFalse);
      expect(await service.readFor('tanzilat'), isNull);
      expect(dir.listSync(), isEmpty);

      // Same version as the bundle: nothing to do.
      result = await service.check(
        manual: true,
        client: clientFor(manifestFor({'tanzilat': (1, tanzilatV2)}), {
          'tanzilat_v1.json': tanzilatV2,
        }),
      );
      expect(result.updated, isEmpty);

      // Needs a newer app than this one.
      AppUpdateService.instance.currentBuild = 125;
      result = await service.check(
        manual: true,
        client: clientFor(
          manifestFor(
            {'tanzilat': (2, tanzilatV2)},
            minBuild: {'tanzilat': 126},
          ),
          {'tanzilat_v2.json': tanzilatV2},
        ),
      );
      expect(result.updated, isEmpty);

      // Not the shape of a tanzilat file.
      result = await service.check(
        manual: true,
        client: clientFor(manifestFor({'tanzilat': (2, '{"ver":2}')}), {
          'tanzilat_v2.json': '{"ver":2}',
        }),
      );
      expect(result.updated, isEmpty);
      expect(service.versionOf('tanzilat'), 1);
    },
  );

  test('an unreachable manifest is a failed check, not an error', () async {
    final client = MockClient((_) async => http.Response('gone', 503));
    final result = await service.check(manual: true, client: client);
    expect(result.failed, isTrue);
    expect(result.message, isNull);
  });

  test(
    'word-box patches wait for the next launch once boxes are loaded',
    () async {
      const patch =
          '{"ver":1,"patches":[{"page":480,"surah":41,"ayah":43,"words":[[[1,2,3,4]]]}]}';
      service.registerItem('word_masks', isLoaded: () => true);
      final result = await service.check(
        manual: true,
        client: clientFor(manifestFor({'word_masks': (1, patch)}), {
          'word_masks_v1.json': patch,
        }),
      );
      expect(result.updated, ['word_masks']);
      expect(result.pendingRestart, ['word_masks']);
      expect(result.message, contains('عند فتح التطبيق من جديد'));
      expect(File('${dir.path}/word_masks_patch_v1.json').existsSync(), isTrue);
    },
  );

  test('parseWordMasks lays a patch over the asset', () {
    const asset =
        '[{"page":480,"hw":[0.04,0.02,0.97,0.95],"ayahs":[{"surah":41,"ayah":43,"words":[[[10,10,5,5]],[[20,10,5,5]]]},{"surah":41,"ayah":44,"words":[[[30,10,5,5]]]}]}]';
    const patch =
        '{"ver":1,"patches":[{"page":480,"surah":41,"ayah":43,"words":[[[10,10,5,5]],[[40,10,8,8]]]},{"page":999,"surah":1,"ayah":1,"words":[]}]}';
    final pages = parseWordMasks((asset, patch));
    final ayah = pages[480]!.ayahs.first;
    expect(ayah.words[1].parts.single.left, closeTo(40 / 720, 1e-9));
    expect(
      pages[480]!.ayahs[1].words.single.parts.single.left,
      closeTo(30 / 720, 1e-9),
    );
    // A broken patch leaves the asset as it is.
    final plain = parseWordMasks((asset, '{"patches":"no"}'));
    expect(
      plain[480]!.ayahs.first.words[1].parts.single.left,
      closeTo(20 / 720, 1e-9),
    );
  });

  group('server-added reciters', () {
    tearDown(() {
      Reciter.installRemote(const {'reciters': []});
      remotePageTurnCues = {};
    });

    const good = {
      'id': 'tester_qaloun',
      'name': 'قارئ تجريبي',
      'shortName': 'تجريبي',
      'scheme': 'timedSurah',
      'audioBaseUrl': 'https://audio.mushaf-qaloon.com/tester/',
      'timingsBaseUrl':
          'https://quran-content.mushaf-qaloon.com/timings/tester/',
      'timingsRevision': 2,
      'pageTurnCues': {
        '35': {'surah': 2, 'ayah': 218, 'file': '002.mp3', 'ms': 5044020},
        'x': {'surah': 2, 'ayah': 218, 'file': '002.mp3', 'ms': 1},
      },
    };

    test('a valid timed-surah reciter is accepted with its cues', () {
      final r = Reciter.fromJson(good)!;
      expect(r.id, 'tester_qaloun');
      expect(r.shortName, 'تجريبي');
      expect(r.riwaya, 'رواية قالون');
      expect(r.scheme, AudioScheme.timedSurah);
      expect(r.cacheFolder, 'audio_cache_tester_qaloun');
      expect(r.timingsRevision, 2);
      expect(
        r.timingsBaseUrlOverride,
        'https://quran-content.mushaf-qaloon.com/timings/tester/',
      );
      final cues = ReciterService.parseRemotePageTurnCues({
        'reciters': [good],
      });
      expect(cues['tester_qaloun']!.keys, [35]);
      expect(cues['tester_qaloun']![35]!.atMs, 5044020);
    });

    test('anything but our hosts and the timed scheme is dropped', () {
      Reciter? of(Map<String, dynamic> changes) =>
          Reciter.fromJson({...good, ...changes});
      expect(of({'scheme': 'covered'}), isNull);
      expect(of({'audioBaseUrl': 'https://example.com/x/'}), isNull);
      expect(of({'audioBaseUrl': 'http://audio.mushaf-qaloon.com/x/'}), isNull);
      expect(of({'audioBaseUrl': 'https://audio.mushaf-qaloon.com/x'}), isNull);
      expect(of({'id': 'Bad Id'}), isNull);
      expect(of({'name': ' '}), isNull);
      expect(
        of({'cacheFolder': '../etc'})!.cacheFolder,
        'audio_cache_tester_qaloun',
      );
    });

    test(
      'installRemote: offered after the bundled, never a bundled id twice',
      () {
        Reciter.installRemote({
          'reciters': [
            good,
            {...good, 'id': 'rajab_qaloun'},
            good,
            {'id': 'broken'},
          ],
          'overrides': {
            'rajab_qaloun': {'timingsRevision': 9},
            'zarrouq_qaloun': {'timingsRevision': 0},
          },
        });
        final offered = Reciter.offered;
        expect(offered.length, Reciter.all.length + 1);
        expect(offered.last.id, 'tester_qaloun');
        expect(
          offered.where((r) => r.id == 'rajab_qaloun').single.timingsRevision,
          9,
        );
        expect(
          offered.where((r) => r.id == 'zarrouq_qaloun').single.timingsRevision,
          Reciter.zarrouqQaloun.timingsRevision,
        );
        expect(Reciter.byId('tester_qaloun').name, 'قارئ تجريبي');
        expect(Reciter.byId('nobody').id, Reciter.fallback.id);
        expect(
          ReciterService.instance.reciters.map((r) => r.id),
          contains('tester_qaloun'),
        );
      },
    );

    test(
      'the cue lookup falls back from the compiled table to the remote one',
      () {
        remotePageTurnCues = {
          'tester_qaloun': {35: const PageTurnCue(2, 218, '002.mp3', 1)},
        };
        expect(pageTurnCuesFor('tester_qaloun')![35]!.atMs, 1);
        expect(
          pageTurnCuesFor('rajab_qaloun'),
          same(pageTurnCues['rajab_qaloun']),
        );
        expect(pageTurnCuesFor('nobody'), isNull);
      },
    );
  });
}

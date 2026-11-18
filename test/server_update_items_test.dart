import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:islamic_dawah_mushaf/models/tafsir_edition.dart';
import 'package:islamic_dawah_mushaf/services/app_update_service.dart';
import 'package:islamic_dawah_mushaf/services/content_update_service.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/page_phoneme_service.dart';
import 'package:islamic_dawah_mushaf/services/quran_data_patch.dart';
import 'package:islamic_dawah_mushaf/services/remote_config.dart';
import 'package:islamic_dawah_mushaf/services/server_notice_service.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_data_patch.dart';
import 'package:islamic_dawah_mushaf/utils/phoneme_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The server items added 2026-11-17 (tasmee_data, app_config, quran_data,
/// notices): every file the app would refuse is refused before it replaces
/// anything, and without a file the app behaves exactly as bundled.
void main() {
  group('app_config (RemoteConfig)', () {
    tearDown(() => RemoteConfig.instance.debugSet(const {}));

    test('without a server file the judge is exactly the bundled one', () {
      RemoteConfig.instance.debugSet(const {});
      const bundled = TrackerConfig();
      final slow = MemorizationTestService.trackerConfigFor(fast: false);
      final fast = MemorizationTestService.trackerConfigFor(fast: true);
      for (final c in [slow, fast]) {
        expect(c.jumpCost, bundled.jumpCost);
        expect(c.repeatCost, bundled.repeatCost);
        expect(c.ayahJumpCost, bundled.ayahJumpCost);
        expect(c.heldRepeatCost, bundled.heldRepeatCost);
        expect(c.farJumpCost, bundled.farJumpCost);
        expect(c.startAyahCost, bundled.startAyahCost);
        expect(c.lexiconDistance, bundled.lexiconDistance);
        expect(c.okDistance, bundled.okDistance);
        expect(c.unsureDistance, bundled.unsureDistance);
        expect(c.minHeardFraction, bundled.minHeardFraction);
        expect(c.minMargin, bundled.minMargin);
        expect(c.lostWindow, bundled.lostWindow);
        expect(c.lostRate, bundled.lostRate);
        expect(c.earlyCommit, bundled.earlyCommit);
        expect(c.orphanVowel, bundled.orphanVowel);
      }
      expect(slow.commitDwell, bundled.commitDwell);
      expect(slow.settleFrames, bundled.settleFrames);
      expect(fast.commitDwell, 0);
      expect(fast.settleFrames, 12);
      expect(MemorizationTestService.settleMsFor(fast: false), 1000);
      expect(MemorizationTestService.settleMsFor(fast: true), 500);
    });

    test('every key default matches what the code used before', () {
      const bundled = TrackerConfig();
      final keys = RemoteConfig.keys;
      expect(keys['tasmee.okDistance']!.defaultValue, bundled.okDistance);
      expect(keys['tasmee.unsureDistance']!.defaultValue, bundled.unsureDistance);
      expect(keys['tasmee.minMargin']!.defaultValue, bundled.minMargin);
      expect(
        keys['tasmee.minHeardFraction']!.defaultValue,
        bundled.minHeardFraction,
      );
      expect(
        keys['tasmee.lexiconDistance']!.defaultValue,
        bundled.lexiconDistance,
      );
      expect(keys['tasmee.commitDwell']!.defaultValue, bundled.commitDwell);
      expect(keys['tasmee.settleFrames']!.defaultValue, bundled.settleFrames);
      expect(keys['tasmee.earlyCommit']!.defaultValue, bundled.earlyCommit);
      expect(keys['tasmee.orphanVowel']!.defaultValue, bundled.orphanVowel);
      expect(keys['chat.enabled']!.defaultValue, isTrue);
      expect(keys['tasmee.drillsEnabled']!.defaultValue, isFalse);
      expect(keys['tasmee.locateEnabled']!.defaultValue, isTrue);
      expect(keys['content.checkHours']!.defaultValue, 24);
      for (final e in keys.entries) {
        final k = e.value;
        if (k.kind == RemoteKind.flag) continue;
        expect(
          (k.defaultValue as num) >= k.min! && (k.defaultValue as num) <= k.max!,
          isTrue,
          reason: '${e.key} default outside its own range',
        );
      }
    });

    test('only known keys, right type, in range', () {
      final v = RemoteConfig.parse(
        json.encode({
          'ver': 1,
          'values': {
            'chat.enabled': false,
            'tasmee.okDistance': 0.17,
            'tasmee.unsureDistance': 0.9, // out of range
            'tasmee.commitDwell': 4.5, // not an int
            'tasmee.settleFrames': 30,
            'tasmee.earlyCommit': 'no', // not a bool
            'nobody.knows': true,
          },
        }),
      );
      expect(v, {
        'chat.enabled': false,
        'tasmee.okDistance': 0.17,
        'tasmee.settleFrames': 30,
      });
      RemoteConfig.instance.debugSet(v);
      final c = MemorizationTestService.trackerConfigFor(fast: false);
      expect(c.okDistance, 0.17);
      expect(c.unsureDistance, const TrackerConfig().unsureDistance);
      expect(c.settleFrames, 30);
      expect(RemoteConfig.instance.flag('chat.enabled'), isFalse);
    });

    test('a file that is not a config is refused', () {
      for (final bad in [
        '[]',
        '{"values": {}}',
        '{"ver": 1}',
        '{"ver": 1, "values": []}',
        'not json',
      ]) {
        expect(() => RemoteConfig.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('server-added tafsir editions: our host only, never a bundled id', () {
      final list = RemoteConfig.parseTafsirEditions(
        json.encode({
          'ver': 1,
          'values': {},
          'tafsirEditions': [
            {'id': 'baghawi', 'name': 'تفسير البغوي', 'subtitle': 'البغوي',
             'approxDownloadMb': 40},
            {'id': 'saddi', 'name': 'x', 'subtitle': ''},
            {'id': 'Bad Id', 'name': 'x', 'subtitle': ''},
            {'id': 'baghawi', 'name': 'مكرر', 'subtitle': ''},
            {'id': 'nameless', 'name': ' ', 'subtitle': ''},
          ],
        }),
      );
      expect(list.map((e) => e.id), ['baghawi']);
      final e = list.single;
      expect(e.isBundled, isFalse);
      expect(e.cacheFolder, 'tafsir_cache_baghawi');
      expect(
        e.pageUrl(7),
        'https://quran-content.mushaf-qaloon.com/tafsir/baghawi/page_007.json',
      );
      TafsirEdition.remote = list;
      addTearDown(() => TafsirEdition.remote = const []);
      expect(TafsirEdition.byId('baghawi').name, 'تفسير البغوي');
      expect(TafsirEdition.onlineEditions.last.id, 'baghawi');
      expect(TafsirEdition.offered.length, TafsirEdition.all.length + 1);
    });
  });

  group('tasmee_data (TasmeeDataPatch)', () {
    final pagesJson = File('assets/data/page_phonemes.json').readAsStringSync();
    final pages = json.decode(pagesJson) as List<dynamic>;
    final page6 = pages.firstWhere((p) => p['page'] == 6) as Map;
    final ayah = (page6['ayahs'] as List).first as Map;
    final key = ayah['key'] as String;
    final words = [for (final w in ayah['w'] as List) List<dynamic>.of(w)];

    String patchWith(List<dynamic> w, {int page = 6, String? k}) => json.encode({
      'ver': 1,
      'ayahs': [
        {'page': page, 'key': k ?? key, 'w': w},
      ],
    });

    test('every bundled word passes the word check', () {
      var n = 0;
      for (final p in pages) {
        for (final a in p['ayahs'] as List) {
          for (final w in a['w'] as List) {
            expect(TasmeeDataPatch.validWord(w), isTrue, reason: '$w');
            n++;
          }
        }
      }
      expect(n, greaterThan(70000));
    });

    test('an ayah with the same word count is replaced, nothing else', () {
      final changed = [for (final w in words) List<dynamic>.of(w)];
      changed[0][1] = 'تَجرِبَة';
      final before = PagePhonemeService.parse(pagesJson);
      final after = PagePhonemeService.parseWithPatch((pagesJson, patchWith(changed)));
      expect(after[6]!.words.first.phon, 'تَجرِبَة');
      expect(after[6]!.words.length, before[6]!.words.length);
      for (var i = 1; i < before[6]!.words.length; i++) {
        expect(after[6]!.words[i].phon, before[6]!.words[i].phon);
      }
      expect(after[7]!.words.first.phon, before[7]!.words.first.phon);
    });

    test('another word count, page or ayah: the bundle stays', () {
      final shorter = words.sublist(1);
      final before = PagePhonemeService.parse(pagesJson);
      for (final patch in [
        patchWith(shorter),
        patchWith(words.map((w) => [...w]..[1] = 'x').toList(), page: 7),
      ]) {
        final after = PagePhonemeService.parseWithPatch((pagesJson, patch));
        for (final p in [6, 7]) {
          expect(
            after[p]!.words.map((w) => w.phon).toList(),
            before[p]!.words.map((w) => w.phon).toList(),
          );
        }
      }
    });

    test('a file out of shape is refused as a whole', () {
      final bad = [for (final w in words) List<dynamic>.of(w)];
      bad[1][3] = 2; // taMarbuta must be 0/1
      for (final source in [
        patchWith(bad),
        patchWith(words, page: 605),
        patchWith(words, k: '115:1'),
        patchWith(words, k: '2-30'),
        json.encode({'ayahs': []}),
        json.encode({'ver': 1, 'lexiconAdd': ['a'], 'lexiconRemove': ['a']}),
        json.encode({'ver': 1, 'lexiconAdd': ['']}),
      ]) {
        expect(
          () => TasmeeDataPatch.parse(source),
          throwsFormatException,
          reason: source.length > 80 ? source.substring(0, 80) : source,
        );
        // ... and at load the bundle is used unchanged.
        final after = PagePhonemeService.parseWithPatch((pagesJson, source));
        expect(after[6]!.words.first.phon, words.first[1]);
      }
    });

    test('lexicon: removed and added entries', () {
      final p = TasmeeDataPatch.parse(
        json.encode({
          'ver': 1,
          'lexiconAdd': ['جَدِيد', 'قَدِيم'],
          'lexiconRemove': ['خَطَأ'],
        }),
      );
      expect(p.applyToLexicon(['قَدِيم', 'خَطَأ', 'بَاقٍ']), [
        'قَدِيم',
        'بَاقٍ',
        'جَدِيد',
      ]);
    });
  });

  group('quran_data (QuranDataPatch)', () {
    final regions = json.decode(
      File('assets/data/ayah_regions.json').readAsStringSync(),
    ) as List<dynamic>;
    final audio = json.decode(
      File('assets/data/audio_ayah_map.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final narration = json.decode(
      File('assets/data/narration_map.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final breath = json.decode(
      File('assets/data/qaniwah_continuations.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('the whole bundle, sent back as a patch, is accepted', () {
      final p = QuranDataPatch.parse(
        json.encode({
          'ver': 1,
          'ayahRegions': {
            for (final page in regions) '${page['page']}': page,
          },
          'audioAyahMap': audio['map'],
          'narrationMap': narration['qalun_to_hafs'],
          'breathData': {'assets/data/qaniwah_continuations.json': breath},
        }),
      );
      expect(p.ayahRegions.length, regions.length);
      expect(p.audioAyahMap![20]![24], [25]);
      // Laid over itself, every page is "replaced" by an equal one.
      final copy = json.decode(json.encode(regions)) as List<dynamic>;
      expect(p.applyToRegions(copy), regions.length);
    });

    test('a page whose ayat differ from the bundle keeps its boxes', () {
      final page35 = Map<String, dynamic>.from(
        regions.firstWhere((p) => p['page'] == 35) as Map,
      );
      final moved = {
        ...page35,
        'ayahs': (page35['ayahs'] as List).sublist(1),
      };
      final p = QuranDataPatch.parse(
        json.encode({
          'ver': 1,
          'ayahRegions': {'35': moved},
        }),
      );
      final copy = json.decode(json.encode(regions)) as List<dynamic>;
      expect(p.applyToRegions(copy), 0);
      expect(json.encode(copy), json.encode(regions));
    });

    test('a file out of shape is refused as a whole', () {
      final page35 = regions.firstWhere((p) => p['page'] == 35) as Map;
      final badRect = json.decode(json.encode(page35)) as Map;
      ((badRect['ayahs'] as List).first['rects'] as List).first['width'] = 0;
      for (final source in [
        json.encode({'ayahRegions': {}}),
        json.encode({'ver': 1, 'ayahRegions': {'605': page35}}),
        json.encode({'ver': 1, 'ayahRegions': {'35': badRect}}),
        json.encode({'ver': 1, 'audioAyahMap': {'115': {}}}),
        json.encode({'ver': 1, 'audioAyahMap': {'20': {'24': ['25']}}}),
        json.encode({'ver': 1, 'narrationMap': {'2': {'1': [3, 2]}}}),
        json.encode({'ver': 1, 'breathData': {'../x.json': breath}}),
        json.encode({
          'ver': 1,
          'tafsirFixes': [
            {'edition': 'ibn_kathir', 'surah': 1, 'ayah': 1, 'text': 'x'},
          ],
        }),
      ]) {
        expect(
          () => QuranDataPatch.parse(source),
          throwsFormatException,
          reason: source.length > 80 ? source.substring(0, 80) : source,
        );
      }
    });

    test('tafsir fixes are kept per edition', () {
      final p = QuranDataPatch.parse(
        json.encode({
          'ver': 1,
          'tafsirFixes': [
            {'edition': 'saddi', 'surah': 2, 'ayah': 5, 'text': 'نص'},
          ],
        }),
      );
      expect(p.tafsirFixes['saddi']!['2:5'], 'نص');
    });
  });

  group('notices (ServerNoticeService)', () {
    Map<String, dynamic> notice([Map<String, dynamic> extra = const {}]) => {
      'id': 'reciter-new',
      'title': 'قارئ جديد',
      'lines': ['أضفنا تلاوة جديدة.'],
      ...extra,
    };
    String file(List<Map<String, dynamic>> n) =>
        json.encode({'ver': 1, 'notices': n});

    test('a valid notice and its window', () {
      final n = ServerNoticeService.parse(
        file([
          notice({
            'from': '2026-11-20',
            'until': '2026-11-30',
            'minBuild': 150,
            'platforms': ['android'],
            'button': {'label': 'افتح', 'action': 'page:255'},
          }),
        ]),
      ).single;
      bool due(DateTime d, {int build = 151, String platform = 'android'}) =>
          n.dueFor(d, build: build, platform: platform);
      expect(due(DateTime(2026, 11, 19, 23)), isFalse);
      expect(due(DateTime(2026, 11, 20, 0, 1)), isTrue);
      expect(due(DateTime(2026, 11, 30, 23, 59)), isTrue);
      expect(due(DateTime(2026, 12, 1)), isFalse);
      expect(due(DateTime(2026, 11, 25), build: 149), isFalse);
      expect(due(DateTime(2026, 11, 25), build: 0), isTrue);
      expect(due(DateTime(2026, 11, 25), platform: 'ios'), isFalse);
      expect(n.buttonAction, 'page:255');
    });

    test('anything out of shape refuses the file', () {
      for (final bad in [
        notice({'id': 'Has Space'}),
        notice({'title': ''}),
        notice({'lines': []}),
        notice({'lines': [1]}),
        notice({'from': '20-11-2026'}),
        notice({'from': '2026-11-30', 'until': '2026-11-01'}),
        notice({'platforms': ['web']}),
        notice({'button': {'label': 'x', 'action': 'url:http://x.com'}}),
        notice({'button': {'label': 'x', 'action': 'page:605'}}),
        notice({'button': {'label': 'x', 'action': 'shell:rm'}}),
        notice({'minBuild': -1}),
      ]) {
        expect(
          () => ServerNoticeService.parse(file([bad])),
          throwsFormatException,
          reason: '$bad',
        );
      }
      expect(
        () => ServerNoticeService.parse(file([notice(), notice()])),
        throwsFormatException,
        reason: 'duplicate id',
      );
    });
  });

  group('download and install', () {
    late Directory dir;
    final service = ContentUpdateService.instance;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('server_items_');
      service.debugReset(dir: dir);
      AppUpdateService.instance.currentBuild = 0;
    });

    tearDown(() async {
      service.debugReset();
      await dir.delete(recursive: true);
    });

    MockClient serve(Map<String, String> files) {
      final items = <String, dynamic>{};
      files.forEach((name, body) {
        final bytes = utf8.encode(body);
        items[name] = {
          'ver': 1,
          'url': 'data/$name/x_v1.json',
          'sha256': sha256.convert(bytes).toString(),
          'bytes': bytes.length,
        };
      });
      final manifest = json.encode({'v': 1, 'items': items});
      return MockClient((request) async {
        if (request.url.path == '/data/manifest.json') {
          return http.Response(manifest, 200);
        }
        for (final e in files.entries) {
          if (request.url.path == '/data/${e.key}/x_v1.json') {
            return http.Response.bytes(utf8.encode(e.value), 200);
          }
        }
        return http.Response('not found', 404);
      });
    }

    test('valid files install; settings and messages are not announced', () async {
      final result = await service.check(
        manual: true,
        client: serve({
          'app_config': '{"ver":1,"values":{"chat.enabled":false}}',
          'notices': json.encode({
            'ver': 1,
            'notices': [
              {'id': 'a', 'title': 'ت', 'lines': ['س']},
            ],
          }),
          'tasmee_data': '{"ver":1,"ayahs":[],"lexiconAdd":["جَدِيد"]}',
          'quran_data': '{"ver":1,"audioAyahMap":{"20":{"24":[25]}}}',
        }),
      );
      expect(
        result.updated.toSet(),
        {'app_config', 'notices', 'tasmee_data', 'quran_data'},
      );
      expect(result.message, isNot(contains('app_config')));
      expect(result.message, contains('التسميع'));
      expect(await service.readFor('app_config'), contains('chat.enabled'));
      // The notice is due, once.
      final n = await ServerNoticeService.instance.next();
      expect(n!.id, 'a');
      await ServerNoticeService.instance.markSeen('a');
      expect(await ServerNoticeService.instance.next(), isNull);
    });

    test('a file the loader would refuse is never installed', () async {
      final result = await service.check(
        manual: true,
        client: serve({
          'app_config': '{"values":{}}',
          'notices': '{"ver":1,"notices":[{"id":"BAD"}]}',
          'tasmee_data': '{"ver":1,"ayahs":[{"page":0}]}',
          'quran_data': '{"ver":1,"narrationMap":{"2":{"1":"x"}}}',
        }),
      );
      expect(result.updated, isEmpty);
      for (final item in ['app_config', 'notices', 'tasmee_data', 'quran_data']) {
        expect(await service.readFor(item), isNull, reason: item);
      }
    });
  });
}

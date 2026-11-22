// A surah's recording corrected after release (owner, 2026-11-22: al-Qryw
// 40:21 had lost «كانوا»): the server names the new file per surah, phones
// that stream get it at once, phones that downloaded the old file keep a
// working pair until the new one is on the phone, then the old one goes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/services/audio_download_service.dart';
import 'package:islamic_dawah_mushaf/services/reciter_service.dart';
import 'package:islamic_dawah_mushaf/services/surah_file_upgrade.dart';
import 'package:islamic_dawah_mushaf/services/surah_timings_service.dart';
import 'package:path/path.dart' as p;

String _timings(int surah, String file, {int shift = 0}) => jsonEncode({
      'surah': surah,
      'file': file,
      'duration_ms': 60000 + shift,
      'ayat': {
        '1': [0, 10000],
        '2': [10000, 30000 + shift],
        '3': [30000 + shift, 60000 + shift],
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('server table', () {
    test('surahFiles / surahTimings add to the bundled ones; bad entries '
        'are dropped one by one', () {
      final base = Reciter.alqrywQaloun;
      final o = Reciter.overrideFromJson(base, {
        'surahFiles': {
          '2': '002_v2.mp3',
          '3': '004_v2.mp3', // another surah's name
          '5': '005.wav',
          '200': '200_v2.mp3',
          '7': 7,
        },
        'surahTimings': {'53': 2, '54': 0, 'x': 3},
      }).reciter!;
      expect(o.surahFiles, {40: '040_v2.mp3', 2: '002_v2.mp3'});
      expect(o.audioFileFor(2), '002_v2.mp3');
      expect(o.audioFileFor(3), '003.mp3');
      expect(o.surahTimingsRevision(53), 2);
      expect(o.surahTimingsRevision(54), 1);
      expect(o.samePlaybackAs(base), isFalse);
    });

    test('a per-surah timings revision never goes down; nothing new = no '
        'override', () {
      final base = Reciter.alqrywQaloun.copyWith(surahTimingsRevisions: {53: 3});
      final o = Reciter.overrideFromJson(base, {
        'surahTimings': {'53': 2},
        'surahFiles': {'40': '040_v2.mp3'},
      });
      expect(o.reciter, isNull);
    });

    test('per-ayah reciters ignore the table; a server-added reciter and a '
        'replaced recording carry their own', () {
      final husary = Reciter.overrideFromJson(Reciter.husaryQaloun, {
        'surahFiles': {'2': '002_v2.mp3'},
      });
      expect(husary.reciter, isNull);

      final added = Reciter.fromJson({
        'id': 'x_qaloun',
        'name': 'x',
        'scheme': 'timedSurah',
        'audioBaseUrl': 'https://audio.mushaf-qaloon.com/x/',
        'timingsBaseUrl': 'https://quran-content.mushaf-qaloon.com/timings/x/',
        'surahFiles': {'1': '001_b.mp3'},
        'surahTimings': {'2': 2},
      })!;
      expect(added.audioFileFor(1), '001_b.mp3');
      expect(added.surahTimingsRevision(2), 2);

      final swapped = Reciter.overrideFromJson(Reciter.alqrywQaloun, {
        'recording': {
          'audioBaseUrl': 'https://audio.mushaf-qaloon.com/alqryw2/',
          'timingsBaseUrl':
              'https://quran-content.mushaf-qaloon.com/timings/alqryw2/',
          'cacheFolder': 'audio_cache_alqryw2',
          'surahFiles': {'9': '009_v2.mp3'},
        },
      }).reciter!;
      // the bundled recording's corrections are not the new recording's
      expect(swapped.surahFiles, {9: '009_v2.mp3'});
    });

    test('downloads ask for the corrected file', () {
      final svc = ReciterService.instance;
      final before = svc.selected.value;
      svc.selected.value = Reciter.alqrywQaloun;
      try {
        final d = AudioDownloadService.instance;
        expect(d.getSurahFilenames(40), ['040_v2.mp3']);
        expect(d.getSurahFilenames(39), ['039.mp3']);
        expect(d.getAllFilenames(), hasLength(114));
        expect(d.getAllFilenames(), isNot(contains('040.mp3')));
      } finally {
        svc.selected.value = before;
      }
    });
  });

  group('on the phone', () {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory tmp;
    late Directory audio;
    final served = <String, String>{}; // url -> body
    final asked = <String>[];
    var online = true;

    http.Client client() => MockClient((request) async {
          final url = request.url.toString();
          asked.add(url);
          if (!online) throw const SocketException('offline');
          final body = served[url];
          return body == null
              ? http.Response('', 404)
              : http.Response.bytes(utf8.encode(body), 200);
        });

    // before the correction: what phones had; after: what the server says
    final before = Reciter.alqrywQaloun.copyWith(
      surahFiles: const {},
      timingsRevision: 1,
    );
    final after = before.copyWith(surahFiles: const {40: '040_v2.mp3'});
    final timingsUrl = '${before.timingsBaseUrl}040.json';
    final newAudioUrl = '${before.audioBaseUrl}040_v2.mp3';

    File audioFile(String name) => File(p.join(audio.path, name));
    File timingsFile(String folder, String name) =>
        File(p.join(audio.path, folder, name));
    void putOldPair() {
      audioFile('040.mp3').writeAsBytesSync(List.filled(100, 1));
      timingsFile('timings', '040.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(_timings(40, '040.mp3'));
    }

    Future<T> net<T>(Future<T> Function() body) =>
        http.runWithClient(body, client);

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('surah_fix');
      audio = Directory(p.join(tmp.path, before.cacheFolder))..createSync();
      messenger.setMockMethodCallHandler(channel, (_) async => tmp.path);
      served
        ..clear()
        ..[timingsUrl] = _timings(40, '040_v2.mp3', shift: 875)
        ..[newAudioUrl] = 'new-audio-bytes';
      asked.clear();
      online = true;
      SurahTimingsService.instance.forget(before);
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      SurahTimingsService.instance.forget(before);
      tmp.deleteSync(recursive: true);
    });

    test('a phone that only streams plays the corrected file at once', () async {
      final t = await net(() => SurahTimingsService.instance.load(after, 40));
      expect(t!.file, '040_v2.mp3');
      expect(t.spans[3]!.$1, const Duration(milliseconds: 30875));
      expect(timingsFile('timings', '040_v2.json').existsSync(), isTrue);
      expect(SurahTimingsService.instance.cached(after, 40), same(t));
      // the pre-correction reciter does not see what was chosen for another
      expect(SurahTimingsService.instance.cached(before, 40), isNull);
    });

    test('a downloaded old file keeps its own spans, online and offline, '
        'until the new file is on the phone', () async {
      putOldPair();
      SurahTimings? t =
          await net(() => SurahTimingsService.instance.load(after, 40));
      expect(t!.file, '040.mp3', reason: 'old audio, old spans: a pair');
      expect(t.spans[3]!.$1, const Duration(milliseconds: 30000));
      // the new spans are kept for when the new audio lands; the old ones stay
      expect(timingsFile('timings', '040_v2.json').existsSync(), isTrue);
      expect(timingsFile('timings', '040.json').existsSync(), isTrue);

      SurahTimingsService.instance.forget(after);
      online = false;
      t = await net<SurahTimings?>(
          () => SurahTimingsService.instance.load(after, 40));
      expect(t!.file, '040.mp3');

      audioFile('040_v2.mp3').writeAsStringSync('new');
      SurahTimingsService.instance.forget(after);
      t = await net<SurahTimings?>(
          () => SurahTimingsService.instance.load(after, 40));
      expect(t!.file, '040_v2.mp3');
    });

    test('offline after a whole-reciter revision: the older folder still '
        'plays (it used to be deleted first)', () async {
      putOldPair();
      online = false;
      final bumped = before.copyWith(timingsRevision: 2);
      SurahTimingsService.instance.forget(bumped);
      final t = await net(() => SurahTimingsService.instance.load(bumped, 40));
      expect(t!.file, '040.mp3');
      expect(timingsFile('timings', '040.json').existsSync(), isTrue);

      // online: the new revision arrives and the superseded copy goes,
      // folder and all
      online = true;
      served[timingsUrl] = _timings(40, '040.mp3', shift: 10);
      SurahTimingsService.instance.forget(bumped);
      final t2 = await net(() => SurahTimingsService.instance.load(bumped, 40));
      expect(t2!.spans[3]!.$1, const Duration(milliseconds: 30010));
      expect(timingsFile('timings_r2', '040.json').existsSync(), isTrue);
      expect(Directory(p.join(audio.path, 'timings')).existsSync(), isFalse);
    });

    test('a per-surah timings revision re-fetches that surah only', () async {
      putOldPair();
      timingsFile('timings', '039.json').writeAsStringSync(_timings(39, '039.mp3'));
      served[timingsUrl] = _timings(40, '040.mp3', shift: 5);
      final r = before.copyWith(surahTimingsRevisions: const {40: 2});
      SurahTimingsService.instance.forget(r);
      final t = await net(() => SurahTimingsService.instance.load(r, 40));
      expect(t!.spans[3]!.$1, const Duration(milliseconds: 30005));
      expect(timingsFile('timings', '040.t2.json').existsSync(), isTrue);
      expect(timingsFile('timings', '040.json').existsSync(), isFalse);
      final t39 = await net(() => SurahTimingsService.instance.load(r, 39));
      expect(t39!.file, '039.mp3');
      expect(asked.where((u) => u.endsWith('039.json')), isEmpty);
    });

    test('the upgrade pass: fetches the corrected file, then removes the old '
        'one on the next pass', () async {
      // the bundled reciter as the next release ships it
      final r = Reciter.byIdIncludingHidden('alqryw_qaloun');
      expect(r.audioFileFor(40), '040_v2.mp3');
      SurahTimingsService.instance.forget(r);
      // what this phone downloaded before the correction
      audioFile('040.mp3').writeAsBytesSync(List.filled(100, 1));
      timingsFile('timings_r2', '040.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(_timings(40, '040.mp3'));
      audioFile('039.mp3').writeAsStringSync('untouched');

      await net(() => SurahFileUpgrade.run(client: client()));
      expect(audioFile('040_v2.mp3').readAsStringSync(), 'new-audio-bytes');
      expect(timingsFile('timings_r2', '040_v2.json').existsSync(), isTrue);
      expect(audioFile('040.mp3').existsSync(), isTrue,
          reason: 'removed only on a later pass');

      await net(() => SurahFileUpgrade.run(client: client()));
      expect(audioFile('040.mp3').existsSync(), isFalse);
      expect(timingsFile('timings_r2', '040.json').existsSync(), isFalse);
      expect(audioFile('039.mp3').readAsStringSync(), 'untouched');
      final t = await net(() => SurahTimingsService.instance.load(r, 40));
      expect(t!.file, '040_v2.mp3');
    });

    test('the upgrade pass offline changes nothing; an old file playing in '
        'this run is not deleted', () async {
      final r = Reciter.byIdIncludingHidden('alqryw_qaloun');
      SurahTimingsService.instance.forget(r);
      audioFile('040.mp3').writeAsBytesSync(List.filled(100, 1));
      timingsFile('timings_r2', '040.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(_timings(40, '040.mp3'));
      online = false;
      await net(() => SurahFileUpgrade.run(client: client()));
      expect(audioFile('040_v2.mp3').existsSync(), isFalse);
      expect(audioFile('040.mp3').existsSync(), isTrue);

      // the old pair is what this run is playing
      final playing = await net(() => SurahTimingsService.instance.load(r, 40));
      expect(playing!.file, '040.mp3');
      online = true;
      await net(() => SurahFileUpgrade.run(client: client()));
      await net(() => SurahFileUpgrade.run(client: client()));
      expect(audioFile('040_v2.mp3').existsSync(), isTrue);
      expect(audioFile('040.mp3').existsSync(), isTrue,
          reason: 'still held by this run');
    });

    test('leftovers of a partly heard old file go once the new spans are '
        'here', () async {
      final r = Reciter.byIdIncludingHidden('alqryw_qaloun');
      SurahTimingsService.instance.forget(r);
      audioFile('040.mp3.seg').writeAsStringSync('partial');
      audioFile('040.mp3.seg.json').writeAsStringSync('{}');
      await net(() => SurahTimingsService.instance.download(r, 40));
      await net(() => SurahFileUpgrade.run(client: client()));
      expect(audioFile('040.mp3.seg').existsSync(), isFalse);
      expect(audioFile('040.mp3.seg.json').existsSync(), isFalse);
      expect(audioFile('040_v2.mp3').existsSync(), isFalse,
          reason: 'never downloaded: it streams when played');
    });
  });
}

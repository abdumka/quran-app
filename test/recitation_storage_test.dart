// Deleting recitations from the phone (owner, 2026-11-22): per reciter on the
// downloads page, per surah in the download sheet, counting what was kept
// while listening as well as what was downloaded.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/services/audio_download_service.dart';
import 'package:islamic_dawah_mushaf/services/reciter_service.dart';
import 'package:islamic_dawah_mushaf/services/surah_timings_service.dart';
import 'package:islamic_dawah_mushaf/widgets/settings/downloads_management_page.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('wording', () {
    test('what a reciter has, in words', () {
      expect(recitationStorageDetail(114, 0), '114 سورة كاملة');
      expect(
        recitationStorageDetail(23, 4),
        '23 سورة كاملة، وأجزاء من 4 سور',
      );
      expect(recitationStorageDetail(0, 6), 'أجزاء من 6 سور');
      expect(recitationStorageDetail(0, 12), 'أجزاء من 12 سورة');
      expect(
        recitationStorageDetail(1, 1),
        'سورة واحدة كاملة، وأجزاء من سورة واحدة',
      );
      expect(
        recitationStorageDetail(2, 2),
        'سورتان كاملتان، وأجزاء من سورتين',
      );
      expect(recitationStorageDetail(3, 0), '3 سور كاملة');
      expect(recitersCountLabel(2), 'قارئَين');
      expect(recitersCountLabel(4), '4 قرّاء');
      expect(recitersCountLabel(11), '11 قارئًا');
    });

    test('sizes, kept left-to-right inside Arabic text', () {
      String plain(String s) => s.replaceAll(RegExp('[\u2066\u2069]'), '');
      expect(plain(formatStorageBytes(0)), '0 MB');
      expect(plain(formatStorageBytes(412 * 1024 * 1024)), '412 MB');
      expect(
        plain(formatStorageBytes((1.55 * 1024 * 1024 * 1024).round())),
        '1.55 GB',
      );
      expect(formatStorageBytes(5 << 20), '\u20665.00 MB\u2069');
    });
  });

  group('on the phone', () {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory tmp;
    final svc = AudioDownloadService.instance;
    final timed = Reciter.byIdIncludingHidden('alqryw_qaloun');
    const perAyah = Reciter.husaryQaloun;

    Directory folder(Reciter r) => Directory(p.join(tmp.path, r.cacheFolder));
    File put(Reciter r, String name, int size) {
      final f = File(p.join(folder(r).path, name));
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(List.filled(size, 7));
      return f;
    }

    Set<String> namesIn(Reciter r) => {
      for (final e in folder(r).listSync(recursive: true))
        if (e is File) p.relative(e.path, from: folder(r).path).replaceAll(r'\', '/'),
    };

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('recitation_storage');
      messenger.setMockMethodCallHandler(channel, (_) async => tmp.path);
      SharedPreferences.setMockInitialValues({
        'selectedReciterId': 'alqryw_qaloun',
      });
      await ReciterService.instance.load();
      ReciterService.instance.selected.value = timed;
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      SurahTimingsService.instance.forget(timed);
      tmp.deleteSync(recursive: true);
    });

    test('each reciter: what was downloaded and what was kept while '
        'listening; the selected one first, then the largest', () async {
      // al-Qryw (selected): surah 1 whole, surah 2 partly heard, timings
      put(timed, '001.mp3', 100);
      put(timed, '002.mp3.seg', 50);
      put(timed, '002.mp3.seg.json', 10);
      put(timed, 'timings_r2/001.json', 20);
      // al-Husary: surah 1 whole (7 ayah files), two ayat of surah 2
      for (var a = 1; a <= 7; a++) {
        put(perAyah, '001${a.toString().padLeft(3, '0')}.mp3', 100);
      }
      put(perAyah, '002001.mp3', 100);
      put(perAyah, '002002.mp3.part', 30);
      // al-Zarrouq: timings only, nothing to hear: not listed
      put(Reciter.zarrouqQaloun, 'timings/001.json', 20);

      final rows = await svc.reciterStorage();
      expect([for (final r in rows) r.reciter.id], [timed.id, perAyah.id]);
      expect(rows[0].bytes, 180);
      expect((rows[0].completeSurahs, rows[0].partialSurahs), (1, 1));
      expect(rows[1].bytes, 830);
      expect((rows[1].completeSurahs, rows[1].partialSurahs), (1, 1));
    });

    test('a timed surah with only its older recording still plays from the '
        'phone', () async {
      put(timed, '040.mp3', 100); // corrected one is 040_v2.mp3
      final rows = await svc.reciterStorage();
      expect((rows.single.completeSurahs, rows.single.partialSurahs), (1, 0));
    });

    test('deleting one reciter leaves the others', () async {
      put(timed, '001.mp3', 100);
      put(timed, 'timings_r2/001.json', 20);
      put(perAyah, '001001.mp3', 100);
      final before = svc.storageRevision.value;

      await svc.deleteReciter(perAyah);
      expect(namesIn(perAyah), isEmpty);
      expect(namesIn(timed), {'001.mp3', 'timings_r2/001.json'});
      expect(svc.storageRevision.value, greaterThan(before));

      // the selected one: its timings go too
      await svc.deleteReciter(timed);
      expect(namesIn(timed), isEmpty);
      expect(await svc.reciterStorage(), isEmpty);
    });

    test('delete all', () async {
      put(timed, '001.mp3', 100);
      put(perAyah, '001001.mp3', 100);
      put(Reciter.zarrouqQaloun, '114.mp3.seg', 5);
      await svc.deleteAllRecitations();
      expect(await svc.reciterStorage(), isEmpty);
      expect(namesIn(timed), isEmpty);
      expect(namesIn(perAyah), isEmpty);
    });

    test('one timed surah: every recording of it and what the stream cache '
        'kept; its timings and other surahs stay', () async {
      put(timed, '040.mp3', 100);
      put(timed, '040_v2.mp3', 100);
      put(timed, '040_v2.mp3.seg.json.tmp', 3);
      put(timed, '040.mp3.seg', 10);
      put(timed, '039.mp3', 100);
      put(timed, '140.mp3', 1); // not a surah: left alone
      put(timed, 'timings_r2/040_v2.json', 20);

      final statuses = await svc.computeSurahStatuses();
      expect(statuses[39].bytes, 213);
      expect(statuses[39].isComplete, isTrue);
      expect(statuses[38].bytes, 100);
      expect(statuses[0].hasFiles, isFalse);

      await svc.deleteSurah(40);
      expect(namesIn(timed), {'039.mp3', '140.mp3', 'timings_r2/040_v2.json'});
      final after = await svc.computeSurahStatuses();
      expect(after[39].hasFiles, isFalse);
      expect(after[39].isComplete, isFalse);
    });

    test('one per-ayah surah: its ayah files, an interrupted download too',
        () async {
      ReciterService.instance.selected.value = perAyah;
      try {
        put(perAyah, '002001.mp3', 100);
        put(perAyah, '002285.mp3', 100);
        put(perAyah, '002286.mp3.part', 30);
        put(perAyah, '003001.mp3', 100);
        final statuses = await svc.computeSurahStatuses();
        expect(statuses[1].bytes, 230);
        expect(statuses[1].isPartial, isTrue);

        await svc.deleteSurah(2);
        expect(namesIn(perAyah), {'003001.mp3'});
      } finally {
        ReciterService.instance.selected.value = timed;
      }
    });

    test('downloading a partly heard timed surah drops what the stream cache '
        'kept of it', () async {
      put(timed, '001.mp3.seg', 50);
      put(timed, '001.mp3.seg.json', 10);
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url == '${timed.timingsBaseUrl}001.json') {
          return http.Response(
            jsonEncode({
              'surah': 1,
              'file': '001.mp3',
              'duration_ms': 1000,
              'ayat': {
                '1': [0, 1000],
              },
            }),
            200,
          );
        }
        if (url == '${timed.audioBaseUrl}001.mp3') {
          return http.Response.bytes(List.filled(100, 1), 200);
        }
        return http.Response('', 404);
      });
      await http.runWithClient(() => svc.downloadSurah(1), () => client);
      expect(namesIn(timed).where((n) => !n.startsWith('timings')), {
        '001.mp3',
      });
    });
  });
}

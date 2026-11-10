import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:islamic_dawah_mushaf/models/quran_page_data.dart';
import 'package:islamic_dawah_mushaf/services/app_update_service.dart';
import 'package:islamic_dawah_mushaf/services/content_update_service.dart';
import 'package:islamic_dawah_mushaf/services/memorization_test_service.dart';
import 'package:islamic_dawah_mushaf/services/page_phoneme_service.dart';
import 'package:islamic_dawah_mushaf/services/quran_json_service.dart';
import 'package:islamic_dawah_mushaf/services/quran_text_patch.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every ayah of the bundled text, in page order.
List<QuranAyahData> ayahsOf(List<QuranPageData> pages) => [
  for (final p in pages) ...p.ayahs,
];

void main() {
  final asset = File('assets/data/output.json').readAsStringSync();
  final bundled = QuranJsonService.parsePages((asset, null));
  QuranAyahData ayah(int s, int a) =>
      ayahsOf(bundled).firstWhere((x) => x.surah == s && x.ayah == a);

  // A spelling change to one word of 20:62 («هَٰذَٰنِ» gets a plain alef),
  // written against the bundled text.
  final was2062 = ayah(20, 62).text;
  final fixed2062 = was2062.replaceFirst('هَٰذَٰنِ', 'هَاذَٰنِ');
  String patchOf(List<Map<String, Object>> patches, {int ver = 1}) =>
      json.encode({'ver': ver, 'patches': patches});
  Map<String, Object> fix(int s, int a, String text, List<String> from) => {
    'surah': s,
    'ayah': a,
    'text': text,
    'from': from,
  };

  group('the bundled text', () {
    test('every ayah satisfies the patch rules', () {
      // Otherwise a real ayah could never be a valid "from".
      final bad = [
        for (final a in ayahsOf(bundled))
          if (!QuranTextPatch.wellFormed(a.text)) '${a.surah}:${a.ayah}',
      ];
      expect(bad, isEmpty);
      expect(ayahsOf(bundled).length, 6214);
    });

    test('the basmala rule agrees with Tasmee over every ayah', () {
      for (final a in ayahsOf(bundled)) {
        final words = a.text.split(RegExp(r'\s+'));
        expect(
          QuranTextPatch.opensWithBasmala(a.text),
          MemorizationTestService.embeddedBasmalaLength(words, 0) > 0,
          reason: '${a.surah}:${a.ayah}',
        );
      }
    });

    test('the test fix really changes 20:62', () {
      expect(fixed2062, isNot(was2062));
      expect(
        QuranTextPatch.wordCount(fixed2062),
        QuranTextPatch.wordCount(was2062),
      );
    });
  });

  group('parse refuses the whole file', () {
    void refused(String why, Map<String, Object> entry) {
      final good = fix(20, 62, fixed2062, [was2062]);
      expect(
        () => QuranTextPatch.parse(patchOf([good, entry])),
        throwsFormatException,
        reason: why,
      );
    }

    test('a good file is read', () {
      final fixes = QuranTextPatch.parse(
        patchOf([
          fix(20, 62, fixed2062, [was2062]),
        ]),
      );
      expect(fixes.single.surah, 20);
      expect(fixes.single.from, [was2062]);
    });

    test('for any broken entry', () {
      final t = ayah(26, 49).text;
      final words = t.split(' ');
      refused('a word more', fix(26, 49, '$t كلمة', [t]));
      refused('a word less', fix(26, 49, words.sublist(1).join(' '), [t]));
      refused('two words joined', fix(26, 49, t.replaceFirst(' ', ''), [t]));
      refused('Eastern digit', fix(26, 49, t.replaceFirst('أ', '\u0663'), [t]));
      refused('Western digit', fix(26, 49, t.replaceFirst('أ', '3'), [t]));
      refused('ayah-end sign', fix(26, 49, t.replaceFirst('أ', '\u06DD'), [t]));
      refused('RLM', fix(26, 49, t.replaceFirst('أ', 'أ\u200F'), [t]));
      refused('double space', fix(26, 49, t.replaceFirst(' ', '  '), [t]));
      refused('trailing space', fix(26, 49, '$t ', [t]));
      refused('newline', fix(26, 49, t.replaceFirst(' ', '\n'), [t]));
      refused('no from', fix(26, 49, '$tا', []));
      refused('from equals text', fix(26, 49, t, [t]));
      refused('bad surah', fix(115, 1, t, ['$tا']));
      refused('bad ayah', fix(26, 0, t, ['$tا']));
      refused('listed twice', fix(20, 62, fixed2062, [was2062]));
      final b = ayah(95, 1).text; // opens with the basmala in this mushaf
      expect(QuranTextPatch.opensWithBasmala(b), isTrue);
      refused(
        'basmala removed',
        fix(95, 1, b.replaceFirst('بِسْمِ', 'بِسْمِي'), [b]),
      );
    });

    test('for a wrong shape', () {
      expect(() => QuranTextPatch.parse('[]'), throwsFormatException);
      expect(
        () => QuranTextPatch.parse('{"patches":[]}'),
        throwsFormatException,
      );
      expect(() => QuranTextPatch.parse('{"ver":1}'), throwsFormatException);
      expect(() => QuranTextPatch.parse('not json'), throwsFormatException);
      final many = [
        for (var i = 1; i <= QuranTextPatch.maxEntries + 1; i++)
          fix(2, (i % 286) + 1, 'ب', ['ا']),
      ];
      expect(() => QuranTextPatch.parse(patchOf(many)), throwsFormatException);
    });
  });

  group('parsePages', () {
    test('lays a fix over exactly one ayah and nothing else', () {
      final patched = QuranJsonService.parsePages((
        asset,
        patchOf([
          fix(20, 62, fixed2062, [was2062]),
        ]),
      ));
      expect(patched.length, bundled.length);
      final a = ayahsOf(patched), b = ayahsOf(bundled);
      expect(a.length, b.length);
      var changed = 0;
      for (var i = 0; i < a.length; i++) {
        expect((a[i].surah, a[i].ayah), (b[i].surah, b[i].ayah));
        expect(a[i].surahName, b[i].surahName);
        if (a[i].text != b[i].text) {
          changed++;
          expect((a[i].surah, a[i].ayah), (20, 62));
          expect(a[i].text, fixed2062);
        }
      }
      expect(changed, 1);
      for (var p = 0; p < patched.length; p++) {
        expect(patched[p].page, bundled[p].page);
      }
    });

    test('a text it was not written for is left as bundled', () {
      final patched = QuranJsonService.parsePages((
        asset,
        patchOf([
          fix(20, 62, fixed2062, ['${was2062.substring(1)}ق']),
        ]),
      ));
      expect(
        ayahsOf(patched).firstWhere((x) => x.surah == 20 && x.ayah == 62).text,
        was2062,
      );
    });

    test('a bad patch, or none, gives the bundled text', () {
      for (final patch in [
        null,
        'garbage',
        '{"ver":1,"patches":[{"surah":20}]}',
        // One good entry next to a bad one: refused as a whole.
        patchOf([
          fix(20, 62, fixed2062, [was2062]),
          fix(26, 49, '${ayah(26, 49).text} زيادة', [ayah(26, 49).text]),
        ]),
      ]) {
        final got = ayahsOf(QuranJsonService.parsePages((asset, patch)));
        final want = ayahsOf(bundled);
        for (var i = 0; i < got.length; i++) {
          expect(got[i].text, want[i].text);
        }
      }
    });

    test('apply counts applied, already and skipped', () {
      List<dynamic> pages() =>
          (json.decode(asset) as List<dynamic>).expand((p) {
            return p is List ? p : [p];
          }).toList();
      final fixes = QuranTextPatch.parse(
        patchOf([
          fix(20, 62, fixed2062, [was2062]),
          fix(26, 49, ayah(26, 49).text, ['${ayah(26, 49).text}ا']),
          fix(1, 2, '${ayah(1, 2).text}ا', ['${ayah(1, 2).text}ب']),
          fix(114, 200, 'ا', ['ب']),
        ]),
      );
      final stats = QuranTextPatch.apply(pages(), fixes);
      expect(stats.applied, 1);
      expect(stats.already, 1);
      expect(stats.skipped, 2);
    });
  });

  group('download', () {
    late Directory dir;
    final service = ContentUpdateService.instance;
    final next = ContentUpdateService.bundledVersions['quran_text']! + 1;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('quran_text_');
      service.debugReset(dir: dir);
      AppUpdateService.instance.currentBuild = 0;
    });

    tearDown(() async {
      service.debugReset();
      await dir.delete(recursive: true);
    });

    Future<ContentCheckResult> offer(String body, {int? ver}) {
      final v = ver ?? next;
      final bytes = utf8.encode(body);
      final manifest = json.encode({
        'v': 1,
        'items': {
          'quran_text': {
            'ver': v,
            'url': 'data/quran_text/patch_v$v.json',
            'sha256': sha256.convert(bytes).toString(),
            'bytes': bytes.length,
          },
        },
      });
      return service.check(
        manual: true,
        client: MockClient((r) async {
          if (r.url.path == '/data/manifest.json') {
            return http.Response(manifest, 200);
          }
          if (r.url.path == '/data/quran_text/patch_v$v.json') {
            return http.Response.bytes(bytes, 200);
          }
          return http.Response('not found', 404);
        }),
      );
    }

    test('a good patch is installed and shows at the next launch', () async {
      service.registerItem('quran_text', isLoaded: () => true);
      final body = patchOf([
        fix(20, 62, fixed2062, [was2062]),
      ], ver: next);
      final result = await offer(body);
      expect(result.updated, ['quran_text']);
      expect(result.pendingRestart, ['quran_text']);
      expect(result.message, contains('نص المصحف'));
      expect(service.versionOf('quran_text'), next);
      expect(await service.readFor('quran_text'), body);
      expect(
        File('${dir.path}/quran_text_patch_v$next.json').existsSync(),
        isTrue,
      );
    });

    test('end to end: downloaded, then read by the next launch', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      QuranJsonService.debugReset();
      service.registerItem('quran_text', isLoaded: () => true);
      final result = await offer(
        patchOf([
          fix(20, 62, fixed2062, [was2062]),
        ], ver: next),
      );
      expect(result.updated, ['quran_text']);
      QuranJsonService.debugReset(); // the next launch
      final pages = await QuranJsonService.loadQuranPages();
      QuranJsonService.debugReset(); // later tests get the bundled text
      final page = pages.firstWhere(
        (p) => p.ayahs.any((a) => a.surah == 20 && a.ayah == 62),
      );
      expect(page.ayahs.firstWhere((a) => a.ayah == 62).text, fixed2062);
      // Tasmee refuses a page whose words and phonemes differ in number.
      final phonemes = PagePhonemeService.parse(
        File('assets/data/page_phonemes.json').readAsStringSync(),
      )[page.page]!;
      final words = [
        for (final a in page.ayahs)
          ...a.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty),
      ];
      expect(words.length, phonemes.words.length);
    });

    test('a patch the loader would refuse is never installed', () async {
      final t = ayah(26, 49).text;
      final result = await offer(
        patchOf([
          fix(26, 49, '$t زيادة', [t]),
        ], ver: next),
      );
      expect(result.updated, isEmpty);
      expect(
        service.versionOf('quran_text'),
        ContentUpdateService.bundledVersions['quran_text'],
      );
      expect(await service.readFor('quran_text'), isNull);
    });

    test('a version the build already bundles is not fetched', () async {
      final bundledVer = ContentUpdateService.bundledVersions['quran_text']!;
      if (bundledVer == 0) {
        // ver 0 is never a valid manifest entry: nothing to fetch either way.
        final result = await offer(patchOf(const [], ver: 0), ver: 0);
        expect(result.updated, isEmpty);
        return;
      }
      final result = await offer(patchOf(const [], ver: bundledVer));
      expect(result.updated, isEmpty);
    });
  });
}

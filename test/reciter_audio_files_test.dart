import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/services/audio_download_service.dart';
import 'package:islamic_dawah_mushaf/services/reciter_service.dart';

/// Guards the per-reciter audio file lists, which decide both what gets
/// downloaded for offline listening and what playback asks the CDN for. Every
/// expectation here was checked against the live bucket with a HEAD sweep.
void main() {
  final downloads = AudioDownloadService.instance;

  void select(Reciter r) => ReciterService.instance.selected.value = r;

  tearDown(() => select(Reciter.fallback));

  group('al-Hudaifi (covered scheme)', () {
    setUp(() => select(Reciter.hudaifiQaloun));

    test('one file per displayed ayah, minus the silent placeholders', () {
      final coveredCount = Reciter.hudaifiCoveredAyat.values
          .fold<int>(0, (sum, ayat) => sum + ayat.length);
      expect(coveredCount, 24);
      expect(downloads.getAllFilenames().length, 6214 - coveredCount);
    });

    test('no basmala file — the bucket has no SSS000.mp3', () {
      for (int s = 1; s <= 114; s++) {
        final stem = '${s.toString().padLeft(3, '0')}000.mp3';
        expect(downloads.getSurahFilenames(s), isNot(contains(stem)));
      }
    });

    test('surah files run 1..madani count with covered ayat left out', () {
      // Al-Kahf: 24, 35 and 87 are recited inside a neighbouring ayah.
      final kahf = downloads.getSurahFilenames(18);
      expect(kahf, contains('018023.mp3'));
      expect(kahf, isNot(contains('018024.mp3')));
      expect(kahf, isNot(contains('018035.mp3')));
      expect(kahf, isNot(contains('018087.mp3')));
      expect(kahf.length, Reciter.madaniAyahCounts[17] - 3);

      // No merged tail: al-Baqarah ends at its displayed last ayah, 285.
      final baqarah = downloads.getSurahFilenames(2);
      expect(baqarah.last, '002285.mp3');
    });
  });

  group('الدوكالي محمد العالم (covered scheme)', () {
    setUp(() => select(Reciter.doukaliQaloun));

    test('one file per displayed ayah, minus the silent placeholders', () {
      final coveredCount = Reciter.doukaliQaloun.coveredAyat.values
          .fold<int>(0, (sum, ayat) => sum + ayat.length);
      expect(coveredCount, 1194);
      expect(downloads.getAllFilenames().length, 6214 - coveredCount);
    });

    test('no basmala file — the bucket has no SSS000.mp3', () {
      for (int s = 1; s <= 114; s++) {
        final stem = '${s.toString().padLeft(3, '0')}000.mp3';
        expect(downloads.getSurahFilenames(s), isNot(contains(stem)));
      }
    });

    test('surah files run 1..madani count with covered ayat left out', () {
      // Al-Fatihah: 2, 3, 6 and 7 are recited inside a neighbouring ayah.
      final fatihah = downloads.getSurahFilenames(1);
      expect(fatihah, ['001001.mp3', '001004.mp3', '001005.mp3']);

      // No merged tail: al-Baqarah ends at its displayed last ayah, 285.
      final baqarah = downloads.getSurahFilenames(2);
      expect(baqarah.last, '002285.mp3');

      // Ash-Shu'ara has his densest joining: 72 of its 227 ayat are covered.
      expect(downloads.getSurahFilenames(26).length, 227 - 72);
    });

    test('unlike al-Naihi, his khatma includes Yusuf 111', () {
      expect(downloads.getSurahFilenames(12), contains('012111.mp3'));
    });
  });

  group('أبوسنينة (native scheme + breath combining)', () {
    setUp(() => select(Reciter.abusenainahQaloun));

    test('basmala file per surah except At-Tawba, native Madani counts', () {
      expect(downloads.getSurahFilenames(2), contains('002000.mp3'));
      expect(downloads.getSurahFilenames(9), isNot(contains('009000.mp3')));
      expect(
        downloads.getSurahFilenames(2).length,
        Reciter.madaniAyahCounts[1] + 1,
      );
    });

    test('the 7 unpublished ayat are left out of the download list', () {
      // Al-Kahf: the mirror stops at 099, so 100..105 have no file at all.
      final kahf = downloads.getSurahFilenames(18);
      expect(kahf, contains('018099.mp3'));
      for (int a = 100; a <= 105; a++) {
        expect(kahf, isNot(contains('018${a.toString().padLeft(3, '0')}.mp3')));
      }
      expect(kahf.length, Reciter.madaniAyahCounts[17] - 6 + 1); // +1 basmala

      // Al-Mutaffifin: stops at 035.
      final mutaffifin = downloads.getSurahFilenames(83);
      expect(mutaffifin, contains('083035.mp3'));
      expect(mutaffifin, isNot(contains('083036.mp3')));
    });

    test('a complete download is the 6320 files that actually exist', () {
      // 6214 ayat + 113 basmalas - 7 upstream gaps. Matches the file count the
      // R2 mirror was verified to hold.
      expect(downloads.getAllFilenames().length, 6214 + 113 - 7);
    });

    test('surah 37 is addressed in normal app numbering', () {
      // The source folder is shifted by one; the mirror renumbers it on upload,
      // so the app must ask for 037000 (basmala) .. 037181 and never 037182.
      final saffat = downloads.getSurahFilenames(37);
      expect(saffat.first, '037000.mp3');
      expect(saffat.last, '037181.mp3');
      expect(saffat.length, Reciter.madaniAyahCounts[36] + 1);
    });
  });

  group('existing reciters are untouched by the scheme refactor', () {
    test('Al-Husary keeps the merged-tail names', () {
      select(Reciter.husaryQaloun);
      final maidah = downloads.getSurahFilenames(5);
      expect(maidah.last, '005120.mp3'); // 121+122 merge onto 120
      expect(downloads.getSurahFilenames(1).length, 7);
    });

    test('al-Naihi keeps the basmala file and native counts', () {
      select(Reciter.naihiQaloun);
      expect(downloads.getSurahFilenames(2), contains('002000.mp3'));
      expect(downloads.getSurahFilenames(9), isNot(contains('009000.mp3')));
      expect(
        downloads.getSurahFilenames(2).length,
        Reciter.madaniAyahCounts[1] + 1,
      );
    });

    test('al-Naihi no longer counts the Yusuf ayah his source lacks', () {
      // 012111.mp3 404s on the source and both mirrors, so including it kept
      // "التحميل مكتمل" permanently out of reach.
      select(Reciter.naihiQaloun);
      final yusuf = downloads.getSurahFilenames(12);
      expect(yusuf, isNot(contains('012111.mp3')));
      expect(yusuf, contains('012110.mp3'));
      expect(downloads.getAllFilenames().length, 6214 + 113 - 1);
    });

    test('قنيوه still lists every file, gaps being none of his', () {
      select(Reciter.qaniwahQaloun);
      // Breath continuations are real files in the bucket (byte-identical
      // duplicates), so they stay in the download list.
      expect(downloads.getAllFilenames().length, 6214 + 113);
      expect(downloads.getSurahFilenames(12), contains('012111.mp3'));
    });
  });

  test('every breath-combining reciter has his own continuations asset', () {
    // The breath groups describe how one sheikh recites — sharing a table
    // between two reciters would silently skip the wrong ayat.
    final assets = <String>[];
    for (final r in Reciter.allDefined) {
      if (r.breathCombining) {
        expect(r.continuationsAsset, isNotNull, reason: r.id);
        assets.add(r.continuationsAsset!);
      } else {
        expect(r.continuationsAsset, isNull, reason: r.id);
      }
    }
    expect(assets.toSet().length, assets.length);
  });

  test('every reciter has a distinct id and cache folder', () {
    expect(Reciter.all.map((r) => r.id).toSet().length, Reciter.all.length);
    expect(
      Reciter.all.map((r) => r.cacheFolder).toSet().length,
      Reciter.all.length,
    );
  });

  test('shortName falls back to name and stays short enough to fit', () {
    expect(Reciter.husaryQaloun.shortName, Reciter.husaryQaloun.name);
    expect(Reciter.hudaifiQaloun.shortName, 'علي الحذيفي');
    for (final r in Reciter.all) {
      expect(r.shortName.length, lessThanOrEqualTo(18), reason: r.id);
    }
  });
}

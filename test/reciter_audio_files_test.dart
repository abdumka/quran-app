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

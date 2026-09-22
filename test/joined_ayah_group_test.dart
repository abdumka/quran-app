import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/quran_page_data.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/services/quran_json_service.dart';
import 'package:islamic_dawah_mushaf/utils/joined_ayah_group.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/playing_ayah_highlight.dart';

QuranAyahData _a(int surah, int ayah) =>
    QuranAyahData(surah: surah, surahName: '', ayah: ayah, text: '');

List<(int, int)> _keys(List<QuranAyahData> g) => [
      for (final x in g) (x.surah, x.ayah),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('joinedAyahGroup', () {
    // A surah of 7 ayat where 2, 3, 6 and 7 are joined to the one before.
    bool joined(QuranAyahData x) => const {2, 3, 6, 7}.contains(x.ayah);
    Iterable<QuranAyahData> after(int ayah, {int surah = 1, int last = 7}) => [
          for (var n = ayah + 1; n <= last; n++) _a(surah, n),
        ];

    test('the head takes the joined ayat after it, and stops there', () {
      expect(_keys(joinedAyahGroup(_a(1, 1), after(1), joined)),
          [(1, 1), (1, 2), (1, 3)]);
      expect(_keys(joinedAyahGroup(_a(1, 4), after(4), joined)), [(1, 4)]);
      expect(_keys(joinedAyahGroup(_a(1, 5), after(5), joined)),
          [(1, 5), (1, 6), (1, 7)]);
    });

    test('a reciter who joins nothing gets just the ayah', () {
      expect(_keys(joinedAyahGroup(_a(1, 1), after(1), (_) => false)),
          [(1, 1)]);
    });

    test('never runs into the next surah', () {
      final following = [_a(1, 7), _a(2, 1), _a(2, 2)];
      expect(_keys(joinedAyahGroup(_a(1, 6), following, (_) => true)),
          [(1, 6), (1, 7)]);
    });

    test('an ayah printed on two pages is counted once', () {
      // ... 2 | page turn | 2 (again), 3, 4
      final following = [_a(1, 2), _a(1, 2), _a(1, 3), _a(1, 4)];
      expect(_keys(joinedAyahGroup(_a(1, 1), following, joined)),
          [(1, 1), (1, 2), (1, 3)]);
    });

    test('a gap in the numbering ends the group', () {
      final following = [_a(1, 2), _a(1, 4)];
      expect(_keys(joinedAyahGroup(_a(1, 1), following, (_) => true)),
          [(1, 1), (1, 2)]);
    });

    test('is capped', () {
      final g = joinedAyahGroup(
        _a(2, 1),
        [for (var n = 2; n <= 200; n++) _a(2, n)],
        (_) => true,
        maxLength: 10,
      );
      expect(g.length, 10);
    });
  });

  group('highlightedAyat', () {
    test('the whole group while its head plays', () {
      expect(highlightedAyat(1, 1, [(1, 1), (1, 2), (1, 3)]),
          {(1, 1), (1, 2), (1, 3)});
    });

    test('a group that does not hold the playing ayah is ignored', () {
      // The group is refreshed a moment after the ayah changes, and the
      // al-Husary 23:45 -> 46 split moves the ayah inside one file.
      expect(highlightedAyat(1, 4, [(1, 1), (1, 2), (1, 3)]), {(1, 4)});
      expect(highlightedAyat(23, 46, [(23, 45)]), {(23, 46)});
      expect(highlightedAyat(2, 5, const []), {(2, 5)});
    });
  });

  group('real data', () {
    late List<QuranAyahData> all; // every ayah once, in reading order

    setUpAll(() async {
      final pages = await QuranJsonService.loadQuranPages();
      final sorted = [...pages]..sort((x, y) => x.page.compareTo(y.page));
      all = [];
      for (final p in sorted) {
        for (final a in p.ayahs) {
          if (all.isNotEmpty &&
              all.last.surah == a.surah &&
              all.last.ayah == a.ayah) {
            continue;
          }
          all.add(a);
        }
      }
    });

    /// Walks the whole Quran the way playback does: a group per ayah that
    /// has audio. Returns how many groups hold more than one ayah.
    int check(Reciter reciter) {
      bool joined(QuranAyahData x) =>
          !reciter.isMissing(x.surah, x.ayah) &&
          (reciter.coveredAyat[x.surah]?.contains(x.ayah) ?? false);
      final seen = <(int, int)>{};
      var multi = 0;
      for (var i = 0; i < all.length; i++) {
        if (joined(all[i])) continue; // no audio of its own: never a head
        final g = joinedAyahGroup(all[i], all.skip(i + 1), joined);
        expect(g.every((x) => x.surah == all[i].surah), isTrue);
        for (final x in g) {
          expect(seen.add((x.surah, x.ayah)), isTrue,
              reason: '${x.surah}:${x.ayah} is in two groups');
        }
        if (g.length > 1) multi++;
      }
      // Every joined ayah was reached from a head before it.
      for (final e in reciter.coveredAyat.entries) {
        for (final a in e.value) {
          expect(seen.contains((e.key, a)), isTrue,
              reason: '${reciter.id}: ${e.key}:$a has no group');
        }
      }
      return multi;
    }

    test('Doukali: al-Fatiha is read as 1-3, 4, 5-7', () {
      const r = Reciter.doukaliQaloun;
      bool joined(QuranAyahData x) =>
          r.coveredAyat[x.surah]?.contains(x.ayah) ?? false;
      final fatiha = all.where((x) => x.surah == 1).toList();
      List<(int, int)> groupAt(int ayah) => _keys(
            joinedAyahGroup(fatiha[ayah - 1], fatiha.skip(ayah), joined),
          );
      expect(groupAt(1), [(1, 1), (1, 2), (1, 3)]);
      expect(groupAt(4), [(1, 4)]);
      expect(groupAt(5), [(1, 5), (1, 6), (1, 7)]);
    });

    test('Doukali: every joined ayah belongs to exactly one group', () {
      expect(check(Reciter.doukaliQaloun), greaterThan(500));
    });

    test('al-Hudaifi: every joined ayah belongs to exactly one group', () {
      expect(check(Reciter.hudaifiQaloun), inInclusiveRange(1, 24));
    });
  });
}

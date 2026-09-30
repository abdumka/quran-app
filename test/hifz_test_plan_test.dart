import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/hifz_test_plan.dart';
import 'package:islamic_dawah_mushaf/services/quran_json_service.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_weak_point_store.dart';
import 'package:islamic_dawah_mushaf/thumn_data.dart';

TasmeeWeakPoint _point(int surah, int ayah, int word, {int count = 1, DateTime? at}) =>
    TasmeeWeakPoint(
      surah: surah,
      ayah: ayah,
      word: word,
      page: 0,
      expected: 'w',
      kind: 'word',
      count: count,
      lastAt: at ?? DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranAyahIndex index;

  setUpAll(() async {
    index = QuranAyahIndex.fromPages(await QuranJsonService.loadQuranPages());
  });

  group('QuranAyahIndex', () {
    test('lists every ayah of the mushaf once, in reading order', () {
      expect(index.length, 6214);
      expect(index.ayahs.first.key, '1:1');
      expect(index.ayahs.last.surah, 114);
      expect(index.indexOf(1, 1), 0);
      expect(index.indexOf(2, 1), 7);
      expect(index.indexOf(999, 1), isNull);
      for (var i = 1; i < index.length; i++) {
        final a = index.ayahs[i - 1];
        final b = index.ayahs[i];
        expect(
          b.surah > a.surah || (b.surah == a.surah && b.ayah == a.ayah + 1),
          isTrue,
          reason: '${a.key} -> ${b.key}',
        );
      }
    });

    test('spans: the whole mushaf, surahs, pages, hizbs', () {
      expect(index.spanOf(const HifzRange.all()), (0, 6213));

      final s1 = index.spanOf(const HifzRange(HifzRangeKind.surahs, from: 1, to: 1))!;
      expect(s1, (0, 6));
      final s2to3 = index.spanOf(const HifzRange(HifzRangeKind.surahs, from: 2, to: 3))!;
      expect(index.ayahs[s2to3.$1].key, '2:1');
      expect(index.ayahs[s2to3.$2].surah, 3);
      expect(index.ayahs[s2to3.$2 + 1].surah, 4);

      final p = index.spanOf(const HifzRange(HifzRangeKind.pages, from: 1, to: 2))!;
      expect(index.ayahs[p.$1].page, 1);
      expect(index.ayahs[p.$2].page, 2);
      expect(index.ayahs[p.$2 + 1].page, 3);

      // Hizb 1 runs from 1:1 up to the ayah before hizb 2's first thumn.
      final h1 = index.spanOf(const HifzRange(HifzRangeKind.hizbs, from: 1, to: 1))!;
      expect(h1.$1, 0);
      final hizb2 = thumnEntries.firstWhere((t) => t.hizb == 2);
      expect(h1.$2, index.indexOf(hizb2.startSurah, hizb2.startAyah)! - 1);
      // The last hizb reaches the end of the mushaf.
      final h60 = index.spanOf(const HifzRange(HifzRangeKind.hizbs, from: 60, to: 60))!;
      expect(h60.$2, 6213);
      // Reversed bounds are put in order.
      expect(
        index.spanOf(const HifzRange(HifzRangeKind.hizbs, from: 3, to: 1)),
        index.spanOf(const HifzRange(HifzRangeKind.hizbs, from: 1, to: 3)),
      );
    });

    test('range labels and json round trip', () {
      expect(const HifzRange.all().label, 'المصحف كله');
      expect(const HifzRange(HifzRangeKind.surahs, from: 2, to: 2).label, 'سورة البقرة');
      expect(const HifzRange(HifzRangeKind.pages, from: 5, to: 9).label, 'الصفحات 5 إلى 9');
      const c = HifzTestConfig(
        source: HifzTestSource.both,
        range: HifzRange(HifzRangeKind.hizbs, from: 4, to: 6),
        questions: 10,
        ayahsPerQuestion: 5,
      );
      final back = HifzTestConfig.fromJson(c.toJson());
      expect(back.source, HifzTestSource.both);
      expect(back.range.kind, HifzRangeKind.hizbs);
      expect(back.range.from, 4);
      expect(back.range.to, 6);
      expect(back.questions, 10);
      expect(back.ayahsPerQuestion, 5);
    });
  });

  group('HifzTestPlanner', () {
    test('random questions stay inside the range and their surah', () {
      const config = HifzTestConfig(
        source: HifzTestSource.random,
        range: HifzRange(HifzRangeKind.surahs, from: 2, to: 3),
        questions: 10,
        ayahsPerQuestion: 3,
      );
      final qs = HifzTestPlanner.plan(
        index: index,
        config: config,
        pool: const [],
        random: Random(7),
      );
      expect(qs.length, 10);
      expect(qs.map((q) => q.start.key).toSet().length, 10, reason: 'no repeated start');
      for (final q in qs) {
        expect(q.start.surah, anyOf(2, 3));
        expect(q.end.surah, q.start.surah);
        expect(q.ayahCount, inInclusiveRange(1, 3));
        expect(q.end.ayah - q.start.ayah + 1, q.ayahCount);
        expect(q.fromMistakes, isFalse);
        if (q.start.ayah == 1) {
          expect(q.before, isNull);
          expect(q.cue, contains('من أولها'));
          expect(q.cue, isNot(contains('بعد قوله')));
        } else {
          expect(q.before!.ayah, q.start.ayah - 1);
          expect(q.cue, contains('بعد قوله تعالى'));
        }
      }
    });

    test('a short surah cannot give more distinct questions than ayahs', () {
      const config = HifzTestConfig(
        source: HifzTestSource.random,
        range: HifzRange(HifzRangeKind.surahs, from: 112, to: 112),
        questions: 10,
        ayahsPerQuestion: 1,
      );
      final qs = HifzTestPlanner.plan(index: index, config: config, pool: const []);
      expect(qs.length, 4);
    });

    test('questions from mistakes end at the missed ayah, most-missed first', () {
      final pool = [
        _point(2, 30, 3, count: 1, at: DateTime(2026, 2, 1)),
        _point(2, 5, 2, count: 3),
        _point(2, 5, 4, count: 1),
        _point(50, 3, 1, count: 9), // outside the range: ignored
      ];
      const config = HifzTestConfig(
        source: HifzTestSource.mistakes,
        range: HifzRange(HifzRangeKind.surahs, from: 2, to: 2),
        questions: 5,
        ayahsPerQuestion: 3,
      );
      final qs = HifzTestPlanner.plan(index: index, config: config, pool: pool);
      expect(qs.length, 2, reason: 'one question per missed ayah in range');
      expect(qs[0].end.key, '2:5');
      expect(qs[0].start.key, '2:3', reason: 'runs up two ayahs before the target');
      expect(qs[0].targets.map((t) => t.word), [2, 4]);
      expect(qs[0].fromMistakes, isTrue);
      expect(qs[1].end.key, '2:30');
      expect(qs[1].start.key, '2:28');
      expect(qs[1].targets.single.word, 3);
    });

    test('a run-up never crosses into the previous surah', () {
      final pool = [_point(3, 1, 1)];
      const config = HifzTestConfig(
        source: HifzTestSource.mistakes,
        range: HifzRange.all(),
        questions: 1,
        ayahsPerQuestion: 3,
      );
      final q = HifzTestPlanner.plan(index: index, config: config, pool: pool).single;
      expect(q.start.key, '3:1');
      expect(q.end.key, '3:1');
      expect(q.before, isNull);
    });

    test('mistakes only, with none in the range, gives no questions', () {
      const config = HifzTestConfig(
        source: HifzTestSource.mistakes,
        range: HifzRange(HifzRangeKind.surahs, from: 2, to: 2),
        questions: 5,
      );
      expect(
        HifzTestPlanner.plan(index: index, config: config, pool: [_point(3, 1, 1)]),
        isEmpty,
      );
    });

    test('both: about half from mistakes, the rest random, no start twice', () {
      final pool = [for (var a = 10; a < 20; a++) _point(2, a, 1)];
      const config = HifzTestConfig(
        source: HifzTestSource.both,
        range: HifzRange(HifzRangeKind.surahs, from: 2, to: 2),
        questions: 6,
      );
      final qs = HifzTestPlanner.plan(
        index: index,
        config: config,
        pool: pool,
        random: Random(3),
      );
      expect(qs.length, 6);
      expect(qs.where((q) => q.fromMistakes).length, 3);
      expect(qs.map((q) => q.start.key).toSet().length, 6);
    });

    test('both falls back to random when few mistakes exist', () {
      const config = HifzTestConfig(
        source: HifzTestSource.both,
        range: HifzRange(HifzRangeKind.surahs, from: 2, to: 2),
        questions: 5,
      );
      final qs = HifzTestPlanner.plan(index: index, config: config, pool: [_point(2, 7, 1)]);
      expect(qs.length, 5);
      expect(qs.where((q) => q.fromMistakes).length, 1);
    });

    test('a question becomes a drill that starts where the planner said', () {
      final pool = [_point(2, 5, 2)];
      const config = HifzTestConfig(
        source: HifzTestSource.mistakes,
        range: HifzRange.all(),
        questions: 1,
        ayahsPerQuestion: 3,
      );
      final q = HifzTestPlanner.plan(index: index, config: config, pool: pool).single;
      final d = q.toDrill(2, 5);
      expect(d.page, q.end.page);
      expect(d.surah, 2);
      expect(d.ayah, 5);
      expect(d.startPage, q.start.page);
      expect(d.startAyahIndex, q.start.indexOnPage);
      expect(d.label, 'اختبار 2 / 5');
      expect(d.cue, q.cue);
      expect(d.targets.single.key, '2:5:2');
    });

    test('the cue quotes only the end of a long ayah', () {
      // 2:282 (the debt ayah) is long; the question starting at 2:283 quotes its tail.
      final s = index.indexOf(2, 283)!;
      const config = HifzTestConfig(
        source: HifzTestSource.mistakes,
        range: HifzRange.all(),
        questions: 1,
        ayahsPerQuestion: 1,
      );
      final q = HifzTestPlanner.plan(
        index: index,
        config: config,
        pool: [_point(2, 283, 1)],
      ).single;
      expect(q.start.key, index.ayahs[s].key);
      expect(q.cueTail, startsWith('… '));
      final quoted = q.cueTail.substring(2).split(' ');
      expect(quoted.length, HifzTestQuestion.cueWords);
      expect(q.before!.text.trim(), endsWith(quoted.join(' ')));
    });
  });

  group('TasmeeWeakPointStore.applyPass', () {
    test('two passes on different days retire a point; the same day counts once', () {
      final pool = [_point(2, 5, 2), _point(2, 5, 4)];
      final day1 = DateTime(2026, 9, 30, 10);
      var next = TasmeeWeakPointStore.applyPass(pool, {'2:5:2'}, day1);
      expect(next.length, 2);
      expect(next.first.passes, 1);
      // Later the same day: still one pass.
      next = TasmeeWeakPointStore.applyPass(next, {'2:5:2'}, day1.add(const Duration(hours: 5)));
      expect(next.first.passes, 1);
      expect(next.length, 2);
      // Another day: retired; the other word untouched.
      next = TasmeeWeakPointStore.applyPass(next, {'2:5:2'}, DateTime(2026, 10, 1));
      expect(next.map((p) => p.key), ['2:5:4']);
      expect(next.single.passes, 0);
    });

    test('passes survive a json round trip', () {
      final p = _point(2, 5, 2)
        ..passes = 1
        ..lastPassAt = DateTime(2026, 9, 30);
      final back = TasmeeWeakPoint.fromJson(
        Map<String, dynamic>.from(p.toJson()),
      );
      expect(back.passes, 1);
      expect(back.lastPassAt, DateTime(2026, 9, 30));
    });
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/hifz_test_plan.dart';
import 'package:islamic_dawah_mushaf/services/hifz_test_stats_store.dart';
import 'package:islamic_dawah_mushaf/services/quran_json_service.dart';
import 'package:islamic_dawah_mushaf/services/tasmee_report_store.dart';
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

    test('spans: athman, and hizbs agree with their athman', () {
      // Thumn 1 runs up to the ayah before thumn 2.
      final t1 = index.spanOf(const HifzRange(HifzRangeKind.athman, from: 1, to: 1))!;
      expect(t1.$1, 0);
      expect(t1.$2, index.indexOf(thumnEntries[1].startSurah, thumnEntries[1].startAyah)! - 1);
      // The last thumn reaches the end of the mushaf.
      final t480 = index.spanOf(const HifzRange(HifzRangeKind.athman, from: 480, to: 480))!;
      expect(t480.$2, 6213);
      // Hizb 12 = its eight athman.
      expect(
        index.spanOf(const HifzRange(HifzRangeKind.hizbs, from: 12, to: 12)),
        index.spanOf(const HifzRange(HifzRangeKind.athman, from: 89, to: 96)),
      );
      expect(HifzRange.hizbOfThumn(89), 12);
      expect(HifzRange.thumnInHizb(96), 8);
      expect(HifzRange.thumnNumber(12, 3), 91);
      expect(HifzRange.hizbStart(12).number, 89);
      expect(HifzRange.hizbStart(12).hizb, 12);
    });

    test('hizb and thumn labels carry number, name and surah', () {
      expect(HifzRange.hizbLabel(1), '1. الفاتحة — الفاتحة');
      expect(HifzRange.hizbLabel(12), startsWith('12. قال رجلان — '));
      expect(HifzRange.hizbLabel(12), endsWith(HifzRange.surahName(HifzRange.hizbStart(12).startSurah)));
      expect(HifzRange.thumnLabel(1), '1. الحمد لله رب العالمين');
      expect(HifzRange.thumnLabel(2), startsWith('2. '));
      expect(HifzRange.thumnLabel(2), endsWith('…'));
      expect(
        const HifzRange(HifzRangeKind.athman, from: 91, to: 91).label,
        'الثمن 3 من الحزب 12',
      );
    });

    test('«الصفحة الحالية» resolves to the open page before planning', () {
      const r = HifzRange(HifzRangeKind.currentPage);
      expect(r.label, 'الصفحة الحالية');
      expect(index.spanOf(r), isNull, reason: 'unresolved, it covers nothing');
      final on = r.onPage(128);
      expect(on.kind, HifzRangeKind.pages);
      expect(on.from, 128);
      expect(on.to, 128);
      expect(index.spanOf(on), index.spanOf(const HifzRange(HifzRangeKind.pages, from: 128, to: 128)));
      expect(const HifzRange(HifzRangeKind.surahs, from: 2, to: 2).onPage(5).kind, HifzRangeKind.surahs);
      expect(HifzRange.fromJson(r.toJson()).kind, HifzRangeKind.currentPage);
    });

    test('an error keeps its repaired mark and category through json', () {
      final e = TasmeeError(surah: 1, ayah: 3, wordInAyah: 1, expected: 'x', kind: 'hafs')
        ..repaired = true;
      expect(e.category, 'repaired');
      expect(TasmeeError.fromJson(Map<String, dynamic>.from(e.toJson())).repaired, isTrue);
      expect(TasmeeError(surah: 1, ayah: 1, wordInAyah: 1, expected: 'x', kind: 'revealed').category, 'asked');
      expect(TasmeeError(surah: 1, ayah: 1, wordInAyah: 1, expected: 'x', kind: 'skippedAyah').category, 'asked');
      expect(TasmeeError(surah: 1, ayah: 1, wordInAyah: 1, expected: 'x', kind: 'word').category, 'wrong');
    });

    test('an open test runs through the range in order', () {
      const config = HifzTestConfig(
        range: HifzRange(HifzRangeKind.surahs, from: 1, to: 1),
        ayahsPerQuestion: 3,
        endless: true,
      );
      final qs = HifzTestPlanner.plan(index: index, config: config, pool: const []);
      // One question per page, whatever the ayah count says.
      expect(qs.map((q) => '${q.start.ayah}-${q.end.ayah}'), ['1-7']);
      final baqara = HifzTestPlanner.plan(
        index: index,
        config: config.copyWith(range: const HifzRange(HifzRangeKind.pages, from: 2, to: 4)),
        pool: const [],
      );
      expect(baqara.map((q) => q.start.page), [2, 3, 4]);
      for (final q in baqara) {
        expect(q.end.page, q.start.page);
      }
      expect(HifzTestConfig.fromJson(config.toJson()).endless, isTrue);
      final open = const HifzRange(HifzRangeKind.currentPage).onPage(600, endless: true);
      expect(open.kind, HifzRangeKind.pages);
      expect(open.from, 600);
      expect(open.to, 602);
      // An older save of «من الصفحة الحالية» reads as the current page, open.
      final old = HifzTestConfig.fromJson({'range': {'kind': 'fromCurrentPage'}});
      expect(old.range.kind, HifzRangeKind.currentPage);
      expect(old.endless, isTrue);
    });

    test('with athman every thumn is one question: all in order when open, as many as asked at random when closed', () {
      final r = HifzRange.athman(start: 9, count: 3); // hizb 2, athman 1-3
      final inOrder = HifzTestPlanner.plan(
        index: index,
        config: HifzTestConfig(range: r, endless: true),
        pool: const [],
      );
      // Each piece covers its thumn exactly (split only at a surah end).
      var covered = 0;
      for (var t = 9; t <= 11; t++) {
        final span = index.thumnSpan(t)!;
        final pieces = inOrder.where((q) {
          final s = index.indexOf(q.start.surah, q.start.ayah)!;
          return s >= span.$1 && s <= span.$2;
        }).toList();
        expect(pieces, isNotEmpty);
        expect(index.indexOf(pieces.first.start.surah, pieces.first.start.ayah), span.$1);
        expect(index.indexOf(pieces.last.end.surah, pieces.last.end.ayah), span.$2);
        covered += pieces.length;
      }
      expect(covered, inOrder.length);
      for (var i = 1; i < inOrder.length; i++) {
        expect(
          index.indexOf(inOrder[i].start.surah, inOrder[i].start.ayah)!,
          greaterThan(index.indexOf(inOrder[i - 1].start.surah, inOrder[i - 1].start.ayah)!),
          reason: 'open: in order',
        );
      }

      // Closed: as many athman as asked for, drawn from the range.
      final two = HifzTestPlanner.plan(
        index: index,
        config: HifzTestConfig(range: r, questions: 2),
        pool: const [],
        random: Random(5),
      );
      final starts = {for (var t = 9; t <= 11; t++) index.thumnSpan(t)!.$1};
      final twoStarts = two.where((q) => starts.contains(index.indexOf(q.start.surah, q.start.ayah))).length;
      expect(twoStarts, 2);
      final all = HifzTestPlanner.plan(
        index: index,
        config: HifzTestConfig(range: r, questions: 10),
        pool: const [],
      );
      expect(all.map((q) => q.start.key).toSet(), inOrder.map((q) => q.start.key).toSet());

      // A self-test keeps the thumn whole too (the session follows the
      // page turn by itself).
      final paged = HifzTestPlanner.plan(
        index: index,
        config: HifzTestConfig(range: HifzRange.athman(start: 9, count: 1)),
        pool: const [],
        singlePage: true,
      );
      expect(paged.length, 1);
      expect(paged.single.end.page, greaterThan(paged.single.start.page));
    });

    test('a thumn that runs into the next surah stays one question', () {
      // The first thumn whose span runs on into another surah (such as the
      // one on p. 576, «ويطوف عليهم ولدان مخلدون», ending in al-Hadid).
      final t = List.generate(480, (i) => i + 1).firstWhere((t) {
        final span = index.thumnSpan(t);
        return span != null && index.ayahs[span.$1].surah != index.ayahs[span.$2].surah;
      });
      final span = index.thumnSpan(t)!;
      final qs = HifzTestPlanner.plan(
        index: index,
        config: HifzTestConfig(range: HifzRange.athman(start: t, count: 1), endless: true),
        pool: const [],
      );
      expect(qs.length, 1);
      expect(qs.single.start.surah, index.ayahs[span.$1].surah);
      expect(qs.single.start.ayah, index.ayahs[span.$1].ayah);
      expect(qs.single.end.surah, index.ayahs[span.$2].surah);
      expect(qs.single.end.surah, isNot(qs.single.start.surah));
      expect(qs.single.end.ayah, index.ayahs[span.$2].ayah);
    });

    test('athman are a start and a count of whole athman', () {
      final r = HifzRange.athman(start: 91, count: 3);
      expect(r.from, 91);
      expect(r.to, 93);
      expect(r.athmanCount, 3);
      expect(r.label, '3 أثمان من الثمن 3 من الحزب 12');
      expect(HifzRange.athman(start: 480, count: 5).to, 480);
      expect(HifzRange.athman(start: 1, count: 1).label, 'الثمن 1 من الحزب 1');
      expect(
        TasmeeDrill(page: 1, surah: 1, ayah: 1, targets: const [], index: 4, total: 0, title: 'اختبار').label,
        'اختبار 4',
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

    test('single-page questions never run past the page they start on', () {
      const config = HifzTestConfig(
        source: HifzTestSource.random,
        range: HifzRange.all(),
        questions: 40,
        ayahsPerQuestion: 5,
      );
      final qs = HifzTestPlanner.plan(
        index: index,
        config: config,
        pool: const [],
        random: Random(11),
        singlePage: true,
      );
      expect(qs.length, 40);
      for (final q in qs) {
        expect(q.end.page, q.start.page, reason: q.title);
      }
      // ...and a mistake at the top of a page gets no run-up from the page
      // before, but still has its cue ayah.
      final topOfPage2 = index.ayahs.firstWhere((a) => a.page == 2);
      final m = HifzTestPlanner.plan(
        index: index,
        config: const HifzTestConfig(
          source: HifzTestSource.mistakes,
          range: HifzRange.all(),
          questions: 1,
          ayahsPerQuestion: 3,
        ),
        pool: [_point(3, 10, 1)],
        singlePage: true,
      ).single;
      expect(m.end.key, '3:10');
      expect(m.start.page, m.end.page);
      expect(m.before, isNotNull);
      expect(topOfPage2.surah, 2); // sanity: page 2 opens with al-Baqarah
    });

    test('a question lists every ayah from its start to its end', () {
      final pool = [_point(2, 5, 2)];
      const config = HifzTestConfig(
        source: HifzTestSource.mistakes,
        range: HifzRange.all(),
        questions: 1,
        ayahsPerQuestion: 3,
      );
      final q = HifzTestPlanner.plan(index: index, config: config, pool: pool).single;
      expect(q.ayahs.map((a) => a.ayah), [3, 4, 5]);
      expect(q.ayahs.first, same(q.start));
      expect(q.ayahs.last, same(q.end));
    });

    test('open-ended questions run to the end of the surah (or page)', () {
      const config = HifzTestConfig(
        source: HifzTestSource.random,
        range: HifzRange(HifzRangeKind.surahs, from: 2, to: 2),
        questions: 5,
        ayahsPerQuestion: 0,
      );
      expect(config.openEnded, isTrue);
      final last = index.ayahs.lastWhere((a) => a.surah == 2);
      final qs = HifzTestPlanner.plan(index: index, config: config, pool: const [], random: Random(1));
      for (final q in qs) {
        expect(q.open, isTrue);
        expect(q.end.key, last.key);
        expect(q.toDrill(1, 1).open, isTrue);
        expect(q.extent, contains('${last.ayah}'));
      }
      final onPage = HifzTestPlanner.plan(
        index: index,
        config: config,
        pool: const [],
        random: Random(1),
        singlePage: true,
      );
      for (final q in onPage) {
        expect(q.end.page, q.start.page);
        expect(index.ayahs[index.indexOf(q.end.surah, q.end.ayah)! + 1].page, q.end.page + 1);
      }
      // From a mistake: a two-ayah run-up, then open.
      final m = HifzTestPlanner.plan(
        index: index,
        config: config.copyWith(source: HifzTestSource.mistakes),
        pool: [_point(2, 10, 1)],
      ).single;
      expect(m.start.key, '2:8');
      expect(m.end.key, last.key);
      expect(m.targets, isNotEmpty);
    });

    test('questions never overlap: a small range gives fewer, not repeats', () {
      // Al-Fatiha, 7 ayat, questions of 2: at most three questions.
      const config = HifzTestConfig(
        range: HifzRange(HifzRangeKind.surahs, from: 1, to: 1),
        questions: 5,
        ayahsPerQuestion: 2,
      );
      final qs = HifzTestPlanner.plan(index: index, config: config, pool: const [], random: Random(2));
      expect(qs.length, lessThanOrEqualTo(3));
      final seen = <int>{};
      for (final q in qs) {
        for (var a = q.start.ayah; a <= q.end.ayah; a++) {
          expect(seen.add(a), isTrue, reason: 'ayah $a asked twice');
        }
      }
      // Mistakes on neighbouring ayat: the second is covered by the first
      // question's run-up and is not asked again.
      final m = HifzTestPlanner.plan(
        index: index,
        config: const HifzTestConfig(
          source: HifzTestSource.mistakes,
          range: HifzRange(HifzRangeKind.surahs, from: 2, to: 2),
          questions: 5,
          ayahsPerQuestion: 3,
        ),
        pool: [_point(2, 10, 1, count: 3), _point(2, 9, 1), _point(2, 30, 1)],
      );
      expect(m.map((q) => '${q.start.ayah}-${q.end.ayah}'), ['8-10', '28-30']);
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

  group('reports and records', () {
    test('a report keeps its stops and repairs; old reports read as zero', () {
      final r = TasmeeReport(
        page: 3,
        at: DateTime(2026, 9, 30),
        seconds: 90,
        words: 100,
        correct: 97,
        errors: const [],
        finished: true,
        holds: 4,
        repairs: 3,
      );
      final back = TasmeeReport.fromJson(Map<String, dynamic>.from(r.toJson()));
      expect(back.holds, 4);
      expect(back.repairs, 3);
      final old = TasmeeReport.fromJson({'page': 1, 'seconds': 5});
      expect(old.holds, 0);
      expect(old.repairs, 0);
    });

    test('a test record is made of a run and survives json', () {
      const config = HifzTestConfig(
        source: HifzTestSource.random,
        range: HifzRange(HifzRangeKind.surahs, from: 2, to: 2),
        questions: 3,
      );
      final qs = HifzTestPlanner.plan(index: index, config: config, pool: const []);
      final run = HifzTestRun(config, qs, silent: true)
        ..judgements.addAll([true, false])
        ..missedAyahs = 2;
      final rec = HifzTestRecord.ofRun(run, run.startedAt.add(const Duration(seconds: 70)));
      expect(rec.answered, 2);
      expect(rec.correct, 1);
      expect(rec.mistakes, 2);
      expect(rec.seconds, 70);
      expect(rec.percent, 50);
      expect(rec.range, 'سورة البقرة');
      final back = HifzTestRecord.fromJson(Map<String, dynamic>.from(rec.toJson()));
      expect(back.silent, isTrue);
      expect(back.questions, 3);
      expect(back.correct, 1);
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

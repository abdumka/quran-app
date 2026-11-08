import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/quran_json_service.dart';
import 'package:islamic_dawah_mushaf/services/tanzilat_notes_store.dart';
import 'package:islamic_dawah_mushaf/services/tanzilat_service.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/tanzilat_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// assets/data/tanzilat.json points at words by their index in output.json's
/// ayah text; an output.json edit that adds or splits words would silently
/// colour the wrong word, so every place is checked against the text.
void main() {
  final groups = parseTanzilat(
    File('assets/data/tanzilat.json').readAsStringSync(),
  );
  final words = <(int, int), int>{};
  for (final e
      in json.decode(File('assets/data/output.json').readAsStringSync())
          as List<dynamic>) {
    for (final p in e is List ? e : [e]) {
      for (final a in (p as Map<String, dynamic>)['ayahs'] as List<dynamic>) {
        final m = a as Map<String, dynamic>;
        words[(m['surah'] as int, m['ayah'] as int)] = (m['text'] as String)
            .split(' ')
            .length;
      }
    }
  }

  test('every coloured word exists in output.json', () {
    var places = 0;
    for (final g in groups) {
      for (final r in g.rows) {
        for (final p in r.places) {
          final n = words[(p.surah, p.ayah)];
          expect(n, isNotNull, reason: 'group ${g.id}: ${p.surah}:${p.ayah}');
          expect(p.words, isNotEmpty);
          for (final i in p.words) {
            expect(
              i,
              inInclusiveRange(0, n! - 1),
              reason: 'group ${g.id}: ${p.surah}:${p.ayah} word $i',
            );
          }
          places++;
        }
      }
    }
    expect(places, greaterThan(2500));
  });

  test('labels are غ or a number, with Western digits only', () {
    for (final g in groups) {
      expect(
        g.label == 'غ' || int.tryParse(g.label) != null,
        isTrue,
        reason: 'group ${g.id} label ${g.label}',
      );
      for (final d in g.danfasi) {
        expect(d.lines.join(), isNot(matches(RegExp('[٠-٩۰-۹]'))));
      }
    }
  });

  test('owner decisions are in the data', () {
    final service = TanzilatService.instance..setGroups(groups);
    // المائدة 31: the memo's «تبوأ», not the Tanzil app's «بإثمي».
    final hit = service.wordsOf(5, 31);
    expect(hit.keys, contains(3)); // إِنِّيَ أُرِيدُ أَن تَبُوٓأَ
    expect(hit.keys, isNot(contains(4))); // not the Tanzil app's «بإثمي»
    expect(hit[3]!.group.isGharibah, isTrue);
    // «ادع» (23), «ظل» (33) and the «لله / اللاعنون …» list (with its
    // uncoloured لفظ الجلالة row) were deleted by the owner in the editor
    // (2026-10-29).
    expect(groups.where((g) => const {936, 945, 946}.contains(g.id)), isEmpty);
    // الدنفاسي's verses sit on the card of their own word (2026-10-21: the
    // old links put «الحيوٰة» on «الموت» and «وقر» on «هدى»).
    List<String> versesAt(int s, int a) => [
      for (final h in service.forAyah(s, a))
        for (final d in h.danfasi) d.title,
    ];
    expect(versesAt(2, 93).join(), isNot(contains('الحيو')));
    expect(versesAt(2, 96).join(), isNot(contains('وَقْر')));
    expect(versesAt(2, 85).join(), contains('الحيو'));
    expect(versesAt(41, 4).join(), contains('وَقْر'));
    // The long-press list of an ayah with a tanzilah.
    expect(service.forAyah(5, 31), isNotEmpty);
    expect(service.forAyah(1, 1), isEmpty);
  });

  test('tanzil_edit.html decisions (2026-10-23) are in the data', () {
    final service = TanzilatService.instance..setGroups(groups);
    // «لِيَسُـُٔواْ»: the hamza drawn this way is only here -> غريبة (red);
    // «الأفئدة» is no longer part of it.
    final g466 = groups.firstWhere((g) => g.id == 466);
    expect(g466.isGharibah, isTrue);
    expect(
      g466.rows.expand((r) => r.places).map((p) => '${p.surah}:${p.ayah}'),
      ['17:7'],
    );
    expect(service.wordsOf(16, 78).containsKey(12), isFalse);
    // «لعلكم تشكرون» النحل 78: both words, one «» when copied.
    expect(service.wordsOf(16, 78).keys, containsAll([13, 14]));
    final raw =
        json.decode(File('assets/data/output.json').readAsStringSync())
            as List<dynamic>;
    final words = <(int, int), List<String>>{};
    for (final e in raw) {
      for (final page in e is List ? e : [e]) {
        for (final a in (page as Map<String, dynamic>)['ayahs'] as List) {
          final m = a as Map<String, dynamic>;
          words[(m['surah'] as int, m['ayah'] as int)] = (m['text'] as String)
              .split(' ');
        }
      }
    }
    final copy = tanzilatCopyText(16, 78, service.forAyah(16, 78), words);
    final line = copy.split('\n').firstWhere((l) => l.startsWith('- النحل 78'));
    expect(RegExp('«[^» ]+ [^» ]+»\$').hasMatch(line), isTrue, reason: line);
    expect('«'.allMatches(line).length, 1, reason: line);

    // the small icon on one card copies that tanzilah only, as «نسخ الكل»
    // writes it
    final hits = service.forAyah(16, 78);
    for (final hit in hits) {
      final one = tanzilahCopyText(16, 78, hit, words);
      final block = one.substring(one.indexOf('\n'));
      expect(copy.contains(block), isTrue, reason: one);
      expect(one.startsWith(copy.split('\n').first), isTrue);
    }
  });

  test('a «متكررة» row is part of its tanzilah: one card, its colour', () {
    final service = TanzilatService.instance..setGroups(groups);
    // 911 «8»: مشكوة، النجوة، منوة، الغدوة، الصلوة، الزكوة، الحيوة، الربوا
    // (2026-11-02: البقرة 2 showed «الصلوة» alone, in موضعين's colour).
    final hits = service.forAyah(2, 2).where((h) => h.group.id == 911);
    expect(hits.length, 1);
    expect(hits.single.count, 8);
    expect(hits.single.group.title, 'كلمات رسمت بمحذوف فوق الواو');
    expect(hits.single.group.rows.length, 8);
    // البينة 5 holds two of its words: still one card
    expect(service.forAyah(98, 5).where((h) => h.group.id == 911).length, 1);
    expect(service.wordsOf(2, 2)[4]!.count, 8);
  });

  test('«صه» stop marks above coloured words are never coloured', () {
    final json = File('assets/data/tanzilat.json').readAsStringSync();
    final holes = parseNoPaint(json);
    expect(holes.length, greaterThan(300));
    final service = TanzilatService.instance
      ..setGroups(groups)
      ..setNoPaint(holes);
    for (final e in holes.entries) {
      final (s, a, i) = e.key;
      // only on words that are coloured, and inside the page
      expect(service.wordsOf(s, a).containsKey(i), isTrue, reason: '$s:$a:$i');
      for (final r in e.value) {
        expect(
          r.left >= 0 && r.top >= 0 && r.right <= 1 && r.bottom <= 1,
          isTrue,
        );
        expect(
          r.width < 0.08 && r.height < 0.04,
          isTrue,
          reason: 'a mark, not a word',
        );
      }
    }
  });

  test('colour buckets: غريبة, 2, 3, 4, then one colour for 5+', () {
    expect(tanzilahBucket(1), 0);
    expect(tanzilahBucket(2), 1);
    expect(tanzilahBucket(4), 3);
    expect(tanzilahBucket(5), 4);
    expect(tanzilahBucket(187), 4);
  });

  testWidgets('the sheet lists every place and opens the tapped one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    TanzilatService.instance.setGroups(groups);
    await tester.runAsync(QuranJsonService.loadQuranPages);
    (int, int, int)? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TanzilatSheetContent(
            surah: 3,
            ayah: 48,
            dark: false,
            onOpenPlace: (page, s, a) => opened = (page, s, a),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    // The card is titled by the tanzilah's title; its count is the badge.
    expect(find.text('ءلاية: بالإفراد'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    // Every text can be marked, and «نسخ الكل» copies the whole sheet,
    // the folded places too.
    expect(find.byType(SelectionArea), findsOneWidget);
    await tester.tap(find.text('نسخ الكل'));
    await tester.pump();
    expect(copied, startsWith('تنزيلات ومتشابهات — سورة آل عمران 48'));
    expect(copied, contains('ءلاية: بالإفراد (20)'));
    expect('\n- '.allMatches(copied!).length, greaterThanOrEqualTo(20));
    expect(copied, contains('- سبأ 9'));
    expect(copied, contains('(هذه الآية)'));
    expect(copied, isNot(matches(RegExp('[٠-٩۰-۹]'))));
    await tester.pump(const Duration(seconds: 3));
    // 20 places, collapsed to 8 behind «عرض كل المواضع».
    await tester.ensureVisible(find.textContaining('عرض كل المواضع (20)'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('عرض كل المواضع (20)'));
    await tester.pumpAndSettle();
    expect(find.text('سبأ 9'), findsOneWidget);
    await tester.ensureVisible(find.text('العنكبوت 44'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('العنكبوت 44'));
    expect(opened?.$2, 29);
    expect(opened?.$3, 44);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«ملاحظاتي»: one line when empty, saved, copied', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    TanzilatService.instance.setGroups(groups);
    await tester.runAsync(TanzilatNotesStore.instance.load);
    await tester.runAsync(QuranJsonService.loadQuranPages);
    // الفاتحة 1 has no tanzilah, yet its sheet opens for the note.
    expect(TanzilatService.instance.forAyah(1, 1), isEmpty);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TanzilatSheetContent(
            surah: 1,
            ayah: 1,
            dark: false,
            onOpenPlace: (_, _, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    const hint = 'ملاحظاتي: اكتب هنا ملاحظاتك عن متشابهات هذه الآية…';
    expect(find.text(hint), findsOneWidget);
    expect(find.text('لا توجد تنزيلة في هذه الآية.'), findsOneWidget);
    final field = find.byType(TextField);
    final emptyHeight = tester.getSize(field).height;
    expect(emptyHeight, lessThan(40));
    // A long paste grows the field, at most 6 lines.
    final long = List.filled(40, 'ملاحظة طويلة').join(' ');
    await tester.enterText(field, long);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final grown = tester.getSize(field).height;
    expect(grown, greaterThan(emptyHeight * 3));
    expect(grown, lessThanOrEqualTo(emptyHeight * 6 + 1));
    expect(find.text('ملاحظاتي'), findsOneWidget);
    expect(TanzilatNotesStore.instance.noteOf(1, 1), long);
    // «نسخ الكل» copies the note too. (Checked through its text: the sheet's
    // ayah index was cached under the test above's fake clock.)
    expect(
      tanzilatCopyText(1, 1, const [], const {}, note: long),
      contains('ملاحظاتي:\n$long'),
    );
    expect(tester.takeException(), isNull);
  });
}

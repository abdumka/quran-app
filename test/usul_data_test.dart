import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/usul.dart';
import 'package:islamic_dawah_mushaf/services/content_update_service.dart';
import 'package:islamic_dawah_mushaf/widgets/usul/usul_pages.dart';

/// «أحكام وأصول الرواية»: the bundled file, the `usul` server item and every
/// chapter drawn without an error.
void main() {
  final text = File('assets/data/usul.json').readAsStringSync();
  final data = UsulData.parse(text);

  test('the bundled version matches bundledVersions', () {
    final j = json.decode(text) as Map<String, dynamic>;
    expect(j['ver'], ContentUpdateService.bundledVersions['usul']);
    expect(ContentUpdateService.items, contains('usul'));
  });

  test('the bundled file is valid; a broken download is refused', () {
    expect(() => ContentUpdateService.validate('usul', text), returnsNormally);
    for (final bad in [
      '[1,2]',
      '{"ver":2,"v":1,"groups":[]}',
      '{"ver":2,"v":2,"groups":[{"name":"x","chapters":[]}]}',
      '{"ver":2,"v":1,"hero":{},"groups":[{"name":"x","chapters":[{"id":"a","title":"t","blocks":[]}]}]}',
    ]) {
      expect(
        () => ContentUpdateService.validate('usul', bad),
        throwsFormatException,
        reason: bad,
      );
    }
  });

  test('31 chapters in 4 lists; only kinds the app draws; Western digits', () {
    expect(data.groups.map((g) => g.name).toList(), [
      'أحكام التلاوة',
      'الأصول',
      'كلمات متكررة',
      '',
    ]);
    expect(data.chapters.length, 31);
    const known = {
      'lead', 'para', 'sub', 'head', 'note', 'minis', 'words', 'ayah',
      'options', 'steps', 'card', 'chips', 'verse', 'src', 'book',
    };
    void check(List<Map<String, dynamic>> blocks) {
      for (final b in blocks) {
        expect(known, contains(b['t']));
        if (b['t'] == 'card') {
          check((b['blocks'] as List).cast<Map<String, dynamic>>());
        }
      }
    }

    for (final c in data.chapters) {
      check(c.blocks);
    }
    expect(RegExp('[٠-٩۰-۹—]').hasMatch(text), isFalse);
  });

  test('the sajdat screen lists the 11 of the Maliki count', () {
    final sajdat = data.chapters.firstWhere((c) => c.title == 'سجدات التلاوة');
    final words = sajdat.blocks.firstWhere((b) => b['t'] == 'words');
    expect((words['items'] as List).length, 11);
  });

  testWidgets('every chapter draws without an error', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    for (final c in data.chapters) {
      await tester.pumpWidget(MaterialApp(home: UsulChapterPage(chapter: c)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: c.title);
      expect(find.text(c.title).evaluate(), isNotEmpty, reason: c.title);
      // scroll to the end so every block is built once
      await tester.fling(find.byType(ListView), const Offset(0, -20000), 5000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: c.title);
    }
  });

  testWidgets('the home page lists the chapters', (tester) async {
    ContentUpdateService.instance.debugReset(
      dir: Directory.systemTemp.createTempSync('usul_test'),
    );
    UsulData.debugReset();
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: UsulHomePage()));
      await UsulData.load();
    });
    await tester.pumpAndSettle();
    expect(find.text('رواية قالون عن نافع'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('النون الساكنة والتنوين'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('النون الساكنة والتنوين'));
    await tester.pumpAndSettle();
    expect(find.byType(UsulChapterPage), findsOneWidget);
    ContentUpdateService.instance.debugReset();
  });

  test('every example knows its surah, ayah and page', () {
    var n = 0;
    void walk(List<Map<String, dynamic>> blocks) {
      for (final b in blocks) {
        if (b['t'] == 'card') {
          walk((b['blocks'] as List).cast<Map<String, dynamic>>());
        }
        if (b['t'] == 'ayah') {
          expect([b['s'], b['a'], b['p']].every((v) => v is int), isTrue);
        }
        for (final i in (b['items'] is List ? b['items'] as List : const [])) {
          if (i is Map && i.containsKey('w')) {
            n++;
            expect(
              [i['s'], i['a'], i['p']].every((v) => v is int),
              isTrue,
              reason: '$i',
            );
          }
        }
      }
    }

    for (final c in data.chapters) {
      walk(c.blocks);
    }
    expect(n, greaterThan(130));
  });

  testWidgets('a kind box scrolls to its list', (tester) async {
    ContentUpdateService.instance.debugReset(
      dir: Directory.systemTemp.createTempSync('usul_test'),
    );
    UsulData.debugReset();
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: UsulHomePage()));
      await UsulData.load();
    });
    await tester.pumpAndSettle();
    expect(find.text('8 فصول'), findsOneWidget); // كلمات متكررة
    expect(find.text('15 فصلًا'), findsOneWidget); // الأصول
    await tester.ensureVisible(find.text('8 فصول'));
    await tester.pumpAndSettle();
    final row = find.text('وَهْوَ، فَهْيَ، لَهْوَ');
    expect(tester.getRect(row).top, greaterThan(600));
    await tester.tap(find.text('8 فصول'));
    await tester.pumpAndSettle();
    expect(tester.getRect(row).top, lessThan(300));
    ContentUpdateService.instance.debugReset();
  });

  testWidgets('an example opens its page over the حكم; back returns', (
    tester,
  ) async {
    ContentUpdateService.instance.debugReset(
      dir: Directory.systemTemp.createTempSync('usul_test'),
    );
    final nun = data.chapters.first;
    await tester.pumpWidget(MaterialApp(home: UsulChapterPage(chapter: nun)));
    await tester.pump();
    // the rule is above its example
    final rule = tester.getRect(find.text('الإظهار'));
    final where = find.text('آل عمران 99 · صفحة 62');
    expect(rule.top, lessThan(tester.getRect(where).top));
    await tester.runAsync(() async {
      await tester.tap(where);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.text('افتح في المصحف'), findsOneWidget);
    expect(find.text('رجوع إلى الحكم'), findsOneWidget);
    await tester.tap(find.text('رجوع إلى الحكم'));
    await tester.pumpAndSettle();
    expect(find.text('افتح في المصحف'), findsNothing);
    expect(find.byType(UsulChapterPage), findsOneWidget);
    expect(find.text('الإظهار'), findsOneWidget);
    ContentUpdateService.instance.debugReset();
  });
}

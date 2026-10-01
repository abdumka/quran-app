import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/hifz_test_plan.dart';
import 'package:islamic_dawah_mushaf/widgets/hifz/hifz_stats_page.dart';
import 'package:islamic_dawah_mushaf/widgets/hifz/hifz_test_sheets.dart';
import 'package:islamic_dawah_mushaf/widgets/hifz/hifz_tools_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A page with one button that runs [open] with a real context.
Widget _host(Future<void> Function(BuildContext) open) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

AyahRef _ayah(int n) => AyahRef(
      page: 2,
      indexOnPage: n - 1,
      surah: 2,
      surahName: 'البقرة',
      ayah: n,
      text: 'كلمة$n أخرى',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('setup sheet', () {
    testWidgets('إلى follows من, fields are named, steppers step, ابدأ returns the choice',
        (tester) async {
      HifzTestConfig? result;
      await tester.pumpWidget(_host((context) async {
        result = await showHifzTestSetup(
          context,
          silentMode: true,
          mistakesInPool: 0,
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('اختبار ذاتي'), findsOneWidget);
      expect(find.text('ابدأ'), findsOneWidget);
      // No mistakes yet: only «عشوائي» can be chosen.
      final mistakesChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'من أخطائي'),
      );
      expect(mistakesChip.onSelected, isNull);

      // Surahs: من and إلى on one line; picking من = 5 drags إلى up to 5.
      await tester.tap(find.widgetWithText(ChoiceChip, 'سور'));
      await tester.pumpAndSettle();
      expect(find.text('من'), findsOneWidget);
      expect(find.text('إلى'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5. المائدة').last);
      await tester.pumpAndSettle();
      final dropdowns = tester.widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>)).toList();
      expect(dropdowns.first.value, 5);
      expect(dropdowns.last.value, 5, reason: 'إلى can never be before من');
      // ...and إلى offers nothing before surah 5.
      expect(dropdowns.last.items!.first.value, 5);
      expect(find.text('النطاق: سورة المائدة'), findsOneWidget);

      // Athman: two columns, each naming its hizb and thumn field.
      await tester.tap(find.widgetWithText(ChoiceChip, 'أثمان'));
      await tester.pumpAndSettle();
      expect(find.text('الحزب'), findsNWidgets(2));
      expect(find.text('الثمن'), findsNWidgets(2));
      expect(find.text('من'), findsOneWidget);
      expect(find.text('إلى'), findsOneWidget);

      // Back to surahs: the earlier choice is remembered.
      await tester.tap(find.widgetWithText(ChoiceChip, 'سور'));
      await tester.pumpAndSettle();
      expect(find.text('النطاق: سورة المائدة'), findsOneWidget);

      // Steppers: + on the question count, − on the ayah count.
      expect(find.text('5 أسئلة'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('6 أسئلة'), findsOneWidget);
      expect(find.text('3 آيات'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.remove_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('آيتان'), findsOneWidget);

      await tester.tap(find.text('ابدأ'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.range.kind, HifzRangeKind.surahs);
      expect(result!.range.from, 5);
      expect(result!.range.to, 5);
      expect(result!.questions, 6);
      expect(result!.ayahsPerQuestion, 2);
      expect(result!.source, HifzTestSource.random);

      // The choice is remembered for next time.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hifz_text_test_config'), contains('"from":5'));
    });

    testWidgets('إلغاء returns nothing; the microphone sheet has its own title', (tester) async {
      HifzTestConfig? result = const HifzTestConfig();
      await tester.pumpWidget(_host((context) async {
        result = await showHifzTestSetup(
          context,
          silentMode: false,
          mistakesInPool: 7,
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('اختبار الحفظ'), findsOneWidget);
      expect(find.text('أخطاؤك المسجّلة: 7 موضعًا.'), findsOneWidget);
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'من أخطائي')).onSelected,
        isNotNull,
      );
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('self-judge sheet', () {
    final question = HifzTestQuestion(
      start: _ayah(1),
      end: _ayah(3),
      before: null,
      ayahs: [_ayah(1), _ayah(2), _ayah(3)],
    );

    testWidgets('every ayah is listed; marking one wrong is returned', (tester) async {
      HifzSelfJudgement? j;
      await tester.pumpWidget(_host((context) async {
        j = await showHifzSelfJudge(
          context,
          question: question,
          label: 'اختبار 1 / 5',
          hasNext: true,
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('الآية 1'), findsOneWidget);
      expect(find.text('الآية 2'), findsOneWidget);
      expect(find.text('الآية 3'), findsOneWidget);
      expect(find.text('اختبار 1 / 5'), findsOneWidget);

      await tester.tap(find.text('خطأ').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('السؤال التالي'));
      await tester.pumpAndSettle();
      expect(j, isNotNull);
      expect(j!.correct, isFalse);
      expect(j!.next, isTrue);
      expect(j!.missed.map((a) => a.ayah), [2]);
    });

    testWidgets('all right by default; the last question leads to the result', (tester) async {
      HifzSelfJudgement? j;
      await tester.pumpWidget(_host((context) async {
        j = await showHifzSelfJudge(
          context,
          question: question,
          label: 'اختبار 5 / 5',
          hasNext: false,
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('النتيجة'));
      await tester.pumpAndSettle();
      expect(j!.correct, isTrue);
      expect(j!.missed, isEmpty);
      expect(j!.next, isFalse);
    });

    testWidgets('ending without judging returns no verdict', (tester) async {
      HifzSelfJudgement? j;
      await tester.pumpWidget(_host((context) async {
        j = await showHifzSelfJudge(
          context,
          question: question,
          label: 'x',
          hasNext: true,
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إنهاء الاختبار دون حكم'));
      await tester.pumpAndSettle();
      expect(j!.correct, isNull);
      expect(j!.next, isFalse);
    });
  });

  group('tools menu', () {
    Future<void> openMenu(
      WidgetTester tester, {
      required void Function(VoidCallback) onTest,
      VoidCallback? onTasmee,
      VoidCallback? onReports,
    }) async {
      await tester.pumpWidget(_host((context) => showHifzToolsSheet(
            context,
            tasmeeActive: false,
            hifzModeActive: false,
            onTasmee: onTasmee ?? () {},
            onHifzMode: () {},
            onTest: onTest,
            onTextTest: (_) {},
            onLogs: () {},
            onReports: onReports ?? () {},
            onStats: () {},
            onWeakPoints: () {},
          )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a test entry keeps the menu underneath until its closer is called',
        (tester) async {
      VoidCallback? closer;
      await openMenu(tester, onTest: (c) => closer = c);
      expect(find.text('أدوات الحفظ'), findsOneWidget);
      await tester.tap(find.text('اختبار الحفظ'));
      await tester.pumpAndSettle();
      expect(closer, isNotNull);
      expect(find.text('أدوات الحفظ'), findsOneWidget, reason: 'back lands here');
      closer!();
      await tester.pumpAndSettle();
      expect(find.text('أدوات الحفظ'), findsNothing);
    });

    testWidgets('a page entry keeps the menu; a mode entry closes it', (tester) async {
      var reports = 0;
      var tasmee = 0;
      await openMenu(
        tester,
        onTest: (_) {},
        onReports: () => reports++,
        onTasmee: () => tasmee++,
      );
      await tester.tap(find.text('تقارير التسميع'));
      await tester.pumpAndSettle();
      expect(reports, 1);
      expect(find.text('أدوات الحفظ'), findsOneWidget);
      await tester.tap(find.text('التسميع'));
      await tester.pumpAndSettle();
      expect(tasmee, 1);
      expect(find.text('أدوات الحفظ'), findsNothing);
    });

    testWidgets('the gear opens the alert settings over the menu', (tester) async {
      await openMenu(tester, onTest: (_) {});
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('إعدادات التسميع'), findsOneWidget);
      expect(find.text('عند الخطأ'), findsOneWidget);
      expect(find.text('عند التصويب'), findsOneWidget);
      // Both default to vibration only.
      expect(find.text('اهتزاز فقط'), findsNWidgets(2));
    });
  });

  testWidgets('the statistics page renders with nothing saved', (tester) async {
    // The stores go through path_provider, which has no handler here and
    // fails through real async; let it, then draw the page.
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: HifzStatsPage()));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    expect(find.text('إحصاءات الحفظ'), findsOneWidget);
    expect(find.text('لا جلسات تسميع محفوظة بعد.'), findsOneWidget);
    expect(find.text('لم تُجرَ اختبارات بعد.'), findsOneWidget);
  });
}

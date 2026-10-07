import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/hifz_test_plan.dart';
import 'package:islamic_dawah_mushaf/widgets/hifz/hifz_stats_page.dart';
import 'package:islamic_dawah_mushaf/widgets/hifz/hifz_test_setup_page.dart';
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

  group('setup page', () {
    testWidgets('range picker: إلى follows من, athman are a start and a count, steppers step, ابدأ returns the choice',
        (tester) async {
      HifzTestConfig? result;
      await tester.pumpWidget(_host((context) async {
        result = await showHifzTestSetup(
          context,
          silentMode: true,
          mistakesInPool: 0,
          currentPage: 128,
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // First open: the guide, with its four steps, closed by «فهمت».
      expect(find.text('كيف يعمل الاختبار الذاتي'), findsOneWidget);
      expect(find.text('احكم على نفسك'), findsOneWidget);
      await tester.tap(find.text('فهمت'));
      await tester.pumpAndSettle();
      expect(find.text('كيف يعمل الاختبار الذاتي'), findsNothing);

      expect(find.text('اختبار ذاتي'), findsOneWidget);
      expect(find.text('ابدأ الاختبار'), findsOneWidget);
      // No mistakes yet: only «عشوائي» can be chosen.
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'من أخطائي')).onSelected,
        isNull,
      );

      // The page open now.
      await tester.tap(find.widgetWithText(ChoiceChip, 'الصفحة الحالية'));
      await tester.pumpAndSettle();
      expect(find.text('الصفحة 128 وحدها.'), findsOneWidget);

      // Surahs, in place: من = 5 drags إلى up to 5.
      await tester.tap(find.widgetWithText(ChoiceChip, 'سور'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5. المائدة').last);
      await tester.pumpAndSettle();
      var dropdowns = tester.widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>)).toList();
      expect(dropdowns.first.value, 5);
      expect(dropdowns.last.value, 5, reason: 'إلى can never be before من');
      expect(dropdowns.last.items!.first.value, 5);

      // Athman: from one thumn to another, two columns each naming its hizb
      // and thumn; each thumn is then a question, so the question rows go.
      await tester.tap(find.widgetWithText(ChoiceChip, 'أثمان'));
      await tester.pumpAndSettle();
      expect(find.text('الحزب'), findsNWidgets(2));
      expect(find.text('الثمن'), findsNWidgets(2));
      expect(find.text('من'), findsOneWidget);
      expect(find.text('إلى'), findsOneWidget);
      expect(find.text('عدد الأسئلة'), findsNothing);
      expect(find.text('آيات كل سؤال'), findsNothing);
      expect(find.text('عدد الأثمان في الاختبار'), findsOneWidget);
      // The count stays with the open switch on: open only drops the pauses.
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('عدد الأثمان في الاختبار'), findsOneWidget);
      expect(find.text('بلا توقف بين الأثمان، حتى تُنهيه أنت'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'أثمان'));
      await tester.pumpAndSettle();
      // «إلى» = thumn 3 of hizb 1: the last thumn dropdown.
      await tester.tap(find.byType(DropdownButton<int>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('3. ').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('3 أثمان من'), findsOneWidget);
      // The count of athman to recite is capped by the range (3 here).
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('3 أثمان'), findsOneWidget);

      // Back to surahs: the earlier choice is remembered.
      await tester.tap(find.widgetWithText(ChoiceChip, 'سور'));
      await tester.pumpAndSettle();
      dropdowns = tester.widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>)).toList();
      expect(dropdowns.first.value, 5);
      expect(find.text('سورة المائدة'), findsOneWidget);

      // Steppers: + on the question count (the first stepper now that the
      // range needs none), − on the ayah count.
      expect(find.text('5 أسئلة'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('6 أسئلة'), findsOneWidget);
      expect(find.text('3 آيات'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.remove_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('آيتان'), findsOneWidget);

      await tester.tap(find.text('ابدأ الاختبار'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.range.kind, HifzRangeKind.surahs);
      expect(result!.range.from, 5);
      expect(result!.range.to, 5);
      expect(result!.questions, 6);
      expect(result!.ayahsPerQuestion, 2);
      expect(result!.endless, isFalse);
      expect(result!.source, HifzTestSource.random);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hifz_text_test_config'), contains('"from":5'));
    });

    testWidgets('«الصفحة الحالية» plus the open switch runs to the end; back returns nothing', (tester) async {
      HifzTestConfig? result = const HifzTestConfig();
      await tester.pumpWidget(_host((context) async {
        result = await showHifzTestSetup(
          context,
          silentMode: false,
          mistakesInPool: 7,
          currentPage: 128,
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('كيف يعمل اختبار الحفظ'), findsOneWidget);
      await tester.tap(find.text('فهمت'));
      await tester.pumpAndSettle();
      expect(find.text('اختبار الحفظ'), findsOneWidget);
      expect(find.text('أخطاؤك المسجّلة: 7 مواضع.'), findsOneWidget);
      // The «؟» button brings the guide back; it is not shown again by itself.
      await tester.tap(find.byIcon(Icons.help_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('كيف يعمل اختبار الحفظ'), findsOneWidget);
      await tester.tap(find.text('فهمت'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'من الصفحة الحالية'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'الصفحة الحالية'));
      await tester.pumpAndSettle();
      expect(find.text('الصفحة 128 وحدها.'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('من الصفحة 128 إلى آخر المصحف، بالترتيب.'), findsOneWidget);
      expect(find.text('في الاختبار المفتوح كل صفحة سؤال'), findsOneWidget);
      expect(find.text('في الاختبار المفتوح تأتي الأسئلة بالترتيب من أول النطاق.'), findsOneWidget);

      await tester.tap(find.text('ابدأ الاختبار'));
      await tester.pumpAndSettle();
      expect(result!.endless, isTrue);
      expect(result!.range.kind, HifzRangeKind.currentPage);
      expect(result!.range.onPage(128, endless: true).from, 128);
      expect(result!.range.onPage(128, endless: true).to, 602);
      expect(result!.range.onPage(128).to, 128);

      // Opened again (no guide this time): back leaves without a choice.
      result = const HifzTestConfig();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('كيف يعمل اختبار الحفظ'), findsNothing);
      await tester.pageBack();
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

      // Nothing is chosen yet: going on is not allowed until every ayah is judged.
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'السؤال التالي')).onPressed, isNull);
      // Three ayahs: the «كل الآيات» pair sits first, the ayahs follow.
      expect(find.text('كل الآيات'), findsOneWidget);
      await tester.tap(find.text('صحيح').at(1));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'السؤال التالي')).onPressed, isNull);
      await tester.tap(find.text('خطأ').at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('صحيح').at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('السؤال التالي'));
      await tester.pumpAndSettle();
      expect(j, isNotNull);
      expect(j!.correct, isFalse);
      expect(j!.next, isTrue);
      expect(j!.missed.map((a) => a.ayah), [2]);
    });

    testWidgets('every ayah marked right; the last question leads to the result', (tester) async {
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
      // One tap on the «كل الآيات» pair marks all three right.
      await tester.tap(find.text('صحيح').first);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'النتيجة')).onPressed, isNotNull);
      // ...and one ayah can still be changed after that.
      await tester.tap(find.text('خطأ').at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('صحيح').at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('النتيجة'));
      await tester.pumpAndSettle();
      expect(j!.correct, isTrue);
      expect(j!.missed, isEmpty);
      expect(j!.next, isFalse);
    });

    testWidgets('marking every ayah goes on by itself after a moment', (tester) async {
      HifzSelfJudgement? j;
      await tester.pumpWidget(_host((context) async {
        j = await showHifzSelfJudge(
          context,
          question: question,
          label: 'اختبار 2 / 5',
          hasNext: true,
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('صحيح').first); // «كل الآيات»
      await tester.pump();
      expect(find.text('ينتقل بعد لحظة؛ غيّر ما شئت قبل ذلك.'), findsOneWidget);
      // A change within the moment is kept and restarts it.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('خطأ').at(1));
      await tester.pump(const Duration(milliseconds: 900));
      expect(j, isNull, reason: 'still open: the moment restarted');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(j, isNotNull);
      expect(j!.correct, isFalse);
      expect(j!.missed.map((a) => a.ayah), [1]);
      expect(j!.next, isTrue);
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
      await tester.tap(find.text('تقارير التسميع والأخطاء'));
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

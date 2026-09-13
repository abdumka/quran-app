import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/utils/copy_helper.dart';

void main() {
  const ayahText = 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ';

  group('CopyHelper formatting', () {
    test('an ayah is bracketed and referenced', () {
      expect(
        CopyHelper.formatAyah(
          surahName: 'الفاتحة',
          ayahNumber: 2,
          text: '  $ayahText  ',
        ),
        '﴿ $ayahText ﴾ [الفاتحة: 2]',
      );
    });

    test('ayah + tafsir carries the edition name as attribution', () {
      final text = CopyHelper.formatAyahWithTafsir(
        surahName: 'الفاتحة',
        ayahNumber: 2,
        ayahText: ayahText,
        tafsirText: '  شرح الآية  ',
        editionName: 'تفسير السعدي',
      );
      expect(
        text,
        '﴿ $ayahText ﴾ [الفاتحة: 2]\n\nتفسير السعدي:\nشرح الآية',
      );
    });
  });

  group('CopyHelper.copy', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> pumpCopyButton(WidgetTester tester, String text) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CopyHelper.copy(context, text),
                child: const Text('copy'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('copy'));
      await tester.pump();
    }

    testWidgets('writes to the clipboard and confirms with a toast', (
      tester,
    ) async {
      await pumpCopyButton(tester, 'نص للنسخ');

      final setData = calls.firstWhere(
        (c) => c.method == 'Clipboard.setData',
        orElse: () => const MethodCall('none'),
      );
      expect(setData.method, 'Clipboard.setData');
      expect((setData.arguments as Map)['text'], 'نص للنسخ');

      expect(find.text('تم النسخ'), findsOneWidget);
      // The toast clears itself, so it must not leak a pending timer.
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('تم النسخ'), findsNothing);
    });

    testWidgets('empty text is not copied at all', (tester) async {
      await pumpCopyButton(tester, '   ');
      expect(calls.where((c) => c.method == 'Clipboard.setData'), isEmpty);
    });

    testWidgets('a refused clipboard write offers manual copy', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              throw PlatformException(code: 'denied');
            }
            return null;
          });

      await pumpCopyButton(tester, 'نص للنسخ');
      await tester.pumpAndSettle();

      expect(find.text('انسخ النص يدويًا'), findsOneWidget);
      expect(find.widgetWithText(SelectableText, 'نص للنسخ'), findsOneWidget);
    });
  });
}

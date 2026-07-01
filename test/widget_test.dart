// Smoke test: the app builds and shows the splash screen.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:islamic_dawah_mushaf/main.dart';
import 'package:islamic_dawah_mushaf/splash_screen.dart';

void main() {
  testWidgets('App starts on the splash screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const QuranApp());
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('مصحف الدعوة الاسلامية الجامع'), findsOneWidget);

    // Unmount before flushing the splash's minimum-display timer so the test
    // doesn't navigate into the full reader (which needs platform plugins).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}

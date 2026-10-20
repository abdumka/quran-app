import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/reciter.dart';
import 'package:islamic_dawah_mushaf/services/reciter_service.dart';
import 'package:islamic_dawah_mushaf/widgets/settings/settings_components.dart';

/// The reciter picker must stay a short scrolling menu however many reciters
/// are added, not grow to fill the screen (owner's request, 2026-10-17).
void main() {
  Future<void> openPicker(WidgetTester tester, Reciter selected) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ReciterTile(
            reciters: Reciter.all,
            selected: selected,
            onSelect: (_) {},
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(DropdownButton<Reciter>));
    await tester.pumpAndSettle();
  }

  ScrollPosition menuPosition(WidgetTester tester) => tester
      .state<ScrollableState>(find
          .descendant(
              of: find.byType(ListView).last, matching: find.byType(Scrollable))
          .first)
      .position;

  testWidgets('menu is capped and scrolls instead of filling the screen',
      (tester) async {
    await openPicker(tester, Reciter.all.first);
    final cap = ReciterService.pickerMenuMaxHeight(54);
    expect(tester.getSize(find.byType(ListView).last).height,
        lessThanOrEqualTo(cap));
    expect(Reciter.all.length * 54, greaterThan(cap),
        reason: 'enough reciters that the cap matters');
    expect(menuPosition(tester).maxScrollExtent, greaterThan(0));
  });

  testWidgets('opens scrolled to the selected reciter, even the last one',
      (tester) async {
    final last = Reciter.all.last;
    await openPicker(tester, last);
    expect(menuPosition(tester).pixels, greaterThan(0));
    final row = find.descendant(
        of: find.byType(ListView).last, matching: find.text(last.shortName));
    final menu = tester.getRect(find.byType(ListView).last);
    expect(menu.contains(tester.getCenter(row)), isTrue);
  });
}

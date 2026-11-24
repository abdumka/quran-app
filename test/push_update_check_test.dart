import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/app_update_service.dart';
import 'package:islamic_dawah_mushaf/services/update_check.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _info = AppUpdateInfo(
  latestVersion: '1.6.0',
  latestBuild: 150,
  changes: [],
  storeUrl: 'https://example.com',
  mandatory: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateCheckOutcome.notice', () {
    test('nothing new says so', () {
      const o = UpdateCheckOutcome();
      expect(o.notice, UpdateCheckOutcome.upToDateText);
    });

    test('no connection says so', () {
      const o = UpdateCheckOutcome(failed: true);
      expect(o.notice, UpdateCheckOutcome.failedText);
    });

    test('a store release alone leaves the line to the dialog', () {
      const o = UpdateCheckOutcome(appUpdate: _info);
      expect(o.notice, isNull);
      expect(o.summary, contains('1.6.0'));
    });

    test('installed data is always reported', () {
      const o = UpdateCheckOutcome(
        appUpdate: _info,
        dataMessage: 'تم تحديث الأذكار.',
      );
      expect(o.notice, 'تم تحديث الأذكار.');
      expect(o.summary, 'يوجد إصدار جديد 1.6.0. تم تحديث الأذكار.');
    });
  });

  group('PushUpdateCheck', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PushUpdateCheck.instance.resetForTest();
    });

    test('a cold-start tap waits for the reader, then runs once', () async {
      final runs = <String>[];
      PushUpdateCheck.instance.request('');
      expect(runs, isEmpty);
      PushUpdateCheck.instance.attachRunner((value) async => runs.add(value));
      await Future<void>.delayed(Duration.zero);
      expect(runs, ['']);
      // attaching again (a rebuilt reader) does not replay it
      PushUpdateCheck.instance.attachRunner((value) async => runs.add(value));
      await Future<void>.delayed(Duration.zero);
      expect(runs, ['']);
    });

    test('a second tap while checking changes nothing', () async {
      final gate = Completer<void>();
      var runs = 0;
      PushUpdateCheck.instance.attachRunner((_) async {
        runs++;
        await gate.future;
      });
      PushUpdateCheck.instance.request('');
      PushUpdateCheck.instance.request('');
      await Future<void>.delayed(Duration.zero);
      expect(runs, 1);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      PushUpdateCheck.instance.request(PushUpdateCheck.localTestValue);
      await Future<void>.delayed(Duration.zero);
      expect(runs, 2);
    });

    test('the last run is kept across launches', () async {
      await PushUpdateCheck.instance.record(
        value: PushUpdateCheck.localTestValue,
        result: 'a | b',
      );
      final saved = PushUpdateCheck.instance.lastRun.value!;
      expect(saved.fromLocalTest, isTrue);

      PushUpdateCheck.instance.resetForTest();
      await PushUpdateCheck.instance.load();
      final loaded = PushUpdateCheck.instance.lastRun.value!;
      expect(loaded.result, 'a | b');
      expect(loaded.fromLocalTest, isTrue);
      expect(loaded.timeLabel, saved.timeLabel);
    });
  });

  test('the time is written in Western digits', () {
    final r = PushUpdateCheckRecord(
      at: DateTime(2026, 11, 23, 8, 5),
      fromLocalTest: false,
      result: '',
    );
    expect(r.timeLabel, '2026-11-23 08:05');
    expect(PushUpdateCheckRecord.decode(r.encode())!.fromLocalTest, isFalse);
    expect(PushUpdateCheckRecord.decode('junk'), isNull);
  });
}

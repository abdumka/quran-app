import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/athkar_reminder_service.dart';
import 'package:islamic_dawah_mushaf/services/city_key.dart';
import 'package:islamic_dawah_mushaf/services/city_search_service.dart';
import 'package:islamic_dawah_mushaf/services/sun_times.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tripoli = AthkarPlace(
  name: 'طرابلس',
  lat: 32.897,
  lon: 13.178,
  source: 'city',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = AthkarReminderService.instance;
  const morning = AthkarReminderKind.morning;
  const evening = AthkarReminderKind.evening;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service.debugReset();
    await service.load();
  });

  group('timing', () {
    test('on by default: 50 minutes before sunrise, 30 before sunset', () {
      expect(service.morning.value.on, isTrue);
      expect(service.evening.value.on, isTrue);
      expect(service.morning.value.offset, -50);
      expect(service.evening.value.offset, -30);
      expect(service.morning.value.mode, AthkarReminderMode.sun);
    });

    test('the time follows the sun at the place', () async {
      await service.setPlace(_tripoli);
      final day = DateTime(2026, 6, 21);
      final sun = SunTimes.of(2026, 6, 21, _tripoli.lat, _tripoli.lon);
      expect(
        service.fireTime(morning, day),
        sun.sunrise!.toLocal().subtract(const Duration(minutes: 50)),
      );
      expect(
        service.fireTime(evening, day),
        sun.sunset!.toLocal().subtract(const Duration(minutes: 30)),
      );
    });

    test('10-minute steps, within -90..+30 (morning) and -90..+60', () async {
      await service.moveOffset(morning, -10);
      expect(service.morning.value.offset, -60);
      for (var i = 0; i < 10; i++) {
        await service.moveOffset(morning, -10);
      }
      expect(service.morning.value.offset, -90);
      for (var i = 0; i < 20; i++) {
        await service.moveOffset(morning, 10);
        await service.moveOffset(evening, 10);
      }
      expect(service.morning.value.offset, 30);
      expect(service.evening.value.offset, 60);
    });

    test('«وقت محدد» starts at today\'s sun time rounded to 10 minutes', () async {
      await service.setPlace(_tripoli);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final sunBased = service.fireTime(morning, today);
      await service.setMode(morning, AthkarReminderMode.fixed);
      final m = service.morning.value.fixedMinutes;
      expect(m % 10, 0);
      expect(
        (m - (sunBased.hour * 60 + sunBased.minute)).abs(),
        lessThanOrEqualTo(5),
      );
      await service.setFixedMinutes(morning, 7 * 60 + 15);
      expect(service.fireTime(morning, today), DateTime(now.year, now.month, now.day, 7, 15));
    });

    test('no place yet, or no sunrise at all: the fixed fallback', () async {
      final day = DateTime(2026, 6, 21);
      expect(service.fireTime(morning, day), DateTime(2026, 6, 21, 6, 30));
      expect(service.fireTime(evening, day), DateTime(2026, 6, 21, 16, 30));
      await service.setPlace(
        const AthkarPlace(name: 'ترومسو', lat: 69.65, lon: 18.96, source: 'city'),
      );
      expect(service.fireTime(morning, day), DateTime(2026, 6, 21, 6, 30));
    });

    test('the next reminder is in the future, and none when off', () async {
      await service.setPlace(_tripoli);
      final now = DateTime.now();
      expect(service.nextFire(morning)!.isAfter(now), isTrue);
      await service.setEnabled(morning, false);
      expect(service.nextFire(morning), isNull);
    });

    test('settings and the place survive a restart', () async {
      await service.setPlace(_tripoli);
      await service.moveOffset(evening, -10);
      await service.setEnabled(morning, false);
      service.debugReset();
      await service.load();
      expect(service.place.value, _tripoli);
      expect(service.evening.value.offset, -40);
      expect(service.morning.value.on, isFalse);
    });
  });

  group('the notification', () {
    test('a tap opens its athkar', () {
      service.handleTap('evening');
      expect(service.pendingOpen.value, evening);
    });

    test('«إيقاف» turns that reminder off and says so', () async {
      service.handleTap('morning#stop');
      await pumpEventQueue();
      expect(service.morning.value.on, isFalse);
      expect(service.evening.value.on, isTrue);
      expect(service.stoppedFromNotification.value, morning);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('athkarReminder.morning.on'), isFalse);
    });
  });

  group('cities', () {
    final cities = CitySearchService.instance;

    test('Libya\'s cities are in the app, found in Arabic or English', () async {
      final all = await cities.libya('');
      expect(all.length, greaterThanOrEqualTo(50));
      expect(all.first.name, 'طرابلس');
      expect((await cities.libya('الخمس')).first.name, 'الخمس');
      expect((await cities.libya('خمس')).first.name, 'الخمس');
      expect((await cities.libya('misrata')).first.name, 'مصراتة');
      expect((await cities.libya('رقدالين')).single.name, 'رقدالين');
      // «ال» while it is still being typed
      expect(CitySearchService.queryWords('الخ'), ['خ']);
      expect(
        (await cities.libya('الخ')).map((r) => r.name),
        contains('الخمس'),
      );
    });

    test('online: the 2-letter file, then a longer one when it says more', () async {
      final asked = <String>[];
      cities.fetch = (uri) async {
        asked.add(uri.pathSegments.last);
        if (uri.pathSegments.last == '${CityKey.prefixFile('lo')}.json') {
          return json.encode({'e': [], 'more': true});
        }
        return json.encode({
          'e': [
            ['لندن', 'London', 'GB', 'إنجلترا', 51.508, -0.126],
            ['لونغ بيتش', 'Long Beach', 'US', 'كاليفورنيا', 33.767, -118.189],
          ],
          'more': false,
        });
      };
      final found = await cities.online('Lond');
      expect(asked, [
        '${CityKey.prefixFile('lo')}.json',
        '${CityKey.prefixFile('lon')}.json',
      ]);
      expect(found.single.name, 'لندن');
      expect(found.single.detail, 'إنجلترا، المملكة المتحدة');
    });

    test('the phone\'s location is named from the list, never sent', () async {
      var near = await cities.placeForLocation(32.17, 13.03);
      expect(near.name, 'موقعي، غريان');
      expect(near.source, 'gps');
      near = await cities.placeForLocation(32.3, 13.2);
      expect(near.name, startsWith('موقعي، قرب'));
      final far = await cities.placeForLocation(51.5, -0.12);
      expect(far.name, 'موقعي الحالي');
    });

    test('before a place is set: the main city of the time zone', () async {
      final z = await cities.zonePlace('Africa/Tripoli');
      expect(z!.name, 'طرابلس');
      expect(z.source, 'zone');
      expect((await cities.zonePlace('Asia/Kuwait'))!.name, 'الكويت');
      expect(await cities.zonePlace('Nowhere/Else'), isNull);
    });
  });
}

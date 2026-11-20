import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/sun_times.dart';

void main() {
  // Reference instants from the astral Python package (UTC), an independent
  // implementation. Within 2 minutes is all a reminder needs.
  void near(DateTime? got, String want, String what) {
    expect(got, isNotNull, reason: what);
    final diff = got!.difference(DateTime.parse('${want}Z')).inSeconds.abs();
    expect(diff, lessThan(120), reason: '$what: $got vs $want');
  }

  test('Libya through the year', () {
    var t = SunTimes.of(2026, 6, 21, 32.897, 13.178);
    near(t.sunrise, '2026-06-21T03:59:36', 'Tripoli June sunrise');
    near(t.sunset, '2026-06-21T18:18:35', 'Tripoli June sunset');
    t = SunTimes.of(2026, 12, 21, 32.897, 13.178);
    near(t.sunrise, '2026-12-21T06:06:07', 'Tripoli December sunrise');
    near(t.sunset, '2026-12-21T16:04:33', 'Tripoli December sunset');
    t = SunTimes.of(2026, 3, 20, 27.04, 14.43);
    near(t.sunrise, '2026-03-20T05:06:34', 'Sabha sunrise');
    near(t.sunset, '2026-03-20T17:13:16', 'Sabha sunset');
    t = SunTimes.of(2026, 11, 20, 24.96, 10.18);
    near(t.sunrise, '2026-11-20T05:39:25', 'Ghat sunrise');
    near(t.sunset, '2026-11-20T16:30:05', 'Ghat sunset');
  });

  test('the local day, far east and far west of Greenwich', () {
    // Sydney's morning of 15 January is the evening of the 14th in UTC
    var t = SunTimes.of(2026, 1, 15, -33.87, 151.21);
    near(t.sunrise, '2026-01-14T18:59:43', 'Sydney sunrise');
    near(t.sunset, '2026-01-15T09:08:45', 'Sydney sunset');
    // Honolulu's evening of 10 August is the 11th in UTC
    t = SunTimes.of(2026, 8, 10, 21.31, -157.86);
    near(t.sunrise, '2026-08-10T16:08:33', 'Honolulu sunrise');
    near(t.sunset, '2026-08-11T05:04:40', 'Honolulu sunset');
    t = SunTimes.of(2026, 7, 1, 51.508, -0.125);
    near(t.sunrise, '2026-07-01T03:47:56', 'London sunrise');
    near(t.sunset, '2026-07-01T20:20:31', 'London sunset');
  });

  test('no sunset in a polar summer', () {
    final t = SunTimes.of(2026, 6, 21, 69.65, 18.96);
    expect(t.sunrise, isNull);
    expect(t.sunset, isNull);
  });
}

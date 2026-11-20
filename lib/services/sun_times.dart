import 'dart:math' as math;

/// Sunrise and sunset from a place's latitude and longitude, on the phone,
/// with no internet: NOAA's solar calculator (the sun's upper edge at the
/// horizon with the usual refraction, zenith 90.833°). Good to about a minute
/// below the polar circles, which is all a reminder needs.
class SunTimes {
  SunTimes._();

  static const double _zenith = 90.833;

  /// Sunrise and sunset of the local day [year]/[month]/[day] at [lat], [lon]
  /// (degrees, east positive), as UTC instants. Null where the sun does not
  /// rise or does not set that day (near the poles).
  static ({DateTime? sunrise, DateTime? sunset}) of(
    int year,
    int month,
    int day,
    double lat,
    double lon,
  ) {
    final jd = _julianDay(year, month, day);
    final midnight = DateTime.utc(year, month, day);
    DateTime? at(bool rise) {
      final minutes = _eventUtcMinutes(rise, jd, lat, lon);
      if (minutes == null) return null;
      return midnight.add(Duration(milliseconds: (minutes * 60000).round()));
    }

    return (sunrise: at(true), sunset: at(false));
  }

  /// Minutes after 0h UTC of the date, refined once at the event itself.
  static double? _eventUtcMinutes(bool rise, double jd, double lat, double lon) {
    final first = _utcMinutes(rise, _centuries(jd), lat, lon);
    if (first == null) return null;
    return _utcMinutes(rise, _centuries(jd + first / 1440.0), lat, lon);
  }

  static double? _utcMinutes(bool rise, double t, double lat, double lon) {
    final eqTime = _equationOfTime(t);
    final decl = _declination(t);
    final latR = _rad(lat), declR = _rad(decl);
    final arg =
        math.cos(_rad(_zenith)) / (math.cos(latR) * math.cos(declR)) -
        math.tan(latR) * math.tan(declR);
    if (arg.abs() > 1) return null;
    var hourAngle = _deg(math.acos(arg));
    if (!rise) hourAngle = -hourAngle;
    return 720 - 4.0 * (lon + hourAngle) - eqTime;
  }

  static double _julianDay(int year, int month, int day) {
    var y = year, m = month;
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = (y / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (y + 4716)).floorToDouble() +
        (30.6001 * (m + 1)).floorToDouble() +
        day +
        b -
        1524.5;
  }

  static double _centuries(double jd) => (jd - 2451545.0) / 36525.0;

  static double _meanLongitude(double t) {
    var l0 = 280.46646 + t * (36000.76983 + t * 0.0003032);
    l0 %= 360;
    return l0 < 0 ? l0 + 360 : l0;
  }

  static double _meanAnomaly(double t) =>
      357.52911 + t * (35999.05029 - 0.0001537 * t);

  static double _eccentricity(double t) =>
      0.016708634 - t * (0.000042037 + 0.0000001267 * t);

  static double _equationOfCenter(double t) {
    final m = _rad(_meanAnomaly(t));
    return math.sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        math.sin(2 * m) * (0.019993 - 0.000101 * t) +
        math.sin(3 * m) * 0.000289;
  }

  static double _apparentLongitude(double t) {
    final trueLong = _meanLongitude(t) + _equationOfCenter(t);
    final omega = 125.04 - 1934.136 * t;
    return trueLong - 0.00569 - 0.00478 * math.sin(_rad(omega));
  }

  static double _obliquity(double t) {
    final seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813));
    final e0 = 23.0 + (26.0 + seconds / 60.0) / 60.0;
    final omega = 125.04 - 1934.136 * t;
    return e0 + 0.00256 * math.cos(_rad(omega));
  }

  static double _declination(double t) => _deg(
    math.asin(math.sin(_rad(_obliquity(t))) * math.sin(_rad(_apparentLongitude(t)))),
  );

  /// Minutes.
  static double _equationOfTime(double t) {
    final epsilon = _obliquity(t);
    final l0 = _rad(_meanLongitude(t));
    final e = _eccentricity(t);
    final m = _rad(_meanAnomaly(t));
    var y = math.tan(_rad(epsilon) / 2);
    y *= y;
    final eTime =
        y * math.sin(2 * l0) -
        2 * e * math.sin(m) +
        4 * e * y * math.sin(m) * math.cos(2 * l0) -
        0.5 * y * y * math.sin(4 * l0) -
        1.25 * e * e * math.sin(2 * m);
    return _deg(eTime) * 4;
  }

  static double _rad(double d) => d * math.pi / 180;
  static double _deg(double r) => r * 180 / math.pi;
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'city_key.dart';

/// A place the athkar reminders can be timed for.
@immutable
class AthkarPlace {
  const AthkarPlace({
    required this.name,
    required this.lat,
    required this.lon,
    required this.source,
    this.detail = '',
  });

  /// As shown: «طرابلس», «موقعي، قرب غريان», «موقعي الحالي».
  final String name;
  final double lat;
  final double lon;

  /// 'city' (picked from the list), 'gps' (the phone's location) or 'zone'
  /// (the main city of the phone's time zone, used until one is set).
  final String source;

  /// The line under the name: «الجبل الغربي، ليبيا».
  final String detail;

  Map<String, Object> toJson() => {
    'name': name,
    'lat': lat,
    'lon': lon,
    'source': source,
    'detail': detail,
  };

  static AthkarPlace? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'], lat = json['lat'], lon = json['lon'];
    if (name is! String || lat is! num || lon is! num) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return AthkarPlace(
      name: name,
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      source: json['source'] is String ? json['source'] as String : 'city',
      detail: json['detail'] is String ? json['detail'] as String : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AthkarPlace &&
      other.name == name &&
      other.lat == lat &&
      other.lon == lon &&
      other.source == source;

  @override
  int get hashCode => Object.hash(name, lat, lon, source);
}

/// One line of the city list.
@immutable
class CityResult {
  const CityResult({
    required this.name,
    required this.detail,
    required this.lat,
    required this.lon,
  });

  final String name;
  final String detail;
  final double lat;
  final double lon;

  AthkarPlace toPlace() =>
      AthkarPlace(name: name, lat: lat, lon: lon, source: 'city', detail: detail);
}

/// The cities for the athkar reminders, with almost nothing added to the app
/// and almost nothing downloaded (owner, 2026-11-19):
/// * inside the app, Libya's main cities (assets/data/cities_ly.json, about
///   60, picked and reviewed by the owner), so a Libyan finds his city with
///   no internet;
/// * on our server, every Libyan place and every town in the world over 5,000
///   people, split into small files by the first letters of each word
///   (`cities/v1/p/<letters>.json`, mostly under 1 KB). The app fetches the one
///   file for what is being typed, only while it is typed.
/// * the main city of each time zone (assets/data/tz_places.json), the place
///   used before the reader picks one.
///
/// The phone's own location is never sent anywhere (owner, 2026-11-19): the
/// times are worked out on the phone, and the place is named from the list
/// inside the app.
class CitySearchService {
  CitySearchService._();
  static final CitySearchService instance = CitySearchService._();

  static const String serverBase =
      'https://quran-content.mushaf-qaloon.com/cities/v1/p/';

  /// Tests replace the network.
  @visibleForTesting
  Future<String> Function(Uri uri) fetch = _httpGet;

  List<_Town>? _libya;
  Map<String, String>? _countries;
  Map<String, List<Object?>>? _zones;
  Future<void>? _loading;
  final Map<String, Future<_PrefixFile>> _files = {};

  Future<void> _load() => _loading ??= () async {
    final ly = json.decode(await rootBundle.loadString('assets/data/cities_ly.json'));
    _libya = [
      for (final p in (ly['places'] as List))
        _Town(
          name: p[0] as String,
          english: p[1] as String,
          lat: (p[2] as num).toDouble(),
          lon: (p[3] as num).toDouble(),
          detail: _join(p[4] as String, 'ليبيا'),
        ),
    ];
    _countries = (json.decode(
      await rootBundle.loadString('assets/data/countries_ar.json'),
    ) as Map).cast<String, String>();
    _zones = (json.decode(
      await rootBundle.loadString('assets/data/tz_places.json'),
    ) as Map).cast<String, List<Object?>>();
  }();

  /// Libya's cities inside the app; all of them for an empty [query].
  Future<List<CityResult>> libya(String query) async {
    await _load();
    final q = queryWords(query);
    return [
      for (final t in _libya!)
        if (q.isEmpty || _matches(q, [t.name, t.english])) t.result,
    ];
  }

  /// Every town on the server that matches [query] (Libya included), biggest
  /// first. Throws when the server cannot be reached.
  Future<List<CityResult>> online(String query) async {
    await _load();
    final q = queryWords(query);
    final lead = q.isEmpty ? '' : q.reduce((a, b) => b.length > a.length ? b : a);
    if (lead.length < 2) return const [];
    var file = await _file(lead.substring(0, 2));
    for (var n = 3; file.more && n <= math.min(lead.length, 4); n++) {
      file = await _file(lead.substring(0, n));
    }
    final out = <CityResult>[];
    for (final e in file.entries) {
      final ar = _plain(e[0] as String? ?? '');
      final en = e[1] as String? ?? '';
      if (!_matches(q, [ar, en])) continue;
      final cc = e[2] as String? ?? '';
      out.add(
        CityResult(
          name: ar.isNotEmpty ? ar : en,
          detail: _join(_plain(e[3] as String? ?? ''), _countries![cc] ?? cc),
          lat: (e[4] as num).toDouble(),
          lon: (e[5] as num).toDouble(),
        ),
      );
    }
    return out;
  }

  /// The place to use before the reader sets one: the main city of the time
  /// zone named [zoneId] (Africa/Tripoli: طرابلس).
  Future<AthkarPlace?> zonePlace(String zoneId) async {
    await _load();
    final z = _zones![zoneId];
    if (z == null || z.length < 3) return null;
    return AthkarPlace(
      name: (z[0] as String?) ?? '',
      lat: (z[1] as num).toDouble(),
      lon: (z[2] as num).toDouble(),
      source: 'zone',
    );
  }

  /// The place for the phone's own location: named after the nearest of the
  /// Libyan cities inside the app when one is close, else «موقعي الحالي».
  Future<AthkarPlace> placeForLocation(double lat, double lon) async {
    await _load();
    _Town? best;
    var bestKm = double.infinity;
    for (final t in _libya!) {
      final d = kmBetween(lat, lon, t.lat, t.lon);
      if (d < bestKm) {
        bestKm = d;
        best = t;
      }
    }
    final name = best != null && bestKm <= 40
        ? (bestKm < 5 ? 'موقعي، ${best.name}' : 'موقعي، قرب ${best.name}')
        : 'موقعي الحالي';
    return AthkarPlace(
      name: name,
      lat: _round(lat),
      lon: _round(lon),
      source: 'gps',
      detail: best != null && bestKm <= 40 ? best.detail : '',
    );
  }

  /// The words a query searches for. A word starting «ال» that is still too
  /// short to lose it (the key drops «ال» from words of 4+ letters) also
  /// matches without it, so «الخ» already finds «الخمس» while it is typed.
  static List<String> queryWords(String query) => [
    for (final w in CityKey.words(query))
      if (w.startsWith('ال') && w.length < 4 && w.length > 2)
        w.substring(2)
      else if (w != 'ال')
        w,
  ];

  static bool _matches(List<String> query, List<String> names) {
    final words = [for (final n in names) ...CityKey.words(n)];
    return query.every((q) => words.any((w) => w.startsWith(q)));
  }

  Future<_PrefixFile> _file(String prefix) {
    final cached = _files[prefix];
    if (cached != null) return cached;
    final future = () async {
      final body = await fetch(
        Uri.parse('$serverBase${CityKey.prefixFile(prefix)}.json'),
      );
      final data = json.decode(body) as Map;
      return _PrefixFile(
        (data['e'] as List).cast<List<dynamic>>(),
        data['more'] == true,
      );
    }();
    _files[prefix] = future;
    // a failed fetch is tried again next time instead of being remembered
    future.catchError((_) {
      _files.remove(prefix);
      return const _PrefixFile([], false);
    });
    return future;
  }

  static Future<String> _httpGet(Uri uri) async {
    final r = await http.get(uri).timeout(const Duration(seconds: 8));
    // a prefix nobody's name starts with has no file
    if (r.statusCode == 404) return '{"e":[],"more":false}';
    if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}', uri);
    return utf8.decode(r.bodyBytes);
  }

  static String _join(String a, String b) =>
      [a, b].where((s) => s.isNotEmpty).toSet().join('، ');

  static final RegExp _harakat = RegExp('[ً-ْ]');
  static String _plain(String s) => s.replaceAll(_harakat, '');

  /// About 100 m: more is not needed for the sun, and the place is stored.
  static double _round(double v) => (v * 1000).roundToDouble() / 1000;

  static double kmBetween(double a, double b, double c, double d) {
    const r = math.pi / 180;
    final x =
        math.pow(math.sin((c - a) * r / 2), 2) +
        math.cos(a * r) * math.cos(c * r) * math.pow(math.sin((d - b) * r / 2), 2);
    return 12742 * math.asin(math.sqrt(x));
  }
}

class _Town {
  _Town({
    required this.name,
    required this.english,
    required this.lat,
    required this.lon,
    required this.detail,
  });

  final String name;
  final String english;
  final double lat;
  final double lon;
  final String detail;

  CityResult get result =>
      CityResult(name: name, detail: detail, lat: lat, lon: lon);
}

class _PrefixFile {
  const _PrefixFile(this.entries, this.more);
  final List<List<dynamic>> entries;
  final bool more;
}

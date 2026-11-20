import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/city_key.dart';

void main() {
  // Written by C:/Down/Cities/pipeline/gen_dart_citykey.py from the server's
  // own key (citykey.py), which named the online city files.
  final vectors =
      (json.decode(File('test/data/city_key_vectors.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();

  test('the app\'s city key is the server\'s, letter for letter', () {
    expect(vectors.length, greaterThan(500));
    for (final v in vectors) {
      final name = v['name'] as String;
      expect(CityKey.words(name), v['words'], reason: name);
      expect(CityKey.key(name), v['key'], reason: name);
      final k = v['key'] as String;
      if (k.length >= 2) {
        expect(CityKey.prefixFile(k.substring(0, 2)), v['file'], reason: name);
      }
    }
  });

  test('hamza, ة and «ال» do not matter', () {
    expect(CityKey.key('إجدابيا'), CityKey.key('اجدابيا'));
    expect(CityKey.key('الخمس'), CityKey.key('خمس'));
    expect(CityKey.key('Az Zāwīyah'), 'zawiyah');
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/content_update_service.dart';
import 'package:islamic_dawah_mushaf/services/share/share_video_config.dart';

void main() {
  final bundled = File('assets/data/share_video.json').readAsStringSync();

  test('the bundled config parses and matches bundledVersions', () {
    final c = ShareVideoConfig.parse(bundled);
    expect(c.ver, ContentUpdateService.bundledVersions['share_video']);
    expect(c.backgrounds.length, greaterThanOrEqualTo(59));
    expect(c.shapes.map((s) => s.id), containsAll(['9x16', '1x1', '16x9']));
    expect(c.effects.map((e) => e.id), ['none', 'echo', 'room', 'hall']);
    expect(c.background(c.defaultBackground), isNotNull);
    expect(c.textTemplate, contains('{text}'));
    expect(RegExp('[٠-٩۰-۹]').hasMatch(bundled), isFalse);
  });

  Map<String, dynamic> base() => jsonDecode(bundled) as Map<String, dynamic>;

  test('a link off our hosts is refused', () {
    final j = base()..['link'] = 'https://example.com/';
    expect(() => ShareVideoConfig.parse(jsonEncode(j)), throwsFormatException);
  });

  test('a background missing a shape is refused', () {
    final j = base();
    ((j['backgrounds'] as List).first as Map)['files'].remove('1x1');
    expect(() => ShareVideoConfig.parse(jsonEncode(j)), throwsFormatException);
  });

  test('a path that climbs out of the folder is refused', () {
    final j = base();
    ((j['backgrounds'] as List).first as Map)['thumb'] = '../secret.jpg';
    expect(() => ShareVideoConfig.parse(jsonEncode(j)), throwsFormatException);
  });

  test('an unknown effect type is refused', () {
    final j = base();
    (j['effects'] as List).add({'id': 'x', 'title': 'x', 'type': 'pitch'});
    expect(() => ShareVideoConfig.parse(jsonEncode(j)), throwsFormatException);
  });

  test('out-of-range look numbers are clamped, not trusted', () {
    final j = base();
    (j['video'] as Map)['dim'] = 5;
    (j['video'] as Map)['maxAyat'] = -3;
    final c = ShareVideoConfig.parse(jsonEncode(j));
    expect(c.video.dim, 0.9);
    expect(c.video.maxAyat, 1);
  });

  test('title pictures give a 3-digit path per surah', () {
    final j = base();
    ((j['video'] as Map)['title'] as Map)['images'] =
        'surah_titles/v1/{surah}.png';
    final c = ShareVideoConfig.parse(jsonEncode(j));
    expect(c.video.titleImageFor(2), 'surah_titles/v1/002.png');
    expect(c.video.titleImageFor(114), 'surah_titles/v1/114.png');
  });

  test('a title picture path that climbs out falls back to text', () {
    final j = base();
    ((j['video'] as Map)['title'] as Map)['images'] = '../x/{surah}.png';
    final c = ShareVideoConfig.parse(jsonEncode(j));
    expect(c.video.titleImageFor(1), isNull);
    expect(c.video.titleTemplate, contains('{surah}'));
  });

  test('switches default to on', () {
    final j = base()
      ..remove('enabled')
      ..remove('videoEnabled');
    final c = ShareVideoConfig.parse(jsonEncode(j));
    expect(c.enabled, isTrue);
    expect(c.videoEnabled, isTrue);
  });
}

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
    // ver 3: the 41 forward-only loops the owner kept on 2026-11-18
    expect(c.backgrounds.length, greaterThanOrEqualTo(41));
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

  test('without the server switches, video is on everywhere', () {
    final c = ShareVideoConfig.parse(bundled);
    expect(c.videoOn(platform: 'android', build: 160), isTrue);
    expect(c.videoOn(platform: 'ios', build: 160), isTrue);
    expect(c.album, ShareVideoConfig.defaultAlbum);
    expect(c.strings, isEmpty);
  });

  test('the server can switch the video off per platform and per build', () {
    final j = base()
      ..['videoPlatforms'] = ['android']
      ..['videoOffBuilds'] = [158];
    final c = ShareVideoConfig.parse(jsonEncode(j));
    expect(c.videoOn(platform: 'ios', build: 160), isFalse);
    expect(c.videoOn(platform: 'android', build: 160), isTrue);
    expect(c.videoOn(platform: 'android', build: 158), isFalse);
    // an arm64 split APK reports 2000 + build
    expect(c.videoOn(platform: 'android', build: 2158), isFalse);
  });

  test('server wording replaces the built-in text, placeholders filled', () {
    final j = base()
      ..['strings'] = {'limitAyat': 'حد الآيات {n}', 'bad': 5, 'empty': '  '};
    final c = ShareVideoConfig.parse(jsonEncode(j));
    expect(c.strings.keys, ['limitAyat']);
    ShareVideoConfig.debugSet(c);
    expect(
      ShareVideoConfig.tr('limitAyat', 'x {n}', {'n': 30}),
      'حد الآيات 30',
    );
    expect(ShareVideoConfig.tr('other', 'نص {n}', {'n': 2}), 'نص 2');
    ShareVideoConfig.debugSet(null);
    expect(ShareVideoConfig.tr('limitAyat', 'x {n}', {'n': 30}), 'x 30');
  });

  test('colours, title position, icon and album come from the server', () {
    final j = base()..['album'] = 'ألبوم';
    final v = j['video'] as Map;
    v['colors'] = {
      'title': '#112233',
      'closingTop': '#80FFFFFF',
      'closingText': 'pink',
    };
    v['icon'] = 'share_icon/v1/icon.png';
    (v['title'] as Map)['top'] = 0.1;
    final c = ShareVideoConfig.parse(jsonEncode(j));
    expect(c.album, 'ألبوم');
    expect(c.video.titleColor, 0xFF112233);
    expect(c.video.closingTop, 0x80FFFFFF);
    expect(c.video.closingText, 0xFFF6ECD6); // not a colour: default kept
    expect(c.video.icon, 'share_icon/v1/icon.png');
    expect(c.video.titleTop, 0.1);
  });

  test(
    'an icon path that climbs out and an album with a slash are ignored',
    () {
      final j = base()..['album'] = '../x';
      (j['video'] as Map)['icon'] = '../icon.png';
      final c = ShareVideoConfig.parse(jsonEncode(j));
      expect(c.video.icon, isNull);
      expect(c.album, ShareVideoConfig.defaultAlbum);
    },
  );
}

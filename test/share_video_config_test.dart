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
    expect(
      c.shapes.map((s) => s.id),
      containsAll(['9x16', '4x5', '1x1', '16x9']),
    );
    // ver 4: the reciter line and its fonts (owner's list, 2026-11-19)
    expect(c.video.showCredit, isTrue);
    expect(c.video.creditTemplate, contains('{reciter}'));
    expect(c.fonts.length, greaterThanOrEqualTo(25));
    expect(c.defaultFont, 'naskh');
    expect(c.fontNone, isTrue);
    expect(c.font('system')!.isSystem, isTrue);
    expect(c.font('thuluth')!.scale, 1.5);
    for (final f in c.fonts.where((f) => !f.isSystem)) {
      expect(f.preview, isNotNull, reason: f.id);
      expect(f.bytes, greaterThan(0), reason: f.id);
    }
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

  test('«السورة كاملة» is off until the server turns it on', () {
    final off = ShareVideoConfig.parse(bundled).video;
    expect(off.wholeSurahOn('android'), isFalse);
    expect(off.wholeSurahOn('ios'), isFalse);
    expect(off.wholeSurahMaxSeconds, ShareVideoLook.wholeSurahCeiling);

    ShareVideoLook look(Object? on, [Object? max]) {
      final j = base();
      final v = j['video'] as Map;
      v['wholeSurah'] = on;
      if (max != null) v['wholeSurahMaxSeconds'] = max;
      return ShareVideoConfig.parse(jsonEncode(j)).video;
    }

    expect(look(true).wholeSurahOn('android'), isTrue);
    expect(look(true).wholeSurahOn('ios'), isTrue);
    final android = look(['android', 'web', 7]);
    expect(android.wholeSurahOn('android'), isTrue);
    expect(android.wholeSurahOn('ios'), isFalse);
    expect(look('yes').wholeSurahOn('android'), isFalse);
    // short surahs first: 30 minutes
    expect(look(true, 1800).wholeSurahMaxSeconds, 1800);
    // never past 3 hours, never under a minute
    expect(look(true, 99999).wholeSurahMaxSeconds, 10800);
    expect(look(true, 5).wholeSurahMaxSeconds, 60);
    // the bitrate of a whole surah: the normal one unless the server says
    expect(off.wholeSurahBitrate, off.bitrate);
    final j = base();
    (j['video'] as Map)['wholeSurahBitrate'] = 2500000;
    final low = ShareVideoConfig.parse(jsonEncode(j)).video;
    expect(low.wholeSurahBitrate, 2500000);
    expect(low.bitrate, 5000000);
  });

  test('the stepper limit can go up to 3 hours, no further', () {
    final j = base();
    (j['video'] as Map)['maxSeconds'] = 50000;
    expect(ShareVideoConfig.parse(jsonEncode(j)).video.maxSeconds, 10800);
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

  test('without credit or fonts the video has no reciter line', () {
    final j = base()..remove('fonts');
    (j['video'] as Map).remove('credit');
    final c = ShareVideoConfig.parse(jsonEncode(j));
    expect(c.video.showCredit, isFalse);
    expect(c.fonts, isEmpty);
    expect(c.defaultFont, 'system');
  });

  test('a bad font entry is dropped, not the whole config', () {
    final j = base();
    j['fonts'] = {
      'default': 'gone',
      'allowNone': true,
      'list': [
        {'id': 'ok', 'title': 'نسخ', 'file': 'fonts/v1/ok.ttf', 'scale': 9},
        {'id': 'Bad Id', 'title': 'x', 'file': 'fonts/v1/x.ttf'},
        {'id': 'climb', 'title': 'x', 'file': '../x.ttf'},
        {'id': 'notitle', 'file': 'fonts/v1/y.ttf'},
        {'id': 'ok', 'title': 'twice'},
        {'id': 'system', 'title': 'خط الهاتف'},
      ],
    };
    final c = ShareVideoConfig.parse(jsonEncode(j));
    expect(c.fonts.map((f) => f.id), ['ok', 'system']);
    expect(c.font('ok')!.scale, 3.0); // clamped
    expect(c.defaultFont, 'ok'); // the unknown default falls to the first
    expect(c.fontSample, ShareVideoConfig.defaultFontSample);
  });

  test('the reciter line numbers are clamped', () {
    final j = base();
    (j['video'] as Map)['credit'] = {
      'template': '{reciter}',
      'size': 1,
      'opacity': 0,
    };
    final c = ShareVideoConfig.parse(jsonEncode(j));
    expect(c.video.showCredit, isTrue);
    expect(c.video.creditTemplate, '{reciter}');
    expect(c.video.creditSize, 0.06);
    expect(c.video.creditOpacity, 0.2);
    expect(c.video.creditSizes, [0.8, 1.0, 1.25]); // the default three
    // no halo numbers = the first soft shadow
    expect(c.video.creditHalo, 0);
    expect(c.video.creditHaloWide, 0);
    expect(c.video.creditDrop, 0);
  });

  test('the reciter line halo comes from the server, clamped', () {
    ShareVideoLook look(Map<String, Object?> credit) {
      final j = base();
      (j['video'] as Map)['credit'] = credit;
      return ShareVideoConfig.parse(jsonEncode(j)).video;
    }

    final half = look({'halo': 0.5, 'drop': 0.45});
    expect(half.creditHalo, 0.5);
    expect(half.creditHaloWide, closeTo(0.35, 1e-9)); // 0.7 of the halo
    expect(half.creditDrop, 0.45);
    final thin = look({'halo': 0.6, 'haloWide': 0});
    expect(thin.creditHaloWide, 0);
    final wild = look({'halo': 7, 'haloWide': -1, 'drop': 'x'});
    expect(wild.creditHalo, 1);
    expect(wild.creditHaloWide, 0);
    expect(wild.creditDrop, 0);
  });

  test('the three sizes of the reciter line come from the server', () {
    List<double> sizes(Object? v) {
      final j = base();
      (j['video'] as Map)['credit'] = {'sizes': v};
      return ShareVideoConfig.parse(jsonEncode(j)).video.creditSizes;
    }

    expect(sizes([0.7, 1, 1.4]), [0.7, 1.0, 1.4]);
    // a wrong list keeps the defaults: not three, not growing, out of range
    expect(sizes([0.8, 1]), [0.8, 1.0, 1.25]);
    expect(sizes([1.2, 1, 0.8]), [0.8, 1.0, 1.25]);
    expect(sizes([0.1, 1, 5]), [0.8, 1.0, 1.25]);
    expect(sizes('big'), [0.8, 1.0, 1.25]);
  });
}

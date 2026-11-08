import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/content_update_service.dart';
import 'package:islamic_dawah_mushaf/services/tanzilat_paint_service.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/tanzilat_overlay.dart';

/// The picture pack (build_tanzilat_paint.py): the colours exactly as the
/// reviewers' brush painted them, one indexed PNG per page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = File('assets/data/tanzilat_paint.bin').readAsBytesSync();
  final pack = TanzilatPaintPack.parse(bytes);
  final tanzilat =
      json.decode(File('assets/data/tanzilat.json').readAsStringSync())
          as Map<String, dynamic>;

  test('the pack names the versions this build carries', () {
    expect(pack.ver, ContentUpdateService.bundledVersions['tanzilat_paint']);
    expect(pack.tanzilatVer, tanzilat['ver']);
    expect(pack.tanzilatVer, ContentUpdateService.bundledVersions['tanzilat']);
    expect(() => ContentUpdateService.validatePaintPack(bytes), returnsNormally);
  });

  test('every page with a coloured word has a picture', () {
    final coloured = <(int, int, int)>{
      for (final g in tanzilat['groups'] as List<dynamic>)
        for (final r in (g as Map<String, dynamic>)['rows'] as List<dynamic>)
          for (final p in (r as Map<String, dynamic>)['p'] as List<dynamic>)
            for (final i in (p as List<dynamic>)[2] as List<dynamic>)
              (p[0] as int, p[1] as int, i as int),
    };
    final masks =
        json.decode(File('assets/data/word_masks.json').readAsStringSync())
            as List<dynamic>;
    final have = pack.pages.toSet();
    final missing = <int>[];
    for (final m in masks) {
      final page = m as Map<String, dynamic>;
      final ayahs = [
        ...page['ayahs'] as List<dynamic>,
        if (page['cont'] != null) page['cont'],
      ];
      var any = false;
      for (final a in ayahs) {
        final words = (a as Map<String, dynamic>)['words'] as List<dynamic>;
        for (var i = 0; i < words.length; i++) {
          if ((words[i] as List<dynamic>).isNotEmpty &&
              coloured.contains((a['surah'] as int, a['ayah'] as int, i))) {
            any = true;
          }
        }
      }
      if (any && !have.contains(page['page'])) missing.add(page['page'] as int);
    }
    expect(missing, isEmpty);
    expect(have.length, greaterThan(500));
  });

  test('a bad pack is refused', () {
    expect(
      () => TanzilatPaintPack.parse(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
      throwsFormatException,
    );
    expect(
      () => ContentUpdateService.validatePaintPack(Uint8List(3)),
      throwsFormatException,
    );
    // the header says more than the file has
    final short = Uint8List.fromList(bytes.sublist(0, 40));
    expect(() => TanzilatPaintPack.parse(short), throwsFormatException);
  });

  test('recolouring rejects a picture that is not ours', () {
    expect(recolourPng(Uint8List(64), const [Colors.red]), isNull);
    final png = pack.pngOf(2)!;
    // five buckets are stored; a different number cannot be swapped in
    expect(recolourPng(png, const [Colors.red]), isNull);
  });

  testWidgets('a page decodes in the chosen colours, paper transparent', (
    tester,
  ) async {
    final colours = TanzilatColors.paintedBuckets(dark: false, byCount: false);
    final out = await tester.runAsync(() async {
      final png = recolourPng(pack.pngOf(2)!, colours)!;
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      codec.dispose();
      final data = await frame.image.toByteData();
      return (frame.image, data!);
    });
    final (image, data) = out!;
    expect(image.width, greaterThan(500));
    final seen = <int>{};
    var transparent = 0;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      final a = data.getUint8(i + 3);
      if (a == 0) {
        transparent++;
      } else {
        seen.add(
          (data.getUint8(i) << 16) | (data.getUint8(i + 1) << 8) | data.getUint8(i + 2),
        );
      }
    }
    // the one-colour setting: every coloured pixel is the one red
    expect(seen, {0xD50000});
    expect(transparent, greaterThan(data.lengthInBytes ~/ 8));
    // and it draws, in the margin view's part of the scan too
    await tester.pumpWidget(
      SizedBox(
        width: 400,
        height: 800,
        child: CustomPaint(
          painter: TanzilatPicturePainter(
            image,
            const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('the dark page paints the inverse of the wanted colour', () {
    final dark = TanzilatColors.paintedBuckets(dark: true, byCount: true);
    expect(dark.length, TanzilatColors.dark.length);
    expect(dark[0], TanzilatColors.inverted(TanzilatColors.dark[0]));
    final one = TanzilatColors.paintedBuckets(dark: true, byCount: false);
    expect(one.toSet(), {TanzilatColors.inverted(TanzilatColors.singleDark)});
  });
}

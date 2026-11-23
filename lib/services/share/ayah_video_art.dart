import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../models/ayah_region_data.dart';
import '../../models/word_region_data.dart';
import '../ayah_region_service.dart';
import '../quran_json_service.dart';
import '../word_region_service.dart';
import 'share_video_config.dart';

/// The pictures of «فيديو الآية», drawn on the phone:
///
///  * [ayatImage]: the ayat cut out of the mushaf page itself (the real
///    calligraphy, not a font), white ink on transparency, line by line as
///    the page has them, with the page's own gold ayah marker. Every word
///    keeps its place inside its line, so letters never drift apart.
///  * [framePng]: one full video frame over the background: a dimming
///    layer, the surah title, the ayat and the app's watermark.
///  * [closingPng]: the 2-second card at the end.
///
/// All wording and numbers come from [ShareVideoLook] (server item).
class AyahVideoArt {
  AyahVideoArt._();

  static const String iconAsset = 'assets/images/share_app_icon.png';

  // ───────────────────── the mushaf text ─────────────────────

  /// [ayat] of [surah] (one recited group) as one picture, in the page
  /// scan's own pixels. Null when the page data has no place for them.
  static Future<ui.Image?> ayatImage(int surah, List<int> ayat) async {
    final pages = await QuranJsonService.loadQuranPages();
    final words = await WordRegionService.loadAll();
    final regions = await AyahRegionService.loadAll();

    final lines = <_Line>[];
    for (final ayah in ayat) {
      int? page;
      for (final p in pages) {
        if (p.ayahs.any((a) => a.surah == surah && a.ayah == ayah)) {
          page = p.page;
          break;
        }
      }
      if (page == null) continue;
      // An ayah printed across a page break starts at the foot of the page
      // before (its `continuing` / `cont` part).
      final before = regions[page - 1]?.continuing;
      if (before != null && before.surah == surah && before.ayah == ayah) {
        final w = words[page - 1]?.continued;
        _addLines(lines, page - 1, before, w?.ayah == ayah ? w : null);
      }
      final region = regions[page]?.ayahs
          .where((r) => r.surah == surah && r.ayah == ayah)
          .firstOrNull;
      if (region == null) continue;
      final w = words[page]?.ayahs
          .where((x) => x.surah == surah && x.ayah == ayah)
          .firstOrNull;
      _addLines(lines, page, region, w);
    }
    if (lines.isEmpty) return null;
    lines.sort((a, b) {
      final c = a.page.compareTo(b.page);
      return c != 0 ? c : a.band.center.dy.compareTo(b.band.center.dy);
    });

    // Pixel geometry per page.
    final images = <int, ui.Image>{};
    final geo = <int, _PageGeo>{};
    for (final l in lines) {
      if (images.containsKey(l.page)) continue;
      final img = await _pageImage(l.page);
      images[l.page] = img;
      final data = words[l.page];
      final hw = data?.marginRect ?? const Rect.fromLTWH(0, 0, 1, 1);
      geo[l.page] = _PageGeo(
        Rect.fromLTWH(
          hw.left * img.width,
          hw.top * img.height,
          hw.width * img.width,
          hw.height * img.height,
        ),
        data?.paper ?? const Color(0xFFF6EEDB),
      );
    }

    // Layout: each line centred, at its own height on its page; a new page
    // starts a little below the last line.
    final placed = <(_Line, Rect, Offset)>[];
    double width = 0;
    double bottom = 0;
    int? curPage;
    double base = 0;
    for (final l in lines) {
      final g = geo[l.page]!;
      final bounds = l.pixelBounds(g.crop);
      if (curPage != l.page) {
        base =
            (curPage == null ? 0 : bottom + bounds.height * 0.15) - bounds.top;
        curPage = l.page;
      }
      final y = bounds.top + base;
      bottom = math.max(bottom, y + bounds.height);
      width = math.max(width, bounds.width);
      placed.add((l, bounds, Offset(0, y)));
    }
    if (width < 1 || bottom < 1) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final (line, bounds, at) in placed) {
      final g = geo[line.page]!;
      final img = images[line.page]!;
      final dx = (width - bounds.width) / 2 - bounds.left;
      final dy = at.dy - bounds.top;
      canvas.save();
      canvas.translate(dx, dy);
      // A word box is a rectangle, so it also holds whatever ink of the line
      // above or below reaches into it. Those pieces have boxes of their own:
      // cut them out (the other lines of this video, and any other ayah's
      // words printed on another line of the page).
      final foreign = Path();
      final foreignRects = <Rect>[];
      var anyForeign = false;
      void addForeign(Rect r) {
        final px = _px(r, g.crop).inflate(1);
        if (!px.overlaps(bounds)) return;
        foreign.addRect(px);
        foreignRects.add(px);
        anyForeign = true;
      }

      for (final o in lines) {
        if (identical(o, line) || o.page != line.page) continue;
        o.parts.forEach(addForeign);
      }
      for (final a in words[line.page]?.allAyahs ?? const <WordRegionAyah>[]) {
        if (a.surah == surah && ayat.contains(a.ayah)) continue;
        for (final wb in a.words) {
          if (wb.parts.isEmpty) continue;
          final box = wb.parts.reduce((x, y) => x.expandToInclude(y));
          final cy = box.center.dy;
          if (cy >= line.band.top && cy <= line.band.bottom) continue;
          wb.parts.forEach(addForeign);
        }
      }
      final clip = Path();
      for (final r in line.parts) {
        final px = _px(r, g.crop);
        // A small piece that sits mostly inside another line's word is that
        // word's ink, listed under ours by the word-box data (15:65 had the
        // top of 15:66's alif): left out, or it floats between the lines.
        if (_isSmallPiece(r) && _covered(px, foreignRects) >= 0.3) continue;
        clip.addRect(px.inflate(2));
      }
      canvas.save();
      canvas.clipPath(
        anyForeign
            ? Path.combine(PathOperation.difference, clip, foreign)
            : clip,
      );
      canvas.drawImageRect(
        img,
        bounds,
        bounds,
        Paint()
          ..filterQuality = FilterQuality.high
          ..colorFilter = _inkToWhite(g.paper),
      );
      canvas.restore();
      for (final m in line.markers) {
        final sq = _markerSquare(m, g.crop);
        canvas.save();
        canvas.clipPath(Path()..addOval(sq.deflate(sq.width * 0.02)));
        canvas.drawImageRect(
          img,
          sq,
          sq,
          Paint()
            ..filterQuality = FilterQuality.high
            ..colorFilter = _markerToGold(g.paper),
        );
        canvas.restore();
      }
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final out = await picture.toImage(width.ceil(), bottom.ceil());
    picture.dispose();
    for (final i in images.values) {
      i.dispose();
    }
    return out;
  }

  static void _addLines(
    List<_Line> lines,
    int page,
    AyahRegion region,
    WordRegionAyah? words,
  ) {
    if (region.rects.isEmpty) return;
    final own = <_Line>[
      for (final r in region.rects)
        _Line(page, Rect.fromLTWH(r.x, r.y, r.width, r.height)),
    ];
    _Line nearest(double y) {
      var best = own.first;
      var dist = double.infinity;
      for (final l in own) {
        final d = y >= l.band.top && y <= l.band.bottom
            ? 0.0
            : (y - l.band.center.dy).abs();
        if (d < dist) {
          dist = d;
          best = l;
        }
      }
      return best;
    }

    // The line a whole word belongs to: the one its ink overlaps most in
    // height. Going piece by piece split words whose marks reach into the
    // line above (25:73 «وعميانا»: its top was drawn with the line before,
    // left behind as stray marks when each line was centred).
    _Line lineOf(Rect box) {
      _Line? best;
      var most = 0.0;
      for (final l in own) {
        if (box.right <= l.band.left || box.left >= l.band.right) continue;
        final o =
            math.min(box.bottom, l.band.bottom) - math.max(box.top, l.band.top);
        if (o > most) {
          most = o;
          best = l;
        }
      }
      return best ?? nearest(box.center.dy);
    }

    for (final w in words?.words ?? const <WordBox>[]) {
      // A piece outside every line of the ayah is the page's frame rule,
      // not a letter (25:73 had a sliver of it at the right edge).
      final parts = [
        for (final p in w.parts)
          if (own.any(
            (l) =>
                p.right > l.band.left - _strayMargin &&
                p.left < l.band.right + _strayMargin,
          ))
            p,
      ];
      if (parts.isEmpty) continue;
      final box = parts.reduce((a, b) => a.expandToInclude(b));
      lineOf(box).parts.addAll(parts);
    }
    final m = region.marker;
    if (m != null) {
      final mr = Rect.fromLTWH(m.x, m.y, m.width, m.height);
      nearest(mr.center.dy).markers.add(mr);
    }
    final hasWords = own.any((l) => l.parts.isNotEmpty);
    for (final l in own) {
      // A line band holding none of the ayah's words is the region data's
      // sliver at the end of the line before (229 ayat; 110:1 had one on
      // 109:6's line, so the video kept the header and basmala as empty
      // space above the ayah): left out.
      if (l.parts.isEmpty && l.markers.isEmpty && hasWords) continue;
      // No word boxes for this ayah: fall back to the line's own band.
      if (l.parts.isEmpty) l.parts.add(l.band);
      // The same printed line already holds the ayah before (an ayah that
      // ends mid-line): one line, not two.
      final same = lines.where(
        (x) =>
            x.page == page &&
            (x.band.center.dy - l.band.center.dy).abs() <
                math.min(x.band.height, l.band.height) * 0.5,
      );
      if (same.isNotEmpty) {
        final x = same.first;
        x.band = x.band.expandToInclude(l.band);
        x.parts.addAll(l.parts);
        x.markers.addAll(l.markers);
      } else {
        lines.add(l);
      }
    }
  }

  /// A diacritic-sized piece (share of the page): never a letter's body.
  static bool _isSmallPiece(Rect r) => r.width < 0.03 && r.height < 0.03;

  /// The share of [r] that lies inside any of [others] (overlaps counted
  /// once per rectangle; good enough for a yes/no threshold).
  static double _covered(Rect r, List<Rect> others) {
    final area = r.width * r.height;
    if (area <= 0) return 0;
    var inside = 0.0;
    for (final o in others) {
      final i = r.intersect(o);
      if (i.width > 0 && i.height > 0) inside += i.width * i.height;
    }
    return math.min(1, inside / area);
  }

  /// How far (share of the page width) a word piece may stick out of its
  /// ayah's line box and still count as a letter.
  static const double _strayMargin = 0.012;

  static Rect _px(Rect r, Rect crop) => Rect.fromLTWH(
    crop.left + r.left * crop.width,
    crop.top + r.top * crop.height,
    r.width * crop.width,
    r.height * crop.height,
  );

  static Rect _markerSquare(Rect m, Rect crop) {
    final px = _px(m, crop);
    final side = math.max(px.width, px.height) * 1.2;
    return Rect.fromCenter(center: px.center, width: side, height: side);
  }

  static double _lum(Color c) =>
      0.299 * (c.r * 255) + 0.587 * (c.g * 255) + 0.114 * (c.b * 255);

  /// Ink to white, paper to transparent: alpha grows with how much darker
  /// than the paper a pixel is.
  static ColorFilter _inkToWhite(Color paper) {
    final p = _lum(paper);
    final k = 255 / math.max(40, p - 60);
    return ColorFilter.matrix(<double>[
      0, 0, 0, 0, 255, //
      0, 0, 0, 0, 255, //
      0, 0, 0, 0, 255, //
      -k * 0.299, -k * 0.587, -k * 0.114, 0, k * (p - 12),
    ]);
  }

  /// The ayah marker keeps its own gold, lightened so it reads on a dark
  /// video; its paper goes transparent.
  static ColorFilter _markerToGold(Color paper) {
    final p = _lum(paper);
    const k = 255 / 45;
    return ColorFilter.matrix(<double>[
      0.6, 0, 0, 0, 102, //
      0, 0.6, 0, 0, 102, //
      0, 0, 0.6, 0, 102, //
      -k * 0.299, -k * 0.587, -k * 0.114, 0, k * (p - 8),
    ]);
  }

  static Future<ui.Image> _pageImage(int page) async {
    final data = await rootBundle.load('assets/images/page_$page.webp');
    return _decode(data.buffer.asUint8List());
  }

  /// A picture file (the surah title cut from the mushaf).
  static Future<ui.Image?> decodeFile(File f) async {
    try {
      return await _decode(await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<ui.Image> _icon() async =>
      _decode((await rootBundle.load(iconAsset)).buffer.asUint8List());

  // ───────────────────── the frames ─────────────────────

  /// One full frame (PNG) laid over the moving background.
  static Future<Uint8List> framePng({
    required int width,
    required int height,
    required String shapeId,
    required ShareVideoLook look,
    required ui.Image? ayat,
    required String? title,
    ui.Image? titleImage,
    ui.Image? iconImage,
    String? credit,
    String? creditFont,
    double creditScale = 1,
  }) async {
    final gold = Color(look.titleColor);
    final w = width.toDouble();
    final h = height.toDouble();
    final unit = math.min(w, h);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Offset.zero & Size(w, h),
      Paint()..color = Color.fromRGBO(0, 0, 0, look.dim),
    );

    var top = h * (look.titleTop - 0.005);
    if (look.showTitle && titleImage != null) {
      // The surah name in the mushaf's own hand (white ink, tinted cream),
      // with a soft shadow so it reads on bright skies too.
      final iw = titleImage.width.toDouble();
      final ih = titleImage.height.toDouble();
      var scale = unit * look.titleImageHeight / ih;
      if (iw * scale > w * look.titleImageMaxWidth) {
        scale = w * look.titleImageMaxWidth / iw;
      }
      final dst = Rect.fromLTWH(
        (w - iw * scale) / 2,
        h * look.titleTop,
        iw * scale,
        ih * scale,
      );
      final src = Rect.fromLTWH(0, 0, iw, ih);
      canvas.drawImageRect(
        titleImage,
        src,
        dst.shift(Offset(0, unit * 0.002)),
        Paint()
          ..filterQuality = FilterQuality.high
          ..colorFilter = const ColorFilter.mode(
            Color(0x8C000000),
            BlendMode.srcIn,
          )
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: unit * 0.006,
            sigmaY: unit * 0.006,
          ),
      );
      canvas.drawImageRect(
        titleImage,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.high
          ..colorFilter = ColorFilter.mode(gold, BlendMode.srcIn),
      );
      top = dst.bottom;
    } else if (look.showTitle && title != null && title.isNotEmpty) {
      final p = _paragraph(title, unit * 0.04, gold, FontWeight.w600, w);
      final pw = p.longestLine;
      final chip = Rect.fromCenter(
        center: Offset(w / 2, h * (look.titleTop + 0.01) + p.height / 2),
        width: pw + unit * 0.06,
        height: p.height + unit * 0.018,
      );
      final rr = RRect.fromRectAndRadius(chip, Radius.circular(chip.height));
      canvas.drawRRect(rr, Paint()..color = const Color(0x2E000000));
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, unit * 0.0022)
          ..color = gold.withValues(alpha: 0.55),
      );
      canvas.drawParagraph(
        p,
        Offset((w - p.width) / 2, chip.top + unit * 0.009),
      );
      top = chip.bottom;
    }

    if (credit != null && credit.trim().isNotEmpty) {
      // The reciter and the riwayah, small and soft under the surah name,
      // in the font the sharer picked ([creditFont] is null for the phone's
      // own font, or when the picked one could not be loaded).
      final p = _paragraph(
        credit,
        unit * look.creditSize * creditScale,
        const Color(0xFFFFFFFF).withValues(alpha: look.creditOpacity),
        FontWeight.w400,
        w * 0.9,
        fontFamily: creditFont,
        shadows: _creditShadows(look, unit),
        maxLines: 2,
      );
      final y =
          (look.showTitle ? top : h * look.titleTop) + unit * look.creditGap;
      canvas.drawParagraph(p, Offset((w - p.width) / 2, y));
      top = y + p.height;
    }

    var markTop = h;
    ui.Image? ownIcon;
    if (look.showWatermark) {
      final icon = iconImage ?? (ownIcon = await _icon());
      markTop = _drawWatermark(canvas, w, h, unit, look, icon);
    }

    if (ayat != null) {
      final maxW = w * look.textWidth;
      final maxH = math.min(
        h * look.textHeightFor(shapeId),
        markTop - top - unit * 0.06,
      );
      final s = math.min(
        math.min(maxW / ayat.width, maxH / ayat.height),
        look.textMaxScale * unit / 1080,
      );
      final dw = ayat.width * s;
      final dh = ayat.height * s;
      final cy = (top + markTop) / 2;
      final dst = Rect.fromLTWH((w - dw) / 2, cy - dh / 2, dw, dh);
      final src =
          Offset.zero & Size(ayat.width.toDouble(), ayat.height.toDouble());
      if (look.textBackdrop > 0) {
        // A soft dark veil behind the block evens out a busy background.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            dst.inflate(unit * 0.035),
            Radius.circular(unit * 0.05),
          ),
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, look.textBackdrop)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.03),
        );
      }
      if (look.textHalo > 0) {
        // A dark halo hugging every letter: a tight one twice (it reads as
        // an outline) and a wide soft one, so white ink stays clear even on
        // gold embroidery, sky or snow.
        Paint halo(double alpha, double sigma) => Paint()
          ..filterQuality = FilterQuality.high
          ..colorFilter = ColorFilter.mode(
            Color.fromRGBO(0, 0, 0, alpha.clamp(0, 1)),
            BlendMode.srcIn,
          )
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
        final tight = halo(look.textHalo, math.max(1.2, unit * 0.0022));
        canvas.drawImageRect(ayat, src, dst, tight);
        canvas.drawImageRect(ayat, src, dst, tight);
        canvas.drawImageRect(
          ayat,
          src,
          dst,
          halo(look.textHalo * 0.7, math.max(3, unit * 0.008)),
        );
      } else {
        canvas.drawImageRect(
          ayat,
          src,
          dst.shift(Offset(2 * s, 4 * s)),
          Paint()
            ..filterQuality = FilterQuality.high
            ..colorFilter = const ColorFilter.mode(
              Color(0xBF000000),
              BlendMode.srcIn,
            )
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              math.max(2, 6 * s),
            ),
        );
      }
      canvas.drawImageRect(
        ayat,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    final bytes = await _png(recorder, width, height);
    ownIcon?.dispose();
    return bytes;
  }

  /// The reciter line's shadow ([ShareVideoLook.creditHalo]): the ayat's
  /// halo made small and light, sized by the frame like theirs.
  static List<Shadow> _creditShadows(ShareVideoLook look, double unit) {
    if (look.creditHalo <= 0 &&
        look.creditHaloWide <= 0 &&
        look.creditDrop <= 0) {
      return const [
        Shadow(color: Color(0xBF000000), blurRadius: 6),
        Shadow(color: Color(0x80000000), blurRadius: 2),
      ];
    }
    // Shadow takes a blur radius; the halos are thought of as a Gaussian
    // sigma, like the ayat's (sigma = radius * 0.57735 + 0.5).
    double radius(double sigma) => sigma <= 0.5 ? 0 : (sigma - 0.5) / 0.57735;
    Color black(double a) => Color.fromRGBO(0, 0, 0, a.clamp(0, 1));
    final tight = radius(math.max(1.2, unit * 0.0015));
    return [
      if (look.creditHalo > 0) ...[
        Shadow(color: black(look.creditHalo), blurRadius: tight),
        Shadow(color: black(look.creditHalo), blurRadius: tight),
      ],
      if (look.creditHaloWide > 0)
        Shadow(
          color: black(look.creditHaloWide),
          blurRadius: radius(math.max(2.5, unit * 0.0046)),
        ),
      if (look.creditDrop > 0)
        Shadow(
          color: black(look.creditDrop),
          offset: Offset(0, math.max(1, unit * 0.0019)),
          blurRadius: radius(math.max(1.2, unit * 0.0019)),
        ),
    ];
  }

  /// Icon, name and link at the foot; returns the top of the mark.
  static double _drawWatermark(
    Canvas canvas,
    double w,
    double h,
    double unit,
    ShareVideoLook look,
    ui.Image icon,
  ) {
    final color = const Color(
      0xFFFFFFFF,
    ).withValues(alpha: look.watermarkOpacity);
    final name = _paragraph(
      look.watermarkName,
      unit * 0.03,
      color,
      FontWeight.w600,
      w,
    );
    final link = _paragraph(
      look.watermarkLink,
      unit * 0.024,
      const Color(0xFFFFFFFF).withValues(alpha: look.watermarkOpacity * 0.78),
      FontWeight.w400,
      w,
      rtl: false,
    );
    final iconSize = unit * 0.05;
    final gap = unit * 0.016;
    final rowW =
        iconSize +
        gap +
        name.longestLine +
        (look.watermarkLink.isEmpty ? 0 : gap + link.longestLine);
    final rowH = math.max(iconSize, name.height);
    final cy = h - unit * 0.05 - rowH / 2;
    // Right to left: icon, name, link.
    var x = (w + rowW) / 2;
    final iconRect = Rect.fromLTWH(
      x - iconSize,
      cy - iconSize / 2,
      iconSize,
      iconSize,
    );
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(iconRect, Radius.circular(iconSize * 0.22)),
    );
    canvas.drawImageRect(
      icon,
      Offset.zero & Size(icon.width.toDouble(), icon.height.toDouble()),
      iconRect,
      Paint()
        ..filterQuality = FilterQuality.high
        ..color = Color.fromRGBO(255, 255, 255, look.watermarkOpacity),
    );
    canvas.restore();
    x -= iconSize + gap;
    canvas.drawParagraph(
      name,
      Offset(
        x - name.longestLine - (name.width - name.longestLine) / 2,
        cy - name.height / 2,
      ),
    );
    x -= name.longestLine + gap;
    if (look.watermarkLink.isNotEmpty) {
      canvas.drawParagraph(
        link,
        Offset(
          x - link.longestLine - (link.width - link.longestLine) / 2,
          cy - link.height / 2,
        ),
      );
    }
    return cy - rowH / 2;
  }

  /// The closing card: opaque, so it hides the background.
  static Future<Uint8List> closingPng({
    required int width,
    required int height,
    required ShareVideoLook look,
    ui.Image? iconImage,
  }) async {
    final w = width.toDouble();
    final h = height.toDouble();
    final unit = math.min(w, h);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & Size(w, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
          Color(look.closingTop),
          Color(look.closingBottom),
        ]),
    );
    final cream = Color(look.closingText);
    final ownIcon = iconImage == null ? await _icon() : null;
    final icon = iconImage ?? ownIcon!;
    final title = _paragraph(
      look.closingTitle,
      unit * 0.06,
      cream,
      FontWeight.w700,
      w,
    );
    final sub = look.closingSubtitle.isEmpty
        ? null
        : _paragraph(
            look.closingSubtitle,
            unit * 0.034,
            cream.withValues(alpha: 0.85),
            FontWeight.w400,
            w * 0.9,
          );
    final stores = [
      for (final s in look.closingStores)
        _paragraph(s, unit * 0.03, cream, FontWeight.w500, w, rtl: false),
    ];
    final link = look.closingLink.isEmpty
        ? null
        : _paragraph(
            look.closingLink,
            unit * 0.028,
            cream.withValues(alpha: 0.7),
            FontWeight.w400,
            w,
            rtl: false,
          );

    final iconSize = unit * 0.2;
    final gap = unit * 0.03;
    final chipPadX = unit * 0.026;
    final chipPadY = unit * 0.012;
    final chipH = stores.isEmpty ? 0.0 : stores.first.height + 2 * chipPadY;
    final total =
        iconSize +
        gap +
        title.height +
        (sub == null ? 0 : gap * 0.5 + sub.height) +
        (stores.isEmpty ? 0 : gap * 1.2 + chipH) +
        (link == null ? 0 : gap * 0.8 + link.height);
    var y = (h - total) / 2;

    final iconRect = Rect.fromLTWH((w - iconSize) / 2, y, iconSize, iconSize);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(iconRect, Radius.circular(iconSize * 0.22)),
    );
    canvas.drawImageRect(
      icon,
      Offset.zero & Size(icon.width.toDouble(), icon.height.toDouble()),
      iconRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    y += iconSize + gap;
    canvas.drawParagraph(title, Offset(0, y));
    y += title.height;
    if (sub != null) {
      y += gap * 0.5;
      canvas.drawParagraph(sub, Offset(w * 0.05, y));
      y += sub.height;
    }
    if (stores.isNotEmpty) {
      y += gap * 1.2;
      final widths = [for (final s in stores) s.longestLine + 2 * chipPadX];
      final rowW =
          widths.reduce((a, b) => a + b) + gap * 0.5 * (stores.length - 1);
      var x = (w - rowW) / 2;
      for (var i = 0; i < stores.length; i++) {
        final chip = Rect.fromLTWH(x, y, widths[i], chipH);
        canvas.drawRRect(
          RRect.fromRectAndRadius(chip, Radius.circular(chipH * 0.3)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, unit * 0.002)
            ..color = cream.withValues(alpha: 0.5),
        );
        final s = stores[i];
        canvas.drawParagraph(
          s,
          Offset(chip.center.dx - s.width / 2, chip.top + chipPadY),
        );
        x += widths[i] + gap * 0.5;
      }
      y += chipH;
    }
    if (link != null) {
      y += gap * 0.8;
      canvas.drawParagraph(link, Offset(0, y));
    }
    final bytes = await _png(recorder, width, height);
    ownIcon?.dispose();
    return bytes;
  }

  static ui.Paragraph _paragraph(
    String text,
    double size,
    Color color,
    FontWeight weight,
    double width, {
    bool rtl = true,
    String? fontFamily,
    List<Shadow> shadows = const [
      Shadow(color: Color(0x66000000), blurRadius: 4),
    ],
    int maxLines = 3,
  }) {
    final b =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              fontSize: size,
              fontWeight: weight,
              fontFamily: fontFamily,
              maxLines: maxLines,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: size,
              fontWeight: weight,
              fontFamily: fontFamily,
              shadows: shadows,
            ),
          )
          ..addText(text);
    return b.build()..layout(ui.ParagraphConstraints(width: width));
  }

  static Future<Uint8List> _png(ui.PictureRecorder r, int w, int h) async {
    final picture = r.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// [seconds] of 16-bit stereo silence at 44.1 kHz, as a WAV file.
  static Uint8List silenceWav(double seconds) {
    const rate = 44100;
    const channels = 2;
    final frames = (seconds * rate).round();
    final dataBytes = frames * channels * 2;
    final b = ByteData(44 + dataBytes);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, channels, Endian.little);
    b.setUint32(24, rate, Endian.little);
    b.setUint32(28, rate * channels * 2, Endian.little);
    b.setUint16(32, channels * 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    b.setUint32(40, dataBytes, Endian.little);
    return b.buffer.asUint8List();
  }
}

class _Line {
  _Line(this.page, this.band);
  final int page;
  Rect band;
  final List<Rect> parts = [];
  final List<Rect> markers = [];

  /// Where this line's ink (and marker) sits in the page scan's pixels.
  Rect pixelBounds(Rect crop) {
    Rect? u;
    for (final p in parts) {
      final r = AyahVideoArt._px(p, crop).inflate(4);
      u = u == null ? r : u.expandToInclude(r);
    }
    for (final m in markers) {
      final r = AyahVideoArt._markerSquare(m, crop);
      u = u == null ? r : u.expandToInclude(r);
    }
    return u ?? AyahVideoArt._px(band, crop);
  }
}

class _PageGeo {
  const _PageGeo(this.crop, this.paper);
  final Rect crop;
  final Color paper;
}

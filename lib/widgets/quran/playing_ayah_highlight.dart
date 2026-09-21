import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/ayah_region_data.dart';
import '../../models/word_region_data.dart';
import '../../services/audio_service.dart';
import '../../services/ayah_region_service.dart';
import '../../services/word_region_service.dart';

/// Whether the ayah being recited is highlighted on the page (on by
/// default; the choice is in the Tilawah options sheet).
class PlayingAyahHighlightSetting {
  static const String _prefKey = 'highlightPlayingAyah';
  static final ValueNotifier<bool> enabled = ValueNotifier(true);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_prefKey) ?? true;
  }

  static Future<void> set(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }
}

/// Tints the lines of the ayah the recitation is on, leaving its text fully
/// readable: the tint is multiplied into the page, so the paper takes the
/// colour and the ink stays as dark as it was.
///
/// Placed like `MemorizationTestOverlay`: inside the box that renders the
/// page `Image` (`BoxFit.fill`), under the reader's `ColorFiltered`, so ratio
/// coordinates map straight onto the image. The dark theme inverts the page
/// there, which is why [dark] picks a tint that comes out warm after the
/// inversion.
class PlayingAyahHighlight extends StatelessWidget {
  const PlayingAyahHighlight({
    super.key,
    required this.pageNumber,
    required this.dark,
    this.marginView = false,
  });

  /// 1-based mushaf page this sits on.
  final int pageNumber;
  final bool dark;

  /// True when the box shows the margin-view image: the page sits inside it
  /// at the placement `word_masks.json` records.
  final bool marginView;

  static final Map<int, Future<(AyahRegionPageData?, WordRegionPageData?)>>
  _cache = {};

  @override
  Widget build(BuildContext context) {
    final audio = AudioService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        audio.currentAyah,
        audio.isRecitationBarVisible,
        PlayingAyahHighlightSetting.enabled,
      ]),
      builder: (context, _) {
        final playing = audio.currentAyah.value;
        if (playing == null ||
            !audio.isRecitationBarVisible.value ||
            !PlayingAyahHighlightSetting.enabled.value) {
          return const SizedBox.shrink();
        }
        final future = _cache.putIfAbsent(pageNumber, () async {
          final r = await AyahRegionService.forPage(pageNumber);
          final w = await WordRegionService.forPage(pageNumber);
          return (r, w);
        });
        if (_cache.length > 8) _cache.remove(_cache.keys.first);
        return FutureBuilder<(AyahRegionPageData?, WordRegionPageData?)>(
          future: future,
          builder: (context, snap) {
            final regions = snap.data?.$1;
            final margin = marginView ? snap.data?.$2?.marginRect : null;
            if (regions == null || (marginView && margin == null)) {
              return const SizedBox.shrink();
            }
            final rects = <Rect>[
              for (final a in regions.ayahs)
                if (a.surah == playing.surah && a.ayah == playing.ayah)
                  for (final r in a.rects)
                    Rect.fromLTWH(r.x, r.y, r.width, r.height),
            ];
            if (rects.isEmpty) return const SizedBox.shrink();
            return IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: PlayingAyahHighlightPainter(rects, margin, dark),
              ),
            );
          },
        );
      },
    );
  }
}

class PlayingAyahHighlightPainter extends CustomPainter {
  const PlayingAyahHighlightPainter(this.rects, this.margin, this.dark);

  /// Line rects of the ayah, as ratios of the page image.
  final List<Rect> rects;
  final Rect? margin;
  final bool dark;

  // Light: paper x this = a soft gold. Dark: the page is inverted after this
  // layer, so paper comes out as roughly (255 - this): a dim warm band.
  static const Color lightTint = Color(0xFFFFE9A8);
  static const Color darkTint = Color(0xFFBEC8E6);

  /// The painted boxes in pixels for a page box of [size].
  List<Rect> boxes(Size size) {
    final out = <Rect>[];
    for (final r in rects) {
      var left = r.left;
      var top = r.top;
      var right = r.right;
      var bottom = r.bottom;
      final m = margin;
      if (m != null) {
        left = m.left + left * m.width;
        right = m.left + right * m.width;
        top = m.top + top * m.height;
        bottom = m.top + bottom * m.height;
      }
      // The band is trimmed a little: the marks of the neighbouring lines
      // reach into the rect and should not be tinted with this ayah.
      final h = (bottom - top) * size.height;
      out.add(
        Rect.fromLTRB(
          left * size.width,
          top * size.height + h * 0.08,
          right * size.width,
          bottom * size.height - h * 0.04,
        ),
      );
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dark ? darkTint : lightTint
      ..blendMode = BlendMode.multiply;
    for (final box in boxes(size)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(6)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PlayingAyahHighlightPainter old) =>
      old.rects != rects || old.margin != margin || old.dark != dark;
}

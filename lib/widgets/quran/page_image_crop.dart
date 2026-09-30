import 'package:flutter/widgets.dart';

import '../../data/page_crops.dart';

/// Shows only the frame interior of a full هوامش page image.
///
/// The app bundles one image per page: the complete scan with its margins.
/// With the margin view off, the reader wants the same box the old
/// margin-less images showed, so this widget draws [child] (the full page
/// image, `BoxFit.fill`) into a box scaled such that the page's [PageCrop]
/// rect lands exactly on this widget's own bounds, and clips the rest away.
///
/// Because the clipped pixels are never part of this widget's box, nothing
/// outside the crop can be revealed by zooming, panning, or the Hifz
/// magnifier; and because the crop is the same rect the margin-view overlays
/// use, the ayah/word ratio coordinates measured against this box line up
/// exactly as they did against the old images.
///
/// With [enabled] false the child is returned untouched (margin view on).
class PageImageCrop extends StatelessWidget {
  const PageImageCrop({
    super.key,
    required this.page,
    required this.enabled,
    required this.child,
  });

  /// 1-based page number.
  final int page;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final crop = PageCrop.forPage(page);
    return ClipRect(
      child: CustomPaint(
        foregroundPainter: _FrameLineCover(crop),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boxW = constraints.maxWidth;
            final boxH = constraints.maxHeight;
            // Size of the full image once the crop rect fills this box.
            final fullW = boxW / crop.width;
            final fullH = boxH / crop.height;
            return ColoredBox(
              // Page 1's rect runs a sliver past the scan's right edge; the
              // paper colour fills it so no page-background seam shows.
              color: crop.paper,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: fullW,
                maxWidth: fullW,
                minHeight: fullH,
                maxHeight: fullH,
                child: Transform.translate(
                  offset: Offset(-crop.left * fullW, -crop.top * fullH),
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints paper over the strips where the frame's line reaches into the crop,
/// so the box never shows in the cropped view — at any zoom.
class _FrameLineCover extends CustomPainter {
  const _FrameLineCover(this.crop);

  final PageCrop crop;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = crop.paper;
    final left = crop.trimLeft * size.width;
    final top = crop.trimTop * size.height;
    final right = crop.trimRight * size.width;
    final bottom = crop.trimBottom * size.height;
    if (left > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, left, size.height), paint);
    }
    if (right > 0) {
      canvas.drawRect(
        Rect.fromLTWH(size.width - right, 0, right, size.height),
        paint,
      );
    }
    if (top > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), paint);
    }
    if (bottom > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - bottom, size.width, bottom),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FrameLineCover oldDelegate) => oldDelegate.crop != crop;
}

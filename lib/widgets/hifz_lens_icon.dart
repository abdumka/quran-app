import 'package:flutter/material.dart';

/// Icon for "عدسة الإخفاء" (the Hifz reveal lens): a blurred page with a
/// rectangular lens revealing the lines beneath it. Rendered from a single
/// [color] so it adapts to whatever context it sits in (settings card, coach
/// overlay, guide dialog), using opacity tiers to keep the "hidden vs revealed"
/// reading of the original artwork.
class HifzLensIcon extends StatelessWidget {
  final double size;
  final Color color;

  const HifzLensIcon({super.key, this.size = 24, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HifzLensPainter(color)),
    );
  }
}

class _HifzLensPainter extends CustomPainter {
  final Color color;

  const _HifzLensPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw in the original 96x96 design space, then scale to fit.
    canvas.scale(size.width / 96.0, size.height / 96.0);

    void line(Paint paint, double x1, double y1, double x2, double y2) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }

    // Blurred (hidden) text lines.
    final blurred = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    line(blurred, 20, 26, 76, 26);
    line(blurred, 28, 38, 68, 38);
    line(blurred, 20, 70, 76, 70);
    line(blurred, 28, 58, 68, 58);

    // Revealed text lines inside the lens window.
    final revealed = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    line(revealed, 30, 44, 66, 44);
    line(revealed, 34, 52, 62, 52);

    // Rectangular revealer lens with rounded corners.
    final frame = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(22, 34, 52, 28),
        const Radius.circular(7),
      ),
      frame,
    );

    // Handle.
    final handle = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    line(handle, 70, 64, 80, 76);
  }

  @override
  bool shouldRepaint(_HifzLensPainter oldDelegate) =>
      oldDelegate.color != color;
}

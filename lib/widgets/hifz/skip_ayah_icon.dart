import 'package:flutter/widgets.dart';

/// The «تخطَّ» glyph of the Tasmee bar: an arrow that hops LEFT over an
/// ayah marker.
///
/// The mushaf reads right to left, so the ayah you skip to lies to the
/// left. Material's skip_next points right (towards the ayah just read),
/// and no Material icon jumps leftwards, hence this painted one. Drawn on
/// the same 24-unit grid as a Material icon so it sits level with them.
class SkipAyahIcon extends StatelessWidget {
  const SkipAyahIcon({super.key, this.size = 24, required this.color});

  final double size;
  final Color color;

  /// For call sites that build their icons from (size, colour).
  static Widget builder(double size, Color color) =>
      SkipAyahIcon(size: size, color: color);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SkipAyahPainter(color)),
    );
  }
}

class _SkipAyahPainter extends CustomPainter {
  const _SkipAyahPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 24;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The hop: up from the right, over the marker, down on the left.
    final arc = Path()
      ..moveTo(20.8 * u, 16.6 * u)
      ..cubicTo(20.8 * u, 10.0 * u, 16.9 * u, 5.4 * u, 12.0 * u, 5.4 * u)
      ..cubicTo(7.4 * u, 5.4 * u, 4.6 * u, 9.4 * u, 4.4 * u, 14.6 * u);
    canvas.drawPath(arc, stroke);

    // Its head, landing on the left.
    final head = Path()
      ..moveTo(2.0 * u, 12.2 * u)
      ..lineTo(4.4 * u, 14.9 * u)
      ..lineTo(7.0 * u, 12.4 * u);
    canvas.drawPath(head, stroke);

    // The ayah marker it jumps over.
    canvas.drawCircle(Offset(12.4 * u, 15.9 * u), 2.8 * u, stroke);
    canvas.drawCircle(
      Offset(12.4 * u, 15.9 * u),
      0.85 * u,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SkipAyahPainter oldDelegate) =>
      oldDelegate.color != color;
}

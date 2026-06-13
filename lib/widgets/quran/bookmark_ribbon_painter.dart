import 'package:flutter/material.dart';
class BookmarkRibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD22F2F).withValues(alpha: 0.94)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeJoin = StrokeJoin.round;

    final radius = 4.5;
    final left = 4.0;
    final top = 3.0;
    final right = size.width - 4.0;
    final bottom = size.height - 4.0;
    final centerX = size.width / 2;
    final notchDepth = 9.0;

    final path = Path()
      ..moveTo(left + radius, top)
      ..lineTo(right - radius, top)
      ..quadraticBezierTo(right, top, right, top + radius)
      ..lineTo(right, bottom - notchDepth)
      ..lineTo(centerX, bottom)
      ..lineTo(left, bottom - notchDepth)
      ..lineTo(left, top + radius)
      ..quadraticBezierTo(left, top, left + radius, top)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'package:flutter/widgets.dart';

/// "ظلّ الكعب": a soft shade along the spine edge of a page, so the reader can
/// tell a right-hand page from a left-hand one the way an open mushaf shows
/// it. Odd pages sit on the right of the spread, so their spine is the LEFT
/// edge; even pages sit on the left, so theirs is the RIGHT edge.
///
/// Purely decorative: it sits over the page image and under the highlight
/// and Tasmee overlays, ignores pointers, and adds nothing to the page
/// geometry. Callers hide it in the margin view (the scan itself shows the
/// side) and in the two-page spread (both sides are on screen).
class SpineShadow extends StatelessWidget {
  const SpineShadow({super.key, required this.page, required this.dark});

  /// 1-based page number.
  final int page;

  /// True under the dark-mode page filter, which inverts colours: the shade
  /// is then painted light so it ends up dark on screen.
  final bool dark;

  /// Share of the page width the shade reaches across.
  static const double _reach = 0.14;

  /// Peak opacity at the spine edge. The dark filter inverts the page to
  /// near-black, where a shade can only appear as a slightly lighter band,
  /// so it is kept gentler there.
  static const double _strength = 0.58;
  static const double _strengthDark = 0.34;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _SpineShadowPainter(spineOnLeft: page.isOdd, dark: dark),
        size: Size.infinite,
      ),
    );
  }
}

class _SpineShadowPainter extends CustomPainter {
  const _SpineShadowPainter({required this.spineOnLeft, required this.dark});

  final bool spineOnLeft;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // Warm dark brown in light mode; its inverse in dark mode, because the
    // reader's dark filter inverts everything it paints.
    final base = dark ? const Color(0xFFBEC4E2) : const Color(0xFF46341E);
    final strength = dark ? SpineShadow._strengthDark : SpineShadow._strength;
    // Stops trace a (1 - t)^1.6 falloff so the shade hugs the spine and fades
    // out without a visible edge.
    const steps = 8;
    final colors = <Color>[];
    final stops = <double>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      var a = (1 - t);
      a = a * a * a; // ~ (1 - t)^3 reads as a soft gutter
      colors.add(base.withValues(alpha: strength * a));
      stops.add(t);
    }
    final width = size.width * SpineShadow._reach;
    final rect = spineOnLeft
        ? Rect.fromLTWH(0, 0, width, size.height)
        : Rect.fromLTWH(size.width - width, 0, width, size.height);
    final gradient = LinearGradient(
      begin: spineOnLeft ? Alignment.centerLeft : Alignment.centerRight,
      end: spineOnLeft ? Alignment.centerRight : Alignment.centerLeft,
      colors: colors,
      stops: stops,
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_SpineShadowPainter old) =>
      old.spineOnLeft != spineOnLeft || old.dark != dark;
}

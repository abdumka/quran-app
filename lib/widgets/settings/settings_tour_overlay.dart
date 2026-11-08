import 'package:flutter/material.dart';

/// One stop of the «أرني أين» settings tour: the widget to light up and the
/// line that explains it.
class SettingsTourStop {
  const SettingsTourStop(this.target, this.text, {this.before});

  final GlobalKey target;
  final String text;

  /// Runs before the stop is measured (opening a group, say).
  final VoidCallback? before;
}

/// The tour's picture over the settings page: everything dimmed except
/// [targetRect], which gets a gold frame, and a caption card on the half of
/// the screen the target is not on. It swallows every touch, so the tour
/// cannot be skipped; only [onDone] (the «فهمت» button, shown on the last
/// stop) ends it. On the reader it also waits for the user's own taps:
/// [onTapAnywhere] for «المس الصفحة» (no [targetRect], nothing lit) and
/// [onTargetTap] for a tap inside the lit spot (the ⚙ button).
class SettingsTourOverlay extends StatelessWidget {
  const SettingsTourOverlay({
    super.key,
    required this.targetRect,
    required this.text,
    required this.index,
    required this.count,
    this.onDone,
    this.onTapAnywhere,
    this.onTargetTap,
  });

  final Rect? targetRect;
  final String text;
  final int index;
  final int count;
  final VoidCallback? onDone;
  final VoidCallback? onTapAnywhere;
  final VoidCallback? onTargetTap;

  static const Color _gold = Color(0xFFD6B35D);
  static const Color _brown = Color(0xFF8D6E3F);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final hole = targetRect?.inflate(4);
        final captionBelow =
            hole == null || hole.center.dy < box.maxHeight / 2;
        final caption = Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFAF0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF35250E),
                ),
              ),
              if (onDone != null) ...[
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _brown,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onDone,
                  child: const Text('فهمت'),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.rtl,
                children: [
                  for (var i = 0; i < count; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: i == index ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == index ? _brown : const Color(0xFFD9C99D),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
        return PopScope(
          canPop: false,
          child: Stack(
            children: [
              // swallows every touch
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    if (hole != null &&
                        onTargetTap != null &&
                        hole.inflate(8).contains(d.localPosition)) {
                      onTargetTap!();
                    } else {
                      onTapAnywhere?.call();
                    }
                  },
                  child: CustomPaint(painter: _HolePainter(hole)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: captionBelow ? null : 24,
                bottom: captionBelow ? 24 : null,
                child: caption,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HolePainter extends CustomPainter {
  _HolePainter(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = this.hole;
    if (hole == null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0x73140E04),
      );
      return;
    }
    final r = RRect.fromRectAndRadius(hole, const Radius.circular(16));
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(r);
    canvas.drawPath(dim, Paint()..color = const Color(0xA6140E04));
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = SettingsTourOverlay._gold,
    );
    canvas.drawRRect(
      r.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = SettingsTourOverlay._gold.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.hole != hole;
}

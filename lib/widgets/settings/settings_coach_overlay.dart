import 'package:flutter/material.dart';
import 'settings_constants.dart';
import '../hifz_lens_icon.dart';
import 'dart:math' as math;
class SettingsCoachOverlay extends StatelessWidget {
  final SettingsCoachStep step;
  final Rect targetRect;
  final bool centerDialog;
  final bool showDontShowAgain;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onDontShowAgain;

  const SettingsCoachOverlay({super.key, 
    required this.step,
    required this.targetRect,
    required this.centerDialog,
    required this.showDontShowAgain,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onDontShowAgain,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        const horizontalPadding = 18.0;
        final cardWidth = math.min(280.0, size.width - (horizontalPadding * 2));
        const manualGap = 20.0;
        final centeredCardLeft = ((size.width - cardWidth) / 2)
            .clamp(
              horizontalPadding,
              size.width - cardWidth - horizontalPadding,
            )
            .toDouble();
        final aboveSpace = (targetRect.top - manualGap - 24).toDouble();
        final belowSpace =
            (size.height - targetRect.bottom - manualGap - 24).toDouble();
        final preferBelow = belowSpace >= aboveSpace;
        final useCenteredFallback = math.max(aboveSpace, belowSpace) < 220;
        final safeCardTop = preferBelow ? targetRect.bottom + manualGap : 24.0;
        final safeCardBottom =
            preferBelow ? 24.0 : (size.height - targetRect.top + manualGap);
        final overlayAlignment = preferBelow
            ? Alignment.topCenter
            : Alignment.bottomCenter;
        final cardContent = Container(
          width: cardWidth,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF8D6E3F).withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFF8D6E3F),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: settingsPrimaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 12.0,
                    height: 1.4,
                    color: settingsSecondaryTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                CoachVisual(step: step),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    textDirection: TextDirection.rtl,
                    children: [
                      if (showDontShowAgain)
                        OutlinedButton(
                          onPressed: onDontShowAgain,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6F5731),
                            side: BorderSide(
                              color: const Color(
                                0xFF8D6E3F,
                              ).withValues(alpha: 0.38),
                            ),
                          ),
                          child: const Text('لا تظهر مرة أخرى'),
                        ),
                      FilledButton(
                        onPressed: onAction,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8D6E3F),
                        ),
                        child: Text(actionLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        );

        return SizedBox.expand(
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                CustomPaint(
                  size: size,
                  painter: CoachOverlayPainter(targetRect),
                ),
                Positioned.fromRect(
                  rect: targetRect.inflate(2),
                  child: const IgnorePointer(
                    child: PulsatingHighlightBorder(),
                  ),
                ),
                if (useCenteredFallback)
                  Positioned.fill(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: cardContent,
                      ),
                    ),
                  )
                else
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: safeCardTop,
                        bottom: safeCardBottom,
                        left: centeredCardLeft,
                        right: size.width - centeredCardLeft - cardWidth,
                      ),
                      child: Align(
                        alignment: overlayAlignment,
                        child: cardContent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PulsatingHighlightBorder extends StatefulWidget {
  const PulsatingHighlightBorder({super.key});

  @override
  State<PulsatingHighlightBorder> createState() => _PulsatingHighlightBorderState();
}

class _PulsatingHighlightBorderState extends State<PulsatingHighlightBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.4 + (_controller.value * 0.6);
        return Opacity(
          opacity: opacity,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFC62828), // Darker red
                width: 5.0, // Thicker border
              ),
            ),
          ),
        );
      },
    );
  }
}

class CoachOverlayPainter extends CustomPainter {
  final Rect targetRect;

  const CoachOverlayPainter(this.targetRect);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          targetRect.inflate(2),
          const Radius.circular(22),
        ),
      );
    final overlay = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.70),
    );
  }

  @override
  bool shouldRepaint(covariant CoachOverlayPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect;
  }
}

class CoachVisual extends StatefulWidget {
  final SettingsCoachStep step;

  const CoachVisual({super.key, required this.step});

  @override
  State<CoachVisual> createState() => _CoachVisualState();
}

class _CoachVisualState extends State<CoachVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFF8F3E8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF8D6E3F).withValues(alpha: 0.18),
            ),
          ),
          child: Center(
            child: switch (widget.step) {
              SettingsCoachStep.browseMode => BrowseModeCoachVisual(t: t),
              SettingsCoachStep.autoScroll => AutoScrollCoachVisual(t: t),
              SettingsCoachStep.marginImages => MarginCoachVisual(t: t),
              SettingsCoachStep.hideBar => HideBarCoachVisual(t: t),
              SettingsCoachStep.screenBrightness =>
                IconCoachVisual(t: t, icon: Icons.brightness_6_rounded),
              SettingsCoachStep.darkMode =>
                IconCoachVisual(t: t, icon: Icons.dark_mode_rounded),
              SettingsCoachStep.hifzLens => IconCoachVisual(
                t: t,
                icon: Icons.psychology_rounded,
                iconOverride: const HifzLensIcon(
                  size: 28,
                  color: Color(0xFF8D6E3F),
                ),
              ),
              SettingsCoachStep.fullScreen =>
                IconCoachVisual(t: t, icon: Icons.fullscreen_rounded),
              SettingsCoachStep.twoPage =>
                IconCoachVisual(t: t, icon: Icons.auto_stories_rounded),
              SettingsCoachStep.resetGuides =>
                IconCoachVisual(t: t, icon: Icons.tips_and_updates_rounded),
            },
          ),
        );
      },
    );
  }
}

/// A simple, animated illustration for settings whose behaviour is best shown
/// by a single emphasised icon (it gently pulses inside the framed box, in the
/// same style as the bespoke visuals).
class IconCoachVisual extends StatelessWidget {
  final double t;
  final IconData icon;

  /// Optional custom icon, used instead of [icon] when provided.
  final Widget? iconOverride;

  const IconCoachVisual({
    super.key,
    required this.t,
    required this.icon,
    this.iconOverride,
  });

  @override
  Widget build(BuildContext context) {
    final scale = 0.9 + (t * 0.2);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF8D6E3F).withValues(alpha: 0.35),
          ),
        ),
        child: iconOverride ??
            Icon(
              icon,
              color: const Color(0xFF8D6E3F),
              size: 28,
            ),
      ),
    );
  }
}

class BrowseModeCoachVisual extends StatelessWidget {
  final double t;

  const BrowseModeCoachVisual({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    final slide = (t - 0.5) * 18;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      textDirection: TextDirection.rtl,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'صفحات',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5C4522),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 72,
              height: 42,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    right: 8 + slide,
                    child: VisualPageCard(opacity: 0.86),
                  ),
                  Positioned(
                    left: 8 - slide,
                    child: VisualPageCard(opacity: 1),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 22),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'تمرير',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5C4522),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 30,
              height: 46,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 22,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF8D6E3F).withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, -10 + (t * 20)),
                    child: const Icon(
                      Icons.swipe_vertical_rounded,
                      color: Color(0xFF8D6E3F),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class AutoScrollCoachVisual extends StatelessWidget {
  final double t;

  const AutoScrollCoachVisual({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      textDirection: TextDirection.rtl,
      children: [
        VisualPageCard(opacity: 1),
        const SizedBox(width: 16),
        SizedBox(
          width: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6DCC9),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Transform.translate(
                offset: Offset(-24 + (t * 48), 0),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFF8D6E3F),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MarginCoachVisual extends StatelessWidget {
  final double t;

  const MarginCoachVisual({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    final padding = 4 + (t * 5);
    return SizedBox(
      width: 108,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFF4E7B9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFD7B86A),
              ),
            ),
          ),
          Container(
            width: 100 - (padding * 2),
            height: 52 - (padding * 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF8D6E3F).withValues(alpha: 0.28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HideBarCoachVisual extends StatelessWidget {
  final double t;

  const HideBarCoachVisual({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    // Animate a golden frame sliding down over a page
    final barY = 4 + (t * 30); // slides from top to middle
    return SizedBox(
      width: 108,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Page background
          Container(
            width: 60,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF8D6E3F).withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (_) => Container(
                  margin: const EdgeInsets.symmetric(vertical: 1.5),
                  width: 36,
                  height: 2.2,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6C39C),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          // Top cover (hidden area)
          Positioned(
            left: 24,
            right: 24,
            top: 4,
            height: barY - 4,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8F3E8),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              ),
            ),
          ),
          // Bottom cover (hidden area)
          Positioned(
            left: 24,
            right: 24,
            top: barY + 12,
            bottom: 3,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8F3E8),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
              ),
            ),
          ),
          // Golden frame (the reading window)
          Positioned(
            left: 22,
            right: 22,
            top: barY,
            height: 12,
            child: Container(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: const Color(0xFFD4A946),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VisualPageCard extends StatelessWidget {
  final double opacity;

  const VisualPageCard({super.key, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 28,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF8D6E3F).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (_) => Container(
              margin: const EdgeInsets.symmetric(vertical: 1.5),
              width: 14,
              height: 2.2,
              decoration: BoxDecoration(
                color: const Color(0xFFD6C39C),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

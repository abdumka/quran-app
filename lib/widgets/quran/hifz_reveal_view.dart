import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "Hifz mode" (memorization / active recall): blurs [child] entirely and
/// lets the user reveal a small sharp window by long-pressing and dragging.
///
/// Gesture contract: a quick horizontal swipe is ignored here so the parent
/// PageView flips pages normally; holding still for [_holdDuration] activates
/// the revealer (the long-press recognizer cancels itself if the finger moves
/// beyond the touch slop before the timer fires). Lifting the finger hides
/// the window instantly and restores normal swiping.
class HifzRevealView extends StatefulWidget {
  const HifzRevealView({
    super.key,
    required this.enabled,
    required this.child,
  });

  /// When false the page is rendered untouched, with no gesture listeners.
  final bool enabled;
  final Widget child;

  @override
  State<HifzRevealView> createState() => _HifzRevealViewState();
}

class _HifzRevealViewState extends State<HifzRevealView> {
  // A rectangle, not a circle: Arabic reading needs horizontal space.
  static const double _glassWidth = 150.0;
  static const double _glassHeight = 60.0;
  static const double _glassRadius = 8.0;
  static const double _blurSigma = 6.0;
  // The window is drawn above the touch point so the finger never covers it.
  static const double _fingerOffset = 80.0;
  // Hysteresis ("anti-twitch"): flip below the finger only when the finger is
  // about to cover the ceiling-pinned window; flip back above only once the
  // finger has pulled clearly away. Without the gap between these two
  // thresholds, slight wiggles near the top edge make the window teleport.
  static const double _flipDownProximity = 15.0;
  static const double _flipUpClearance = 20.0;
  // Lower zone: once the above-finger window would enter the bottom 15% of
  // the page, it slides smoothly the rest of the way to the bottom edge as
  // the finger keeps moving down, reaching the very bottom exactly when the
  // finger reaches the bottom of the screen. (A hard flip below the finger
  // here used to jump past the line just above the last one, and the
  // hysteresis around that jump made the window snap back and forth.)
  static const double _bottomZoneFraction = 0.15;
  static const Duration _holdDuration = Duration(milliseconds: 350);

  Offset? _glassTopLeft;
  bool _isFlippedDown = false;

  void _updateGlass(Offset touch, Size area) {
    final halfH = _glassHeight / 2;
    final x = touch.dx.clamp(0.0, area.width).toDouble();
    final y = touch.dy.clamp(0.0, area.height).toDouble();

    final left = (x - _glassWidth / 2)
        .clamp(0.0, math.max(0.0, area.width - _glassWidth))
        .toDouble();

    final maxTop = math.max(0.0, area.height - _glassHeight);
    final idealTopAbove = y - _fingerOffset - halfH;
    final idealTopBelow = y + _fingerOffset - halfH;
    final bottomZoneStart = area.height * (1 - _bottomZoneFraction);
    double top;
    if (!_isFlippedDown) {
      // Pin to the ceiling while the finger keeps pushing up...
      top = math.max(idealTopAbove, 0.0);
      // ...and flip below once the finger nearly covers the ceiling-pinned
      // window.
      final nearPinnedWindow = y < top + _glassHeight + _flipDownProximity;
      if (nearPinnedWindow) {
        _isFlippedDown = true;
        top = idealTopBelow;
      } else if (top + _glassHeight > bottomZoneStart) {
        // Bottom zone: continue sliding the window down smoothly so its
        // bottom edge reaches the page's bottom edge exactly as the finger
        // does, instead of jumping below the finger.
        final zoneEntryY =
            bottomZoneStart - _glassHeight + _fingerOffset + halfH;
        final entryTop =
            (bottomZoneStart - _glassHeight).clamp(0.0, maxTop).toDouble();
        final span = area.height - zoneEntryY;
        if (span > 0) {
          final t = ((y - zoneEntryY) / span).clamp(0.0, 1.0).toDouble();
          top = entryTop + (maxTop - entryTop) * t;
        }
      }
    } else {
      top = math.min(idealTopBelow, maxTop);
      // Flip back above only once clear of the ceiling (hysteresis).
      if (idealTopAbove > _flipUpClearance) {
        _isFlippedDown = false;
        top = idealTopAbove;
      }
    }
    top = top.clamp(0.0, maxTop).toDouble();

    setState(() => _glassTopLeft = Offset(left, top));
  }

  void _hideGlass() {
    if (_glassTopLeft == null) return;
    setState(() {
      _glassTopLeft = null;
      _isFlippedDown = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        final glass = _glassTopLeft;
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: _holdDuration),
              (LongPressGestureRecognizer instance) {
                instance.onLongPressStart = (details) {
                  HapticFeedback.selectionClick();
                  _updateGlass(details.localPosition, area);
                };
                instance.onLongPressMoveUpdate = (details) {
                  _updateGlass(details.localPosition, area);
                };
                instance.onLongPressEnd = (_) => _hideGlass();
                instance.onLongPressCancel = _hideGlass;
              },
            ),
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: _blurSigma,
                    sigmaY: _blurSigma,
                    tileMode: ui.TileMode.decal,
                  ),
                  child: widget.child,
                ),
              ),
              if (glass != null)
                Positioned(
                  left: glass.dx,
                  top: glass.dy,
                  width: _glassWidth,
                  height: _glassHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_glassRadius),
                        border: Border.all(
                          color: const Color(0xFFD4A946),
                          width: 2.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 16,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      // Show the sharp page clipped to the window: the full
                      // page is laid out at its real size and shifted so the
                      // region under the window lines up exactly.
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_glassRadius - 2),
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: area.width,
                          maxWidth: area.width,
                          minHeight: area.height,
                          maxHeight: area.height,
                          child: Transform.translate(
                            offset: Offset(-glass.dx, -glass.dy),
                            child: SizedBox(
                              width: area.width,
                              height: area.height,
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

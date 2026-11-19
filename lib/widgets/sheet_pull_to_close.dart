import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A tall bottom sheet whose content scrolls: Flutter lets only the parts
/// that do not scroll drag the sheet down, so a swipe down on the content
/// does nothing. This opens the sheet with its own slide controller and
/// lets a pull past the top of the scroll move the sheet with the finger
/// and close it, the same way the handle does (a quick flick, or let go
/// below 70 % of its height).
///
/// The scroll view inside should use [ClampingScrollPhysics]: with the iOS
/// bounce the pull becomes a bounce instead of an overscroll.
Future<T?> showPullToCloseSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool useSafeArea = true,
}) async {
  final motion = BottomSheet.createAnimationController(Navigator.of(context));
  try {
    return await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: useSafeArea,
      backgroundColor: backgroundColor,
      shape: shape,
      transitionAnimationController: motion,
      builder: (context) =>
          SheetPullToClose(motion: motion, child: builder(context)),
    );
  } finally {
    // The future ends when the sheet starts sliding away; the route lets go
    // of the controller once the slide is over and the sheet is gone.
    void dispose() => SchedulerBinding.instance.addPostFrameCallback(
      (_) => motion.dispose(),
    );
    if (motion.isDismissed) {
      dispose();
    } else {
      late final AnimationStatusListener done;
      done = (status) {
        if (status != AnimationStatus.dismissed) return;
        motion.removeStatusListener(done);
        dispose();
      };
      motion.addStatusListener(done);
    }
  }
}

/// Moves the sheet driven by [motion] (1 = open, 0 = gone) when the vertical
/// scroll view in [child] is pulled down past its top.
class SheetPullToClose extends StatefulWidget {
  const SheetPullToClose({
    super.key,
    required this.motion,
    required this.child,
  });

  final AnimationController motion;
  final Widget child;

  /// Let go below this much of the sheet showing and it closes.
  static const double closeBelow = 0.7;

  /// A downward flick faster than this (logical pixels a second) closes it.
  static const double flickSpeed = 700;

  @override
  State<SheetPullToClose> createState() => _SheetPullToCloseState();
}

class _SheetPullToCloseState extends State<SheetPullToClose> {
  bool _pulling = false;

  /// How much of the sheet shows while pulled (1 = all of it).
  double _shown = 1;

  double get _height {
    final box = context.findRenderObject() as RenderBox?;
    final h = box != null && box.hasSize ? box.size.height : 0.0;
    return h > 1 ? h : 1;
  }

  /// The modal sheet draws [motion] through Flutter's decelerating curve,
  /// which its own handle drag switches off; it is private, so the pull
  /// sets the controller to the value the curve turns into [shown], and
  /// the sheet stays under the finger.
  static double _valueFor(double shown) {
    const curve = Easing.legacyDecelerate; // the modal sheet's curve
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 30; i++) {
      final mid = (lo + hi) / 2;
      if (curve.transform(mid) < shown) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  void _move(double dy) {
    _shown = (_shown - dy / _height).clamp(0.0, 1.0);
    widget.motion.value = _shown >= 1 ? 1 : _valueFor(_shown);
  }

  bool _onScroll(ScrollNotification n) {
    // Only the sheet's own scroll, not the rows of chips inside it.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final m = widget.motion;
    if (m.status == AnimationStatus.reverse) return false; // already closing
    if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll < 0) {
      if (!_pulling) _shown = 1;
      _pulling = true;
      _move(-n.overscroll);
    } else if (n is ScrollUpdateNotification &&
        _pulling &&
        n.dragDetails != null &&
        (n.scrollDelta ?? 0) > 0) {
      // The finger goes back up: the sheet comes back up first.
      _move(-n.scrollDelta!);
      if (_shown >= 1) _pulling = false;
    } else if (n is ScrollEndNotification && _pulling) {
      _pulling = false;
      final speed = n.dragDetails?.velocity.pixelsPerSecond.dy ?? 0;
      if (speed > SheetPullToClose.flickSpeed ||
          _shown < SheetPullToClose.closeBelow) {
        Navigator.of(context).maybePop();
      } else {
        m.forward();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      );
}

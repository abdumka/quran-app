import 'dart:async';

import 'package:flutter/widgets.dart';

/// Work that would make a page stutter while it slides in (counting files,
/// running a search, raising the keyboard) waits for the slide to finish
/// (owner, 2026-11-13: "make sure it's as smooth as possible").
extension AfterOpening<T extends StatefulWidget> on State<T> {
  /// Runs [work] once this page's opening slide has finished: at once if it
  /// already has, or outside a route. A timer stands in if the slide never
  /// reports its end (an opening that was interrupted).
  void afterOpening(VoidCallback work) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null || animation.isCompleted) {
        work();
        return;
      }
      var done = false;
      Timer? fallback;
      late final AnimationStatusListener onStatus;
      void run() {
        if (done) return;
        done = true;
        fallback?.cancel();
        animation.removeStatusListener(onStatus);
        if (mounted) work();
      }

      onStatus = (status) {
        if (status == AnimationStatus.completed) run();
      };
      animation.addStatusListener(onStatus);
      fallback = Timer(const Duration(milliseconds: 800), run);
    });
  }
}

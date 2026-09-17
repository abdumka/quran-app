import 'package:flutter/material.dart';

import '../services/tv_service.dart';

class TabletLayoutHelper {
  const TabletLayoutHelper._();

  static double shortestSide(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide;
  }

  static bool isTabletDevice(BuildContext context) {
    // A TV never passes the size test -- 1080p at density 320 is 960x540
    // logical, so shortestSide is 540 -- but a 16:9 screen viewed from across
    // the room is exactly where the two-page spread belongs, so treat it as a
    // tablet regardless of its reported size.
    if (TvService.instance.isTv) return true;
    return shortestSide(context) >= 600;
  }

  static bool isTabletLandscape(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return isTabletDevice(context) && size.width > size.height;
  }

  static bool shouldShowTabletOptions(BuildContext context) {
    return isTabletDevice(context);
  }

  static double bottomMenuMaxWidth(BuildContext context) {
    if (!isTabletDevice(context)) return double.infinity;
    return isTabletLandscape(context) ? 760 : 620;
  }

  static bool useCompactBottomMenuButtons(BuildContext context) {
    return isTabletLandscape(context);
  }
}

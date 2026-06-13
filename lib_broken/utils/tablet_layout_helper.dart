import 'package:flutter/material.dart';

class TabletLayoutHelper {
  const TabletLayoutHelper._();

  static double shortestSide(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide;
  }

  static bool isTabletDevice(BuildContext context) {
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

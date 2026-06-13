import 'package:flutter/material.dart';

class ResponsiveHelper {
  static Size _size(BuildContext context) => MediaQuery.of(context).size;

  static double shortestSide(BuildContext context) {
    final size = _size(context);
    return size.shortestSide;
  }

  static bool isTablet(BuildContext context) {
    return shortestSide(context) >= 600;
  }

  static bool isLandscape(BuildContext context) {
    final size = _size(context);
    return size.width > size.height;
  }

  static bool isSmallPhone(BuildContext context) {
    return shortestSide(context) < 360;
  }

  static bool showTwoPages(BuildContext context) {
    return isTablet(context) && isLandscape(context);
  }

  static double pageHorizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width >= 1200) return 40;
    if (width >= 900) return 24;
    if (width >= 700) return 16;
    if (width >= 500) return 12;
    return 8;
  }

  static double overlayIconSize(BuildContext context) {
    if (isTablet(context)) return 30;
    if (isSmallPhone(context)) return 20;
    return 24;
  }

  static double overlayFontSize(BuildContext context) {
    if (isTablet(context)) return 18;
    if (isSmallPhone(context)) return 12;
    return 14;
  }

  static double bottomMenuCollapsedHeight(BuildContext context) {
  if (showTwoPages(context)) return 260;
  if (isTablet(context)) return 320;
  if (isLandscape(context)) return 185;
  if (isSmallPhone(context)) return 320;
  return 390;
}

  static double surahCardNumberSize(BuildContext context) {
    if (isTablet(context)) return 20;
    return 16;
  }

  static double surahTitleSize(BuildContext context) {
    if (isTablet(context)) return 20;
    return 18;
  }

  static double surahSubtitleSize(BuildContext context) {
    if (isTablet(context)) return 14;
    return 12;
  }
}
import 'package:flutter/material.dart';

class TopOverlayBar extends StatelessWidget {
  final bool show;
  final bool isSearching;
  final int currentPage;
  final bool isTwoPageView;
  final int Function(int) getHizbNumber;
  final String Function(int) getSurahName;
  final VoidCallback onSettingsPressed;
  final bool isHideBarEnabled;
  final ValueChanged<bool> onToggleHideBar;
  final bool isFullScreenMode;
  final ValueChanged<bool> onToggleFullScreenMode;

  /// Tapping anywhere on the page/hizb block opens الفهرس on its pages tab;
  /// anywhere in the middle (the surah name) opens it on the surahs tab.
  final VoidCallback? onPageAreaPressed;
  final VoidCallback? onSurahAreaPressed;

  /// Which of the three controls the TV remote is on (0 full-screen,
  /// 1 hide-bar, 2 settings), or null off-TV / when focus is elsewhere.
  /// Drawn as a ring because Flutter's own focus styling is invisible at
  /// couch distance.
  final int? tvFocusedIndex;

  const TopOverlayBar({
    super.key,
    required this.show,
    required this.isSearching,
    required this.currentPage,
    required this.isTwoPageView,
    required this.getHizbNumber,
    required this.getSurahName,
    required this.onSettingsPressed,
    required this.isHideBarEnabled,
    required this.onToggleHideBar,
    required this.isFullScreenMode,
    required this.onToggleFullScreenMode,
    this.onPageAreaPressed,
    this.onSurahAreaPressed,
    this.tvFocusedIndex,
  });

  Widget _tvRing(int index, Widget child) {
    if (tvFocusedIndex != index) return child;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFD2B97E).withValues(alpha: 0.30),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFD2B97E), width: 3),
      ),
      child: child,
    );
  }

  /// A tap target that fills its whole slot of the bar, top to bottom, so the
  /// user doesn't have to hit the text itself.
  Widget _tapArea({
    required VoidCallback? onTap,
    required String label,
    required EdgeInsetsGeometry padding,
    required Widget child,
  }) {
    return Semantics(
      button: onTap != null,
      label: label,
      child: InkWell(
        onTap: onTap,
        // Touch only: the TV remote walks the three icons through
        // [tvFocusedIndex], and an extra focus stop would confuse it.
        canRequestFocus: false,
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isVisible = show && !isSearching;
    if (!isVisible) return const SizedBox.shrink();

    final int pageNumber = currentPage + 1;
    final String surahName = getSurahName(currentPage);
    final int hizbNumber = getHizbNumber(currentPage);
    final String surahLabel = surahName.contains(' - ')
        ? surahName
        : 'سورة $surahName';

    // In landscape the vertical space is scarce, so the chrome is made
    // noticeably more compact (smaller paddings, fonts and icons) to free up
    // screen real estate for the page image.
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double verticalPadding = isLandscape ? 4 : 12;
    final double pageFontSize = isLandscape ? 13 : 16;
    final double hizbFontSize = isLandscape ? 10 : 12;
    final double surahFontSize = isLandscape ? 15 : 18;

    return Material(
      color: Colors.transparent,
      child: Container(
        color: const Color(0xFF1C1C1E).withValues(alpha: 0.65),
        child: SafeArea(
          bottom: false,
          // IntrinsicHeight + stretch: every slot is as tall as the bar, so the
          // page and surah tap areas cover it top to bottom.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Page Number & Hizb on Left -> الفهرس, pages tab
                _tapArea(
                  onTap: onPageAreaPressed,
                  label:
                      'صفحة $pageNumber، الحزب $hizbNumber. فتح فهرس الصفحات',
                  padding: EdgeInsetsDirectional.fromSTEB(
                    16,
                    verticalPadding,
                    12,
                    verticalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'صفحة $pageNumber',
                        style: TextStyle(
                          color: const Color(0xFFD2B97E),
                          fontSize: pageFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'الحزب $hizbNumber',
                        style: TextStyle(
                          color: const Color(0xFFD2B97E).withValues(alpha: 0.8),
                          fontSize: hizbFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Surah Name in Middle -> الفهرس, surahs tab. Expanded, so the
                // whole gap between the page block and the icons is tappable.
                Expanded(
                  child: _tapArea(
                    onTap: onSurahAreaPressed,
                    label: '$surahLabel. فتح فهرس السور',
                    padding: EdgeInsets.symmetric(vertical: verticalPadding),
                    child: Center(
                      child: Text(
                        surahLabel,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFD2B97E),
                          fontSize: surahFontSize,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                    ),
                  ),
                ),
                // Full Screen + Hide Bar Toggles + Settings Icon on Right
                Padding(
                  padding: EdgeInsetsDirectional.only(end: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _tvRing(
                        0,
                        IconButton(
                          icon: Icon(
                            isFullScreenMode
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            color: isFullScreenMode
                                ? const Color(0xFFD2B97E)
                                : const Color(
                                    0xFFD2B97E,
                                  ).withValues(alpha: 0.5),
                            size: isLandscape ? 20 : 24,
                          ),
                          onPressed: () =>
                              onToggleFullScreenMode(!isFullScreenMode),
                          padding: EdgeInsets.all(isLandscape ? 2 : 6),
                          constraints: BoxConstraints(
                            minWidth: isLandscape ? 32 : 40,
                            minHeight: isLandscape ? 32 : 40,
                          ),
                          tooltip: isFullScreenMode
                              ? 'إيقاف وضع ملء الشاشة'
                              : 'تفعيل وضع ملء الشاشة',
                        ),
                      ),
                      _tvRing(
                        1,
                        IconButton(
                          icon: Icon(
                            isHideBarEnabled
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: isHideBarEnabled
                                ? const Color(0xFFD2B97E)
                                : const Color(
                                    0xFFD2B97E,
                                  ).withValues(alpha: 0.5),
                            size: isLandscape ? 20 : 24,
                          ),
                          onPressed: () => onToggleHideBar(!isHideBarEnabled),
                          padding: EdgeInsets.all(isLandscape ? 2 : 6),
                          constraints: BoxConstraints(
                            minWidth: isLandscape ? 32 : 40,
                            minHeight: isLandscape ? 32 : 40,
                          ),
                          tooltip: isHideBarEnabled
                              ? 'إخفاء شريط الإخفاء'
                              : 'إظهار شريط الإخفاء',
                        ),
                      ),
                      _tvRing(
                        2,
                        IconButton(
                          icon: Icon(
                            Icons.settings_outlined,
                            color: const Color(0xFFD2B97E),
                            size: isLandscape ? 22 : 26,
                          ),
                          onPressed: onSettingsPressed,
                          padding: EdgeInsets.all(isLandscape ? 4 : 8),
                          constraints: BoxConstraints(
                            minWidth: isLandscape ? 36 : 44,
                            minHeight: isLandscape ? 36 : 44,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

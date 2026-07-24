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
  final bool isMemorizationTestEnabled;
  final ValueChanged<bool> onToggleMemorizationTest;

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
    required this.isMemorizationTestEnabled,
    required this.onToggleMemorizationTest,
  });

  @override
  Widget build(BuildContext context) {
    final bool isVisible = show && !isSearching;
    if (!isVisible) return const SizedBox.shrink();

    final int pageNumber = currentPage + 1;
    final String surahName = getSurahName(currentPage);
    final int hizbNumber = getHizbNumber(currentPage);

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
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Page Number & Hizb on Left
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
              // Surah Name in Middle
              Flexible(
                child: Text(
                  surahName.contains(' - ') ? surahName : 'سورة $surahName',
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
              // Memorization Test + Full Screen + Hide Bar Toggles + Settings Icon on Right
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Only offered where the word-reveal test can actually
                  // run: single-page view on page 1 (the Al-Fatihah POC).
                  if (currentPage == 0 && !isTwoPageView)
                    IconButton(
                      icon: Icon(
                        isMemorizationTestEnabled
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        color: isMemorizationTestEnabled
                            ? const Color(0xFFD2B97E)
                            : const Color(0xFFD2B97E).withValues(alpha: 0.5),
                        size: isLandscape ? 20 : 24,
                      ),
                      onPressed: () =>
                          onToggleMemorizationTest(!isMemorizationTestEnabled),
                      padding: EdgeInsets.all(isLandscape ? 2 : 6),
                      constraints: BoxConstraints(
                        minWidth: isLandscape ? 32 : 40,
                        minHeight: isLandscape ? 32 : 40,
                      ),
                      tooltip: isMemorizationTestEnabled
                          ? 'إنهاء اختبار الحفظ'
                          : 'اختبار الحفظ',
                    ),
                  IconButton(
                    icon: Icon(
                      isFullScreenMode
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: isFullScreenMode
                          ? const Color(0xFFD2B97E)
                          : const Color(0xFFD2B97E).withValues(alpha: 0.5),
                      size: isLandscape ? 20 : 24,
                    ),
                    onPressed: () => onToggleFullScreenMode(!isFullScreenMode),
                    padding: EdgeInsets.all(isLandscape ? 2 : 6),
                    constraints: BoxConstraints(
                      minWidth: isLandscape ? 32 : 40,
                      minHeight: isLandscape ? 32 : 40,
                    ),
                    tooltip: isFullScreenMode
                        ? 'إيقاف وضع ملء الشاشة'
                        : 'تفعيل وضع ملء الشاشة',
                  ),
                  IconButton(
                    icon: Icon(
                      isHideBarEnabled
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: isHideBarEnabled
                          ? const Color(0xFFD2B97E)
                          : const Color(0xFFD2B97E).withValues(alpha: 0.5),
                      size: isLandscape ? 20 : 24,
                    ),
                    onPressed: () => onToggleHideBar(!isHideBarEnabled),
                    padding: EdgeInsets.all(isLandscape ? 2 : 6),
                    constraints: BoxConstraints(
                      minWidth: isLandscape ? 32 : 40,
                      minHeight: isLandscape ? 32 : 40,
                    ),
                    tooltip: isHideBarEnabled ? 'إخفاء شريط الإخفاء' : 'إظهار شريط الإخفاء',
                  ),
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
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

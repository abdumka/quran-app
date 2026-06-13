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
  final bool isHifzModeEnabled;
  final ValueChanged<bool> onToggleHifzMode;
  final bool isFullScreenMode;
  final ValueChanged<bool> onToggleFullScreenMode;

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
    required this.isHifzModeEnabled,
    required this.onToggleHifzMode,
    required this.isFullScreenMode,
    required this.onToggleFullScreenMode,
  });

  @override
  Widget build(BuildContext context) {
    final bool isVisible = show && !isSearching;
    if (!isVisible) return const SizedBox.shrink();

    final int pageNumber = currentPage + 1;
    final String surahName = getSurahName(currentPage);
    final int hizbNumber = getHizbNumber(currentPage);

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
          padding: const EdgeInsets.symmetric(vertical: 12),
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
                    style: const TextStyle(
                      color: Color(0xFFD2B97E),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'الحزب $hizbNumber',
                    style: TextStyle(
                      color: const Color(0xFFD2B97E).withValues(alpha: 0.8),
                      fontSize: 12,
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
                  style: const TextStyle(
                    color: Color(0xFFD2B97E),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ),
              // Full Screen + Hifz Mode + Hide Bar Toggles + Settings Icon on Right
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isFullScreenMode
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: isFullScreenMode
                          ? const Color(0xFFD2B97E)
                          : const Color(0xFFD2B97E).withValues(alpha: 0.5),
                      size: 24,
                    ),
                    onPressed: () => onToggleFullScreenMode(!isFullScreenMode),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    tooltip: isFullScreenMode
                        ? 'إيقاف وضع ملء الشاشة'
                        : 'تفعيل وضع ملء الشاشة',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.psychology_rounded,
                      color: isHifzModeEnabled
                          ? const Color(0xFFD2B97E)
                          : const Color(0xFFD2B97E).withValues(alpha: 0.5),
                      size: 24,
                    ),
                    onPressed: () => onToggleHifzMode(!isHifzModeEnabled),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    tooltip: isHifzModeEnabled
                        ? 'إيقاف عدسة الإخفاء'
                        : 'تفعيل عدسة الإخفاء',
                  ),
                  IconButton(
                    icon: Icon(
                      isHideBarEnabled
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: isHideBarEnabled
                          ? const Color(0xFFD2B97E)
                          : const Color(0xFFD2B97E).withValues(alpha: 0.5),
                      size: 24,
                    ),
                    onPressed: () => onToggleHideBar(!isHideBarEnabled),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    tooltip: isHideBarEnabled ? 'إخفاء شريط الإخفاء' : 'إظهار شريط الإخفاء',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Color(0xFFD2B97E),
                      size: 26,
                    ),
                    onPressed: onSettingsPressed,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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

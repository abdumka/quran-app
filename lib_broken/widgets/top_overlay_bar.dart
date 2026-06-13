import 'package:flutter/material.dart';

class TopOverlayBar extends StatelessWidget {
  final bool show;
  final bool isSearching;
  final int currentPage;
  final bool isTwoPageView;
  final int Function(int) getHizbNumber;
  final String Function(int) getSurahName;
  final VoidCallback onSettingsPressed;

  const TopOverlayBar({
    super.key,
    required this.show,
    required this.isSearching,
    required this.currentPage,
    required this.isTwoPageView,
    required this.getHizbNumber,
    required this.getSurahName,
    required this.onSettingsPressed,
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
      color: const Color(0xFF1C1C1E),
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
          // Settings Icon on Right
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              color: Color(0xFFD2B97E),
              size: 26,
            ),
            onPressed: onSettingsPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
        ),
      ),
      ),
    );
  }
}

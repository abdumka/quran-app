import 'package:flutter/material.dart';
import '../utils/responsive_helper.dart';

class SurahCardTile extends StatelessWidget {
  static const double tileHeight = 112;

  final int number;
  final String arabicName;
  final String englishName;
  final String revelationType;
  final int ayahCount;
  final bool isCurrent;
  final VoidCallback? onTap;

  const SurahCardTile({
    super.key,
    required this.number,
    required this.arabicName,
    required this.englishName,
    required this.revelationType,
    required this.ayahCount,
    this.isCurrent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final isWideTablet = isTablet && ResponsiveHelper.isLandscape(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 16 : 12,
        vertical: 6,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: isWideTablet ? 116 : tileHeight,
          decoration: BoxDecoration(
            color: isCurrent
                ? const Color(0xFFE6D4A7)
                : const Color(0xFFF3EFE6),
            borderRadius: BorderRadius.circular(16),
            border: isCurrent
                ? Border.all(
                    color: const Color(0xFF8D6E3F),
                    width: 1.4,
                  )
                : null,
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: const Color(0xFF8D6E3F).withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          padding: EdgeInsets.all(isTablet ? 16 : 14),
          child: Row(
            children: [
              Container(
                width: isTablet ? 56 : 46,
                height: isTablet ? 56 : 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent ? const Color(0xFF6F5228) : const Color(0xFF8D6E3F),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$number',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: ResponsiveHelper.surahCardNumberSize(context),
                  ),
                ),
              ),
              SizedBox(width: isTablet ? 14 : 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      arabicName,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: ResponsiveHelper.surahTitleSize(context),
                        fontWeight: FontWeight.bold,
                        color: isCurrent ? const Color(0xFF3D3122) : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      englishName,
                      style: TextStyle(
                        color: isCurrent ? const Color(0xFF6D5B3E) : Colors.grey,
                        fontSize: isTablet ? 14 : 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$revelationType • $ayahCount آية',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.surahSubtitleSize(context),
                        color: isCurrent
                            ? const Color(0xFF5E503A)
                            : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isCurrent ? Icons.radio_button_checked : Icons.arrow_forward_ios,
                size: isTablet ? 18 : 16,
                color: isCurrent ? const Color(0xFF8D6E3F) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

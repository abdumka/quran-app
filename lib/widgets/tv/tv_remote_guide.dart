import 'package:flutter/material.dart';

import '../../services/tv_service.dart';

/// Android TV onboarding: how to drive the reader with a remote.
///
/// Presentational only — visibility and key handling live in QuranPages, which
/// drives this through the same HardwareKeyboard handler that already owns the
/// reader's arrow keys. That is deliberate: Flutter's focus traversal does not
/// respond to D-pad arrows on a TV (only to TAB, which no remote has), so a
/// normal focusable dialog cannot be dismissed with a remote at all.
///
/// Every line here must describe behaviour that actually works. If a control
/// changes, change the matching row.
class TvRemoteGuide extends StatelessWidget {
  const TvRemoteGuide({super.key, required this.isDarkMode});

  final bool isDarkMode;

  static const Color _gold = Color(0xFFD2B97E);
  static const Color _goldDark = Color(0xFF8D6E3F);

  @override
  Widget build(BuildContext context) {
    final Color surface = isDarkMode
        ? const Color(0xFF15120B)
        : const Color(0xFFFDFBF5);
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;

    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: Center(
        child: SingleChildScrollView(
          // TVs crop roughly 5% of every edge (overscan), so keep the card well
          // inside the panel rather than relying on the screen bounds.
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _gold.withValues(alpha: 0.75), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.settings_remote_rounded,
                          color: _gold,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'التنقل بجهاز التحكم',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 19,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _row(
                      Icons.swap_horiz_rounded,
                      'السهمان يمين ويسار',
                      'تصفّح الصفحات (الأيسر: الصفحة التالية)',
                      textColor,
                    ),
                    _row(
                      Icons.circle_outlined,
                      'زر الاختيار (OK)',
                      'فتح القائمة، ثم اختيار العنصر',
                      textColor,
                    ),
                    _row(
                      Icons.menu_rounded,
                      'الأسهم داخل القائمة',
                      'التنقل بين أزرار القائمة',
                      textColor,
                    ),
                    _row(
                      Icons.unfold_more_rounded,
                      'السهمان أعلى وأسفل من القائمة',
                      'أعلى: الشريط العلوي والإعدادات · أسفل: شريط التلاوة',
                      textColor,
                    ),
                    _row(
                      Icons.play_circle_outline_rounded,
                      'أزرار شريط التلاوة',
                      'تنقّل بالأسهم: تشغيل/إيقاف، اختيار الآية، تكرار الآية والصفحة، إغلاق',
                      textColor,
                    ),
                    _row(
                      Icons.swap_horiz_rounded,
                      'زر «ص» في شريط التلاوة',
                      'يحدد أي الصفحتين تُتلى عند عرض صفحتين',
                      textColor,
                    ),
                    _row(
                      Icons.undo_rounded,
                      'زر الرجوع',
                      'إغلاق القائمة، ثم الخروج من التطبيق',
                      textColor,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _goldDark,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'اضغط زر الاختيار (OK) للمتابعة',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      kTvBuildStamp,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String control, String meaning, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _gold.withValues(alpha: 0.55)),
            ),
            // LTR forces the glyph to render unmirrored: inside the RTL
            // Directionality a 'left' chevron would otherwise flip and point
            // right, contradicting the label next to it.
            child: Icon(
              icon,
              color: _gold,
              size: 18,
              textDirection: TextDirection.ltr,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  control,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.15,
                  ),
                ),
                Text(
                  meaning,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.72),
                    fontSize: 13,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

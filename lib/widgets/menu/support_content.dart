import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_surfaces.dart';

class SupportContent extends StatelessWidget {
  const SupportContent({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // null in the previous look and in night mode: the old colours stay
    final s = AppSurfaces.maybeOf(context);
    final cardColor = isDarkMode ? const Color(0xFF1A1A1A) : s?.card ?? const Color(0xFFF8F1DE);
    final borderColor = isDarkMode ? const Color(0xFF53401F) : s?.border ?? const Color(0xFFE2D2A5);
    final titleColor = isDarkMode ? Colors.white : s?.text ?? const Color(0xFF35250E);
    final bodyColor = isDarkMode ? Colors.white70 : s?.text ?? const Color(0xFF6E5837);
    // the thin gold rule between the lines
    final ruleColor = s?.accent ?? const Color(0xFFB58A2B);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(
              s == null ? 22 : AppSurfaces.radius,
            ),
            border: Border.all(color: borderColor),
            // the new look uses the hairline alone
            boxShadow: s != null
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: s == null ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: s == null ? null : BorderRadius.circular(16),
                  color: s?.tile ??
                      const Color(0xFFB58A2B).withValues(alpha: isDarkMode ? 0.26 : 0.16),
                ),
                child: Icon(
                  Icons.favorite_rounded,
                  color: s?.icon ?? const Color(0xFF8A661B),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'لا نريد منكم إلا الدعاء لنا ولوالدينا، جزاكم الله خيرًا',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.8,
                  fontWeight: s == null ? FontWeight.w800 : FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 90,
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: LinearGradient(
                    colors: [
                      ruleColor.withValues(alpha: 0),
                      ruleColor,
                      ruleColor.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'وتقييمنا حتى يصل التطبيق لغيرك',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.7,
                  fontWeight: s == null ? FontWeight.w700 : FontWeight.w500,
                  color: bodyColor,
                ),
              ),
              const SizedBox(height: 24),
              InkWell(
                onTap: () async {
                  try {
                    final InAppReview inAppReview = InAppReview.instance;
                    if (await inAppReview.isAvailable()) {
                      await inAppReview.requestReview();
                    } else {
                      // iOS needs the App Store id: without it this threw
                      // and the catch below sent iPhones to Google Play.
                      await inAppReview.openStoreListing(
                        appStoreId: '6783147903',
                      );
                    }
                  } catch (e) {
                    // Force opening PlayStore using URL directly!
                    try {
                      final url = Uri.parse('https://play.google.com/store/apps/details?id=com.mahfodqr.qalon_mushaf');
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.0),
                        child: Icon(
                          Icons.star_rounded,
                          color: Color(0xFFECA311),
                          size: 38,
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

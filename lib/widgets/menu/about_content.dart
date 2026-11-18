import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_update_service.dart';
import '../../theme/app_surfaces.dart';

class AboutContent extends StatelessWidget {
  const AboutContent({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // null in the previous look and in night mode: the old colours stay
    final s = AppSurfaces.maybeOf(context);
    final cardColor = isDarkMode ? const Color(0xFF1A1A1A) : s?.card ?? const Color(0xFFF8F1DE);
    final borderColor = isDarkMode ? const Color(0xFF53401F) : s?.border ?? const Color(0xFFE2D2A5);
    final titleColor = isDarkMode ? Colors.white : s?.text ?? const Color(0xFF35250E);
    final bodyColor = isDarkMode ? Colors.white70 : s?.muted ?? const Color(0xFF6E5837);
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
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: s == null ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: s == null ? null : BorderRadius.circular(16),
                  color: s?.tile ??
                      const Color(0xFFB58A2B).withValues(alpha: isDarkMode ? 0.26 : 0.16),
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  color: s?.icon ?? const Color(0xFF8A661B),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'المصحف الجامع',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 19,
                  height: 1.5,
                  fontWeight: s == null ? FontWeight.w900 : FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppUpdateService.instance.currentVersion.isEmpty
                    ? 'الإصدار'
                    : 'الإصدار: ${AppUpdateService.instance.currentVersion}',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: s == null ? FontWeight.w800 : FontWeight.w500,
                  color: bodyColor,
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
              const SizedBox(height: 16),
              Text(
                'تطبيق لقراءة القرآن الكريم من المصحف الجامع، مع تصميم مريح وواضح يدعم العرض العمودي والأفقي، والبحث، والعلامات المرجعية، وبعض الأدوات المساعدة للقارئ.\n\nونعمل على تحسينه وتطويره تدريجيًا بإذن الله.',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.85,
                  fontWeight: s == null ? FontWeight.w700 : FontWeight.w500,
                  color: s?.text ?? bodyColor,
                ),
              ),
              // The installed apps don't need a link back to themselves; this
              // is only useful to visitors on the web build.
              if (kIsWeb) ...[
                const SizedBox(height: 20),
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
                const SizedBox(height: 16),
                Text(
                  'حمّل التطبيق على هاتفك',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: s == null ? FontWeight.w800 : FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _StoreButton(
                        icon: Icons.android_rounded,
                        label: 'Google Play',
                        color: const Color(0xFF34A853),
                        cardColor: cardColor,
                        borderColor: borderColor,
                        titleColor: titleColor,
                        onTap: () => _launchStoreUrl(AppUpdateService.playStoreUrl),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StoreButton(
                        icon: Icons.apple,
                        label: 'App Store',
                        color: isDarkMode ? Colors.white : Colors.black,
                        cardColor: cardColor,
                        borderColor: borderColor,
                        titleColor: titleColor,
                        onTap: () => _launchStoreUrl(AppUpdateService.appStoreUrl),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _launchStoreUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

class _StoreButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color cardColor;
  final Color borderColor;
  final Color titleColor;
  final VoidCallback onTap;

  const _StoreButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.cardColor,
    required this.borderColor,
    required this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: titleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

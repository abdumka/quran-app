import 'package:flutter/material.dart';

class AboutContent extends StatelessWidget {
  const AboutContent({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF8F1DE);
    final borderColor = isDarkMode ? const Color(0xFF53401F) : const Color(0xFFE2D2A5);
    final titleColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
    final bodyColor = isDarkMode ? Colors.white70 : const Color(0xFF6E5837);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
            boxShadow: [
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
                  shape: BoxShape.circle,
                  color: const Color(0xFFB58A2B).withValues(alpha: isDarkMode ? 0.26 : 0.16),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Color(0xFF8A661B),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'مصحف الدعوة الاسلامية الجامع',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 19,
                  height: 1.5,
                  fontWeight: FontWeight.w900,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'الإصدار: 2.0.3',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: bodyColor,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 90,
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0x00B58A2B),
                      Color(0xFFB58A2B),
                      Color(0x00B58A2B),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'تطبيق لقراءة القرآن الكريم من مصحف الدعوة الاسلامية الجامع، مع تصميم مريح وواضح يدعم العرض العمودي والأفقي، والبحث، والعلامات المرجعية، وبعض الأدوات المساعدة للقارئ.\n\nونعمل على تحسينه وتطويره تدريجيًا بإذن الله.',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.85,
                  fontWeight: FontWeight.w700,
                  color: bodyColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

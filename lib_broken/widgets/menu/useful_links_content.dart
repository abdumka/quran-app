import 'package:flutter/material.dart';


class UsefulLinksContent extends StatelessWidget {
  final Future<void> Function(String url) onOpenLink;

  const UsefulLinksContent({super.key, required this.onOpenLink});

  static const List<({String title, String url, IconData icon})> usefulLinks = [
    (
      title: 'الشيخ عبد الرزاق البدر',
      url: 'https://www.al-badr.net/',
      icon: Icons.school_rounded,
    ),
    (
      title: 'الشيخ ابن باز',
      url: 'https://binbaz.org.sa/',
      icon: Icons.menu_book_rounded,
    ),
    (
      title: 'الشيخ ابن العثيمين',
      url: 'https://binothaimeen.net/',
      icon: Icons.auto_stories_rounded,
    ),
    (
      title: 'الشيخ رسلان',
      url: 'https://www.rslan.com/',
      icon: Icons.record_voice_over_rounded,
    ),
    (
      title: 'جميع التلاوات MP3',
      url: 'https://www.mp3quran.net/ar',
      icon: Icons.headphones_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkMode ? const Color(0xFF191919) : const Color(0xFFF8F1DE);
    final borderColor = isDarkMode ? const Color(0xFF53401F) : const Color(0xFFE2D2A5);
    final titleColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
    
    final bool isPhoneLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isPhoneLandscape ? 3 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: isPhoneLandscape ? 1.5 : 1.28,
      ),
      itemCount: usefulLinks.length,
      itemBuilder: (context, index) {
        final link = usefulLinks[index];
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onOpenLink(link.url),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB58A2B).withValues(alpha: isDarkMode ? 0.28 : 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(link.icon, color: const Color(0xFF8A661B)),
                ),
                const SizedBox(height: 10),
                Text(
                  link.title,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

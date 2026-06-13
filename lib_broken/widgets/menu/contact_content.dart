import 'package:flutter/material.dart';

class ContactContent extends StatelessWidget {
  final Future<void> Function(String url) onOpenLink;

  const ContactContent({super.key, required this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFF8F1DE);
    final borderColor = isDarkMode ? const Color(0xFF53401F) : const Color(0xFFE2D2A5);
    final titleColor = isDarkMode ? Colors.white : const Color(0xFF35250E);

    Widget buildContactButton({
      required String title,
      required String subtitle,
      required IconData icon,
      required VoidCallback onTap,
      required Color accentColor,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: titleColor.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        buildContactButton(
          title: 'واتساب',
          subtitle: 'مراسلة مباشرة',
          icon: Icons.chat_rounded,
          accentColor: const Color(0xFF25D366),
          onTap: () => onOpenLink('https://wa.me/218915449613'),
        ),
        const SizedBox(height: 12),
        buildContactButton(
          title: 'البريد الإلكتروني',
          subtitle: 'mahfodqr@gmail.com',
          icon: Icons.email_rounded,
          accentColor: const Color(0xFFB58A2B),
          onTap: () => onOpenLink('mailto:mahfodqr@gmail.com'),
        ),
      ],
    );
  }
}

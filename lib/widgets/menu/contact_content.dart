import 'package:flutter/material.dart';

import '../../services/chat_service.dart';
import '../chat/chat_screen.dart';

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
      TextDirection subtitleDirection = TextDirection.ltr,
      bool highlighted = false,
      int badge = 0,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: highlighted
                ? Color.alphaBlend(
                    accentColor.withValues(alpha: 0.10),
                    cardColor,
                  )
                : cardColor,
            borderRadius: BorderRadius.circular(18),
            border: highlighted
                ? Border.all(color: accentColor, width: 1.5)
                : Border.all(color: borderColor),
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
                      textDirection: subtitleDirection,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: titleColor.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 10),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC2412D),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (ChatService.isAvailable) ...[
          ValueListenableBuilder<int>(
            valueListenable: ChatService.instance.unread,
            builder: (context, unread, _) => buildContactButton(
              title: 'راسلنا مباشرة',
              subtitle: 'ونردّ عليك هنا في التطبيق',
              subtitleDirection: TextDirection.rtl,
              icon: Icons.forum_rounded,
              accentColor: const Color(0xFF8B7355),
              highlighted: true,
              badge: unread,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        buildContactButton(
          title: 'صفحة فيسبوك',
          subtitle: 'AlMushafAlJami',
          icon: Icons.facebook_rounded,
          accentColor: const Color(0xFF1877F2),
          onTap: () => onOpenLink('https://www.facebook.com/AlMushafAlJami'),
        ),
        const SizedBox(height: 12),
        buildContactButton(
          title: 'قناة تيليجرام',
          subtitle: '@moshafqr',
          icon: Icons.send_rounded,
          accentColor: const Color(0xFF0088CC),
          onTap: () => onOpenLink('https://t.me/moshafqr/2'),
        ),
        const SizedBox(height: 12),
        buildContactButton(
          title: 'واتساب',
          subtitle: 'مجتمع واتساب',
          icon: Icons.chat_rounded,
          accentColor: const Color(0xFF25D366),
          onTap: () => onOpenLink('https://chat.whatsapp.com/Bqyg5vkh8KN8ISOMESk67N'),
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

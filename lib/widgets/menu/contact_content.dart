import 'package:flutter/material.dart';

import '../../services/chat_service.dart';
import '../../theme/app_surfaces.dart';
import '../chat/chat_screen.dart';

class ContactContent extends StatelessWidget {
  final Future<void> Function(String url) onOpenLink;

  const ContactContent({super.key, required this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // null in the previous look and in night mode: the old colours stay
    final s = AppSurfaces.maybeOf(context);
    final cardColor = isDarkMode ? const Color(0xFF1A1A1A) : s?.card ?? const Color(0xFFF8F1DE);
    final borderColor = isDarkMode ? const Color(0xFF53401F) : s?.border ?? const Color(0xFFE2D2A5);
    final titleColor = isDarkMode ? Colors.white : s?.text ?? const Color(0xFF35250E);
    final radius = s == null ? 18.0 : AppSurfaces.cardRadius;

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
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            // the new look: one icon colour for every row, the chosen gold
            // outline on «راسلنا مباشرة», no shadow
            color: highlighted && s == null
                ? Color.alphaBlend(
                    accentColor.withValues(alpha: 0.10),
                    cardColor,
                  )
                : cardColor,
            borderRadius: BorderRadius.circular(radius),
            border: highlighted
                ? Border.all(color: s?.selected ?? accentColor, width: 1.5)
                : Border.all(color: borderColor),
            boxShadow: s != null
                ? null
                : [
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
                  color: s?.tile ?? accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: s?.icon ?? accentColor),
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
                        fontWeight: s == null ? FontWeight.w800 : FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      textDirection: subtitleDirection,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: s == null ? FontWeight.w600 : FontWeight.w500,
                        color: s?.muted ?? titleColor.withValues(alpha: 0.75),
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

import 'package:flutter/material.dart';
import 'settings_constants.dart';
import '../../services/high_quality_images_service.dart';
import '../../services/margin_images_service.dart';

class PremiumIconWrapper extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const PremiumIconWrapper({super.key, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? const Color(0xFF8B7355);
    return Icon(icon, color: iconColor, size: 24);
  }
}

class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(right: 16, left: 16, top: 24, bottom: 8),
      child: Text(
        title,
        textDirection: TextDirection.rtl,
        style: const TextStyle(
          color: Color(0xFF8B7355), // Light gold
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  final Widget child;

  const SettingsCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE8DCC8),
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}

class SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final VoidCallback? onHelp;
  final ValueChanged<bool> onChanged;

  const SwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    this.onHelp,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Switch(
        activeColor: const Color(0xFF8B7355),
        value: value,
        onChanged: onChanged,
      ),
      title: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Text(
              title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C2C2C),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PremiumIconWrapper(icon: icon),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          subtitle,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF888888),
            height: 1.5,
          ),
        ),
      ),
      onTap: () => onChanged(!value),
    );
  }
}

class ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const ActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF8B7355)),
      title: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Text(
              title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C2C2C),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PremiumIconWrapper(icon: icon),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          subtitle,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF888888),
            height: 1.5,
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

class DownloadsManagementTile extends StatelessWidget {
  final VoidCallback onOpen;

  const DownloadsManagementTile({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'إدارة الملفات المحمّلة',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'اعرض الملفات الإضافية التي حملتها، وحجمها الحالي، واحذف ما لا تحتاجه لاحقًا.',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF888888),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_outlined, color: Color(0xFF8B7355)),
            label: const Text('فتح إدارة الملفات',
                style: TextStyle(color: Color(0xFF8B7355))),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF8B7355)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

class HighQualityImagesTile extends StatelessWidget {
  final HighQualityImagesState state;
  final Future<void> Function() onDownload;

  const HighQualityImagesTile({
    super.key,
    required this.state,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'الصور عالية الجودة',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            state.isAvailable
                ? 'تم تحميل الصور عالية الجودة وسيستخدمها التطبيق تلقائيًا.'
                : 'نزّل ملف الصور عالية الجودة مرة واحدة، وبعد اكتمال التحميل سيستخدمها التطبيق تلقائيًا.',
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF888888),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          if (!state.isAvailable && !state.isDownloading)
            OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, color: Color(0xFF8B7355)),
              label: Text('تحميل الجودة العالية (${state.packageSizeLabel})',
                  style: const TextStyle(color: Color(0xFF8B7355))),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF8B7355)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          if (state.isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: state.totalBytes > 0 ? state.progress : null,
                backgroundColor: const Color(0xFFE8DCC8).withOpacity(0.3),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF8B7355)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              textDirection: TextDirection.rtl,
              children: [
                Text(
                  state.progressLabel,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF888888)),
                ),
                Text(
                  state.percentLabel,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8B7355)),
                ),
              ],
            ),
          ],
          if (state.isAvailable)
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              textDirection: TextDirection.rtl,
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 19, color: Color(0xFF4B7F3A)),
                SizedBox(width: 6),
                Text(
                  'الجودة العالية مفعّلة',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4B7F3A),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class MarginImagesTile extends StatelessWidget {
  final MarginImagesState state;
  final Future<void> Function() onDownload;
  final Future<void> Function() onCancelDownload;
  final Future<void> Function(bool value) onToggleEnabled;

  const MarginImagesTile({
    super.key,
    required this.state,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'عرض الهوامش',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            state.isAvailable
                ? 'بعد تنزيل صور الهوامش يمكنك التبديل بين العرض بالهوامش والعرض العادي.'
                : 'نزّل حزمة صور الهوامش أولًا، ثم اختر لاحقًا تفعيل عرض الهوامش أو إيقافه.',
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF888888),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          if (!state.isAvailable && !state.isDownloading)
            OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, color: Color(0xFF8B7355)),
              label: Text('تحميل عرض الهوامش (${state.packageSizeLabel})',
                  style: const TextStyle(color: Color(0xFF8B7355))),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF8B7355)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          if (state.isDownloading) ...[
            LinearProgressIndicator(
              minHeight: 8,
              value: state.totalBytes > 0 ? state.progress : null,
              backgroundColor: const Color(0xFFE8DCC8).withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B7355)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              textDirection: TextDirection.rtl,
              children: [
                Text(state.progressLabel,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF888888))),
                Text(state.percentLabel,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF8B7355))),
              ],
            ),
          ],
          if (state.isAvailable)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'تفعيل عرض الهوامش',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C2C2C),
                ),
              ),
              activeColor: const Color(0xFF8B7355),
              value: state.isEnabled,
              onChanged: onToggleEnabled,
            ),
        ],
      ),
    );
  }
}

class TabletLayoutTile extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const TabletLayoutTile({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchTile(
      title: 'عرض الصفحتين',
      subtitle: 'عرض صفحتين معاً في الوضع الأفقي (للأجهزة اللوحية).',
      icon: Icons.auto_stories_rounded,
      value: value,
      onChanged: enabled ? onChanged : (_) {},
    );
  }
}

class ModeTile extends StatelessWidget {
  final bool isTablet;
  final bool isPortraitScrollMode;
  final bool allowPortraitScrollMode;
  final bool lockToScrollMode;
  final VoidCallback? onHelp;
  final VoidCallback? onDisabledTap;
  final ValueChanged<bool> onTogglePortraitScrollMode;

  const ModeTile({
    super.key,
    required this.isTablet,
    required this.isPortraitScrollMode,
    required this.allowPortraitScrollMode,
    required this.lockToScrollMode,
    this.onHelp,
    this.onDisabledTap,
    required this.onTogglePortraitScrollMode,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchTile(
      title: 'وضع التمرير',
      subtitle: isPortraitScrollMode
          ? 'التمرير الرأسي المستمر (مثل صفحات الويب).'
          : 'التصفح عن طريق سحب الصفحات يميناً ويساراً.',
      icon: Icons.swap_calls_rounded,
      value: isPortraitScrollMode,
      onChanged: allowPortraitScrollMode ? onTogglePortraitScrollMode : (_) => onDisabledTap?.call(),
    );
  }
}

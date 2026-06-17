import 'package:flutter/material.dart';
import '../../services/audio_download_service.dart';
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
      padding: const EdgeInsets.only(right: 16, left: 16, top: 14, bottom: 6),
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      dense: true,
      visualDensity: VisualDensity.compact,
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF8B7355)),
      title: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Text(
              title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontSize: 14,
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
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          subtitle,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF888888),
            height: 1.4,
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

/// A compact, square-ish navigation card meant to sit two-per-row. Shows an
/// icon and a short title only (no subtitle), so a pair fits the width that a
/// single full ActionTile used to take.
/// A small circular ℹ️ button used to open a setting's instruction card.
class InfoHintButton extends StatelessWidget {
  final VoidCallback onTap;

  const InfoHintButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: Color(0xFF8B7355),
        ),
      ),
    );
  }
}

class CompactActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onInfo;

  const CompactActionTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8DCC8), width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              PremiumIconWrapper(icon: icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  textDirection: TextDirection.rtl,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C2C2C),
                  ),
                ),
              ),
              if (onInfo != null) InfoHintButton(onTap: onInfo!),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact toggle card meant to sit two-per-row: icon, single-line title,
/// and a switch — for simple on/off settings that don't need a subtitle.
class CompactSwitchTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onInfo;

  const CompactSwitchTile({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(!value),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8DCC8), width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(icon, color: const Color(0xFF8B7355), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  textDirection: TextDirection.rtl,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C2C2C),
                  ),
                ),
              ),
              if (onInfo != null) ...[
                InfoHintButton(onTap: onInfo!),
                const SizedBox(width: 2),
              ],
              const SizedBox(width: 4),
              Switch(
                activeThumbColor: const Color(0xFF8B7355),
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DownloadsManagementTile extends StatelessWidget {
  final VoidCallback onOpen;

  const DownloadsManagementTile({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'إدارة الملفات المحمّلة',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'اعرض الملفات الإضافية التي حملتها، وحجمها الحالي، واحذف ما لا تحتاجه لاحقًا.',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF888888),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_outlined, color: Color(0xFF8B7355), size: 18),
            label: const Text('فتح إدارة الملفات',
                style: TextStyle(color: Color(0xFF8B7355), fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF8B7355)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

class AudioDownloadTile extends StatelessWidget {
  final AudioDownloadState state;
  final Future<void> Function() onDownload;
  final void Function() onCancelDownload;
  final void Function() onPauseDownload;

  const AudioDownloadTile({
    super.key,
    required this.state,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onPauseDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'تحميل جميع الصوتيات',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            state.isComplete
                ? 'جميع ملفات الصوت محملة، يمكن الاستماع للتلاوة بدون إنترنت.'
                : 'نزّل ملفات الصوت كاملة للاستماع بدون اتصال بالإنترنت. الحجم التقريبي ~500 MB.',
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF888888),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          if (!state.isComplete && !state.isDownloading && !state.isPaused)
            OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, color: Color(0xFF8B7355), size: 18),
              label: Text(
                state.downloadedFiles > 0
                    ? 'استئناف تحميل الصوت (${state.progressLabel})'
                    : 'تحميل ملفات الصوت (~500 MB)',
                style: const TextStyle(color: Color(0xFF8B7355), fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF8B7355)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          if (state.isPaused && !state.isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: state.progressFraction,
                backgroundColor: const Color(0xFFE8DCC8).withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFB0956E)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              textDirection: TextDirection.rtl,
              children: [
                Text(state.progressLabel, style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
                Text(state.percentLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8B7355))),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF8B7355), size: 18),
              label: const Text('استئناف التحميل', style: TextStyle(color: Color(0xFF8B7355), fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF8B7355)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
          if (state.isDownloading) ...[
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                  onPressed: onCancelDownload,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.pause_circle_filled_rounded, color: Color(0xFF8B7355)),
                  onPressed: onPauseDownload,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: state.progressFraction > 0 ? state.progressFraction : null,
                      backgroundColor: const Color(0xFFE8DCC8).withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B7355)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              textDirection: TextDirection.rtl,
              children: [
                Text(state.progressLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF888888))),
                Text(state.percentLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8B7355))),
              ],
            ),
          ],
          if (state.isComplete)
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              textDirection: TextDirection.rtl,
              children: [
                Icon(Icons.check_circle_rounded, size: 19, color: Color(0xFF4B7F3A)),
                SizedBox(width: 6),
                Text(
                  'الصوت محمّل بالكامل',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF4B7F3A)),
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
  final Future<void> Function() onPauseDownload;
  final Future<void> Function(bool value) onToggleEnabled;

  const MarginImagesTile({
    super.key,
    required this.state,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onPauseDownload,
    required this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'عرض الهوامش',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            state.isAvailable
                ? 'بعد تنزيل صور الهوامش يمكنك التبديل بين العرض بالهوامش والعرض العادي.'
                : 'نزّل حزمة صور الهوامش أولًا، ثم اختر لاحقًا تفعيل عرض الهوامش أو إيقافه.',
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF888888),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          if (!state.isAvailable && !state.isDownloading && !state.isPaused)
            OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, color: Color(0xFF8B7355), size: 18),
              label: Text('تحميل عرض الهوامش (${state.packageSizeLabel})',
                  style: const TextStyle(color: Color(0xFF8B7355), fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF8B7355)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          if (state.isPaused && !state.isDownloading) ...[
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.cancel_rounded, color: Colors.red, size: 22),
                  onPressed: onCancelDownload,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: state.totalBytes > 0 ? state.progress : null,
                      backgroundColor: const Color(0xFFE8DCC8).withValues(alpha: 0.3),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Color(0xFFB0956E)),
                    ),
                  ),
                ),
              ],
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
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8B7355))),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF8B7355), size: 18),
              label: const Text('استئناف التحميل',
                  style: TextStyle(color: Color(0xFF8B7355), fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF8B7355)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
          if (state.isDownloading) ...[
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                  onPressed: onCancelDownload,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.pause_circle_filled_rounded, color: Color(0xFF8B7355)),
                  onPressed: onPauseDownload,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: state.totalBytes > 0 ? state.progress : null,
                      backgroundColor: const Color(0xFFE8DCC8).withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B7355)),
                    ),
                  ),
                ),
              ],
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
              dense: true,
              visualDensity: VisualDensity.compact,
              title: const Text(
                'تفعيل عرض الهوامش',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C2C2C),
                ),
              ),
              activeThumbColor: const Color(0xFF8B7355),
              value: state.isEnabled,
              onChanged: onToggleEnabled,
            ),
        ],
      ),
    );
  }
}

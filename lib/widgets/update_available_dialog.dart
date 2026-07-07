import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';

/// The in-app "there is an update" message: a short intro, a bulleted list of
/// what's new, and an "Update" button that opens the store page.
///
/// Shown on startup (once per version) and on demand from Settings. Returns
/// after the user dismisses it; opening the store happens inside the dialog.
class UpdateAvailableDialog extends StatelessWidget {
  final AppUpdateInfo info;

  const UpdateAvailableDialog({super.key, required this.info});

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !info.mandatory,
      builder: (_) => UpdateAvailableDialog(info: info),
    );
  }

  Future<void> _openStore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(
        Uri.parse(info.storeUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        messenger.showSnackBar(
          const SnackBar(content: Text('تعذر فتح المتجر')),
        );
      }
    } on PlatformException {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر فتح المتجر')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF35250E);
    final bodyColor = isDark ? Colors.white70 : const Color(0xFF6E5837);
    const accent = Color(0xFF8D6E3F);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFBF6E8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
        title: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: isDark ? 0.26 : 0.15),
              ),
              child: const Icon(
                Icons.system_update_rounded,
                color: accent,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'يوجد تحديث جديد',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'الإصدار ${info.latestVersion}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: bodyColor,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ننصحك بالتحديث للحصول على آخر التحسينات. يتضمن هذا التحديث:',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    fontWeight: FontWeight.w600,
                    color: bodyColor,
                  ),
                ),
                const SizedBox(height: 12),
                if (info.changes.isEmpty)
                  Text(
                    'تحسينات وإصلاحات عامة.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.7,
                      color: bodyColor,
                    ),
                  )
                else
                  ...info.changes.map(
                    (change) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Icon(
                              Icons.circle,
                              size: 7,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              change,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          if (!info.mandatory)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'لاحقًا',
                style: TextStyle(color: bodyColor, fontWeight: FontWeight.w700),
              ),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('تحديث الآن'),
            onPressed: () => _openStore(context),
          ),
        ],
      ),
    );
  }
}

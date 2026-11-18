import 'package:flutter/material.dart';

import '../theme/app_surfaces.dart';

/// A one-time "what's new" popup listing changes already included in the
/// installed build. Unlike [UpdateAvailableDialog] (which offers to open the
/// store for a *newer* release), this has nothing to download — just an
/// acknowledgement button.
///
/// With [tour] its only button is «أرني أين» and it cannot be dismissed any
/// other way; [show] then returns true, and the caller runs the settings tour.
///
/// [showNotice] uses the same card for a message from our server
/// (`ServerNoticeService`): its own [title], no intro line, and an optional
/// second button ([actionLabel]).
class WhatsNewDialog extends StatelessWidget {
  final List<String> changes;
  final bool tour;
  final String title;
  final String? intro;
  final String? actionLabel;

  const WhatsNewDialog({
    super.key,
    required this.changes,
    this.tour = false,
    this.title = 'ما الجديد',
    this.intro = 'أضفنا وحسّنّا في هذا الإصدار:',
    this.actionLabel,
  });

  /// A server notice. Returns true when its [actionLabel] button was pressed.
  static Future<bool> showNotice(
    BuildContext context, {
    required String title,
    required List<String> lines,
    String? actionLabel,
  }) async {
    final pressed = await showDialog<bool>(
      context: context,
      builder: (_) => WhatsNewDialog(
        changes: lines,
        title: title,
        intro: null,
        actionLabel: actionLabel,
      ),
    );
    return pressed == true;
  }

  static Future<bool> show(
    BuildContext context,
    List<String> changes, {
    bool tour = false,
  }) async {
    final showMe = await showDialog<bool>(
      context: context,
      barrierDismissible: !tour,
      builder: (_) => WhatsNewDialog(changes: changes, tour: tour),
    );
    return tour && showMe == true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // null in the previous look and in night mode: the old colours stay
    final s = AppSurfaces.maybeOf(context);
    final titleColor = isDark ? Colors.white : s?.text ?? const Color(0xFF35250E);
    final bodyColor = isDark ? Colors.white70 : s?.muted ?? const Color(0xFF6E5837);
    final accent = s?.accent ?? const Color(0xFF8D6E3F);

    return PopScope(
      canPop: !tour,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: isDark
              ? const Color(0xFF1A1A1A)
              : s?.sheet ?? const Color(0xFFFBF6E8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              s == null ? 22 : AppSurfaces.radius,
            ),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
          title: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s?.tile ?? accent.withValues(alpha: isDark ? 0.26 : 0.15),
                ),
                child: Icon(
                  Icons.campaign_rounded,
                  color: s?.icon ?? accent,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: s == null ? FontWeight.w900 : FontWeight.w600,
                  color: titleColor,
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
                  if (intro != null)
                    Text(
                      intro!,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        fontWeight: s == null
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: bodyColor,
                      ),
                    ),
                  if (intro != null) const SizedBox(height: 12),
                  ...changes.map(
                    (change) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Icon(Icons.circle, size: 7, color: accent),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              change,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                fontWeight: s == null
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: titleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (tour)
                    Text(
                      'المس الصفحة متى شئت لتظهر الأدوات والإعدادات.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.6,
                        fontWeight: s == null ? FontWeight.w700 : FontWeight.w600,
                        color: accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          actions: [
            if (actionLabel != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: accent),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('حسنًا'),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: s?.button ?? accent,
                foregroundColor: s?.onButton,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () =>
                  Navigator.of(context).pop(actionLabel != null ? true : tour),
              child: Text(actionLabel ?? (tour ? 'أرني أين' : 'حسنًا')),
            ),
          ],
        ),
      ),
    );
  }
}

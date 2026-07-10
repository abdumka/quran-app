import 'package:flutter/material.dart';

/// A one-time "what's new" popup listing changes already included in the
/// installed build. Unlike [UpdateAvailableDialog] (which offers to open the
/// store for a *newer* release), this has nothing to download — just an
/// acknowledgement button.
class WhatsNewDialog extends StatelessWidget {
  final List<String> changes;

  const WhatsNewDialog({super.key, required this.changes});

  static Future<void> show(BuildContext context, List<String> changes) {
    return showDialog<void>(
      context: context,
      builder: (_) => WhatsNewDialog(changes: changes),
    );
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
                Icons.auto_awesome_rounded,
                color: accent,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'ما الجديد',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
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
                Text(
                  'أضفنا وحسّنّا في هذا الإصدار:',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    fontWeight: FontWeight.w600,
                    color: bodyColor,
                  ),
                ),
                const SizedBox(height: 12),
                ...changes.map(
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
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }
}

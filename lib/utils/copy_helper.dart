import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Clipboard helpers shared by the tafsir sheet and the search results.
///
/// `Clipboard.setData` is the one write path that behaves the same on Android,
/// iOS and web (on web Flutter routes it through the async Clipboard API and
/// falls back to `document.execCommand('copy')`). Browsers only honour it from
/// inside a user gesture and may still refuse it outright, so every copy is
/// wrapped: when the write fails the text is shown in a selectable dialog so it
/// can still be copied by hand.
class CopyHelper {
  const CopyHelper._();

  /// Formats one verse for the clipboard: the text between ornate brackets
  /// followed by its reference, e.g. `﴿ ... ﴾ [البقرة: 2]`.
  static String formatAyah({
    required String surahName,
    required int ayahNumber,
    required String text,
  }) {
    return '﴿ ${text.trim()} ﴾ [$surahName: $ayahNumber]';
  }

  /// Formats a commentary block: the verse, then the edition name, then the
  /// tafsir itself — so a pasted block always carries its attribution.
  static String formatAyahWithTafsir({
    required String surahName,
    required int ayahNumber,
    required String ayahText,
    required String tafsirText,
    required String editionName,
  }) {
    final ayah = formatAyah(
      surahName: surahName,
      ayahNumber: ayahNumber,
      text: ayahText,
    );
    return '$ayah\n\n$editionName:\n${tafsirText.trim()}';
  }

  /// Writes [text] to the clipboard and confirms with a floating toast. Shows a
  /// manual-copy dialog instead when the platform refuses the write.
  static Future<void> copy(
    BuildContext context,
    String text, {
    String message = 'تم النسخ',
  }) async {
    if (text.trim().isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      showToast(context, message);
    } catch (_) {
      if (!context.mounted) return;
      await _showManualCopyDialog(context, text);
    }
  }

  static OverlayEntry? _activeToast;

  /// A toast drawn in the **root** overlay so it stays visible above modal
  /// bottom sheets — a `SnackBar` would be painted underneath the tafsir sheet.
  static void showToast(BuildContext context, String message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(message, textDirection: TextDirection.rtl),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    _activeToast?.remove();
    _activeToast = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _CopyToast(
        message: message,
        onFinished: () {
          if (_activeToast == entry) _activeToast = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _activeToast = entry;
    overlay.insert(entry);
  }

  static Future<void> _showManualCopyDialog(
    BuildContext context,
    String text,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('انسخ النص يدويًا'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 16, height: 1.7),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades in, holds, fades out, then asks to be removed from the overlay.
class _CopyToast extends StatefulWidget {
  final String message;
  final VoidCallback onFinished;

  const _CopyToast({required this.message, required this.onFinished});

  @override
  State<_CopyToast> createState() => _CopyToastState();
}

class _CopyToastState extends State<_CopyToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: media.viewPadding.bottom + 90,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _controller,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOut),
            ),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.message,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

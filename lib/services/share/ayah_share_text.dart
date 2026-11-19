import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../surah_data.dart';
import '../../utils/quran_display_text.dart';
import '../quran_json_service.dart';
import 'share_video_config.dart';

/// «نص الآية»: the ayah as text, with its surah and number, the riwaya, the
/// app's name and its link, all from the server template
/// ([ShareVideoConfig.textTemplate]).
class AyahShareText {
  AyahShareText._();

  /// The ayah's text as the app displays it (the same tanween and alef
  /// maqsura fixes as the reader, so it reads right in other apps' fonts).
  static Future<String?> ayahText(int surah, int ayah) async {
    final pages = await QuranJsonService.loadQuranPages();
    final parts = <String>[];
    for (final page in pages) {
      for (final a in page.ayahs) {
        if (a.surah == surah && a.ayah == ayah) parts.add(a.text);
      }
    }
    if (parts.isEmpty) return null;
    return quranDisplayText(parts.join(' ').trim());
  }

  static String surahName(int surah) =>
      surahList
          .firstWhere(
            (s) => s['number'] == surah,
            orElse: () => const {},
          )['name']
          ?.toString() ??
      '$surah';

  static Future<String?> build(int surah, int ayah) async {
    final config = await ShareVideoConfig.load();
    final text = await ayahText(surah, ayah);
    if (text == null) return null;
    return config.textTemplate
        .replaceAll('{text}', text)
        .replaceAll('{surah}', surahName(surah))
        .replaceAll('{ayah}', '$ayah')
        .replaceAll('{link}', config.link);
  }

  /// Opens the system share sheet with the text; copies it where sharing is
  /// unavailable.
  static Future<void> share(BuildContext anchor, int surah, int ayah) async {
    final messenger = ScaffoldMessenger.maybeOf(anchor);
    final box = anchor.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final message = await build(surah, ayah);
    if (message == null) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            ShareVideoConfig.tr('textFailed', 'تعذّر تجهيز نص الآية'),
          ),
        ),
      );
      return;
    }
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: message, sharePositionOrigin: origin),
      );
      if (result.status != ShareResultStatus.unavailable) return;
    } catch (_) {
      // fall through to the clipboard
    }
    await Clipboard.setData(ClipboardData(text: message));
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          ShareVideoConfig.tr('textCopied', 'تم نسخ نص الآية، الصقه لمشاركته'),
        ),
      ),
    );
  }
}

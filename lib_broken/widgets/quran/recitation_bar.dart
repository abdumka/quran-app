import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/audio_service.dart';
import '../../services/quran_json_service.dart';
import '../../models/quran_page_data.dart';

/// Recitation bottom bar with playback controls.
class RecitationBottomBar extends StatelessWidget {
  final VoidCallback onResetHideTimer;

  /// Current page (0-indexed) used by the ayah selection dialog.
  final int currentPageIndex;

  /// Cached quran page data for ayah selection.
  final List<QuranPageData>? allQuranPages;

  /// Called when quran pages are loaded for the first time.
  final ValueChanged<List<QuranPageData>> onQuranPagesLoaded;

  const RecitationBottomBar({
    super.key,
    required this.onResetHideTimer,
    required this.currentPageIndex,
    required this.allQuranPages,
    required this.onQuranPagesLoaded,
  });

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFFD2B97E);
    final audio = AudioService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([
        audio.isPlaying,
        audio.currentAyah,
        audio.pageRepeatMode,
        audio.repeatMode,
      ]),
      builder: (context, _) {
        final isPlaying = audio.isPlaying.value;
        final currentAyah = audio.currentAyah.value;
        final repeatModeVal = audio.repeatMode.value;
        final pageRepeatModeVal = audio.pageRepeatMode.value;
        final isRepeating = repeatModeVal != AyahRepeatMode.off;
        final repeatLabel = audio.repeatLabel;
        final isPageRepeating = pageRepeatModeVal != AyahRepeatMode.off;
        final pageRepeatLabel = audio.pageRepeatLabel;

        return Container(
          color: const Color(0xFF1C1C1E),
          padding: const EdgeInsets.only(
            left: 6,
            right: 6,
            top: 10,
            bottom: 24,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _barIcon(
                icon: Icons.replay_rounded,
                color: isPageRepeating ? accentColor : Colors.white.withValues(alpha: 0.7),
                badgeText: isPageRepeating && pageRepeatLabel.isNotEmpty ? pageRepeatLabel : null,
                badgeColor: accentColor,
                onPressed: () {
                  onResetHideTimer();
                  audio.cyclePageRepeatMode();
                },
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.skip_previous_rounded,
                    color: accentColor.withValues(alpha: 0.9), size: 28),
                onPressed: () {
                  onResetHideTimer();
                  audio.previousAyah();
                },
              ),
              GestureDetector(
                onTap: () {
                  onResetHideTimer();
                  if (currentAyah != null) {
                    _showAyahSelectionDialog(context, currentAyah);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    currentAyah != null
                        ? '\u0622\u064A\u0629 ${currentAyah.ayah}'
                        : '\u0622\u064A\u0629 1',
                    style: const TextStyle(
                      color: accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  onResetHideTimer();
                  if (isPlaying) {
                    audio.pause();
                  } else {
                    audio.resume();
                  }
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: accentColor,
                    size: 32,
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.skip_next_rounded,
                    color: accentColor.withValues(alpha: 0.9), size: 28),
                onPressed: () {
                  onResetHideTimer();
                  audio.nextAyah();
                },
              ),
              _barIcon(
                icon: Icons.repeat_rounded,
                color: isRepeating ? accentColor : Colors.white.withValues(alpha: 0.7),
                badgeText: isRepeating && repeatLabel.isNotEmpty ? repeatLabel : null,
                badgeColor: accentColor,
                onPressed: () {
                  onResetHideTimer();
                  audio.cycleAyahRepeatMode();
                },
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.grey, size: 24),
                onPressed: () {
                  onResetHideTimer();
                  audio.stop();
                },
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.help_outline_rounded,
                    color: Colors.grey, size: 20),
                onPressed: () {
                  onResetHideTimer();
                  showRecitationBarGuide(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _barIcon({
    required IconData icon,
    required Color color,
    String? badgeText,
    Color? badgeColor,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: onPressed,
      icon: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          if (badgeText != null)
            Positioned(
              bottom: -2,
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 7,
                  color: badgeColor ?? color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAyahSelectionDialog(BuildContext context, QuranAyahData currentAyah) async {
    var pages = allQuranPages;
    if (pages == null) {
      final data = await QuranJsonService.loadQuranPages();
      onQuranPagesLoaded(data);
      pages = data;
    }

    if (!context.mounted) return;

    final pageData = pages.firstWhere(
      (p) => p.page == currentPageIndex + 1,
      orElse: () => QuranPageData(page: currentPageIndex + 1, ayahs: []),
    );
    final pageAyahs = pageData.ayahs;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  // "اختر الآية - صفحة"
                  '\u0627\u062E\u062A\u0631 \u0627\u0644\u0622\u064A\u0629 - \u0635\u0641\u062D\u0629 ${currentPageIndex + 1}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: pageAyahs.length,
                  itemBuilder: (context, index) {
                    final ayah = pageAyahs[index];
                    final isCurrent = ayah.ayah == currentAyah.ayah && ayah.surah == currentAyah.surah;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        AudioService.instance.jumpToAyah(ayah.surah, ayah.ayah);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? const Color(0xFFD6B35D).withValues(alpha: 0.2)
                              : Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? const Color(0xFFD6B35D)
                                : Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${ayah.ayah}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent ? const Color(0xFFD6B35D) : Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shows the recitation bar help/guide dialog.
void showRecitationBarGuide(BuildContext context) {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  final bgColor = isDarkMode ? const Color(0xFF1E1A12) : const Color(0xFFF8F1DE);
  final titleColor = isDarkMode ? const Color(0xFFD6B35D) : const Color(0xFF8D6E3F);
  final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
  final borderColor = isDarkMode ? const Color(0xFF53401F) : const Color(0xFFE2D2A5);
  bool doNotShowAgain = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          // "شرح أزرار شريط التلاوة"
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.help_outline_rounded, color: titleColor, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '\u0634\u0631\u062D \u0623\u0632\u0631\u0627\u0631 \u0634\u0631\u064A\u0637 \u0627\u0644\u062A\u0644\u0627\u0648\u0629',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: titleColor),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // "إغلاق شريط التلاوة"
                _guideRow(Icons.close_rounded, '\u0625\u063A\u0644\u0627\u0642 \u0634\u0631\u064A\u0637 \u0627\u0644\u062A\u0644\u0627\u0648\u0629', textColor, borderColor),
                // "الآية السابقة"
                _guideRow(Icons.skip_next_rounded, '\u0627\u0644\u0622\u064A\u0629 \u0627\u0644\u0633\u0627\u0628\u0642\u0629', textColor, borderColor),
                // "تشغيل / إيقاف مؤقت"
                _guideRow(Icons.play_arrow_rounded, '\u062A\u0634\u063A\u064A\u0644 / \u0625\u064A\u0642\u0627\u0641 \u0645\u0624\u0642\u062A', textColor, borderColor),
                // "الآية التالية"
                _guideRow(Icons.skip_previous_rounded, '\u0627\u0644\u0622\u064A\u0629 \u0627\u0644\u062A\u0627\u0644\u064A\u0629', textColor, borderColor),
                // "تكرار الصفحة (اضغط للتبديل)"
                _guideRow(Icons.replay_rounded, '\u062A\u0643\u0631\u0627\u0631 \u0627\u0644\u0635\u0641\u062D\u0629 (\u0627\u0636\u063A\u0637 \u0644\u0644\u062A\u0628\u062F\u064A\u0644)', textColor, borderColor),
                // "تكرار الآية (اضغط عدة مرات للتبديل)"
                _guideRow(Icons.repeat_rounded, '\u062A\u0643\u0631\u0627\u0631 \u0627\u0644\u0622\u064A\u0629 (\u0627\u0636\u063A\u0637 \u0639\u062F\u0629 \u0645\u0631\u0627\u062A \u0644\u0644\u062A\u0628\u062F\u064A\u0644)', textColor, borderColor),
                const SizedBox(height: 16),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: CheckboxListTile(
                    value: doNotShowAgain,
                    onChanged: (value) {
                      setState(() {
                        doNotShowAgain = value ?? false;
                      });
                    },
                    // "لا تظهر هذه الرسالة مرة أخرى"
                    title: Text(
                      '\u0644\u0627 \u062A\u0638\u0647\u0631 \u0647\u0630\u0647 \u0627\u0644\u0631\u0633\u0627\u0644\u0629 \u0645\u0631\u0629 \u0623\u062E\u0631\u0649',
                      style: TextStyle(color: textColor, fontSize: 14),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: titleColor,
                    checkColor: bgColor,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (doNotShowAgain) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('recitation_guide_dismissed', true);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              // "فهمت"
              child: Text('\u0641\u0647\u0645\u062A', style: TextStyle(color: titleColor, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    ),
  );
}

Widget _guideRow(IconData icon, String label, Color textColor, Color borderColor) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      textDirection: TextDirection.rtl,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: borderColor.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: textColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildRecitationTopBar({required double topOffset}) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      top: topOffset,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<bool>(
        valueListenable: AudioService.instance.isRecitationBarVisible,
        builder: (context, isVisible, _) {
          if (!isVisible) return const SizedBox.shrink();

          final isDarkMode = Theme.of(context).brightness == Brightness.dark;
          final bgColor = isDarkMode
              ? const Color(0xFF15120B).withValues(alpha: 0.97)
              : Colors.white.withValues(alpha: 0.97);
          final borderColor = isDarkMode
              ? const Color(0xFFD6B35D).withValues(alpha: 0.60)
              : Colors.black.withValues(alpha: 0.08);
          final accentColor = isDarkMode
              ? const Color(0xFFD6B35D)
              : const Color(0xFF8D6E3F);
          final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
          final subtleColor = isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04);

          return SafeArea(
            bottom: false,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ValueListenableBuilder<QuranAyahData?>(
                valueListenable: AudioService.instance.currentAyah,
                builder: (context, currentAyah, _) {
                  return ValueListenableBuilder<AyahRepeatMode>(
                    valueListenable: AudioService.instance.pageRepeatMode,
                    builder: (context, pageRepeatModeVal, _) {
                      return ValueListenableBuilder<AyahRepeatMode>(
                        valueListenable: AudioService.instance.repeatMode,
                        builder: (context, repeatModeVal, _) {
                          final isRepeating = repeatModeVal != AyahRepeatMode.off;
                          final repeatLabel = AudioService.instance.repeatLabel;
                          final isPageRepeating = pageRepeatModeVal != AyahRepeatMode.off;
                          final pageRepeatLabel = AudioService.instance.pageRepeatLabel;

                          return Row(
                            children: [
                              // Close button
                              Container(
                                decoration: BoxDecoration(
                                  color: subtleColor,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: () => AudioService.instance.closeRecitationBar(),
                                  icon: Icon(Icons.close_rounded, color: textColor, size: 14),
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                  tooltip: 'إغلاق شريط التلاوة',
                                ),
                              ),
                              const SizedBox(width: 6),

                              // Replay page button
                              Container(
                                decoration: BoxDecoration(
                                  color: isPageRepeating
                                      ? accentColor.withValues(alpha: 0.18)
                                      : subtleColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isPageRepeating
                                      ? Border.all(color: accentColor.withValues(alpha: 0.5))
                                      : null,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => AudioService.instance.cyclePageRepeatMode(),
                                    child: Container(
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.replay_rounded,
                                            color: isPageRepeating ? accentColor : textColor,
                                            size: 14,
                                          ),
                                          if (isPageRepeating && pageRepeatLabel.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              pageRepeatLabel,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: accentColor,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // Repeat ayah button
                              Container(
                                decoration: BoxDecoration(
                                  color: isRepeating
                                      ? accentColor.withValues(alpha: 0.18)
                                      : subtleColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isRepeating
                                      ? Border.all(color: accentColor.withValues(alpha: 0.5))
                                      : null,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => AudioService.instance.cycleRepeatMode(),
                                    child: Container(
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.repeat_rounded,
                                            color: isRepeating ? accentColor : textColor,
                                            size: 14,
                                          ),
                                          if (isRepeating && repeatLabel.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              repeatLabel,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: accentColor,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              const Spacer(),

                              // Ayah info
                              Expanded(
                                flex: 2,
                                child: currentAyah != null
                                    ? Text(
                                        '${currentAyah.surahName} : ${currentAyah.ayah}',
                                        textAlign: TextAlign.end,
                                        textDirection: TextDirection.rtl,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: textColor,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecitationBottomBar(double bottomOffset) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      bottom: bottomOffset,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<bool>(
        valueListenable: AudioService.instance.isRecitationBarVisible,
        builder: (context, isVisible, _) {
          if (!isVisible) return const SizedBox.shrink();

          final isDarkMode = Theme.of(context).brightness == Brightness.dark;
          final bgColor = isDarkMode
              ? const Color(0xFF15120B).withValues(alpha: 0.97)
              : Colors.white.withValues(alpha: 0.97);
          final borderColor = isDarkMode
              ? const Color(0xFFD6B35D).withValues(alpha: 0.60)
              : Colors.black.withValues(alpha: 0.08);
          final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
          final subtleColor = isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04);
          final accentColor = isDarkMode
              ? const Color(0xFFD6B35D)
              : const Color(0xFF8D6E3F);

          return SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: AudioService.instance.isLoadingAudio,
                    builder: (context, isLoading, _) {
                      if (isLoading) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: accentColor,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'جارٍ تحميل الصوت...',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ValueListenableBuilder<bool>(
                        valueListenable: AudioService.instance.isPlaying,
                        builder: (context, isPlaying, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Previous ayah (RTL: skip_next visually points to previous)
                              Container(
                                decoration: BoxDecoration(
                                  color: subtleColor,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: () => AudioService.instance.previousAyah(),
                                  icon: Icon(Icons.skip_next_rounded, color: textColor, size: 20),
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                  tooltip: 'الآية السابقة',
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Play / Pause button
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isDarkMode
                                        ? const [Color(0xFFD6B35D), Color(0xFFB78D2D)]
                                        : const [Color(0xFF2D2A24), Color(0xFF15120B)],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: IconButton(
                                  onPressed: () {
                                    if (isPlaying) {
                                      AudioService.instance.pause();
                                    } else {
                                      if (!AudioService.instance.isAudioOnPage(_topBarCurrentPage)) {
                                        AudioService.instance.playPage(_topBarCurrentPage);
                                      } else {
                                        AudioService.instance.resume();
                                      }
                                    }
                                  },
                                  iconSize: 24,
                                  padding: const EdgeInsets.all(8),
                                  color: isDarkMode ? const Color(0xFF15120B) : Colors.white,
                                  icon: Icon(
                                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  ),
                                  tooltip: isPlaying ? 'إيقاف مؤقت' : 'تشغيل التلاوة',
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Next ayah (RTL: skip_previous visually points to next)
                              Container(
                                decoration: BoxDecoration(
                                  color: subtleColor,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: () => AudioService.instance.nextAyah(),
                                  icon: Icon(Icons.skip_previous_rounded, color: textColor, size: 20),
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                  tooltip: 'الآية التالية',
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

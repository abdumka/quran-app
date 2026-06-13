import re

quran_pages_path = r'c:\Users\Mahfod501\Desktop\flutter\quran\quran_app\lib\quran_pages.dart'

with open(quran_pages_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Define the new top bar
new_top_bar = """  Widget _buildRecitationTopBar({required double topOffset}) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      top: _isRecitationTopBarMinimized ? -100 : topOffset,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isRecitationTopBarMinimized ? 0.0 : 1.0,
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
              child: IgnorePointer(
                ignoring: _isRecitationTopBarMinimized,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                                      icon: Icon(Icons.close_rounded, color: textColor, size: 12),
                                      padding: const EdgeInsets.all(2),
                                      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
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
                                      borderRadius: BorderRadius.circular(10),
                                      border: isPageRepeating
                                          ? Border.all(color: accentColor.withValues(alpha: 0.5))
                                          : null,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () => AudioService.instance.cyclePageRepeatMode(),
                                        child: Container(
                                          constraints: const BoxConstraints(minWidth: 26, minHeight: 24),
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.replay_rounded,
                                                color: isPageRepeating ? accentColor : textColor,
                                                size: 12,
                                              ),
                                              if (isPageRepeating && pageRepeatLabel.isNotEmpty) ...[
                                                const SizedBox(width: 2),
                                                Text(
                                                  pageRepeatLabel,
                                                  style: TextStyle(
                                                    fontSize: 9,
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
                                  const SizedBox(width: 4),

                                  // Repeat ayah button
                                  Container(
                                    decoration: BoxDecoration(
                                      color: isRepeating
                                          ? accentColor.withValues(alpha: 0.18)
                                          : subtleColor,
                                      borderRadius: BorderRadius.circular(10),
                                      border: isRepeating
                                          ? Border.all(color: accentColor.withValues(alpha: 0.5))
                                          : null,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () => AudioService.instance.cycleAyahRepeatMode(),
                                        child: Container(
                                          constraints: const BoxConstraints(minWidth: 26, minHeight: 24),
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.repeat_rounded,
                                                color: isRepeating ? accentColor : textColor,
                                                size: 12,
                                              ),
                                              if (isRepeating && repeatLabel.isNotEmpty) ...[
                                                const SizedBox(width: 2),
                                                Text(
                                                  repeatLabel,
                                                  style: TextStyle(
                                                    fontSize: 9,
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

                                  // Help Button
                                  Container(
                                    decoration: BoxDecoration(
                                      color: subtleColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      onPressed: () {
                                        AudioService.instance.pause();
                                        _showRecitationBarGuide();
                                      },
                                      icon: Icon(Icons.help_outline_rounded, color: textColor.withValues(alpha: 0.5), size: 12),
                                      padding: const EdgeInsets.all(2),
                                      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                                      tooltip: 'إرشادات',
                                    ),
                                  ),
                                  const SizedBox(width: 6),

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
                                              fontSize: 11,
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
              ),
            );
          },
        ),
      ),
    );
  }"""

new_bottom_bar = """  Widget _buildRecitationBottomBar(double bottomOffset) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
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
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: _isRecitationTopBarMinimized ? Alignment.centerLeft : Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                margin: EdgeInsets.only(
                  bottom: 12, 
                  top: 12, 
                  left: _isRecitationTopBarMinimized ? 16 : 0,
                  right: _isRecitationTopBarMinimized ? 0 : 0
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                            if (!_isRecitationTopBarMinimized) ...[
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
                            ]
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
                            // Expand/Collapse Toggle Button
                            Container(
                              decoration: BoxDecoration(
                                color: subtleColor,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _isRecitationTopBarMinimized = !_isRecitationTopBarMinimized;
                                  });
                                },
                                icon: Icon(
                                  _isRecitationTopBarMinimized 
                                      ? Icons.open_in_full_rounded 
                                      : Icons.close_fullscreen_rounded, 
                                  color: textColor, 
                                  size: 18
                                ),
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                tooltip: _isRecitationTopBarMinimized ? 'توسيع الشريط' : 'تصغير الشريط',
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Previous ayah
                            if (!_isRecitationTopBarMinimized) ...[
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
                              const SizedBox(width: 8),
                            ],

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
                                iconSize: 20,
                                padding: const EdgeInsets.all(8),
                                color: isDarkMode ? const Color(0xFF15120B) : Colors.white,
                                icon: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                ),
                                tooltip: isPlaying ? 'إيقاف مؤقت' : 'تشغيل التلاوة',
                              ),
                            ),

                            // Next ayah
                            if (!_isRecitationTopBarMinimized) ...[
                              const SizedBox(width: 8),
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
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }"""

start_top = content.find('  Widget _buildRecitationTopBar({required double topOffset}) {')
end_bottom = content.find('  class _TafsirSheetContent extends StatefulWidget {')

# The Tafsir sheet class definition is actually 'class _TafsirSheetContent extends StatefulWidget {'
# Wait, no, we can just replace the block between start_top and end_bottom, but let's be safe and match the brace of _buildRecitationBottomBar.
start_bottom = content.find('  Widget _buildRecitationBottomBar(double bottomOffset) {')

def find_end_brace(text, start_idx):
    brace_count = 0
    for i in range(start_idx, len(text)):
        if text[i] == '{':
            brace_count += 1
        elif text[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                return i + 1
    return -1

end_idx = find_end_brace(content, start_bottom)

if start_top != -1 and start_bottom != -1 and end_idx != -1:
    new_content = content[:start_top] + new_top_bar + "\n\n" + new_bottom_bar + "\n\n" + content[end_idx:]
    with open(quran_pages_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print("Replaced both top and bottom bars successfully.")
else:
    print("Could not find the bounds.")

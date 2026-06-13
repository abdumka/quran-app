import re

file_path = r'c:\Users\Mahfod501\Desktop\flutter\quran\quran_app\lib\quran_pages.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add _lastAudioPageChangePromptTime
state_var_pattern = r'bool _isRecitationTopBarMinimized = false;'
state_var_replacement = r'bool _isRecitationTopBarMinimized = false;\n  DateTime? _lastAudioPageChangePromptTime;'
content = content.replace(state_var_pattern, state_var_replacement)

# 2. Add _showAudioSyncPrompt
prompt_func = """  void _showAudioSyncPrompt(int newPage) {
    _lastAudioPageChangePromptTime = DateTime.now();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        content: Text(
          'هل تود إكمال التلاوة من هذه الصفحة؟',
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
            fontFamily: 'Tajawal',
          ),
        ),
        action: SnackBarAction(
          label: 'نعم',
          textColor: const Color(0xFFD6B35D),
          onPressed: () {
            AudioService.instance.playPage(newPage);
          },
        ),
      ),
    );
  }"""
  
# Insert before _setCurrentPage
content = content.replace('  void _setCurrentPage(', prompt_func + '\n\n  void _setCurrentPage(')

# 3. Modify _setCurrentPage to call prompt
sync_target = """    if (showHizbPopup) {
      _showHizbPopupIfNeeded(safePage);
      _showSajdaPopupIfNeeded(safePage);
    }"""
sync_replacement = """    if (showHizbPopup) {
      _showHizbPopupIfNeeded(safePage);
      _showSajdaPopupIfNeeded(safePage);
    }

    if (AudioService.instance.isPlaying.value) {
      final audioPage = AudioService.instance.currentAudioPageIndex;
      if (audioPage != -1 && audioPage != safePage) {
        if (_lastAudioPageChangePromptTime == null ||
            DateTime.now().difference(_lastAudioPageChangePromptTime!).inMinutes > 60) {
          _showAudioSyncPrompt(safePage);
        }
      }
    }"""
content = content.replace(sync_target, sync_replacement)

# 4. Add _showAyahSelectionDialog
dialog_func = """  void _showAyahSelectionDialog(QuranAyahData currentAyah) {
    final surahNum = currentAyah.surah;
    final totalAyahs = surahList.firstWhere((s) => s['number'] == surahNum)['ayahs'] as int;

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
                  'اختر الآية - سورة ${currentAyah.surahName}',
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
                    crossAxisCount: 6,
                    childAspectRatio: 1,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: totalAyahs,
                  itemBuilder: (context, index) {
                    final ayahNum = index + 1;
                    final isCurrent = ayahNum == currentAyah.ayah;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        AudioService.instance.jumpToAyah(surahNum, ayahNum);
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
                          '$ayahNum',
                          style: TextStyle(
                            fontSize: 16,
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
  }"""
content = content.replace('  Widget _buildRecitationTopBar({required double topOffset}) {', dialog_func + '\n\n  Widget _buildRecitationTopBar({required double topOffset}) {')

# 5. Modify _buildRecitationTopBar
# color change to black and size increase

top_bar_start = content.find('  Widget _buildRecitationTopBar({required double topOffset}) {')
top_bar_end = content.find('  Widget _buildRecitationBottomBar(double bottomOffset) {')

if top_bar_start != -1 and top_bar_end != -1:
    top_bar_code = content[top_bar_start:top_bar_end]
    
    # colors
    top_bar_code = re.sub(
        r'final bgColor = isDarkMode\s*\?\s*const Color\(0xFF15120B\)\.withValues\(alpha: 0\.97\)\s*:\s*Colors\.white\.withValues\(alpha: 0\.97\);',
        'final bgColor = isDarkMode ? Colors.black.withValues(alpha: 0.90) : const Color(0xFF151515).withValues(alpha: 0.90);',
        top_bar_code
    )
    top_bar_code = re.sub(
        r'final textColor = isDarkMode \? Colors\.white : const Color\(0xFF35250E\);',
        'final textColor = Colors.white;', # always white because bg is black
        top_bar_code
    )
    
    # Increase button constraints and icon size
    top_bar_code = top_bar_code.replace('constraints: const BoxConstraints.tightFor(width: 24, height: 24),', 'constraints: const BoxConstraints.tightFor(width: 28, height: 28),')
    top_bar_code = top_bar_code.replace('size: 12', 'size: 14')
    top_bar_code = top_bar_code.replace('padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),', 'padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),')
    
    # Wrap Ayah Info in GestureDetector
    ayah_info_old = """                                  Expanded(
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
                                  ),"""
    ayah_info_new = """                                  Expanded(
                                    flex: 2,
                                    child: currentAyah != null
                                        ? GestureDetector(
                                            onTap: () => _showAyahSelectionDialog(currentAyah),
                                            child: Container(
                                              color: Colors.transparent,
                                              child: Text(
                                                '${currentAyah.surahName} : ${currentAyah.ayah}',
                                                textAlign: TextAlign.end,
                                                textDirection: TextDirection.rtl,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: textColor,
                                                ),
                                              ),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),"""
    top_bar_code = top_bar_code.replace(ayah_info_old, ayah_info_new)
    
    content = content[:top_bar_start] + top_bar_code + content[top_bar_end:]

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated successfully")

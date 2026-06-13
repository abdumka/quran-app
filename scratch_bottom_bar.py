import re

file_path = r'c:\Users\Mahfod501\Desktop\flutter\quran\quran_app\lib\quran_pages.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

start_idx = content.find('  Widget _buildRecitationBottomBar(double bottomOffset) {')

def find_end_brace(text, start):
    brace_count = 0
    for i in range(start, len(text)):
        if text[i] == '{':
            brace_count += 1
        elif text[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                return i + 1
    return -1

end_idx = find_end_brace(content, start_idx)

if start_idx != -1 and end_idx != -1:
    old_code = content[start_idx:end_idx]
    
    # 1. Update the AnimatedContainer padding and decoration to hide the background when minimized
    old_padding = 'padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),'
    new_padding = 'padding: _isRecitationTopBarMinimized ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),'
    old_code = old_code.replace(old_padding, new_padding)
    
    old_color = 'color: bgColor,'
    new_color = 'color: _isRecitationTopBarMinimized ? Colors.transparent : bgColor,'
    old_code = old_code.replace(old_color, new_color)
    
    old_border = 'border: Border.all(color: borderColor),'
    new_border = 'border: _isRecitationTopBarMinimized ? null : Border.all(color: borderColor),'
    old_code = old_code.replace(old_border, new_border)
    
    old_shadow = 'boxShadow: ['
    new_shadow = 'boxShadow: _isRecitationTopBarMinimized ? [] : ['
    old_code = old_code.replace(old_shadow, new_shadow)
    
    # 2. Hide the Expand/Collapse button when minimized
    old_button_block = """                            // Expand/Collapse Toggle Button
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
                            const SizedBox(width: 8),"""
    new_button_block = """                            // Expand/Collapse Toggle Button (Only show when expanded)
                            if (!_isRecitationTopBarMinimized) ...[
                              Container(
                                decoration: BoxDecoration(
                                  color: subtleColor,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _isRecitationTopBarMinimized = true;
                                    });
                                  },
                                  icon: Icon(Icons.close_fullscreen_rounded, color: textColor, size: 18),
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                  tooltip: 'تصغير الشريط',
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],"""
    old_code = old_code.replace(old_button_block, new_button_block)
    
    # 3. Replace the Play/Pause button with an InkWell inside Material so we can capture onLongPress
    old_play = """                            // Play / Pause button
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
                            ),"""
                            
    new_play = """                            // Play / Pause button
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
                                    blurRadius: _isRecitationTopBarMinimized ? 12 : 6,
                                    offset: const Offset(0, _isRecitationTopBarMinimized ? 4 : 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () {
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
                                  onLongPress: () {
                                    if (_isRecitationTopBarMinimized) {
                                      setState(() {
                                        _isRecitationTopBarMinimized = false;
                                      });
                                    }
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.all(_isRecitationTopBarMinimized ? 16.0 : 12.0),
                                    child: Icon(
                                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      size: _isRecitationTopBarMinimized ? 28 : 20,
                                      color: isDarkMode ? const Color(0xFF15120B) : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),"""
                            
    old_code = old_code.replace(old_play, new_play)
    
    new_content = content[:start_idx] + old_code + content[end_idx:]
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print("Done replacing bottom bar")
else:
    print("Could not find bottom bar")

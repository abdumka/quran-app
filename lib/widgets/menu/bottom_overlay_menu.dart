import 'package:flutter/material.dart';

class BottomOverlayMenu extends StatefulWidget {
  final VoidCallback onGoToBookmark;
  final bool showIndex;
  final bool showSurahs;
  final List<Map<String, dynamic>> surahs;
  final VoidCallback onToggleSurahs;
  final Function(int page) onGoToPage;
  final bool isDarkMode;
  final ValueChanged<bool> onToggleDarkMode;
  final bool isAutoScrollEnabled;
  final bool isPortraitScrollMode;
  final bool allowPortraitScrollMode;
  final bool showTabletLayoutSetting;
  final bool isTabletLayoutMode;
  final double bottomOffset;
  final ValueChanged<bool> onToggleAutoScroll;
  final ValueChanged<bool> onTogglePortraitScrollMode;
  final ValueChanged<bool> onToggleTabletLayoutMode;
  final Function(bool)? onSearchStateChanged;
  final VoidCallback? onOpenTafsir;
  final VoidCallback? onPlayTapped;
  final VoidCallback? onSearchTapped;
  final VoidCallback onDismiss;

  const BottomOverlayMenu({
    super.key,
    required this.showIndex,
    required this.showSurahs,
    required this.surahs,
    required this.onToggleSurahs,
    required this.onGoToPage,
    required this.isDarkMode,
    required this.isAutoScrollEnabled,
    required this.isPortraitScrollMode,
    required this.allowPortraitScrollMode,
    required this.showTabletLayoutSetting,
    this.isTabletLayoutMode = false,
    this.bottomOffset = 0,
    required this.onGoToBookmark,
    required this.onToggleDarkMode,
    required this.onToggleAutoScroll,
    required this.onTogglePortraitScrollMode,
    required this.onToggleTabletLayoutMode,
    this.onSearchStateChanged,
    this.onOpenTafsir,
    this.onPlayTapped,
    this.onSearchTapped,
    required this.onDismiss,
  });

  @override
  State<BottomOverlayMenu> createState() => _BottomOverlayMenuState();
}

class _BottomOverlayMenuState extends State<BottomOverlayMenu> {
  String? _selectedItem;

  void _handleTap(String label) {
    setState(() => _selectedItem = label);
    
    switch (label) {
      case 'الفهرس':
        widget.onToggleSurahs();
        break;
      case 'التلاوة':
        widget.onPlayTapped?.call();
        break;
      case 'العلامات':
        widget.onGoToBookmark();
        break;
      case 'التفسير':
        widget.onOpenTafsir?.call();
        break;
      case 'البحث':
        widget.onSearchTapped?.call();
        break;
      case 'أدوات الحفظ':
        // Placeholder: memorization tools / test (اختبار الحفظ) — not wired up yet.
        break;
    }
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _selectedItem = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final double safeBottom = MediaQuery.of(context).padding.bottom;
    // Landscape has far less vertical room, so the action bar is made shorter
    // and its items are drawn more compactly to free up the page area.
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double barHeight = isLandscape ? 52 : 75;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      left: 0,
      right: 0,
      bottom: widget.showIndex ? widget.bottomOffset : -130 - safeBottom,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta! > 5) {
            widget.onDismiss();
          }
        },
        child: Material(
          color: Colors.transparent,
        child: Container(
          height: barHeight + (widget.bottomOffset > 0 ? 0 : safeBottom), // Don't add safeBottom if pushed above recitation bar
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Placeholder: memorization tools / test. Sits at the far-left
                    // slot so an RTL reader reads it right after البحث, as the last item.
                    Expanded(
                      child: _NavItem(
                        icon: Icons.quiz_rounded,
                        label: 'أدوات الحفظ',
                        isSelected: _selectedItem == 'أدوات الحفظ',
                        compact: isLandscape,
                        onTap: () => _handleTap('أدوات الحفظ'),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.search_rounded,
                        label: 'البحث',
                        isSelected: _selectedItem == 'البحث',
                        compact: isLandscape,
                        onTap: () => _handleTap('البحث'),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        imagePath: 'assets/images/tafsir_icon.png',
                        label: 'التفسير',
                        isSelected: _selectedItem == 'التفسير',
                        compact: isLandscape,
                        onTap: () => _handleTap('التفسير'),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.play_circle_rounded,
                        label: 'التلاوة',
                        isSelected: _selectedItem == 'التلاوة',
                        compact: isLandscape,
                        onTap: () => _handleTap('التلاوة'),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.bookmark_rounded,
                        label: 'العلامات',
                        isSelected: _selectedItem == 'العلامات',
                        compact: isLandscape,
                        onTap: () => _handleTap('العلامات'),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.menu_book_rounded,
                        label: 'الفهرس',
                        isSelected: _selectedItem == 'الفهرس',
                        compact: isLandscape,
                        onTap: () => _handleTap('الفهرس'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (safeBottom > 0 && widget.bottomOffset == 0) SizedBox(height: safeBottom),
          ],
        ),
      ),
      ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData? icon;
  final String? imagePath;
  final String label;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  const _NavItem({
    this.icon,
    this.imagePath,
    required this.label,
    required this.onTap,
    this.isSelected = false,
    this.compact = false,
  }) : assert(icon != null || imagePath != null);

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? const Color(0xFFD2B97E) : const Color(0xFF888888);
    final double iconSize = compact ? 22 : 30;
    final double gap = compact ? 2 : 6;
    final double fontSize = compact ? 10 : 13;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: compact ? 2 : 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imagePath != null)
              Image.asset(
                imagePath!,
                width: iconSize,
                height: iconSize,
                color: color,
              )
            else
              Icon(
                icon,
                color: color,
                size: iconSize,
              ),
            SizedBox(height: gap),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

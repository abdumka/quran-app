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
  final VoidCallback? onOpenHifzTools;
  final VoidCallback onDismiss;

  /// Index of the item the TV remote is currently on, or null off-TV.
  /// Drawn as a ring instead of relying on Flutter focus, which a D-pad
  /// cannot drive here (the reader's key handler owns the arrow keys).
  final int? tvFocusedIndex;

  /// TV only: adds الإعدادات to the bar. On a TV the settings gear lives in
  /// the top bar, which a remote cannot reach, and Settings is the only route
  /// to the offline surah downloads -- so it gets a first-class entry here.
  final bool showSettingsItem;
  final VoidCallback? onOpenSettings;

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
    this.onOpenHifzTools,
    required this.onDismiss,
    this.tvFocusedIndex,
    this.showSettingsItem = false,
    this.onOpenSettings,
  });

  /// Labels in bar order. Index 5 exists only when [showSettingsItem].
  static const List<String> tvItemLabels = [
    'البحث',
    'التفسير',
    'التلاوة',
    'العلامات',
    'الفهرس',
    'الإعدادات',
  ];

  @override
  State<BottomOverlayMenu> createState() => BottomOverlayMenuState();
}

class BottomOverlayMenuState extends State<BottomOverlayMenu> {
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
      case 'الإعدادات':
        widget.onOpenSettings?.call();
        break;
      case 'أدوات الحفظ':
        widget.onOpenHifzTools?.call();
        break;
    }
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _selectedItem = null);
    });
  }

  /// Fires the item the TV remote is sitting on. Called by the reader's key
  /// handler so the tap and remote paths run exactly the same routing.
  void activateTvIndex(int index) {
    final labels = _itemLabels;
    if (index < 0 || index >= labels.length) return;
    _handleTap(labels[index]);
  }

  static IconData? _iconFor(String label) {
    switch (label) {
      case 'البحث':
        return Icons.search_rounded;
      case 'التلاوة':
        return Icons.play_circle_rounded;
      case 'العلامات':
        return Icons.bookmark_rounded;
      case 'الفهرس':
        return Icons.menu_book_rounded;
      case 'الإعدادات':
        return Icons.settings_rounded;
      case 'أدوات الحفظ':
        // Shown only until the artwork below loads (or if it is missing).
        return Icons.psychology_rounded;
    }
    return null; // التفسير uses an image asset instead.
  }

  static String? _imageFor(String label) {
    switch (label) {
      case 'التفسير':
        return 'assets/images/tafsir_icon.png';
      case 'أدوات الحفظ':
        return 'assets/images/hifz_tools_icon.png';
    }
    return null;
  }

  /// Android TV ([showSettingsItem]): main's bar exactly. Everywhere else
  /// the memorization tools (التسميع، تقوية الحفظ، وضع الحفظ) come first and
  /// التفسير is not in the bar: a touch reader reaches it by long-pressing
  /// an ayah (which a remote cannot do, so the TV keeps the item).
  static const List<String> touchItemLabels = [
    'أدوات الحفظ',
    'البحث',
    'التلاوة',
    'العلامات',
    'الفهرس',
  ];

  List<String> get _itemLabels => widget.showSettingsItem
      ? BottomOverlayMenu.tvItemLabels
      : touchItemLabels;

  /// Five items share the width off-TV; the TV bar keeps its own spacing.
  Widget _wrapForBar(Widget item) =>
      widget.showSettingsItem ? item : Expanded(child: item);

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
                    // Phones and tablets: the memorization tools lead the bar (far
                    // left for an RTL reader, right after البحث) and the items share
                    // the width. Android TV keeps its own bar untouched: no
                    // microphone or touch there, and the remote's focus index
                    // counts on [BottomOverlayMenu.tvItemLabels].
                    for (int i = 0; i < _itemLabels.length; i++)
                      _wrapForBar(
                        _NavItem(
                          icon: _iconFor(_itemLabels[i]),
                          imagePath: _imageFor(_itemLabels[i]),
                          label: _itemLabels[i],
                          isSelected: _selectedItem == _itemLabels[i],
                          isTvFocused: widget.tvFocusedIndex == i,
                          compact: isLandscape,
                          spacious: !widget.showSettingsItem,
                          onTap: () => _handleTap(_itemLabels[i]),
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
  final bool isTvFocused;
  final bool compact;

  /// Five items share the touch bar, so each gets room for a bigger glyph
  /// and label than the six-item TV bar.
  final bool spacious;
  final VoidCallback onTap;

  const _NavItem({
    this.icon,
    this.imagePath,
    required this.label,
    required this.onTap,
    this.isSelected = false,
    this.isTvFocused = false,
    this.compact = false,
    this.spacious = false,
  }) : assert(icon != null || imagePath != null);

  @override
  Widget build(BuildContext context) {
    // The TV ring has to read from across a room, so a focused item is drawn
    // in full gold on a filled, outlined plate rather than the faint overlay
    // InkWell uses for keyboard focus.
    final color = (isSelected || isTvFocused)
        ? const Color(0xFFD2B97E)
        : const Color(0xFF888888);
    // Sized so 32 + 4 + the 14pt label + 16 of padding stay inside the
    // 75 dp portrait bar.
    final double iconSize = compact ? (spacious ? 24 : 22) : (spacious ? 32 : 30);
    final double gap = compact ? 2 : (spacious ? 4 : 6);
    final double fontSize = compact ? (spacious ? 11 : 10) : (spacious ? 14 : 13);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: isTvFocused
            ? BoxDecoration(
                color: const Color(0xFFD2B97E).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFD2B97E),
                  width: 2,
                ),
              )
            : null,
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
                errorBuilder: (context, error, stack) => Icon(
                  icon ?? Icons.apps_rounded,
                  color: color,
                  size: iconSize,
                ),
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

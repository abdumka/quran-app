import 'package:flutter/material.dart';

import '../utils/responsive_helper.dart';

class SurahIndexPanel extends StatefulWidget {
  final List<Map<String, dynamic>> surahs;
  final int initialSurahIndex;
  final int currentSurahNumber;
  final Function(int page, {double yOffsetRatio}) onGoToPage;
  final ValueChanged<int> onSelectSurah;
  final VoidCallback onClose;
  final Function(bool)? onSearchChanged;

  const SurahIndexPanel({
    super.key,
    required this.surahs,
    required this.initialSurahIndex,
    required this.currentSurahNumber,
    required this.onGoToPage,
    required this.onSelectSurah,
    required this.onClose,
    this.onSearchChanged,
  });

  @override
  State<SurahIndexPanel> createState() => _SurahIndexPanelState();
}

class _SurahIndexPanelState extends State<SurahIndexPanel> {
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _currentSurahKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollCurrentSurahIntoView();
    });
  }

  String _normalizeArabic(String text) {
    String value = text.trim().toLowerCase();

    value = value
        .replaceAll(RegExp(r'[ً-ٰٟـ]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');

    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (value.startsWith('ال')) {
      value = value.substring(2).trim();
    }

    return value;
  }

  bool _matchesSurah(Map<String, dynamic> surah, String query) {
    if (query.isEmpty) return true;

    final arabicName = _normalizeArabic((surah['name'] ?? '').toString());
    final englishName =
        (surah['english'] ?? '').toString().toLowerCase().trim();

    final compactArabic = arabicName.replaceAll(' ', '');
    final compactQuery = query.replaceAll(' ', '');

    return arabicName.contains(query) ||
        compactArabic.contains(compactQuery) ||
        englishName.contains(query);
  }

  List<Map<String, dynamic>> _filteredSurahs() {
    final query = _normalizeArabic(_searchController.text);
    return widget.surahs.where((surah) => _matchesSurah(surah, query)).toList();
  }

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  bool get _isLandscape =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  @override
  void dispose() {
    widget.onSearchChanged?.call(false);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollCurrentSurahIntoView() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentContext = _currentSurahKey.currentContext;
      if (currentContext == null) return;

      Scrollable.ensureVisible(
        currentContext,
        alignment: 0.35,
        duration: Duration.zero,
      );
    });
  }

  Widget _buildHeader() {
    final bool compactLandscape = _isLandscape && !ResponsiveHelper.isTablet(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        compactLandscape ? 4 : 6,
        12,
        compactLandscape ? 2 : 8,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: ResponsiveHelper.isTablet(context)
              ? 16
              : compactLandscape
                  ? 8
                  : 14,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF8D6E3F).withValues(alpha: 0.45),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFFF6F1E5),
              Color(0xFFEADFC7),
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              right: 0,
              child: Icon(
                Icons.auto_awesome,
                size: ResponsiveHelper.isTablet(context)
                    ? 20
                    : compactLandscape
                        ? 16
                        : 18,
                color: const Color(0xFF8D6E3F).withValues(alpha: 0.75),
              ),
            ),
            Positioned(
              left: 0,
              child: Icon(
                Icons.auto_awesome,
                size: ResponsiveHelper.isTablet(context)
                    ? 20
                    : compactLandscape
                        ? 16
                        : 18,
                color: const Color(0xFF8D6E3F).withValues(alpha: 0.75),
              ),
            ),
            Text(
              'قائمة السور',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ResponsiveHelper.isTablet(context)
                    ? 28
                    : compactLandscape
                        ? 20
                        : 24,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF3D3122),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final bool compactLandscape = _isLandscape && !ResponsiveHelper.isTablet(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        compactLandscape ? 2 : 8,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {});
          widget.onSearchChanged?.call(value.trim().isNotEmpty);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollCurrentSurahIntoView();
          });
        },
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: 'ابحث عن سورة',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                    widget.onSearchChanged?.call(false);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollCurrentSurahIntoView();
                    });
                  },
                  icon: const Icon(Icons.close),
                )
              : IconButton(
                  onPressed: () {
                    widget.onSearchChanged?.call(false);
                    final navigator = Navigator.of(context);
                    if (navigator.canPop()) {
                      navigator.pop();
                    } else {
                      widget.onClose();
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.94),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: ResponsiveHelper.isTablet(context)
                ? 16
                : compactLandscape
                    ? 8
                    : 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Colors.black.withValues(alpha: 0.08),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Colors.black.withValues(alpha: 0.08),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFF8D6E3F),
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  int _gridColumnCount(BuildContext context) {
    if (ResponsiveHelper.isTablet(context)) {
      return _isLandscape ? 6 : 5;
    }
    return _isLandscape ? 5 : 4;
  }

  double _gridChildAspectRatio(BuildContext context) {
    if (ResponsiveHelper.isTablet(context)) {
      return _isLandscape ? 2.8 : 2.45;
    }
    return _isLandscape ? 2.8 : 2.15;
  }

  Widget _buildSurahGridTile(Map<String, dynamic> surah, bool isCurrent) {
    final accentColor = const Color(0xFF8D6E3F);

    return KeyedSubtree(
      key: isCurrent ? _currentSurahKey : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            widget.onSearchChanged?.call(false);
            widget.onSelectSurah(surah['number'] as int);
            widget.onGoToPage(surah['page'], yOffsetRatio: (surah['yOffsetRatio'] as num?)?.toDouble() ?? 0.0);
          },
          child: Container(
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFFE7D7AF)
                  : Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isCurrent
                    ? accentColor
                    : accentColor.withValues(alpha: 0.22),
                width: isCurrent ? 1.6 : 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Center(
              child: Text(
                (surah['name'] ?? '').toString(),
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ResponsiveHelper.isTablet(context) ? 18 : 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF2F2418),
                  height: 1.18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSurahs = _filteredSurahs();
    final bool compactLandscape = _isLandscape && !ResponsiveHelper.isTablet(context);

    return Expanded(
      child: Column(
        children: [
          _buildHeader(),
          _buildSearchField(),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: compactLandscape ? 1.0 : (_isSearching ? 0.72 : 1.0),
                child: filteredSurahs.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد نتيجة',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      )
                    : Directionality(
                        textDirection: TextDirection.rtl,
                        child: GridView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                            12,
                            4,
                            12,
                            compactLandscape ? 6 : 12,
                          ),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _gridColumnCount(context),
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: _gridChildAspectRatio(context),
                          ),
                          itemCount: filteredSurahs.length,
                          itemBuilder: (context, index) {
                            final surah = filteredSurahs[index];
                            final isCurrent =
                                surah['number'] == widget.currentSurahNumber;
                            return _buildSurahGridTile(surah, isCurrent);
                          },
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

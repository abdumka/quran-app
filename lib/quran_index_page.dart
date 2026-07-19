import 'package:flutter/material.dart';

import 'quran_constants.dart';
import 'thumn_data.dart';
import 'utils/responsive_helper.dart';

enum QuranIndexTab {
  surahs,
  juzs,
  hizbs,
  pages,
  sajdas,
}

class QuranIndexPage extends StatefulWidget {
  final List<Map<String, dynamic>> surahs;
  final Function(int page, {double yOffsetRatio}) onGoToPage;
  final int currentSurahNumber;
  final int currentPage;
  final ValueChanged<int> onSelectSurah;
  final QuranIndexTab initialTab;

  const QuranIndexPage({
    super.key,
    required this.surahs,
    required this.onGoToPage,
    required this.currentSurahNumber,
    required this.currentPage,
    required this.onSelectSurah,
    this.initialTab = QuranIndexTab.surahs,
  });

  @override
  State<QuranIndexPage> createState() => _QuranIndexPageState();
}

class _QuranIndexPageState extends State<QuranIndexPage> {
  static const Map<int, String> _sajdaNotices = <int, String>{
    175: 'سجدة: وله يسجدون',
    250: 'سجدة: وظلالهم بالغدو والآصال',
    271: 'سجدة: ويفعلون ما يؤمرون',
    292: 'سجدة: ويزيدهم خشوعا',
    308: 'سجدة: خروا سجدا وبكيا',
    333: 'سجدة: إن الله يفعل ما يشاء',
    364: 'سجدة: وزادهم نفورا',
    378: 'سجدة: رب العرش العظيم',
    415: 'سجدة: وهم لا يستكبرون',
    452: 'سجدة: وخر راكعا وأناب',
    478: 'سجدة: إن كنتم إياه تعبدون',
  };

  final TextEditingController _searchController = TextEditingController();
  late QuranIndexTab _selectedTab;
  final Set<int> _expandedHizbs = <int>{};
  bool _expandedHizbsInitialized = false;
  final TextEditingController _hizbSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _hizbSearchController.dispose();
    super.dispose();
  }

  String _normalizeArabic(String text) {
    String value = text.trim().toLowerCase();
    value = value
        .replaceAll('\u0670', 'ا')
        .replaceAll(RegExp(r'[\u064B-\u065F\u0640]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
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

  List<Map<String, dynamic>> _filteredSurahs() {
    final query = _normalizeArabic(_searchController.text);
    if (query.isEmpty) return widget.surahs;

    return widget.surahs.where((surah) {
      final arabicName = _normalizeArabic((surah['name'] ?? '').toString());
      final englishName =
          (surah['english'] ?? '').toString().toLowerCase().trim();
      final compactArabic = arabicName.replaceAll(' ', '');
      final compactQuery = query.replaceAll(' ', '');

      return arabicName.contains(query) ||
          compactArabic.contains(compactQuery) ||
          englishName.contains(query);
    }).toList();
  }

  void _goToPageAndClose(int page, {double yOffsetRatio = 0.0}) {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onGoToPage(page, yOffsetRatio: yOffsetRatio);
    });
  }

  int _currentJuzNumber() {
    final realPage = widget.currentPage + 1;
    for (int i = 0; i < 30; i++) {
      final start = hizbStartPages[i * 2];
      final end = i < 29 ? hizbStartPages[(i * 2) + 2] - 1 : 602;
      if (realPage >= start && realPage <= end) {
        return i + 1;
      }
    }
    return 1;
  }

  int _crossAxisCount() {
    final isTablet = ResponsiveHelper.isTablet(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (isTablet) {
      return isLandscape ? 6 : 4;
    }
    return isLandscape ? 8 : 4;
  }

  double _surahAspectRatio() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 2.8 : 2.35;
  }

  Widget _buildFullScreenLabelGrid({
    required int itemCount,
    required String Function(int index) titleBuilder,
    required bool Function(int index) isCurrentBuilder,
    required int Function(int index) pageBuilder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 12.0;
        const verticalPadding = 12.0;
        const spacing = 8.0;
        const minColumns = 3;
        const minTileHeight = 34.0;
        const minTileWidth = 50.0;

        final availableWidth = constraints.maxWidth - (horizontalPadding * 2);
        final availableHeight = constraints.maxHeight - (verticalPadding * 2);
        final maxRows = ((availableHeight + spacing) / (minTileHeight + spacing))
            .floor()
            .clamp(1, itemCount);
        final neededColumns = (itemCount / maxRows).ceil();
        final maxColumnsByWidth =
            ((availableWidth + spacing) / (minTileWidth + spacing))
                .floor()
                .clamp(minColumns, itemCount);
        final crossAxisCount =
            neededColumns.clamp(minColumns, maxColumnsByWidth);
        final rowCount = (itemCount / crossAxisCount).ceil();
        final tileWidth =
            (availableWidth - ((crossAxisCount - 1) * spacing)) /
                crossAxisCount;
        final tileHeight =
            (availableHeight - ((rowCount - 1) * spacing)) / rowCount;
        final childAspectRatio = tileWidth / tileHeight;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              horizontalPadding,
              verticalPadding,
              horizontalPadding,
              verticalPadding,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: childAspectRatio,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              return _buildInfoTile(
                title: titleBuilder(index),
                isCurrent: isCurrentBuilder(index),
                onTap: () => _goToPageAndClose(pageBuilder(index)),
                compact: true,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFullScreenSajdaGrid({
    required List<MapEntry<int, String>> entries,
    required int currentRealPage,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 12.0;
        const verticalPadding = 12.0;
        const spacing = 10.0;
        const minColumns = 3;
        const minTileHeight = 86.0;
        const minTileWidth = 92.0;

        final itemCount = entries.length;
        final availableWidth = constraints.maxWidth - (horizontalPadding * 2);
        final availableHeight = constraints.maxHeight - (verticalPadding * 2);
        final maxRows = ((availableHeight + spacing) / (minTileHeight + spacing))
            .floor()
            .clamp(1, itemCount);
        final neededColumns = (itemCount / maxRows).ceil();
        final maxColumnsByWidth =
            ((availableWidth + spacing) / (minTileWidth + spacing))
                .floor()
                .clamp(minColumns, itemCount);
        final crossAxisCount =
            neededColumns.clamp(minColumns, maxColumnsByWidth);
        final rowCount = (itemCount / crossAxisCount).ceil();
        final tileWidth =
            (availableWidth - ((crossAxisCount - 1) * spacing)) /
                crossAxisCount;
        final tileHeight =
            (availableHeight - ((rowCount - 1) * spacing)) / rowCount;
        final childAspectRatio = tileWidth / tileHeight;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              horizontalPadding,
              verticalPadding,
              horizontalPadding,
              verticalPadding,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: childAspectRatio,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              final shiftedPage = (entries[index].key + 1).clamp(1, 602);
              final notice = entries[index].value
                  .replaceFirst(RegExp(r'^سجدة:\s*'), '')
                  .trim();

              return _buildSajdaTile(
                title: 'السجدة ${index + 1}',
                subtitle: notice,
                isCurrent: currentRealPage == shiftedPage,
                onTap: () => _goToPageAndClose(shiftedPage),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTopTabs() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    Widget chip(QuranIndexTab tab, String label) {
      final isSelected = _selectedTab == tab;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _selectedTab = tab;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 9 : 9,
            vertical: isLandscape ? 8 : 9,
          ),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF8D6E3F) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF8D6E3F)
                  : const Color(0xFF8D6E3F).withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            label,
            textDirection: TextDirection.rtl,
            maxLines: 1,
            style: TextStyle(
              fontSize: isLandscape ? 11.5 : 12,
              fontWeight: FontWeight.w800,
              color: isSelected ? Colors.white : const Color(0xFF4C3A22),
            ),
          ),
        ),
      );
    }

    final chips = [
      chip(QuranIndexTab.surahs, 'السور'),
      chip(QuranIndexTab.juzs, 'الأجزاء'),
      chip(QuranIndexTab.hizbs, 'الأحزاب والأثمان'),
      chip(QuranIndexTab.pages, 'الصفحات'),
      chip(QuranIndexTab.sajdas, 'السجدات'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        isLandscape ? 4 : 6,
        12,
        isLandscape ? 12 : 8,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep all five tabs on a single line. If they don't fit the
            // available width, allow the row to scroll horizontally.
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (int i = 0; i < chips.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      chips[i],
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, isLandscape ? 8 : 10),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: 'ابحث عن سورة',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded),
                )
              : IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.96),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: isLandscape ? 10 : 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: const Color(0xFF8D6E3F).withValues(alpha: 0.12),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: const Color(0xFF8D6E3F).withValues(alpha: 0.12),
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

  Widget _buildSurahChip(Map<String, dynamic> surah) {
    final number = surah['number'] as int;
    final name = (surah['name'] ?? '').toString();
    final page = surah['page'] as int;
    final isCurrent = number == widget.currentSurahNumber;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          widget.onSelectSurah(number);
          _goToPageAndClose(page, yOffsetRatio: (surah['yOffsetRatio'] as num?)?.toDouble() ?? 0.0);
        },
        child: Container(
          decoration: BoxDecoration(
            color: isCurrent ? const Color(0xFFE7D7AF) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isCurrent
                  ? const Color(0xFF8D6E3F)
                  : const Color(0xFF8D6E3F).withValues(alpha: 0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                name,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2F2418),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required String title,
    required bool isCurrent,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isCurrent ? const Color(0xFFE7D7AF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isCurrent
                  ? const Color(0xFF8D6E3F)
                  : const Color(0xFF8D6E3F).withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 10,
            vertical: compact ? 6 : 10,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 1,
                style: TextStyle(
                  fontSize: compact ? 14 : 17,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF2F2418),
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSajdaTile({
    required String title,
    String? subtitle,
    required bool isCurrent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isCurrent ? const Color(0xFFE7D7AF) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCurrent
                  ? const Color(0xFF8D6E3F)
                  : const Color(0xFF8D6E3F).withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Image.asset(
                  'assets/images/sajdah_icon.png',
                  width: 66,
                  height: 66,
                  color: isCurrent
                      ? const Color(0xFF8D6E3F)
                      : const Color(0xFF9E824C),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2F2418),
                  ),
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6A5A45),
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSurahsGrid() {
    final surahs = _filteredSurahs();

    if (surahs.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد نتيجة',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6A5A45),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: _surahAspectRatio(),
        ),
        itemCount: surahs.length,
        itemBuilder: (context, index) => _buildSurahChip(surahs[index]),
      ),
    );
  }

  Widget _buildJuzGrid() {
    final currentJuz = _currentJuzNumber();

    return _buildFullScreenLabelGrid(
      itemCount: 30,
      titleBuilder: (index) => 'الجزء ${index + 1}',
      isCurrentBuilder: (index) => (index + 1) == currentJuz,
      pageBuilder: (index) => hizbStartPages[index * 2],
    );
  }

  int _currentThumnIndex() {
    final realPage = widget.currentPage + 1;
    int result = 0;
    for (int i = 0; i < thumnEntries.length; i++) {
      if (thumnEntries[i].page <= realPage) {
        result = i;
      } else {
        break;
      }
    }
    return result;
  }

  String _surahNameForPage(int page) {
    String name = '';
    for (final surah in widget.surahs) {
      final surahPage = (surah['page'] as num?)?.toInt() ?? 0;
      if (surahPage <= page) {
        name = (surah['name'] ?? '').toString();
      } else {
        break;
      }
    }
    return name;
  }

  // "الصفحات" view: a dense grid of all page numbers, styled like the surah
  // grid, so the user can jump straight to any page.
  Widget _buildPagesGrid() {
    const totalPages = 602;
    final currentRealPage = widget.currentPage + 1;
    final isTablet = ResponsiveHelper.isTablet(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final crossAxisCount = isTablet
        ? (isLandscape ? 10 : 7)
        : (isLandscape ? 9 : 5);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.15,
        ),
        itemCount: totalPages,
        itemBuilder: (context, index) {
          final page = index + 1;
          final isCurrent = page == currentRealPage;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _goToPageAndClose(page),
              child: Container(
                decoration: BoxDecoration(
                  color: isCurrent ? const Color(0xFFE7D7AF) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isCurrent
                        ? const Color(0xFF8D6E3F)
                        : const Color(0xFF8D6E3F).withValues(alpha: 0.10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$page',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2F2418),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Converts Arabic-Indic (٠-٩) and Eastern Arabic-Indic (۰-۹) digits to
  // ASCII 0-9 so numeric searches work regardless of keyboard.
  String _toAsciiDigits(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(rune - 0x0660 + 0x30);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.writeCharCode(rune - 0x06F0 + 0x30);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  // Returns the hizb numbers (1-60) that match the current search query,
  // in order. Empty query = all 60. A query auto-expands matching hizbs.
  List<int> _filteredHizbNumbers(String query) {
    if (query.isEmpty) {
      return List<int>.generate(60, (i) => i + 1);
    }

    // Extract a bare number if present (matches "حزب 14", "14", "الحزب ١٤").
    // Convert Arabic-Indic digits (٠-٩) to ASCII first.
    final digits = _toAsciiDigits(query).replaceAll(RegExp(r'[^0-9]'), '');
    final queryNumber = digits.isNotEmpty ? int.tryParse(digits) : null;

    // Drop the "حزب"/"الحزب" keyword and any digits from the text portion of
    // the query so "حزب 14" or a bare "حزب" doesn't wipe out results.
    String textQuery = _normalizeArabic(query);
    textQuery = textQuery
        .replaceAll(RegExp(r'[0-9٠-٩۰-۹]'), '')
        .replaceAll('حزب', '')
        .trim();
    final normalizedQuery = textQuery;
    final compactQuery = normalizedQuery.replaceAll(' ', '');

    // "حزب" or "الحزب" alone (no number, no other text) => show all.
    if (queryNumber == null && normalizedQuery.isEmpty) {
      return List<int>.generate(60, (i) => i + 1);
    }

    final result = <int>[];
    for (int hizb = 1; hizb <= 60; hizb++) {
      final title = hizb - 1 < hizbTitles.length
          ? _normalizeArabic(hizbTitles[hizb - 1])
          : '';
      final athman = thumnEntries.where((e) => e.hizb == hizb);

      final numberMatch = queryNumber != null && queryNumber == hizb;
      final titleMatch = normalizedQuery.isNotEmpty &&
          (title.contains(normalizedQuery) ||
              title.replaceAll(' ', '').contains(compactQuery));
      final thumnMatch = normalizedQuery.isNotEmpty &&
          athman.any((e) {
            final t = _normalizeArabic(e.text);
            return t.contains(normalizedQuery) ||
                t.replaceAll(' ', '').contains(compactQuery);
          });

      if (numberMatch || titleMatch || thumnMatch) {
        result.add(hizb);
      }
    }
    return result;
  }

  // "الأحزاب والأثمان" view: the 480 athman grouped into 60 collapsible
  // hizb sections. A search bar filters by hizb number/name or thumn text;
  // the expand/collapse-all button sits inline to the left of it.
  Widget _buildThumnsByHizb() {
    final currentIndex = _currentThumnIndex();
    final currentHizb = thumnEntries[currentIndex].hizb;

    if (!_expandedHizbsInitialized) {
      _expandedHizbsInitialized = true;
      _expandedHizbs.add(currentHizb);
    }

    final query = _hizbSearchController.text.trim();
    final hasQuery = query.isNotEmpty;
    final visibleHizbs = _filteredHizbNumbers(query);
    // Text portion only (digits and the "حزب" keyword removed) so highlighting
    // matches the same rule the filter uses.
    final textQuery = _normalizeArabic(query)
        .replaceAll(RegExp(r'[0-9٠-٩۰-۹]'), '')
        .replaceAll('حزب', '')
        .trim();
    final compactQuery = textQuery.replaceAll(' ', '');
    final allExpanded = _expandedHizbs.length >= 60;

    bool thumnMatchesQuery(ThumnEntry e) {
      if (!hasQuery || textQuery.isEmpty) return false;
      final t = _normalizeArabic(e.text);
      return t.contains(textQuery) ||
          t.replaceAll(' ', '').contains(compactQuery);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _buildHizbSearchHeader(allExpanded: allExpanded),
          Expanded(
            child: visibleHizbs.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد نتيجة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6A5A45),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
                    itemCount: visibleHizbs.length,
                    itemBuilder: (context, index) {
                      final hizbNumber = visibleHizbs[index];
                      // When searching, force the matching hizbs open.
                      final isExpanded = hasQuery ||
                          _expandedHizbs.contains(hizbNumber);
                      return _buildHizbCard(
                        hizbNumber: hizbNumber,
                        isExpanded: isExpanded,
                        isCurrentHizb: hizbNumber == currentHizb,
                        currentIndex: currentIndex,
                        toggleEnabled: !hasQuery,
                        highlight: thumnMatchesQuery,
                        // When the search matches thumn text, show only the
                        // matching thumns within each hizb.
                        onlyMatching: hasQuery && textQuery.isNotEmpty,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHizbSearchHeader({required bool allExpanded}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          _buildExpandAllButton(allExpanded: allExpanded),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _hizbSearchController,
              onChanged: (_) => setState(() {}),
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'ابحث: حزب ١٤ أو اسم الحزب أو الثمن',
                hintTextDirection: TextDirection.rtl,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _hizbSearchController.text.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _hizbSearchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 20),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.96),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: const Color(0xFF8D6E3F).withValues(alpha: 0.12),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: const Color(0xFF8D6E3F).withValues(alpha: 0.12),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF8D6E3F),
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandAllButton({required bool allExpanded}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            if (allExpanded) {
              _expandedHizbs.clear();
            } else {
              _expandedHizbs
                ..clear()
                ..addAll(List.generate(60, (i) => i + 1));
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF8D6E3F).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                allExpanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                size: 16,
                color: const Color(0xFF6A5330),
              ),
              const SizedBox(width: 4),
              Text(
                allExpanded ? 'طي الكل' : 'توسيع الكل',
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4C3A22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHizbCard({
    required int hizbNumber,
    required bool isExpanded,
    required bool isCurrentHizb,
    required int currentIndex,
    required bool toggleEnabled,
    required bool Function(ThumnEntry) highlight,
    bool onlyMatching = false,
  }) {
    final hizbTitle = hizbNumber - 1 < hizbTitles.length
        ? hizbTitles[hizbNumber - 1]
        : '';
    final allAthman =
        thumnEntries.where((e) => e.hizb == hizbNumber).toList();
    final hasMatch = allAthman.any(highlight);
    // Each thumn keeps its real position within the hizb (1-8) even when we
    // only render the matching ones. If this hizb matched by title/number
    // (no thumn text match), fall back to showing all its thumns.
    final filterThisHizb = onlyMatching && hasMatch;
    final athman = <MapEntry<int, ThumnEntry>>[
      for (int i = 0; i < allAthman.length; i++)
        if (!filterThisHizb || highlight(allAthman[i]))
          MapEntry(i + 1, allAthman[i]),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isCurrentHizb && !isExpanded
              ? const Color(0xFFE7D7AF)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrentHizb
                ? const Color(0xFF8D6E3F)
                : const Color(0xFF8D6E3F).withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: toggleEnabled
                    ? () {
                        setState(() {
                          if (_expandedHizbs.contains(hizbNumber)) {
                            _expandedHizbs.remove(hizbNumber);
                          } else {
                            _expandedHizbs.add(hizbNumber);
                          }
                        });
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: [
                              Color(0xFFA8844A),
                              Color(0xFF8D6E3F),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFFE7D7B5),
                            width: 1.6,
                          ),
                        ),
                        child: Text(
                          '$hizbNumber',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الحزب $hizbNumber',
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF2F2418),
                              ),
                            ),
                            if (hizbTitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '﴿ $hizbTitle ﴾',
                                textDirection: TextDirection.rtl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8A7757),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFF8D6E3F),
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  children: [
                    for (final e in athman)
                      _buildThumnRow(
                        e.value,
                        e.key,
                        thumnEntries.indexOf(e.value) == currentIndex,
                        matched: highlight(e.value),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumnRow(
    ThumnEntry entry,
    int ordinal,
    bool isCurrent, {
    bool matched = false,
  }) {
    final Color background = isCurrent
        ? const Color(0xFFE7D7AF)
        : matched
            ? const Color(0xFFFBF3DC)
            : const Color(0xFFF6F1E5);
    final Color borderColor = isCurrent || matched
        ? const Color(0xFF8D6E3F)
        : const Color(0xFF8D6E3F).withValues(alpha: 0.08);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _goToPageAndClose(entry.page),
          child: Container(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF8D6E3F).withValues(alpha: 0.12),
                  ),
                  child: Text(
                    '$ordinal',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF6A5330),
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.text,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2F2418),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _surahNameForPage(entry.page),
                        textDirection: TextDirection.rtl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8A7757),
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSajdaGrid() {
    final entries = _sajdaNotices.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final currentRealPage = widget.currentPage + 1;

    return _buildFullScreenSajdaGrid(
      entries: entries,
      currentRealPage: currentRealPage,
    );
  }

  Widget _buildBody() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    switch (_selectedTab) {
      case QuranIndexTab.surahs:
        if (isLandscape) {
          return _buildSurahsGrid();
        }
        return Column(
          children: [
            _buildSearchField(),
            Expanded(child: _buildSurahsGrid()),
          ],
        );
      case QuranIndexTab.juzs:
        return _buildJuzGrid();
      case QuranIndexTab.hizbs:
        return _buildThumnsByHizb();
      case QuranIndexTab.pages:
        return _buildPagesGrid();
      case QuranIndexTab.sajdas:
        return _buildSajdaGrid();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F1E5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F1E5),
        foregroundColor: const Color(0xFF3D3122),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'الفهرس',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopTabs(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}

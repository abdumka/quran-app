import 'package:flutter/material.dart';

import 'quran_constants.dart';
import 'thumn_data.dart';
import 'utils/responsive_helper.dart';

enum QuranIndexTab {
  surahs,
  juzs,
  hizbs,
  sajdas,
  thumns,
}

enum ThumnLayout {
  columns,
  rows,
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
  ThumnLayout _thumnLayout = ThumnLayout.rows;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  int _currentHizbNumber() {
    final realPage = widget.currentPage + 1;
    for (int i = 0; i < hizbStartPages.length; i++) {
      final start = hizbStartPages[i];
      final end =
          i < hizbStartPages.length - 1 ? hizbStartPages[i + 1] - 1 : 602;
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
            horizontal: isLandscape ? 10 : 11,
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
              fontSize: isLandscape ? 12 : 12.5,
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
      chip(QuranIndexTab.hizbs, 'الأحزاب'),
      chip(QuranIndexTab.thumns, 'الثمن والصفحة'),
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
                      if (i > 0) const SizedBox(width: 6),
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

  Widget _buildHizbGrid() {
    final currentHizb = _currentHizbNumber();

    return _buildFullScreenLabelGrid(
      itemCount: hizbStartPages.length,
      titleBuilder: (index) => 'الحزب ${index + 1}',
      isCurrentBuilder: (index) => (index + 1) == currentHizb,
      pageBuilder: (index) => hizbStartPages[index],
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

  Widget _buildThumnLayoutToggle() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    Widget segment(ThumnLayout layout, IconData icon, String label) {
      final isSelected = _thumnLayout == layout;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _thumnLayout = layout;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: EdgeInsets.symmetric(vertical: isLandscape ? 7 : 9),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF8D6E3F) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : const Color(0xFF6A5330),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : const Color(0xFF4C3A22),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, isLandscape ? 6 : 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF8D6E3F).withValues(alpha: 0.16),
          ),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              segment(ThumnLayout.rows, Icons.view_agenda_rounded, 'قائمة'),
              const SizedBox(width: 4),
              segment(ThumnLayout.columns, Icons.view_column_rounded, 'أعمدة'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumnBody() {
    return Column(
      children: [
        _buildThumnLayoutToggle(),
        Expanded(
          child: _thumnLayout == ThumnLayout.rows
              ? _buildThumnRowsList()
              : _buildThumnColumns(),
        ),
      ],
    );
  }

  // Design B: one aligned row per thumn (number | text | hizb | page).
  Widget _buildThumnRowsList() {
    final currentIndex = _currentThumnIndex();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
        itemCount: thumnEntries.length,
        itemBuilder: (context, index) {
          final entry = thumnEntries[index];
          final isCurrent = index == currentIndex;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _goToPageAndClose(entry.page),
                child: Ink(
                  decoration: BoxDecoration(
                    color: isCurrent ? const Color(0xFFE7D7AF) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isCurrent
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      _ThumnNumberBadge(number: entry.number),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          entry.text,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2F2418),
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ThumnMetaChip(
                        label: 'الحزب',
                        value: '${entry.hizb}',
                      ),
                      const SizedBox(width: 6),
                      _ThumnMetaChip(
                        label: 'صفحة',
                        value: '${entry.page}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Design A: four independently-scrollable columns.
  Widget _buildThumnColumns() {
    final currentIndex = _currentThumnIndex();

    Widget column({
      required String header,
      required int flex,
      required Widget Function(int index, ThumnEntry entry, bool isCurrent)
          cellBuilder,
    }) {
      return Expanded(
        flex: flex,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF8D6E3F).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                header,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF4C3A22),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 14),
                itemCount: thumnEntries.length,
                itemBuilder: (context, index) {
                  final entry = thumnEntries[index];
                  final isCurrent = index == currentIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: cellBuilder(index, entry, isCurrent),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    Widget cell({
      required Widget child,
      required bool isCurrent,
      VoidCallback? onTap,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrent ? const Color(0xFFE7D7AF) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent
                    ? const Color(0xFF8D6E3F)
                    : const Color(0xFF8D6E3F).withValues(alpha: 0.10),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: child,
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            column(
              header: 'الثمن',
              flex: 74,
              cellBuilder: (index, entry, isCurrent) => cell(
                isCurrent: isCurrent,
                onTap: () => _goToPageAndClose(entry.page),
                child: Row(
                  children: [
                    _ThumnNumberBadge(number: entry.number),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            entry.text,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2F2418),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'الحزب ${entry.hizb} • ${_surahNameForPage(entry.page)}',
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.right,
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
            const SizedBox(width: 6),
            column(
              header: 'الصفحة',
              flex: 16,
              cellBuilder: (index, entry, isCurrent) => cell(
                isCurrent: isCurrent,
                onTap: () => _goToPageAndClose(entry.page),
                child: Text(
                  '${entry.page}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6A5330),
                  ),
                ),
              ),
            ),
          ],
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
        return _buildHizbGrid();
      case QuranIndexTab.sajdas:
        return _buildSajdaGrid();
      case QuranIndexTab.thumns:
        return _buildThumnBody();
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

class _ThumnNumberBadge extends StatelessWidget {
  final int number;

  const _ThumnNumberBadge({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFA8844A), Color(0xFF8D6E3F)],
        ),
        border: Border.all(color: const Color(0xFFE7D7B5), width: 1.6),
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 15,
          height: 1,
        ),
      ),
    );
  }
}

class _ThumnMetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _ThumnMetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF8D6E3F).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A7757),
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF6A5330),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

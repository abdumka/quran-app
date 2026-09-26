import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'quran_constants.dart';
import 'services/tv_service.dart';
import 'thumn_data.dart';
import 'utils/responsive_helper.dart';

enum QuranIndexTab { surahs, juzs, hizbs, pages, sajdas }

/// Pages in this mushaf.
const int kQuranPageCount = 602;

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

  // Remembers the tab the user last picked an item from, so reopening the index
  // returns to it (e.g. jump to page 602 from "الصفحات" → next open shows
  // "الصفحات" scrolled to 602). Kept in memory for the app session.
  static QuranIndexTab? _lastSelectedTab;

  // Scroll controllers are created lazily with an initialScrollOffset that
  // centers the current reading position, so each scrollable tab opens already
  // scrolled to where the user is (no visible jump).
  ScrollController? _pagesScrollController;
  ScrollController? _surahsScrollController;
  ScrollController? _hizbScrollController;
  final GlobalKey _currentHizbKey = GlobalKey();
  bool _hizbEnsuredVisible = false;

  /// Android TV only. The grids are plain GridViews with no focus indicator,
  /// so a remote could scroll them via Flutter's traversal but the user could
  /// not see where they were or reliably open anything. These drive an explicit
  /// highlight instead. [_tvOnTabs] parks the highlight on the tab row above.
  int _tvIndex = 0;
  bool _tvOnTabs = false;
  bool _tvSeeded = false;

  /// Geometry of the grid currently on screen, published by its own
  /// LayoutBuilder during build. الأجزاء and السجدات size their columns to
  /// fill the screen exactly, so the column count is not something the key
  /// handler could re-derive; and taking the row pitch from the same code
  /// that laid the tiles out keeps the auto-scroll exact on every tab.
  int _tvCols = 1;
  double _tvRowStride = 0;

  /// Attached to the highlighted row of الأحزاب. That tab is a lazily built
  /// list of variable-height cards, so there is no offset to compute -- the
  /// row is scrolled into view through its own context instead.
  final GlobalKey _tvRowKey = GlobalKey();

  /// Lets the remote hand the on-screen keyboard over to the hizb search box,
  /// and lets the key handler stand down while the user is typing in it.
  final FocusNode _hizbSearchFocus = FocusNode();

  /// TV only: whether the search box is allowed to hold focus at all.
  ///
  /// Returning true from a HardwareKeyboard handler stops the raw-key path but
  /// not the Shortcuts/Actions path, so every arrow press ALSO ran Flutter's
  /// directional focus traversal. Traversal found the one focusable widget on
  /// the page, the search TextField, and simply walking down the list threw
  /// the TV's on-screen keyboard over it -- which then swallowed every
  /// subsequent key, leaving the remote dead. The field is therefore kept out
  /// of the focus tree and only let in when its row is selected.
  bool _hizbSearchActive = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = _lastSelectedTab ?? widget.initialTab;
    if (TvService.instance.isTv) {
      HardwareKeyboard.instance.addHandler(_onTvKey);
      // Once the user leaves the field, shut it out of the focus tree again.
      _hizbSearchFocus.addListener(_onHizbSearchFocusChanged);
    }
  }

  void _onHizbSearchFocusChanged() {
    if (!mounted || _hizbSearchFocus.hasFocus || !_hizbSearchActive) return;
    setState(() => _hizbSearchActive = false);
  }

  @override
  void dispose() {
    if (TvService.instance.isTv) {
      HardwareKeyboard.instance.removeHandler(_onTvKey);
      _hizbSearchFocus.removeListener(_onHizbSearchFocusChanged);
    }
    _searchController.dispose();
    _hizbSearchController.dispose();
    _hizbSearchFocus.dispose();
    _pagesScrollController?.dispose();
    _surahsScrollController?.dispose();
    _hizbScrollController?.dispose();
    super.dispose();
  }

  static const List<QuranIndexTab> _tvTabOrder = [
    QuranIndexTab.surahs,
    QuranIndexTab.juzs,
    QuranIndexTab.hizbs,
    QuranIndexTab.pages,
    QuranIndexTab.sajdas,
  ];

  /// The search-derived state of the الأحزاب tab, resolved once per build and
  /// shared with the TV row flattening so the two can never disagree about
  /// which cards and thumns are on screen.
  _HizbView _hizbViewModel() {
    final query = _hizbSearchController.text.trim();
    final hasQuery = query.isNotEmpty;
    // Text portion only (digits and the "حزب" keyword removed) so highlighting
    // matches the same rule the filter uses.
    final textQuery = _normalizeArabic(
      query,
    ).replaceAll(RegExp(r'[0-9٠-٩۰-۹]'), '').replaceAll('حزب', '').trim();
    final compactQuery = textQuery.replaceAll(' ', '');

    bool highlight(ThumnEntry e) {
      if (!hasQuery || textQuery.isEmpty) return false;
      final t = _normalizeArabic(e.text);
      return t.contains(textQuery) ||
          t.replaceAll(' ', '').contains(compactQuery);
    }

    return _HizbView(
      hasQuery: hasQuery,
      hizbs: _filteredHizbNumbers(query),
      highlight: highlight,
      onlyMatching: hasQuery && textQuery.isNotEmpty,
    );
  }

  /// The thumns rendered inside one hizb card, each paired with its real
  /// position in the hizb (1-8), which survives filtering.
  List<MapEntry<int, ThumnEntry>> _athmanFor(int hizb, _HizbView model) {
    final all = thumnEntries.where((e) => e.hizb == hizb).toList();
    // If this hizb matched by title/number rather than by thumn text, show all
    // of its thumns instead of none.
    final filter = model.onlyMatching && all.any(model.highlight);
    return <MapEntry<int, ThumnEntry>>[
      for (int i = 0; i < all.length; i++)
        if (!filter || model.highlight(all[i])) MapEntry(i + 1, all[i]),
    ];
  }

  /// الأحزاب flattened into the rows a remote walks, in screen order: the
  /// search box, the expand-all button, then every hizb card followed by the
  /// thumns of the ones that are open.
  ///
  /// Rebuilt on demand rather than cached -- expanding a card or typing in the
  /// search box changes it, and a stale copy would leave the highlight on a
  /// row that is no longer there.
  List<_TvHizbRow> _tvHizbRows([_HizbView? view]) {
    final model = view ?? _hizbViewModel();
    final rows = <_TvHizbRow>[
      const _TvHizbRow.search(),
      const _TvHizbRow.expandAll(),
    ];
    for (final hizb in model.hizbs) {
      rows.add(_TvHizbRow.card(hizb));
      // A search forces its matches open, exactly as the card builder does.
      if (!model.hasQuery && !_expandedHizbs.contains(hizb)) continue;
      for (final e in _athmanFor(hizb, model)) {
        rows.add(_TvHizbRow.thumn(hizb, e.value));
      }
    }
    return rows;
  }

  /// Flat index of each hizb's card row, so the lazily built list can place
  /// the highlight without re-walking the whole structure for every item.
  Map<int, int> _tvHizbCardBases(List<_TvHizbRow> rows) {
    final out = <int, int>{};
    for (int i = 0; i < rows.length; i++) {
      if (rows[i].isCard) out[rows[i].hizb] = i;
    }
    return out;
  }

  /// How many items the active tab offers the remote.
  int get _tvItemCount {
    switch (_selectedTab) {
      case QuranIndexTab.surahs:
        return _filteredSurahs().length;
      case QuranIndexTab.juzs:
        return 30;
      case QuranIndexTab.hizbs:
        return _tvHizbRows().length;
      case QuranIndexTab.pages:
        return kQuranPageCount;
      case QuranIndexTab.sajdas:
        return _sajdaNotices.length;
    }
  }

  /// Columns in the active tab. الأحزاب is a single-column list; the grids
  /// publish theirs from the layout that drew them.
  int get _tvColumns =>
      _selectedTab == QuranIndexTab.hizbs ? 1 : (_tvCols < 1 ? 1 : _tvCols);

  /// Where the highlight starts when a tab opens: on the item the reader is
  /// already at, matching the offset each grid seeds its scroll with. Landing
  /// on item 1 while the view showed page 300 was disorienting.
  int _tvInitialIndex() {
    switch (_selectedTab) {
      case QuranIndexTab.surahs:
        final i = _filteredSurahs().indexWhere(
          (s) => (s['number'] as int?) == widget.currentSurahNumber,
        );
        return i < 0 ? 0 : i;
      case QuranIndexTab.juzs:
        return _currentJuzNumber() - 1;
      case QuranIndexTab.hizbs:
        final current = thumnEntries[_currentThumnIndex()].hizb;
        final i = _tvHizbRows().indexWhere(
          (r) => r.isCard && r.hizb == current,
        );
        return i < 0 ? 0 : i;
      case QuranIndexTab.pages:
        return widget.currentPage.clamp(0, kQuranPageCount - 1);
      case QuranIndexTab.sajdas:
        return 0;
    }
  }

  /// True when [index] of the active tab is the one the remote points at.
  bool _tvFocused(int index) =>
      TvService.instance.isTv && !_tvOnTabs && index == _tvIndex;

  List<MapEntry<int, String>> _sortedSajdas() =>
      _sajdaNotices.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

  /// Does exactly what a tap on the highlighted item would do.
  void _tvActivate() {
    final int count = _tvItemCount;
    if (_tvIndex < 0 || _tvIndex >= count) return;

    switch (_selectedTab) {
      case QuranIndexTab.surahs:
        final surah = _filteredSurahs()[_tvIndex];
        widget.onSelectSurah(surah['number'] as int);
        _goToPageAndClose(
          surah['page'] as int,
          yOffsetRatio: (surah['yOffsetRatio'] as num?)?.toDouble() ?? 0.0,
        );
      case QuranIndexTab.juzs:
        _goToPageAndClose(hizbStartPages[_tvIndex * 2]);
      case QuranIndexTab.hizbs:
        _tvActivateHizbRow(_tvHizbRows()[_tvIndex]);
      case QuranIndexTab.pages:
        _goToPageAndClose(_tvIndex + 1);
      case QuranIndexTab.sajdas:
        final entry = _sortedSajdas()[_tvIndex];
        _goToPageAndClose((entry.key + 1).clamp(1, kQuranPageCount));
    }
  }

  void _tvActivateHizbRow(_TvHizbRow row) {
    switch (row.kind) {
      case _TvHizbRowKind.search:
        // Hands over to the TV's on-screen keyboard; the key handler stands
        // down while the field holds focus, so the arrows drive the keyboard
        // rather than the highlight. The field has to be let into the focus
        // tree first -- see _hizbSearchActive -- which takes a frame.
        setState(() => _hizbSearchActive = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _hizbSearchFocus.requestFocus();
        });
      case _TvHizbRowKind.expandAll:
        setState(() {
          if (_expandedHizbs.length >= 60) {
            _expandedHizbs.clear();
          } else {
            _expandedHizbs
              ..clear()
              ..addAll(List<int>.generate(60, (i) => i + 1));
          }
          _tvIndex = _tvIndex.clamp(0, _tvItemCount - 1);
        });
      case _TvHizbRowKind.card:
        // A search keeps its matches open, so collapsing is disabled there
        // for the remote exactly as it is for touch.
        if (_hizbSearchController.text.trim().isNotEmpty) return;
        setState(() {
          if (!_expandedHizbs.remove(row.hizb)) _expandedHizbs.add(row.hizb);
        });
        _tvEnsureVisible();
      case _TvHizbRowKind.thumn:
        _goToPageAndClose(row.thumn!.page);
    }
  }

  /// Steps to the previous/next hizb card, skipping the thumn rows between.
  /// With 60 cards and up to eight thumns each, walking a row at a time is
  /// unusable on a remote; the horizontal axis is otherwise dead on this tab,
  /// so it does the jumping.
  void _tvJumpHizbCard(int step) {
    final rows = _tvHizbRows();
    int i = _tvIndex + step;
    while (i >= 0 && i < rows.length && !rows[i].isCard) {
      i += step;
    }
    if (i >= rows.length) return;
    // Past the first card, carry on into the expand-all and search rows rather
    // than stopping dead. Holding this direction is then the way back to the
    // top of a 60-card list, and from there one more Up reaches the tabs.
    if (i < 0) i = 1;
    setState(() => _tvIndex = i);
    _tvEnsureVisible();
  }

  bool _onTvKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // While the hizb search field is being typed into, the arrows belong to
    // the text cursor and the on-screen keyboard.
    if (_hizbSearchFocus.hasFocus) return false;

    final key = event.logicalKey;
    final bool select =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA;

    // The tab row sits above the grid.
    if (_tvOnTabs) {
      final int i = _tvTabOrder.indexOf(_selectedTab);
      // Chips are laid out right-to-left, so Left advances through the list.
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        final int step = key == LogicalKeyboardKey.arrowLeft ? 1 : -1;
        setState(() {
          _selectedTab =
              _tvTabOrder[(i + step + _tvTabOrder.length) % _tvTabOrder.length];
          _tvIndex = _tvInitialIndex();
        });
        return true;
      }
      if (key == LogicalKeyboardKey.arrowDown || select) {
        setState(() => _tvOnTabs = false);
        _tvEnsureVisible();
        return true;
      }
      return key == LogicalKeyboardKey.arrowUp;
    }

    final int count = _tvItemCount;
    if (count <= 0) {
      // An empty tab (a search with no result) must still let Up reach the
      // tabs, or the user is stuck.
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _tvOnTabs = true);
        return true;
      }
      return false;
    }

    if (_tvIndex >= count) _tvIndex = count - 1;
    final int cols = _tvColumns;

    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_tvIndex < cols) {
          _tvOnTabs = true;
        } else {
          _tvIndex -= cols;
        }
      });
      _tvEnsureVisible();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _tvIndex = (_tvIndex + cols).clamp(0, count - 1));
      _tvEnsureVisible();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      // RTL: index increases leftwards, so Left is "next".
      final int step = key == LogicalKeyboardKey.arrowLeft ? 1 : -1;
      if (_selectedTab == QuranIndexTab.hizbs) {
        _tvJumpHizbCard(step);
      } else {
        setState(() => _tvIndex = (_tvIndex + step).clamp(0, count - 1));
        _tvEnsureVisible();
      }
      return true;
    }
    if (select) {
      _tvActivate();
      return true;
    }
    return false;
  }

  /// Keeps the highlighted item on screen as the remote walks the tab.
  void _tvEnsureVisible() {
    if (!TvService.instance.isTv) return;

    if (_selectedTab == QuranIndexTab.hizbs) {
      // Variable-height, lazily built rows: there is no offset to compute, so
      // scroll by the row's own context. Stepping one row at a time always
      // has something built to scroll to (the list's cache extent covers the
      // rows just past the fold), and the search and expand-all rows sit
      // outside the list, where ensureVisible harmlessly finds no scrollable.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _tvRowKey.currentContext;
        if (ctx == null || !mounted) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      });
      return;
    }

    // الأجزاء and السجدات fit on one screen and never scroll.
    final ScrollController? c = switch (_selectedTab) {
      QuranIndexTab.surahs => _surahsScrollController,
      QuranIndexTab.pages => _pagesScrollController,
      _ => null,
    };
    if (c == null || !c.hasClients || _tvRowStride <= 0) return;

    final int row = _tvIndex ~/ _tvColumns;
    // viewportDimension is the main-axis (vertical) extent here, which is
    // exactly what centring a row needs.
    final double target =
        (row * _tvRowStride) -
        ((c.position.viewportDimension - _tvRowStride) / 2);
    c.animateTo(
      target.clamp(0.0, c.position.maxScrollExtent),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
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
      final englishName = (surah['english'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final compactArabic = arabicName.replaceAll(' ', '');
      final compactQuery = query.replaceAll(' ', '');

      return arabicName.contains(query) ||
          compactArabic.contains(compactQuery) ||
          englishName.contains(query);
    }).toList();
  }

  void _goToPageAndClose(int page, {double yOffsetRatio = 0.0}) {
    // Remember which tab this selection came from so the next open returns here.
    _lastSelectedTab = _selectedTab;
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

  // Pixel offset that vertically centers [targetIndex] within a fixed-count
  // grid of the given geometry. Used to seed a scroll controller's
  // initialScrollOffset so the tab opens scrolled to the current item. The
  // scroll physics clamp any over-/under-shoot on the first layout pass.
  double _gridScrollOffset({
    required double maxWidth,
    required double maxHeight,
    required int crossAxisCount,
    required double childAspectRatio,
    required double spacing,
    required double topPadding,
    required double horizontalPadding,
    required int targetIndex,
  }) {
    if (targetIndex <= 0 || crossAxisCount <= 0) return 0.0;
    final availableWidth = maxWidth - (horizontalPadding * 2);
    if (availableWidth <= 0) return 0.0;
    final tileWidth =
        (availableWidth - ((crossAxisCount - 1) * spacing)) / crossAxisCount;
    final tileHeight = tileWidth / childAspectRatio;
    final rowStride = tileHeight + spacing;
    final targetRow = targetIndex ~/ crossAxisCount;
    final offset =
        topPadding +
        (targetRow * rowStride) +
        (tileHeight / 2) -
        (maxHeight / 2);
    return offset < 0 ? 0.0 : offset;
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

  /// Grids publish the geometry they just laid out, so the remote's stepping
  /// and auto-scroll work from the same numbers the tiles were drawn with
  /// rather than from a second, drifting copy of the arithmetic.
  void _publishTvGrid(int crossAxisCount, double rowStride) {
    if (!TvService.instance.isTv) return;
    _tvCols = crossAxisCount;
    _tvRowStride = rowStride;
  }

  /// Vertical pitch of one row of a fixed-count grid.
  double _tileStride({
    required double maxWidth,
    required int crossAxisCount,
    required double childAspectRatio,
    required double spacing,
    required double horizontalPadding,
  }) {
    if (crossAxisCount <= 0) return 0;
    final available =
        maxWidth - (horizontalPadding * 2) - ((crossAxisCount - 1) * spacing);
    if (available <= 0) return 0;
    return ((available / crossAxisCount) / childAspectRatio) + spacing;
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
        final maxRows =
            ((availableHeight + spacing) / (minTileHeight + spacing))
                .floor()
                .clamp(1, itemCount);
        final neededColumns = (itemCount / maxRows).ceil();
        final maxColumnsByWidth =
            ((availableWidth + spacing) / (minTileWidth + spacing))
                .floor()
                .clamp(minColumns, itemCount);
        final crossAxisCount = neededColumns.clamp(
          minColumns,
          maxColumnsByWidth,
        );
        final rowCount = (itemCount / crossAxisCount).ceil();
        final tileWidth =
            (availableWidth - ((crossAxisCount - 1) * spacing)) /
            crossAxisCount;
        final tileHeight =
            (availableHeight - ((rowCount - 1) * spacing)) / rowCount;
        final childAspectRatio = tileWidth / tileHeight;
        _publishTvGrid(crossAxisCount, tileHeight + spacing);

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
                tvFocused: _tvFocused(index),
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
        final maxRows =
            ((availableHeight + spacing) / (minTileHeight + spacing))
                .floor()
                .clamp(1, itemCount);
        final neededColumns = (itemCount / maxRows).ceil();
        final maxColumnsByWidth =
            ((availableWidth + spacing) / (minTileWidth + spacing))
                .floor()
                .clamp(minColumns, itemCount);
        final crossAxisCount = neededColumns.clamp(
          minColumns,
          maxColumnsByWidth,
        );
        final rowCount = (itemCount / crossAxisCount).ceil();
        final tileWidth =
            (availableWidth - ((crossAxisCount - 1) * spacing)) /
            crossAxisCount;
        final tileHeight =
            (availableHeight - ((rowCount - 1) * spacing)) / rowCount;
        final childAspectRatio = tileWidth / tileHeight;
        _publishTvGrid(crossAxisCount, tileHeight + spacing);

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
              final shiftedPage = (entries[index].key + 1).clamp(
                1,
                kQuranPageCount,
              );
              final notice = entries[index].value
                  .replaceFirst(RegExp(r'^سجدة:\s*'), '')
                  .trim();

              return _buildSajdaTile(
                title: 'السجدة ${index + 1}',
                subtitle: notice,
                isCurrent: currentRealPage == shiftedPage,
                tvFocused: _tvFocused(index),
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
      final bool tvFocused = TvService.instance.isTv && _tvOnTabs && isSelected;
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
              color: tvFocused
                  ? const Color(0xFFD2B97E)
                  : (isSelected
                        ? const Color(0xFF8D6E3F)
                        : const Color(0xFF8D6E3F).withValues(alpha: 0.18)),
              width: tvFocused ? 3 : 1,
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
      child: _tvExcludeFocus(
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
            borderSide: const BorderSide(color: Color(0xFF8D6E3F), width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _buildSurahChip(Map<String, dynamic> surah, int index) {
    final number = surah['number'] as int;
    final name = (surah['name'] ?? '').toString();
    final page = surah['page'] as int;
    final isCurrent = number == widget.currentSurahNumber;
    final bool tvFocused =
        TvService.instance.isTv && !_tvOnTabs && index == _tvIndex;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          widget.onSelectSurah(number);
          _goToPageAndClose(
            page,
            yOffsetRatio: (surah['yOffsetRatio'] as num?)?.toDouble() ?? 0.0,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: tvFocused
                ? const Color(0xFFD2B97E)
                : (isCurrent ? const Color(0xFFE7D7AF) : Colors.white),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              // A thick gold ring is the remote's cursor here; without it the
              // grid scrolls but nothing looks selected.
              color: tvFocused
                  ? const Color(0xFF5A4520)
                  : (isCurrent
                        ? const Color(0xFF8D6E3F)
                        : const Color(0xFF8D6E3F).withValues(alpha: 0.10)),
              width: tvFocused ? 3 : 1,
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
    bool tvFocused = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: tvFocused
                ? const Color(0xFFD2B97E)
                : (isCurrent ? const Color(0xFFE7D7AF) : Colors.white),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              // A thick gold ring is the remote's cursor.
              color: tvFocused
                  ? const Color(0xFF5A4520)
                  : (isCurrent
                        ? const Color(0xFF8D6E3F)
                        : const Color(0xFF8D6E3F).withValues(alpha: 0.12)),
              width: tvFocused ? 3 : 1,
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
    bool tvFocused = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: tvFocused
                ? const Color(0xFFD2B97E)
                : (isCurrent ? const Color(0xFFE7D7AF) : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: tvFocused
                  ? const Color(0xFF5A4520)
                  : (isCurrent
                        ? const Color(0xFF8D6E3F)
                        : const Color(0xFF8D6E3F).withValues(alpha: 0.14)),
              width: tvFocused ? 3 : 1,
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

    final crossAxisCount = _crossAxisCount();
    final aspectRatio = _surahAspectRatio();

    return LayoutBuilder(
      builder: (context, constraints) {
        _surahsScrollController ??= ScrollController(
          initialScrollOffset: _gridScrollOffset(
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
            crossAxisCount: crossAxisCount,
            childAspectRatio: aspectRatio,
            spacing: 10,
            topPadding: 0,
            horizontalPadding: 12,
            targetIndex: surahs.indexWhere(
              (s) => (s['number'] as int?) == widget.currentSurahNumber,
            ),
          ),
        );
        _publishTvGrid(
          crossAxisCount,
          _tileStride(
            maxWidth: constraints.maxWidth,
            crossAxisCount: crossAxisCount,
            childAspectRatio: aspectRatio,
            spacing: 10,
            horizontalPadding: 12,
          ),
        );
        return Directionality(
          textDirection: TextDirection.rtl,
          child: GridView.builder(
            controller: _surahsScrollController,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: aspectRatio,
            ),
            itemCount: surahs.length,
            itemBuilder: (context, index) =>
                _buildSurahChip(surahs[index], index),
          ),
        );
      },
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
    const totalPages = kQuranPageCount;
    final currentRealPage = widget.currentPage + 1;
    final isTablet = ResponsiveHelper.isTablet(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final crossAxisCount = isTablet
        ? (isLandscape ? 10 : 7)
        : (isLandscape ? 9 : 5);

    return LayoutBuilder(
      builder: (context, constraints) {
        _pagesScrollController ??= ScrollController(
          initialScrollOffset: _gridScrollOffset(
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.15,
            spacing: 8,
            topPadding: 2,
            horizontalPadding: 12,
            targetIndex: currentRealPage - 1,
          ),
        );
        _publishTvGrid(
          crossAxisCount,
          _tileStride(
            maxWidth: constraints.maxWidth,
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.15,
            spacing: 8,
            horizontalPadding: 12,
          ),
        );
        return Directionality(
          textDirection: TextDirection.rtl,
          child: GridView.builder(
            controller: _pagesScrollController,
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
              final tvFocused = _tvFocused(index);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _goToPageAndClose(page),
                  child: Container(
                    decoration: BoxDecoration(
                      color: tvFocused
                          ? const Color(0xFFD2B97E)
                          : (isCurrent
                                ? const Color(0xFFE7D7AF)
                                : Colors.white),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: tvFocused
                            ? const Color(0xFF5A4520)
                            : (isCurrent
                                  ? const Color(0xFF8D6E3F)
                                  : const Color(
                                      0xFF8D6E3F,
                                    ).withValues(alpha: 0.10)),
                        width: tvFocused ? 3 : 1,
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
      },
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
      final titleMatch =
          normalizedQuery.isNotEmpty &&
          (title.contains(normalizedQuery) ||
              title.replaceAll(' ', '').contains(compactQuery));
      final thumnMatch =
          normalizedQuery.isNotEmpty &&
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

    final model = _hizbViewModel();
    final hasQuery = model.hasQuery;
    final visibleHizbs = model.hizbs;
    final allExpanded = _expandedHizbs.length >= 60;
    // The remote walks a flattened view of these same rows; this maps each
    // card back to its place in it, so the lazily built list can position the
    // highlight without re-walking the structure per item.
    final tvBases = TvService.instance.isTv
        ? _tvHizbCardBases(_tvHizbRows(model))
        : const <int, int>{};

    // On the first open (no active search) seed the list roughly at the current
    // hizb using an estimated collapsed-card height, then fine-tune with
    // ensureVisible once the cards are laid out so it's precisely in view.
    if (_hizbScrollController == null) {
      double initialOffset = 0.0;
      if (!hasQuery) {
        final targetListIndex = visibleHizbs.indexOf(currentHizb);
        const collapsedStride = 70.0; // approx. height of a collapsed hizb card
        initialOffset = targetListIndex <= 1
            ? 0.0
            : (targetListIndex - 1) * collapsedStride;
      }
      _hizbScrollController = ScrollController(
        initialScrollOffset: initialOffset,
      );
    }
    if (!hasQuery && !_hizbEnsuredVisible) {
      _hizbEnsuredVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _currentHizbKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.12,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _buildHizbSearchHeader(allExpanded: allExpanded),
          Expanded(
            child: _tvExcludeFocus(
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
                      controller: _hizbScrollController,
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
                      itemCount: visibleHizbs.length,
                      itemBuilder: (context, index) {
                        final hizbNumber = visibleHizbs[index];
                        // When searching, force the matching hizbs open.
                        final isExpanded =
                            hasQuery || _expandedHizbs.contains(hizbNumber);
                        return _buildHizbCard(
                          hizbNumber: hizbNumber,
                          isExpanded: isExpanded,
                          isCurrentHizb: hizbNumber == currentHizb,
                          currentIndex: currentIndex,
                          toggleEnabled: !hasQuery,
                          model: model,
                          tvBaseIndex: tvBases[hizbNumber],
                          // Key the current hizb so ensureVisible can scroll to it.
                          cardKey: hizbNumber == currentHizb
                              ? _currentHizbKey
                              : null,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Keeps Flutter's directional focus traversal out of a subtree on TV.
  ///
  /// The D-pad is driven explicitly here, but arrow presses still reach the
  /// Shortcuts/Actions path and move focus behind the highlight's back. A
  /// focused widget is also scrolled into view by the focus system, which
  /// fights the highlight's own auto-scroll in the long grids.
  /// Off TV this returns [child] untouched, so phones and tablets keep exactly
  /// the widget tree they had before any of this existed.
  Widget _tvExcludeFocus({required Widget child}) =>
      _tvGateFocus(blocked: TvService.instance.isTv, child: child);

  /// Keeps [child] out of the focus tree while [blocked], and is a plain
  /// pass-through otherwise -- never a wrapper that merely does nothing.
  Widget _tvGateFocus({required bool blocked, required Widget child}) =>
      blocked ? ExcludeFocus(child: child) : child;

  Widget _buildHizbSearchHeader({required bool allExpanded}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          _buildExpandAllButton(
            allExpanded: allExpanded,
            // Rows 0 and 1 of the flattened الأحزاب list are the search box
            // and this button; see _tvHizbRows.
            tvFocused: _tvFocused(1),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _tvGateFocus(
              blocked: TvService.instance.isTv && !_hizbSearchActive,
              child: TextField(
                controller: _hizbSearchController,
                focusNode: _hizbSearchFocus,
                onChanged: (_) => setState(() {}),
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'ابحث: حزب 14 أو اسم الحزب أو الثمن',
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
                    borderSide: _tvFocused(0)
                        ? const BorderSide(color: Color(0xFF5A4520), width: 3)
                        : BorderSide(
                            color: const Color(
                              0xFF8D6E3F,
                            ).withValues(alpha: 0.12),
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
          ),
        ],
      ),
    );
  }

  Widget _buildExpandAllButton({
    required bool allExpanded,
    bool tvFocused = false,
  }) {
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
            color: tvFocused ? const Color(0xFFD2B97E) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: tvFocused
                  ? const Color(0xFF5A4520)
                  : const Color(0xFF8D6E3F).withValues(alpha: 0.25),
              width: tvFocused ? 3 : 1,
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
    required _HizbView model,
    int? tvBaseIndex,
    Key? cardKey,
  }) {
    final hizbTitle = hizbNumber - 1 < hizbTitles.length
        ? hizbTitles[hizbNumber - 1]
        : '';
    final athman = _athmanFor(hizbNumber, model);
    // The card header is the row at tvBaseIndex and its thumns follow it, in
    // the order _tvHizbRows flattened them.
    final bool headerFocused = tvBaseIndex != null && _tvFocused(tvBaseIndex);

    return Padding(
      key: cardKey,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: headerFocused
              ? const Color(0xFFD2B97E)
              : (isCurrentHizb && !isExpanded
                    ? const Color(0xFFE7D7AF)
                    : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: headerFocused
                ? const Color(0xFF5A4520)
                : (isCurrentHizb
                      ? const Color(0xFF8D6E3F)
                      : const Color(0xFF8D6E3F).withValues(alpha: 0.12)),
            width: headerFocused ? 3 : 1,
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
            KeyedSubtree(
              key: headerFocused ? _tvRowKey : null,
              child: Material(
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
                              colors: [Color(0xFFA8844A), Color(0xFF8D6E3F)],
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
                    for (int i = 0; i < athman.length; i++)
                      _buildThumnRow(
                        athman[i].value,
                        athman[i].key,
                        thumnEntries.indexOf(athman[i].value) == currentIndex,
                        matched: model.highlight(athman[i].value),
                        tvFocused:
                            tvBaseIndex != null &&
                            _tvFocused(tvBaseIndex + 1 + i),
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
    bool tvFocused = false,
  }) {
    final Color background = tvFocused
        ? const Color(0xFFD2B97E)
        : isCurrent
        ? const Color(0xFFE7D7AF)
        : matched
        ? const Color(0xFFFBF3DC)
        : const Color(0xFFF6F1E5);
    final Color borderColor = tvFocused
        ? const Color(0xFF5A4520)
        : isCurrent || matched
        ? const Color(0xFF8D6E3F)
        : const Color(0xFF8D6E3F).withValues(alpha: 0.08);

    return Padding(
      key: tvFocused ? _tvRowKey : null,
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
              border: Border.all(color: borderColor, width: tvFocused ? 3 : 1),
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
          return _tvExcludeFocus(child: _buildSurahsGrid());
        }
        return Column(
          children: [
            _buildSearchField(),
            Expanded(child: _tvExcludeFocus(child: _buildSurahsGrid())),
          ],
        );
      case QuranIndexTab.juzs:
        return _tvExcludeFocus(child: _buildJuzGrid());
      case QuranIndexTab.hizbs:
        // Not wrapped as a whole: its search box must stay focusable so the
        // remote can hand it the on-screen keyboard.
        return _buildThumnsByHizb();
      case QuranIndexTab.pages:
        return _tvExcludeFocus(child: _buildPagesGrid());
      case QuranIndexTab.sajdas:
        return _tvExcludeFocus(child: _buildSajdaGrid());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (TvService.instance.isTv && !_tvSeeded) {
      // Done here rather than in initState because the hizb tab's expansion
      // state is not set up until its first build.
      _tvSeeded = true;
      _tvIndex = _tvInitialIndex();
    }
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

/// The search-derived state of the الأحزاب tab.
class _HizbView {
  const _HizbView({
    required this.hasQuery,
    required this.hizbs,
    required this.highlight,
    required this.onlyMatching,
  });

  /// Whether the search box has anything in it. A search forces its matching
  /// cards open.
  final bool hasQuery;

  /// The hizb numbers to show, in order.
  final List<int> hizbs;

  /// Whether a thumn matched the text part of the query.
  final bool Function(ThumnEntry) highlight;

  /// Whether cards should show only their matching thumns.
  final bool onlyMatching;
}

enum _TvHizbRowKind { search, expandAll, card, thumn }

/// One row of الأحزاب as the remote sees it. The tab is a nested structure
/// (cards that open to reveal thumns), so D-pad navigation walks a flattened
/// view of whatever is currently on screen instead.
class _TvHizbRow {
  const _TvHizbRow.search()
    : kind = _TvHizbRowKind.search,
      hizb = 0,
      thumn = null;

  const _TvHizbRow.expandAll()
    : kind = _TvHizbRowKind.expandAll,
      hizb = 0,
      thumn = null;

  const _TvHizbRow.card(this.hizb) : kind = _TvHizbRowKind.card, thumn = null;

  const _TvHizbRow.thumn(this.hizb, this.thumn) : kind = _TvHizbRowKind.thumn;

  final _TvHizbRowKind kind;
  final int hizb;
  final ThumnEntry? thumn;

  bool get isCard => kind == _TvHizbRowKind.card;
}

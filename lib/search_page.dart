import 'dart:async';

import 'package:flutter/material.dart';

import 'services/quran_json_service.dart';
import 'services/ayah_position_service.dart';
import 'utils/arabic_text_normalizer.dart';

class SearchPage extends StatefulWidget {
  final Function(int page) onGoToPage;

  const SearchPage({super.key, required this.onGoToPage});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class SearchResult {
  final int page;
  final int surah;
  final String surahName;
  final int ayah;
  final String text;
  final int score;
  final bool containsFullQuery;

  const SearchResult({
    required this.page,
    required this.surah,
    required this.surahName,
    required this.ayah,
    required this.text,
    required this.score,
    required this.containsFullQuery,
  });
}

class _IndexedAyah {
  final int page;
  final int surah;
  final String surahName;
  final int ayah;
  final String text;
  final String normalizedText;
  final List<String> normalizedWords;

  const _IndexedAyah({
    required this.page,
    required this.surah,
    required this.surahName,
    required this.ayah,
    required this.text,
    required this.normalizedText,
    required this.normalizedWords,
  });
}

class _NormalizedTextMapping {
  final String normalizedText;
  final List<int> originalIndices;

  const _NormalizedTextMapping({
    required this.normalizedText,
    required this.originalIndices,
  });
}

class _SurahOption {
  final int surah;
  final String surahName;

  const _SurahOption({required this.surah, required this.surahName});
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Remembers the last query across openings of the search page so the user
  // can pick a result, return to the reader, and resume the same search.
  static String _lastQuery = '';

  String _query = '';
  bool _isLoading = true;
  List<_IndexedAyah> _searchIndex = [];
  List<SearchResult> _results = [];
  Timer? _searchDebounce;

  // The surahs available to filter by, ordered by surah number. Built from the
  // search index once it loads. `_selectedSurah == 0` means "the whole Quran".
  List<_SurahOption> _surahOptions = [];
  static int _selectedSurah = 0;

  // When true, only exact (full-query) matches are shown. Deliberately not
  // static: every opening of the search page starts back at smart + exact.
  bool _exactOnly = false;

  // Accumulates horizontal drag distance on the search field so a finger swipe
  // moves the text cursor (cursor control) — handy for editing RTL Arabic text.
  double _cursorDragRemainder = 0;

  bool get _isLandscape =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  void _closeSearchPage() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
    }
  }

  @override
  void initState() {
    super.initState();
    // Resume the previous search if the page was opened before in this session.
    if (_lastQuery.isNotEmpty) {
      _query = _lastQuery;
      _controller.text = _lastQuery;
      _controller.selection = TextSelection.collapsed(
        offset: _lastQuery.length,
      );
    }
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final pages = await QuranJsonService.loadQuranPages();

      // Load visual positions to act as the ultimate source of truth for page numbers
      final positionsByPage = await AyahPositionService.loadAyahPositions();
      final Map<String, int> visualPageMap = {};

      positionsByPage.forEach((pageNum, ayahs) {
        for (final pos in ayahs) {
          visualPageMap['${pos.surah}_${pos.ayah}'] = pageNum;
        }
      });

      if (!mounted) return;

      final searchIndex = <_IndexedAyah>[];
      for (final page in pages) {
        for (final ayah in page.ayahs) {
          final normalizedText = _normalizeText(ayah.text);
          final truePage =
              visualPageMap['${ayah.surah}_${ayah.ayah}'] ?? page.page;

          searchIndex.add(
            _IndexedAyah(
              page: truePage,
              surah: ayah.surah,
              surahName: ayah.surahName,
              ayah: ayah.ayah,
              text: ayah.text,
              normalizedText: normalizedText,
              normalizedWords: normalizedText
                  .split(' ')
                  .where((e) => e.isNotEmpty)
                  .toList(growable: false),
            ),
          );
        }
      }

      // Build the surah filter list (one entry per surah, in order).
      final Map<int, String> surahNames = {};
      for (final ayah in searchIndex) {
        surahNames.putIfAbsent(ayah.surah, () => ayah.surahName);
      }
      final surahOptions =
          surahNames.entries
              .map((e) => _SurahOption(surah: e.key, surahName: e.value))
              .toList()
            ..sort((a, b) => a.surah.compareTo(b.surah));

      setState(() {
        _searchIndex = searchIndex;
        _surahOptions = surahOptions;
        _isLoading = false;
      });

      // Re-run the restored query now that the index is available so the user
      // sees the same results they left off on.
      if (_query.trim().isNotEmpty) {
        _runSearch(_query);
      }
    } catch (e) {
      debugPrint('ط®ط·ط£ طھط­ظ…ظٹظ„ JSON: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Delegates to the shared normalizer (lib/utils/arabic_text_normalizer.dart)
  // so search and the memorization-test recitation aligner apply
  // identical rules.
  String _normalizeText(String text) => normalizeArabicText(text);

  _NormalizedTextMapping _normalizeTextWithMap(String text) {
    final buffer = StringBuffer();
    final indices = <int>[];
    bool previousWasSpace = false;

    for (int i = 0; i < text.length; i++) {
      final normalizedChar = _normalizeChar(text[i]);
      if (normalizedChar == null) continue;

      if (normalizedChar == ' ') {
        if (buffer.isEmpty || previousWasSpace) continue;
        buffer.write(' ');
        indices.add(i);
        previousWasSpace = true;
        continue;
      }

      buffer.write(normalizedChar);
      indices.add(i);
      previousWasSpace = false;
    }

    var normalized = buffer.toString();
    while (normalized.endsWith(' ')) {
      normalized = normalized.substring(0, normalized.length - 1);
      indices.removeLast();
    }

    return _NormalizedTextMapping(
      normalizedText: normalized,
      originalIndices: indices,
    );
  }

  // Delegates to the shared normalizer (lib/utils/arabic_text_normalizer.dart).
  String? _normalizeChar(String char) => normalizeArabicChar(char);

  void _scheduleSearch(String rawQuery) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      _runSearch(rawQuery);
    });
  }

  void _runSearch(String rawQuery) {
    final query = _normalizeText(rawQuery.trim());
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _results = [];
      });
      return;
    }

    final queryWords = query.split(' ').where((e) => e.isNotEmpty).toList();
    final results = <SearchResult>[];

    for (final ayah in _searchIndex) {
      // Restrict to the chosen surah when a specific one is selected.
      if (_selectedSurah != 0 && ayah.surah != _selectedSurah) continue;

      // In exact-only mode, skip smart (fuzzy) matches before scoring.
      if (_exactOnly && !ayah.normalizedText.contains(query)) continue;

      final score = _calculateMatchScore(
        query,
        queryWords,
        ayah.normalizedText,
        ayah.normalizedWords,
      );
      if (score > 0) {
        results.add(
          SearchResult(
            page: ayah.page,
            surah: ayah.surah,
            surahName: ayah.surahName,
            ayah: ayah.ayah,
            text: ayah.text,
            score: score,
            containsFullQuery: ayah.normalizedText.contains(query),
          ),
        );
      }
    }

    results.sort((a, b) {
      final containsFullQueryCompare =
          (b.containsFullQuery ? 1 : 0) - (a.containsFullQuery ? 1 : 0);
      if (containsFullQueryCompare != 0) return containsFullQueryCompare;

      if (a.containsFullQuery && b.containsFullQuery) {
        final surahCompare = a.surah.compareTo(b.surah);
        if (surahCompare != 0) return surahCompare;

        final ayahCompare = a.ayah.compareTo(b.ayah);
        if (ayahCompare != 0) return ayahCompare;

        return a.page.compareTo(b.page);
      }

      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;

      final surahCompare = a.surah.compareTo(b.surah);
      if (surahCompare != 0) return surahCompare;

      final ayahCompare = a.ayah.compareTo(b.ayah);
      if (ayahCompare != 0) return ayahCompare;

      return a.page.compareTo(b.page);
    });

    if (!mounted) return;
    setState(() {
      _results = results;
    });
  }

  int _calculateMatchScore(
    String query,
    List<String> queryWords,
    String text,
    List<String> textWords,
  ) {
    if (query.isEmpty || text.isEmpty) return 0;

    int score = 0;

    if (text == query) {
      score += 20000;
    }

    if (text.contains(query)) {
      score += 12000;

      if (text.startsWith(query)) {
        score += 1500;
      }

      final diff = (text.length - query.length).abs();
      score += (1200 - diff).clamp(0, 1200);
    }

    if (queryWords.isEmpty || textWords.isEmpty) {
      return score;
    }

    score += _scorePhraseSequence(queryWords, textWords);

    int matchedWords = 0;
    for (final qWord in queryWords) {
      int bestWordScore = 0;
      for (final tWord in textWords) {
        final wordScore = _scoreWordMatch(qWord, tWord);
        if (wordScore > bestWordScore) {
          bestWordScore = wordScore;
        }
      }

      if (bestWordScore > 0) {
        matchedWords++;
        score += bestWordScore;
      }
    }

    if (queryWords.length > 1 && matchedWords < queryWords.length) {
      return 0;
    }

    if (matchedWords == queryWords.length) {
      score += 1800;
    }

    score += matchedWords * 120;
    return score;
  }

  int _scorePhraseSequence(List<String> queryWords, List<String> textWords) {
    if (queryWords.isEmpty || textWords.isEmpty) return 0;

    int bestScore = 0;
    for (int start = 0; start < textWords.length; start++) {
      final score = _scoreWindowMatch(queryWords, textWords, start);
      if (score > bestScore) {
        bestScore = score;
      }
    }
    return bestScore;
  }

  int _scoreWindowMatch(
    List<String> queryWords,
    List<String> textWords,
    int startIndex,
  ) {
    int score = 0;
    int consecutiveMatches = 0;
    int matchedCount = 0;
    int textIndex = startIndex;

    for (int qIndex = 0; qIndex < queryWords.length; qIndex++) {
      final qWord = queryWords[qIndex];

      int bestLocalScore = 0;
      int bestMatchIndex = -1;

      for (
        int tIndex = textIndex;
        tIndex < textWords.length && tIndex <= textIndex + 3;
        tIndex++
      ) {
        final localScore = _scoreWordMatch(qWord, textWords[tIndex]);
        if (localScore > bestLocalScore) {
          bestLocalScore = localScore;
          bestMatchIndex = tIndex;
        }
      }

      if (bestLocalScore > 0 && bestMatchIndex != -1) {
        matchedCount++;
        score += bestLocalScore;

        if (bestMatchIndex == textIndex) {
          consecutiveMatches++;
          score += 1800 * consecutiveMatches;
        } else {
          final gap = bestMatchIndex - textIndex;
          score += 500 - (gap * 120);
          consecutiveMatches = 0;
        }

        if (bestMatchIndex >= textIndex) {
          score += 400;
        }

        textIndex = bestMatchIndex + 1;
      } else {
        score -= 900;
        consecutiveMatches = 0;
      }
    }

    if (matchedCount == queryWords.length) {
      score += 5000;
    }

    if (matchedCount >= 2) {
      score += matchedCount * 700;
    }

    return score;
  }

  int _scoreWordMatch(String queryWord, String textWord) {
    if (queryWord.isEmpty || textWord.isEmpty) return 0;

    if (queryWord == textWord) {
      return 3000;
    }

    if (textWord.contains(queryWord)) {
      final diff = (textWord.length - queryWord.length).abs();
      return 2200 - (diff * 50);
    }

    if (queryWord.length >= 4 &&
        textWord.length >= 4 &&
        textWord.startsWith(queryWord.substring(0, queryWord.length - 1))) {
      final diff = (textWord.length - queryWord.length).abs();
      return 900 - (diff * 80);
    }

    final qSkeleton = queryWord.replaceAll('ا', '');
    final tSkeleton = textWord.replaceAll('ا', '');

    if (qSkeleton.length >= 2 && qSkeleton == tSkeleton) {
      return 1500;
    }

    if (qSkeleton.length >= 3 && tSkeleton.contains(qSkeleton)) {
      return 1000;
    }

    return 0;
  }

  List<InlineSpan> _buildHighlightedTextSpans(String text, String query) {
    final normalizedQuery = _normalizeText(query.trim());
    if (normalizedQuery.isEmpty) {
      return [TextSpan(text: text)];
    }

    final mapping = _normalizeTextWithMap(text);
    if (mapping.normalizedText.isEmpty) {
      return [TextSpan(text: text)];
    }

    final spans = <InlineSpan>[];
    final normalizedText = mapping.normalizedText;

    int start = 0;
    while (start < text.length) {
      final normalizedStart = mapping.originalIndices.indexWhere(
        (originalIndex) => originalIndex >= start,
      );
      if (normalizedStart == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      final matchIndex = normalizedText.indexOf(
        normalizedQuery,
        normalizedStart,
      );
      if (matchIndex == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      final originalStart = mapping.originalIndices[matchIndex];
      if (originalStart > start) {
        spans.add(TextSpan(text: text.substring(start, originalStart)));
      }

      final matchEnd = matchIndex + normalizedQuery.length;
      final originalEnd = matchEnd < mapping.originalIndices.length
          ? mapping.originalIndices[matchEnd]
          : text.length;

      spans.add(
        TextSpan(
          text: text.substring(originalStart, originalEnd),
          style: const TextStyle(
            backgroundColor: Color(0xFFF3D36A),
            color: Color(0xFF2D2112),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      start = originalEnd;
    }

    return spans;
  }

  void _openResult(SearchResult ayah) {
    widget.onGoToPage(ayah.page);
    Navigator.pop(context);
  }

  // --- Swipe-to-move-cursor (cursor control) -------------------------------
  // The native "spacebar cursor control" is unreliable inside an RTL field, so
  // we let the user drag a finger horizontally across the search box to nudge
  // the caret. Because the text is right-to-left, dragging the finger to the
  // right moves the caret visually right (toward the start of the text) and
  // dragging left moves it toward the end.
  void _onCursorDragStart(DragStartDetails details) {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    _cursorDragRemainder = 0;
  }

  void _onCursorDragUpdate(DragUpdateDetails details) {
    final text = _controller.text;
    if (text.isEmpty) return;

    // Distance the finger must travel to move the caret by one character.
    const double pixelsPerChar = 7.0;

    _cursorDragRemainder += details.delta.dx;
    final int steps = (_cursorDragRemainder / pixelsPerChar).truncate();
    if (steps == 0) return;
    _cursorDragRemainder -= steps * pixelsPerChar;

    final selection = _controller.selection;
    final int current = selection.baseOffset >= 0
        ? selection.baseOffset
        : text.length;

    // RTL: a rightward drag (positive dx) moves the caret toward the start.
    final int next = (current - steps).clamp(0, text.length);
    if (next == current) return;

    _controller.selection = TextSelection.collapsed(offset: next);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // The surah-scope dropdown shown under the search field. Selecting a surah
  // limits the search to that surah; the first entry restores the whole Quran.
  Widget _buildSurahFilter(bool compactLandscape, double horizontalSystemInset) {
    // Two-digit surah numbers keep the menu neatly aligned (e.g. "01 الفاتحة").
    String label(int surah, String name) =>
        '${surah.toString().padLeft(2, '0')} $name';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12 + (compactLandscape ? horizontalSystemInset : 0),
        0,
        12,
        compactLandscape ? 4 : 8,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            Expanded(child: _buildSurahDropdown(label)),
            const SizedBox(width: 8),
            _buildExactMatchToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildSurahDropdown(String Function(int, String) label) {
    return DropdownButtonFormField<int>(
          initialValue: _selectedSurah,
          isExpanded: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.arrow_drop_down),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.menu_book_outlined),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          items: [
            const DropdownMenuItem<int>(
              value: 0,
              child: Text(
                'القرآن كاملاً',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final option in _surahOptions)
              DropdownMenuItem<int>(
                value: option.surah,
                child: Text(
                  label(option.surah, option.surahName),
                  textDirection: TextDirection.rtl,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedSurah = value;
            });
            if (_query.trim().isNotEmpty) {
              _runSearch(_query);
            }
          },
    );
  }

  // A compact outlined toggle sitting beside the surah dropdown. Off (default)
  // shows exact + smart matches; on restricts results to exact matches only.
  Widget _buildExactMatchToggle() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          _exactOnly = !_exactOnly;
        });
        if (_query.trim().isNotEmpty) {
          _runSearch(_query);
        }
      },
      child: Container(
        height: 48,
        padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _exactOnly
                ? Theme.of(context).colorScheme.primary
                : Colors.black38,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'بحث مطابق فقط',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 13,
                fontWeight: _exactOnly ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            Transform.scale(
              scale: 0.7,
              child: Switch(
                value: _exactOnly,
                onChanged: (value) {
                  setState(() {
                    _exactOnly = value;
                  });
                  if (_query.trim().isNotEmpty) {
                    _runSearch(_query);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // A thin, right-aligned section label separating exact matches from smart
  // (fuzzy) matches. Kept minimal so it costs almost no vertical space.
  Widget _buildSectionHeader(String label, bool compactLandscape) {
    return Padding(
      padding: EdgeInsets.only(top: compactLandscape ? 6 : 8, bottom: 2),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Text(
            label,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey[600],
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(height: 1, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildResultCard(SearchResult ayah) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openResult(ayah),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3EA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            RichText(
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.8,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
                children: _buildHighlightedTextSpans(ayah.text, _query),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'سورة ${ayah.surahName} • آية ${ayah.ayah} • صفحة ${ayah.page}',
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  // Renders the results with a compact count line and, when both kinds exist,
  // inline "exact match" / "smart match" section headers. Results arrive already
  // sorted with exact (containsFullQuery) matches first, so we split on that.
  Widget _buildResultsList(bool compactLandscape) {
    final exact = _results.where((r) => r.containsFullQuery).toList();
    final smart = _results.where((r) => !r.containsFullQuery).toList();
    final bool showHeaders = exact.isNotEmpty && smart.isNotEmpty;

    // Build a flat row list: optional header + its cards, per section.
    final rows = <Widget>[];
    void addSection(String header, List<SearchResult> items) {
      if (items.isEmpty) return;
      if (showHeaders) rows.add(_buildSectionHeader(header, compactLandscape));
      for (final ayah in items) {
        rows.add(_buildResultCard(ayah));
      }
    }

    addSection('مطابقة تامة', exact);
    addSection('مطابقة ذكية', smart);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, compactLandscape ? 4 : 8),
          child: Align(
            child: Text(
              'عدد النتائج: ${_results.length}',
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: compactLandscape ? 13 : 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(12, 0, 12, compactLandscape ? 8 : 12),
            itemCount: rows.length,
            separatorBuilder: (context, index) {
              // No gap directly above a section header (it carries its own top
              // padding); a normal card gap otherwise.
              final bool nextIsHeader = rows[index + 1] is Padding;
              return SizedBox(height: nextIsHeader ? 0 : 8);
            },
            itemBuilder: (context, index) => rows[index],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool compactLandscape = _isLandscape;
    final mediaPadding = MediaQuery.of(context).padding;
    final horizontalSystemInset = compactLandscape
        ? (mediaPadding.left > mediaPadding.right
              ? mediaPadding.left
              : mediaPadding.right)
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        // Keep the header slim so the added surah filter doesn't push content
        // too far down and the whole page stays compact.
        toolbarHeight: 44,
        leadingWidth: compactLandscape
            ? kToolbarHeight + horizontalSystemInset
            : null,
        leading: Padding(
          padding: EdgeInsetsDirectional.only(
            start: compactLandscape ? horizontalSystemInset : 0,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _closeSearchPage,
          ),
        ),
        title: Padding(
          padding: EdgeInsetsDirectional.only(
            start: compactLandscape ? horizontalSystemInset : 0,
          ),
          child: const Text('\u0627\u0644\u0628\u062d\u062b'),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: true,
        left: true,
        right: true,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                12 + (compactLandscape ? horizontalSystemInset : 0),
                compactLandscape ? 8 : 12,
                12,
                compactLandscape ? 4 : 8,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _onCursorDragStart,
                onHorizontalDragUpdate: _onCursorDragUpdate,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textDirection: TextDirection.rtl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText:
                        '\u0627\u0628\u062d\u062b \u0639\u0646 \u0622\u064a\u0629 \u0623\u0648 \u0643\u0644\u0645\u0629',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _controller.clear();
                              _lastQuery = '';
                              setState(() {
                                _query = '';
                                _results = [];
                              });
                            },
                            icon: const Icon(Icons.close),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: compactLandscape ? 10 : 14,
                    ),
                  ),
                  onChanged: (value) {
                    _lastQuery = value;
                    setState(() {
                      _query = value;
                    });
                    _scheduleSearch(value);
                  },
                ),
              ),
            ),
            _buildSurahFilter(compactLandscape, horizontalSystemInset),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _query.trim().isEmpty
                  ? const Center(
                      child: Text(
                        '\u0627\u0643\u062a\u0628 \u0643\u0644\u0645\u0629 \u0644\u0644\u0628\u062d\u062b',
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : _results.isEmpty
                  ? const Center(
                      child: Text(
                        '\u0644\u0627 \u062a\u0648\u062c\u062f \u0646\u062a\u0627\u0626\u062c',
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : _buildResultsList(compactLandscape),
            ),
          ],
        ),
      ),
    );
  }
}

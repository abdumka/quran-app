import 'dart:async';

import 'package:flutter/material.dart';

import 'services/quran_json_service.dart';
import 'services/ayah_position_service.dart';

class SearchPage extends StatefulWidget {
  final Function(int page) onGoToPage;

  const SearchPage({
    super.key,
    required this.onGoToPage,
  });

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

  const SearchResult({
    required this.page,
    required this.surah,
    required this.surahName,
    required this.ayah,
    required this.text,
    required this.score,
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

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();

  String _query = '';
  bool _isLoading = true;
  List<_IndexedAyah> _searchIndex = [];
  List<SearchResult> _results = [];
  Timer? _searchDebounce;

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
          visualPageMap['\${pos.surah}_\${pos.ayah}'] = pageNum;
        }
      });

      if (!mounted) return;

      final searchIndex = <_IndexedAyah>[];
      for (final page in pages) {
        for (final ayah in page.ayahs) {
          final normalizedText = _normalizeText(ayah.text);
          final truePage = visualPageMap['\${ayah.surah}_\${ayah.ayah}'] ?? page.page;
          
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

      setState(() {
        _searchIndex = searchIndex;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('ط®ط·ط£ طھط­ظ…ظٹظ„ JSON: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _normalizeText(String text) {
    return text
        // Remove all diacritics and quranic symbols
        .replaceAll(RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
        // Remove Tatweel
        .replaceAll('ـ', '')
        // Normalize Alef variations
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        // Normalize Ya variations (including Qalon specific marks)
        .replaceAll(RegExp(r'[ىےئ]'), 'ي')
        // Normalize Waw variations
        .replaceAll('ؤ', 'و')
        // Normalize Ta Marbuta to Ha
        .replaceAll('ة', 'ه')
        // Remove standalone Hamza
        .replaceAll('ء', '')
        // Remove commas
        .replaceAll('،', '')
        // Remove extra spaces
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

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

  String? _normalizeChar(String char) {
    if (char.trim().isEmpty) return ' ';

    final code = char.codeUnitAt(0);
    final isDiacritic = (code >= 0x0610 && code <= 0x061A) ||
        (code >= 0x064B && code <= 0x065F) ||
        code == 0x0670 ||
        (code >= 0x06D6 && code <= 0x06ED);
    
    if (isDiacritic) return null;

    switch (char) {
      case 'ـ':
      case '،':
      case 'ء':
        return null; // Ignore these entirely
      case 'أ':
      case 'إ':
      case 'آ':
      case 'ٱ':
        return 'ا';
      case 'ى':
      case 'ے':
      case 'ئ':
        return 'ي';
      case 'ؤ':
        return 'و';
      case 'ة':
        return 'ه';
      default:
        return char;
    }
  }

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
          ),
        );
      }
    }

    results.sort((a, b) {
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

      final matchIndex = normalizedText.indexOf(normalizedQuery, normalizedStart);
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

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    super.dispose();
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
              child: TextField(
                controller: _controller,
                textDirection: TextDirection.rtl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '\u0627\u0628\u062d\u062b \u0639\u0646 \u0622\u064a\u0629 \u0623\u0648 \u0643\u0644\u0645\u0629',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _controller.clear();
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
                  setState(() {
                    _query = value;
                  });
                  _scheduleSearch(value);
                },
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
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
                          : Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    compactLandscape ? 4 : 8,
                                  ),
                                  child: Align(
                                    child: Text(
                                      '\u0639\u062f\u062f \u0627\u0644\u0646\u062a\u0627\u0626\u062c: ${_results.length}',
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
                                    padding: EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      compactLandscape ? 8 : 12,
                                    ),
                                    itemCount: _results.length,
                                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final ayah = _results[index];
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
                                                  children: _buildHighlightedTextSpans(
                                                    ayah.text,
                                                    _query,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '\u0633\u0648\u0631\u0629 ${ayah.surahName} • \u0622\u064a\u0629 ${ayah.ayah} • \u0635\u0641\u062d\u0629 ${ayah.page}',
                                                textAlign: TextAlign.right,
                                                textDirection: TextDirection.rtl,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }
}



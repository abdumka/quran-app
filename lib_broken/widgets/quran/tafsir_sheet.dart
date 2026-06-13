import 'package:flutter/material.dart';

import '../../services/tafsir_service.dart';

/// Stateful Tafsir sheet with page navigation.
class TafsirSheetContent extends StatefulWidget {
  final int initialPageIndex;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final Color titleColor;
  final Color accentColor;
  final ValueChanged<int> onPageChanged;

  const TafsirSheetContent({
    super.key,
    required this.initialPageIndex,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.titleColor,
    required this.accentColor,
    required this.onPageChanged,
  });

  @override
  State<TafsirSheetContent> createState() => _TafsirSheetContentState();
}

class _TafsirSheetContentState extends State<TafsirSheetContent> {
  late int _currentPage;
  List<Map<String, dynamic>> _tafsirData = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPageIndex;
    _loadTafsir(_currentPage);
  }

  Future<void> _loadTafsir(int pageIndex) async {
    setState(() => _isLoading = true);
    final data = await TafsirService.getTafsirForPage(pageIndex);
    if (!mounted) return;
    setState(() {
      _tafsirData = data;
      _isLoading = false;
    });
  }

  void _goToPage(int newPage) {
    if (newPage < 0 || newPage >= 604) return;
    setState(() => _currentPage = newPage);
    widget.onPageChanged(newPage);
    _loadTafsir(newPage);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: widget.borderColor, width: 2)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: widget.borderColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 12),
              // Title + navigation row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Next page (left arrow in RTL = next page)
                    Container(
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: _currentPage < 603 ? () => _goToPage(_currentPage + 1) : null,
                        icon: Icon(Icons.chevron_left_rounded, color: widget.accentColor),
                        iconSize: 22,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                        tooltip: 'الصفحة التالية',
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'تفسير السعدي - الصفحة ${_currentPage + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: widget.titleColor,
                        ),
                      ),
                    ),
                    // Previous page (right arrow in RTL = previous page)
                    Container(
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: _currentPage > 0 ? () => _goToPage(_currentPage - 1) : null,
                        icon: Icon(Icons.chevron_right_rounded, color: widget.accentColor),
                        iconSize: 22,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                        tooltip: 'الصفحة السابقة',
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 20),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: widget.borderColor),
                      )
                    : _tafsirData.isEmpty
                        ? Center(
                            child: Text(
                              'لا يوجد تفسير لهذه الصفحة',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(color: widget.textColor, fontSize: 18),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _tafsirData.length,
                            separatorBuilder: (_, __) => const Divider(height: 32),
                            itemBuilder: (context, index) {
                              final data = _tafsirData[index];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '${data['surahName']} - آية ${data['ayahNumber']}',
                                    textAlign: TextAlign.center,
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                      color: widget.borderColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    data['ayahText'],
                                    textAlign: TextAlign.center,
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                      color: widget.titleColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 22,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    data['tafsir'],
                                    textAlign: TextAlign.justify,
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                      color: widget.textColor,
                                      fontSize: 18,
                                      height: 1.8,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

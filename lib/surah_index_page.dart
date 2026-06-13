import 'package:flutter/material.dart';
import 'widgets/surah_index_panel.dart';

class SurahIndexPage extends StatelessWidget {
  final List<Map<String, dynamic>> surahs;
  final Function(int page, {double yOffsetRatio}) onGoToPage;
  final int initialSurahIndex;
  final int currentSurahNumber;
  final ValueChanged<int> onSelectSurah;

  const SurahIndexPage({
    super.key,
    required this.surahs,
    required this.onGoToPage,
    required this.initialSurahIndex,
    required this.currentSurahNumber,
    required this.onSelectSurah,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F1E5),
      appBar: AppBar(
        title: const Text('الفهرس'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            SurahIndexPanel(
              surahs: surahs,
              initialSurahIndex: initialSurahIndex,
              currentSurahNumber: currentSurahNumber,
              onGoToPage: (page, {double yOffsetRatio = 0.0}) {
                Navigator.pop(context);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  onGoToPage(page, yOffsetRatio: yOffsetRatio);
                });
              },
              onSelectSurah: onSelectSurah,
              onClose: () {
                Navigator.pop(context);
              },
              onSearchChanged: null,
            ),
          ],
        ),
      ),
    );
  }
}

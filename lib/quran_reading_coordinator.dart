import 'package:flutter/foundation.dart';

class QuranReadingCoordinator extends ChangeNotifier {
  QuranReadingCoordinator({
    required this.pageCount,
    int initialPage = 0,
  }) : _currentPage = initialPage.clamp(0, pageCount - 1);

  final int pageCount;

  int _currentPage;

  int get currentPage => _currentPage;

  void setCurrentPage(int page) {
    final safePage = page.clamp(0, pageCount - 1);
    if (safePage == _currentPage) return;
    _currentPage = safePage;
    notifyListeners();
  }
}

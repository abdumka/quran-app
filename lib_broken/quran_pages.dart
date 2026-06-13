import 'dart:async'; // Quran Pages View

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'widgets/quran/bookmark_picker_dialog.dart';
import 'widgets/quran/bookmark_ribbon_painter.dart';
import 'continuous_quran_view.dart';
import 'models/reader_bookmark.dart';
import 'quran_constants.dart';
import 'quran_reading_coordinator.dart';
import 'services/high_quality_images_service.dart';
import 'services/margin_images_service.dart';
import 'services/theme_service.dart';
import 'services/tafsir_service.dart';
import 'services/audio_service.dart';
import 'services/quran_json_service.dart';
import 'models/quran_page_data.dart';
import 'surah_data.dart';
import 'quran_index_page.dart';
import 'utils/responsive_helper.dart';
import 'utils/tablet_layout_helper.dart';
import 'widgets/menu/bottom_overlay_menu.dart';
import 'widgets/top_overlay_bar.dart';
import 'widgets/settings/settings_page.dart';
import 'search_page.dart';

class QuranPages extends StatefulWidget {
  const QuranPages({super.key});

  @override
  State<QuranPages> createState() => _QuranPagesState();
}

class _QuranPagesState extends State<QuranPages>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _defaultPageAspectRatio = 720 / 1640;
  static const double _marginPageAspectRatio = 1178 / 1878;
  static const String _portraitScrollModePrefKey = 'portraitScrollMode';
  static const String _tabletLayoutModePrefKey = 'tabletLayoutMode';
  static const String _bookmarkGuideDismissedPrefKey =
      'bookmarkGuideDismissed';
  static const String _bookmarksPrefKey = 'readerBookmarks';
  static const String _sajdaDua =
      'سجد وجهي للذي خلقه وشق سمعه وبصره بحوله وقوته، فتبارك الله أحسن الخالقين.';
  static const String _dawudSajdaDua =
      'اللهم اكتب لي بها عندك أجرا، وضع عني بها وزرا، واجعلها لي عندك ذخرا، وتقبلها مني كما تقبلتها من عبدك داوود.';

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

  static const Map<int, String> _hizbProgressNotices = <int, String>{
    5: 'ربع الحزب 1',
    7: 'نصف الحزب 1',
    9: 'ثلاثة أرباع الحزب 1',
    14: 'ربع الحزب 2',
    17: 'نصف الحزب 2',
    19: 'ثلاثة أرباع الحزب 2',
    24: 'ربع الحزب 3',
    27: 'نصف الحزب 3',
    29: 'ثلاثة أرباع الحزب 3',
    34: 'ربع الحزب 4',
    37: 'نصف الحزب 4',
    39: 'ثلاثة أرباع الحزب 4',
    44: 'ربع الحزب 5',
    46: 'نصف الحزب 5',
    49: 'ثلاثة أرباع الحزب 5',
    54: 'ربع الحزب 6',
    56: 'نصف الحزب 6',
    59: 'ثلاثة أرباع الحزب 6',
    64: 'ربع الحزب 7',
    67: 'نصف الحزب 7',
    69: 'ثلاثة أرباع الحزب 7',
    74: 'ربع الحزب 8',
    77: 'نصف الحزب 8',
    79: 'ثلاثة أرباع الحزب 8',
    84: 'ربع الحزب 9',
    87: 'نصف الحزب 9',
    89: 'ثلاثة أرباع الحزب 9',
    94: 'ربع الحزب 10',
    97: 'نصف الحزب 10',
    99: 'ثلاثة أرباع الحزب 10',
    104: 'ربع الحزب 11',
    107: 'نصف الحزب 11',
    109: 'ثلاثة أرباع الحزب 11',
    114: 'ربع الحزب 12',
    116: 'نصف الحزب 12',
    119: 'ثلاثة أرباع الحزب 12',
    124: 'ربع الحزب 13',
    126: 'نصف الحزب 13',
    129: 'ثلاثة أرباع الحزب 13',
    134: 'ربع الحزب 14',
    137: 'نصف الحزب 14',
    140: 'ثلاثة أرباع الحزب 14',
    144: 'ربع الحزب 15',
    146: 'نصف الحزب 15',
    148: 'ثلاثة أرباع الحزب 15',
    153: 'ربع الحزب 16',
    156: 'نصف الحزب 16',
    158: 'ثلاثة أرباع الحزب 16',
    164: 'ربع الحزب 17',
    167: 'نصف الحزب 17',
    170: 'ثلاثة أرباع الحزب 17',
    175: 'ربع الحزب 18',
    177: 'نصف الحزب 18',
    179: 'ثلاثة أرباع الحزب 18',
    184: 'ربع الحزب 19',
    187: 'نصف الحزب 19',
    189: 'ثلاثة أرباع الحزب 19',
    194: 'ربع الحزب 20',
    196: 'نصف الحزب 20',
    199: 'ثلاثة أرباع الحزب 20',
    204: 'ربع الحزب 21',
    207: 'نصف الحزب 21',
    209: 'ثلاثة أرباع الحزب 21',
    214: 'ربع الحزب 22',
    217: 'نصف الحزب 22',
    219: 'ثلاثة أرباع الحزب 22',
    224: 'ربع الحزب 23',
    226: 'نصف الحزب 23',
    228: 'ثلاثة أرباع الحزب 23',
    233: 'ربع الحزب 24',
    236: 'نصف الحزب 24',
    239: 'ثلاثة أرباع الحزب 24',
    244: 'ربع الحزب 25',
    247: 'نصف الحزب 25',
    249: 'ثلاثة أرباع الحزب 25',
    254: 'ربع الحزب 26',
    256: 'نصف الحزب 26',
    259: 'ثلاثة أرباع الحزب 26',
    264: 'ربع الحزب 27',
    267: 'نصف الحزب 27',
    270: 'ثلاثة أرباع الحزب 27',
    274: 'ربع الحزب 28',
    277: 'نصف الحزب 28',
    280: 'ثلاثة أرباع الحزب 28',
    284: 'ربع الحزب 29',
    287: 'نصف الحزب 29',
    289: 'ثلاثة أرباع الحزب 29',
    295: 'ربع الحزب 30',
    297: 'نصف الحزب 30',
    300: 'ثلاثة أرباع الحزب 30',
    304: 'ربع الحزب 31',
    306: 'نصف الحزب 31',
    309: 'ثلاثة أرباع الحزب 31',
    315: 'ربع الحزب 32',
    317: 'نصف الحزب 32',
    319: 'ثلاثة أرباع الحزب 32',
    324: 'ربع الحزب 33',
    326: 'نصف الحزب 33',
    329: 'ثلاثة أرباع الحزب 33',
    334: 'ربع الحزب 34',
    336: 'نصف الحزب 34',
    339: 'ثلاثة أرباع الحزب 34',
    344: 'ربع الحزب 35',
    347: 'نصف الحزب 35',
    349: 'ثلاثة أرباع الحزب 35',
    354: 'ربع الحزب 36',
    356: 'نصف الحزب 36',
    359: 'ثلاثة أرباع الحزب 36',
    364: 'ربع الحزب 37',
    367: 'نصف الحزب 37',
    369: 'ثلاثة أرباع الحزب 37',
    374: 'ربع الحزب 38',
    377: 'نصف الحزب 38',
    379: 'ثلاثة أرباع الحزب 38',
    384: 'ربع الحزب 39',
    386: 'نصف الحزب 39',
    389: 'ثلاثة أرباع الحزب 39',
    394: 'ربع الحزب 40',
    397: 'نصف الحزب 40',
    399: 'ثلاثة أرباع الحزب 40',
    405: 'ربع الحزب 41',
    407: 'نصف الحزب 41',
    410: 'ثلاثة أرباع الحزب 41',
    415: 'ربع الحزب 42',
    418: 'نصف الحزب 42',
    420: 'ثلاثة أرباع الحزب 42',
    425: 'ربع الحزب 43',
    426: 'نصف الحزب 43',
    428: 'ثلاثة أرباع الحزب 43',
    433: 'ربع الحزب 44',
    436: 'نصف الحزب 44',
    439: 'ثلاثة أرباع الحزب 44',
    444: 'ربع الحزب 45',
    446: 'نصف الحزب 45',
    448: 'ثلاثة أرباع الحزب 45',
    453: 'ربع الحزب 46',
    455: 'نصف الحزب 46',
    458: 'ثلاثة أرباع الحزب 46',
    463: 'ربع الحزب 47',
    466: 'نصف الحزب 47',
    468: 'ثلاثة أرباع الحزب 47',
    473: 'ربع الحزب 48',
    476: 'نصف الحزب 48',
    478: 'ثلاثة أرباع الحزب 48',
    483: 'ربع الحزب 49',
    486: 'نصف الحزب 49',
    487: 'ثلاثة أرباع الحزب 49',
    493: 'ربع الحزب 50',
    496: 'نصف الحزب 50',
    498: 'ثلاثة أرباع الحزب 50',
    503: 'ربع الحزب 51',
    506: 'نصف الحزب 51',
    508: 'ثلاثة أرباع الحزب 51',
    513: 'ربع الحزب 52',
    514: 'نصف الحزب 52',
    516: 'ثلاثة أرباع الحزب 52',
    521: 'ربع الحزب 53',
    523: 'نصف الحزب 53',
    526: 'ثلاثة أرباع الحزب 53',
    530: 'ربع الحزب 54',
    533: 'نصف الحزب 54',
    536: 'ثلاثة أرباع الحزب 54',
    541: 'ربع الحزب 55',
    544: 'نصف الحزب 55',
    547: 'ثلاثة أرباع الحزب 55',
    552: 'ربع الحزب 56',
    554: 'نصف الحزب 56',
    556: 'ثلاثة أرباع الحزب 56',
    562: 'ربع الحزب 57',
    565: 'نصف الحزب 57',
    567: 'ثلاثة أرباع الحزب 57',
    572: 'ربع الحزب 58',
    574: 'نصف الحزب 58',
    576: 'ثلاثة أرباع الحزب 58',
    581: 'ربع الحزب 59',
    583: 'نصف الحزب 59',
    587: 'ثلاثة أرباع الحزب 59',
    591: 'ربع الحزب 60',
    594: 'نصف الحزب 60',
    598: 'ثلاثة أرباع الحزب 60',
  };



  late PageController _portraitController;
  ScrollController? _portraitAutoScrollController;
  late final QuranReadingCoordinator _readingCoordinator;
  final HighQualityImagesService _highQualityImagesService =
      HighQualityImagesService.instance;
  final MarginImagesService _marginImagesService = MarginImagesService.instance;

  final GlobalKey<ContinuousQuranViewState> _continuousViewKey =
      GlobalKey<ContinuousQuranViewState>();

  bool _isSearching = false;
  bool _showIndex = false;
  bool _hideTopBarTemporarily = false;
  bool _hideBottomMenuTemporarily = false;
  bool _showSurahs = false;
  bool _showHizbPopup = false;
  bool _showSajdaPopup = false;
  bool _isAutoScrollEnabled = false;
  bool _showAutoScrollBar = false;
  bool _isAutoScrollBarCollapsed = false;
  bool _isPortraitScrollMode = false;
  bool _preferredPortraitScrollMode = false;
  bool _isTabletLayoutMode = false;
  double _autoScrollSpeedMultiplier = 1.0;

  int? _activeBookmarkSlot;
  bool _showBookmarkNotice = false;
  bool _showBookmarkGuide = false;
  bool _hideBookmarkGuideForeverChecked = false;
  String? _visibleHizbText;
  String? _visibleSajdaText;
  int _currentSurahNumber = 1;
  bool? _wasPhoneLandscape;
  bool? _wasLandscapeOrientation;
  Map<int, ReaderBookmark> _bookmarks = <int, ReaderBookmark>{};
  final Map<int, Offset> _draggingBookmarkOffsets = <int, Offset>{};
  ReaderBookmark? _previousBookmark;
  int? _previousBookmarkSlot;

  Timer? _hizbPopupTimer;
  Timer? _sajdaPopupTimer;
  Timer? _bookmarkNoticeTimer;
  late final AnimationController _bookmarkGuideAnimationController;
  Timer? _savePageTimer;
  Timer? _topBarHideTimer;
  Timer? _portraitAutoScrollTimer;
  Timer? _portraitAutoScrollResumeTimer;

  bool _showTopBarWhilePaging = false;
  double? _portraitAutoScrollViewportHeight;
  int? _portraitScrollCurrentPage;
  bool _isRecitationTopBarMinimized = false;
  DateTime? _lastAudioPageChangePromptTime;
  Offset _miniPlayerOffset = Offset.zero;
  Timer? _recitationBarHideTimer;
  bool _showMarginTopBar = false;
  List<QuranPageData>? _allQuranPages;
  Timer? _marginTopBarTimer;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  void _startTopBarHideTimer() {
    _cancelTopBarHideTimer();
    _recitationBarHideTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && AudioService.instance.isPlaying.value) {
        setState(() {
          _isRecitationTopBarMinimized = true;
        });
      }
    });
  }

  void _cancelTopBarHideTimer() {
    _recitationBarHideTimer?.cancel();
    _recitationBarHideTimer = null;
  }

  void _handleAudioPlaybackChanged() {
    if (!mounted) return;
    if (AudioService.instance.isPlaying.value) {
      if (!_isRecitationTopBarMinimized) {
        _startTopBarHideTimer();
      }
    } else {
      _cancelTopBarHideTimer();
    }
  }

  void _triggerMarginTopBar() {
    if (!_isMarginImagesEnabled) return;
    _marginTopBarTimer?.cancel();
    setState(() => _showMarginTopBar = true);
    _marginTopBarTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showMarginTopBar = false);
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      _hideTopBarTemporarily = false;
      _hideBottomMenuTemporarily = false;
    });
    if (_showControls) {
      _resetHideTimer();
    }
  }

  void _ensureControlsVisible() {
    setState(() {
      _showControls = true;
    });
    _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }



  // ط¸â€‍ط¸â€‍ط·ع¾ط·آ¬ط·آ±ط¸ظ¹ط·آ¨ ط·آ¨ط¸ظ¹ط¸â€  contain / cover / fill
  BoxFit currentFit = BoxFit.contain;

  final List<String> pages = [
    for (int i = 1; i <= 602; i++) 'assets/images/page_$i.webp',
  ];

  int get _currentPage => _readingCoordinator.currentPage;

  int get _topBarCurrentPage {
    final usePortraitScrolling =
        _supportsPortraitScrollMode(context) &&
        (_showAutoScrollBar || _isPortraitScrollMode);

    if (!(_isPhoneLandscape(context)) && usePortraitScrolling) {
      return _portraitScrollCurrentPage ?? _currentPage;
    }

    return _currentPage;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bookmarkGuideAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _bookmarkGuideAnimationController.repeat(reverse: true);
    _readingCoordinator = QuranReadingCoordinator(pageCount: pages.length);
    _readingCoordinator.addListener(_handleReadingCoordinatorChanged);
    _highQualityImagesService.state.addListener(_handleHighQualityImagesChanged);
    _marginImagesService.state.addListener(_handleMarginImagesChanged);
    _portraitController = PageController(initialPage: 0);
    _highQualityImagesService.initialize();
    _marginImagesService.initialize();

    _loadReadingPreferences();
    _loadLastPage();
    _loadBookmark();
    _loadBookmarkGuidePreference();
    _setReadingMode(true);
    _resetHideTimer();
    
    QuranJsonService.loadQuranPages().then((data) {
      if (mounted) setState(() => _allQuranPages = data);
    });
    
    AudioService.instance.init();
    AudioService.instance.onPageChangeRequired = (pageIndex) {
      if (mounted) {
        _goToPage(pageIndex + 1);
      }
    };
    AudioService.instance.isRecitationBarVisible.addListener(() async {
      if (!mounted) return;
      if (AudioService.instance.isRecitationBarVisible.value) {
        _ensureControlsVisible(); // Ensure controls are visible when bar becomes visible

        final prefs = await SharedPreferences.getInstance();
        final dismissed = prefs.getBool('recitation_guide_dismissed') ?? false;
        if (!dismissed && mounted) {
          _showRecitationBarGuide();
        }

        if (_showAutoScrollBar || _isAutoScrollEnabled) {
          _stopPortraitAutoScroll();
          setState(() {
            _isAutoScrollEnabled = false;
            _showAutoScrollBar = false;
            _isAutoScrollBarCollapsed = false;
          });
        }
      }
    });
    AudioService.instance.isPlaying.addListener(_handleAudioPlaybackChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final isPhoneLandscape = _isPhoneLandscape(context);
    final isLandscapeOrientation =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (_wasPhoneLandscape == null || _wasLandscapeOrientation == null) {
      _wasPhoneLandscape = isPhoneLandscape;
      _wasLandscapeOrientation = isLandscapeOrientation;
      return;
    }

    final useTwoPageView = _useTwoPageView(context);
    final didPhoneLandscapeChange = _wasPhoneLandscape != isPhoneLandscape;
    final didTwoPageOrientationChange =
        useTwoPageView && _wasLandscapeOrientation != isLandscapeOrientation;

    _wasPhoneLandscape = isPhoneLandscape;
    _wasLandscapeOrientation = isLandscapeOrientation;

    if (didPhoneLandscapeChange || didTwoPageOrientationChange) {
      _portraitAutoScrollResumeTimer?.cancel();
      _stopPortraitAutoScroll();
      _portraitAutoScrollController?.dispose();
      _portraitAutoScrollController = null;
      _portraitAutoScrollViewportHeight = null;
      _portraitScrollCurrentPage = null;

      if (_isPortraitScrollMode || _showAutoScrollBar || _isAutoScrollEnabled) {
        setState(() {
          _isPortraitScrollMode = _supportsPortraitScrollMode(context)
              ? _preferredPortraitScrollMode
              : false;
          _isAutoScrollEnabled = false;
          _showAutoScrollBar = false;
          _isAutoScrollBarCollapsed = false;
        });
      }

      if (!isPhoneLandscape || useTwoPageView) {
        _recreatePortraitController(initialPage: _currentPage);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _marginTopBarTimer?.cancel();
    _hizbPopupTimer?.cancel();
    _sajdaPopupTimer?.cancel();
    _savePageTimer?.cancel();
    _recitationBarHideTimer?.cancel();
    _portraitAutoScrollTimer?.cancel();
    _portraitAutoScrollResumeTimer?.cancel();
    _portraitAutoScrollController?.dispose();
    AudioService.instance.isPlaying.removeListener(_handleAudioPlaybackChanged);
    AudioService.instance.stop();
    _setReadingMode(false);
    _highQualityImagesService.state.removeListener(_handleHighQualityImagesChanged);
    _marginImagesService.state.removeListener(_handleMarginImagesChanged);
    _readingCoordinator.removeListener(_handleReadingCoordinatorChanged);
    _readingCoordinator.dispose();
    _bookmarkGuideAnimationController.dispose();
    _portraitController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      AudioService.instance.pause();
    }
  }

  Future<void> _setReadingMode(bool enabled) async {
    await WakelockPlus.toggle(enable: enabled);
  }

  bool _isPhoneLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape &&
        !_useTwoPageView(context);
  }

  bool _supportsPortraitScrollMode(BuildContext context) {
    return !_useTwoPageView(context);
  }

  bool _useTwoPageView(BuildContext context) {
    return TabletLayoutHelper.isTabletDevice(context) && _isTabletLayoutMode;
  }

  bool _shouldShowTabletLayoutSetting(BuildContext context) {
    return TabletLayoutHelper.shouldShowTabletOptions(context);
  }

  int _getViewIndexForPage(int pageIndex, BuildContext context) {
    if (!_useTwoPageView(context)) return pageIndex;
    return pageIndex ~/ 2;
  }

  int _getFirstPageIndexForView(int viewIndex, BuildContext context) {
    if (!_useTwoPageView(context)) return viewIndex;
    return viewIndex * 2;
  }

  bool _isHizbStartPage(int pageIndex) {
    final realPage = pageIndex + 1;
    return hizbStartPages.contains(realPage);
  }

  void _handleReadingCoordinatorChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleHighQualityImagesChanged() {
    if (!mounted) return;
    _downloadedPageFileCache.clear();
    setState(() {});
  }

  void _handleMarginImagesChanged() {
    if (!mounted) return;
    _downloadedPageFileCache.clear();
    final isEnabled = _marginImagesService.state.value.isEnabled;
    setState(() {
      if (isEnabled) {
        _showHizbPopup = false;
        _showSajdaPopup = false;
        _visibleHizbText = null;
        _visibleSajdaText = null;
      }
    });
  }

  bool get _isMarginImagesEnabled => _marginImagesService.state.value.isEnabled;
  double get _activePageAspectRatio =>
      _isMarginImagesEnabled ? _marginPageAspectRatio : _defaultPageAspectRatio;

  final Map<String, File?> _downloadedPageFileCache = {};

  File? _downloadedPageFileForIndex(String directoryPath, int pageNumber) {
    final key = '$directoryPath/page_$pageNumber';
    if (_downloadedPageFileCache.containsKey(key)) {
      return _downloadedPageFileCache[key];
    }
    for (final ext in const ['webp', 'jpg', 'jpeg', 'png']) {
      final file = File(
        '$directoryPath${Platform.pathSeparator}page_$pageNumber.$ext',
      );
      if (file.existsSync()) {
        _downloadedPageFileCache[key] = file;
        return file;
      }
    }
    _downloadedPageFileCache[key] = null;
    return null;
  }



  Widget _buildBookmarkBadge(int slot) {
    return Container(
      width: 26, height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF8B7355), // ذهبي بدل أحمر
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: const Icon(
        Icons.bookmark,
        color: Colors.white,
        size: 16,
      ),
    );
  }
  ImageProvider _imageProviderForPage(int pageIndex, String assetPath) {
    ImageProvider provider;
    final marginState = _marginImagesService.state.value;
    if (marginState.isEnabled && marginState.imagesDirectoryPath != null) {
      final file = _downloadedPageFileForIndex(
        marginState.imagesDirectoryPath!,
        pageIndex + 1,
      );
      if (file != null) {
        provider = FileImage(file);
        return ResizeImage(provider, width: 1080);
      }
    }

    final state = _highQualityImagesService.state.value;
    if (state.isEnabled && state.imagesDirectoryPath != null) {
      final file = _downloadedPageFileForIndex(
        state.imagesDirectoryPath!,
        pageIndex + 1,
      );
      if (file != null) {
        provider = FileImage(file);
        return ResizeImage(provider, width: 1080);
      }
    }
    provider = AssetImage(assetPath);
    return ResizeImage(provider, width: 1080);
  }

  void _recreatePortraitController({required int initialPage}) {
    final nextController = PageController(
      initialPage: _getViewIndexForPage(initialPage, context),
    );
    final oldController = _portraitController;
    _portraitController = nextController;
    oldController.dispose();
  }



  void _setCurrentPage(
    int page, {
    bool persist = true,
    bool showHizbPopup = false,
  }) {
    final safePage = page.clamp(0, pages.length - 1);
    _readingCoordinator.setCurrentPage(safePage);
    _syncCurrentSurahForPage(safePage);

    if (persist) {
      _savePageDebounced(safePage);
    }

    if (showHizbPopup) {
      _showHizbPopupIfNeeded(safePage);
      _showSajdaPopupIfNeeded(safePage);
    }


  }

  void _openQuranIndexPage({QuranIndexTab initialTab = QuranIndexTab.surahs}) {
    if (_showAutoScrollBar || _isAutoScrollEnabled) {
      _stopPortraitAutoScroll();
      setState(() {
        _isAutoScrollEnabled = false;
        _showAutoScrollBar = false;
        _isAutoScrollBarCollapsed = false;
      });
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuranIndexPage(
          surahs: surahList,
          currentSurahNumber: _currentSurahNumber,
          currentPage: _currentPage,
          initialTab: initialTab,
          onSelectSurah: _setCurrentSurahNumber,
          onGoToPage: _goToPage,
        ),
      ),
    );
  }

  void _showTopBarOnNavigation() {
    _topBarHideTimer?.cancel();

    if (!mounted) return;

    if (!_showTopBarWhilePaging || _hideTopBarTemporarily || _hideBottomMenuTemporarily) {
      setState(() {
        _showTopBarWhilePaging = true;
        _hideTopBarTemporarily = false;
        _hideBottomMenuTemporarily = false;
      });
    }
  }

  void _hideTopBarAfterNavigation() {
    _topBarHideTimer?.cancel();

    _topBarHideTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _showTopBarWhilePaging = false;
      });
    });
  }

  void _hideHizbPopup() {
    _hizbPopupTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _showHizbPopup = false;
      _visibleHizbText = null;
    });
  }

  void _hideSajdaPopup() {
    _sajdaPopupTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _showSajdaPopup = false;
      _visibleSajdaText = null;
    });
  }

  void _showHizbPopupIfNeeded(int pageIndex) {
    if (_isMarginImagesEnabled) return;
    _hideHizbPopup();

    final progressText = _hizbProgressNotices[pageIndex + 1];
    final isHizbStart = _isHizbStartPage(pageIndex);
    if (!isHizbStart && progressText == null) return;

    final List<String> lines = <String>[];

    if (isHizbStart) {
      final hizbNumber = _getHizbNumber(pageIndex);
      lines.add('الحزب $hizbNumber');

      if (hizbNumber.isEven) {
        lines.add('الجزء ${(hizbNumber ~/ 2)}');
      }
    }

    if (progressText != null) {
      lines.add(progressText);
    }

    setState(() {
      _showHizbPopup = true;
      _visibleHizbText = lines.join('\n');
    });

    _hizbPopupTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _showHizbPopup = false;
        _visibleHizbText = null;
      });
    });
  }

  void _showSajdaPopupIfNeeded(int pageIndex) {
    if (_isMarginImagesEnabled) return;
    _hideSajdaPopup();

    final sajdaText = _sajdaNotices[pageIndex];
    if (sajdaText == null) return;

    setState(() {
      _showSajdaPopup = true;
      _visibleSajdaText = sajdaText;
    });

    _sajdaPopupTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _showSajdaPopup = false;
        _visibleSajdaText = null;
      });
    });
  }

  Future<void> _showSajdaDuaDialog() async {
    _hideSajdaPopup();
    if (!mounted) return;

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkMode
              ? const Color(0xFF19130A)
              : const Color(0xFFF8F1DE),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: isDarkMode
                  ? const Color(0xFFD6B35D).withValues(alpha: 0.55)
                  : const Color(0xFFE2D2A5),
            ),
          ),
          title: Text(
            'دعاء السجود',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: isDarkMode ? const Color(0xFFFFF4D6) : const Color(0xFF35250E),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            '$_sajdaDua\n\n$_dawudSajdaDua',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              height: 1.9,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDarkMode ? Colors.white : const Color(0xFF35250E),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'إغلاق',
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showTafsirDialog(int pageIndex) async {
    if (!mounted) return;
    
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF19130A) : const Color(0xFFF8F1DE);
    final borderColor = isDarkMode ? const Color(0xFFD6B35D).withValues(alpha: 0.55) : const Color(0xFFE2D2A5);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
    final titleColor = isDarkMode ? const Color(0xFFFFF4D6) : const Color(0xFF35250E);
    final accentColor = isDarkMode ? const Color(0xFFD6B35D) : const Color(0xFF8D6E3F);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Center(
          child: CircularProgressIndicator(color: borderColor),
        );
      },
    );

    // Pre-warm the data cache
    await TafsirService.getTafsirForPage(pageIndex);
    
    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss loading

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _TafsirSheetContent(
          initialPageIndex: pageIndex,
          backgroundColor: backgroundColor,
          borderColor: borderColor,
          textColor: textColor,
          titleColor: titleColor,
          accentColor: accentColor,
          onPageChanged: (newPage) {
            _goToPage(newPage + 1);
          },
        );
      },
    );
  }

  Future<void> _loadLastPage() async {
    final prefs = await SharedPreferences.getInstance();
    final page = prefs.getInt('lastPage') ?? 0;
    _readingCoordinator.setCurrentPage(page);
    _syncCurrentSurahForPage(page);
    _recreatePortraitController(initialPage: page);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (!_isPhoneLandscape(context) && _portraitController.hasClients) {
        final targetViewIndex = _getViewIndexForPage(page, context);
        _portraitController.jumpToPage(targetViewIndex);
      }

      _showHizbPopupIfNeeded(page);
      _showSajdaPopupIfNeeded(page);
    });
  }

  Future<void> _savePage(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastPage', page);
  }

  void _savePageDebounced(int page) {
    _savePageTimer?.cancel();

    _savePageTimer = Timer(const Duration(milliseconds: 300), () {
      _savePage(page);
    });
  }

  void _showBookmarkNoticeOverlay() {
    _bookmarkNoticeTimer?.cancel();
    setState(() {
      _showBookmarkNotice = true;
    });
    _bookmarkNoticeTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _showBookmarkNotice = false;
      });
    });
  }

  void _handleReaderTap() {
    if (_isMarginImagesEnabled) {
      _triggerMarginTopBar();
    }
    _toggleControls();
    if (!_showControls) return;
    if (_showIndex) return;
    setState(() => _showIndex = true);
    _updateSystemUI();
  }

  String _bookmarkDisplayName(int slot, [ReaderBookmark? bookmark]) {
    final resolvedBookmark = bookmark ?? _bookmarks[slot];
    final label = resolvedBookmark?.label?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return 'العلامة $slot';
  }

  String get _bookmarkNoticeTitle {
    final slot = _activeBookmarkSlot;
    if (slot == null) return 'تم حفظ العلامة';
    return 'تم حفظ ${_bookmarkDisplayName(slot)}';
  }

  Future<void> _persistBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final items = _bookmarks.values.toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
    await prefs.setString(
      _bookmarksPrefKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _deleteBookmarkSlot(int slot) async {
    setState(() {
      _bookmarks.remove(slot);
      if (_activeBookmarkSlot == slot) {
        final remaining = _bookmarks.keys.toList()..sort();
        _activeBookmarkSlot = remaining.isEmpty ? null : remaining.first;
      }
    });
    await _persistBookmarks();
  }

  Future<void> _renameBookmarkSlot(int slot, String? newLabel) async {
    final bookmark = _bookmarks[slot];
    if (bookmark == null) return;
    if (newLabel == null) return;

    final normalized = newLabel.trim();
    setState(() {
      _bookmarks[slot] = bookmark.copyWith(
        label: normalized.isEmpty ? null : normalized,
        clearLabel: normalized.isEmpty,
      );
    });
    await _persistBookmarks();
  }

  Future<BookmarkPickerResult?> _pickBookmarkSlot({
    required String title,
    required bool onlySaved,
  }) async {
    return showDialog<BookmarkPickerResult>(
      context: context,
      builder: (_) => BookmarkPickerDialog(
        title: title,
        onlySaved: onlySaved,
        bookmarks: _bookmarks,
        displayNameBuilder: _bookmarkDisplayName,
        surahNameForBookmark: _getSurahNameForBookmark,
        onRename: _renameBookmarkSlot,
        onDelete: _deleteBookmarkSlot,
      ),
    );
  }

  Future<void> _undoBookmarkSave() async {
    final slot = _previousBookmarkSlot;
    if (slot == null) return;
    _bookmarkNoticeTimer?.cancel();
    setState(() {
      if (_previousBookmark == null) {
        _bookmarks.remove(slot);
        if (_activeBookmarkSlot == slot) {
          _activeBookmarkSlot = null;
        }
      } else {
        _bookmarks[slot] = _previousBookmark!;
        _activeBookmarkSlot = slot;
      }
      _showBookmarkNotice = false;
    });
    await _persistBookmarks();
  }

  Future<void> _promptSaveBookmark(
    int page,
    double x,
    double y, {
    double? sourceWidth,
    double? sourceHeight,
  }) async {
    final slotResult = await _pickBookmarkSlot(
      title: 'اختر رقم العلامة للحفظ',
      onlySaved: false,
    );
    final slot = slotResult?.selectedSlot;
    if (slot == null || !mounted) return;
    await _saveBookmark(
      slot,
      page,
      x,
      y,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  Future<void> _saveBookmark(
    int slot,
    int page,
    double x,
    double y, {
    double? sourceWidth,
    double? sourceHeight,
  }) async {
    final previousBookmark = _bookmarks[slot];
    final bookmark = ReaderBookmark(
      slot: slot,
      page: page,
      x: x,
      y: y,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );

    setState(() {
      _bookmarks[slot] = bookmark;
      _activeBookmarkSlot = slot;
    });
    await _persistBookmarks();

    if (!mounted) return;
    _previousBookmarkSlot = slot;
    _previousBookmark = previousBookmark;
    // _showBookmarkNoticeOverlay();
  }

  Size _bookmarkBadgeSize(BuildContext context) {
    final base = ResponsiveHelper.overlayIconSize(context);
    return Size(base + 24, base + 8);
  }

  void _startBookmarkDrag(
    ReaderBookmark bookmark, {
    required double displayWidth,
    required double displayHeight,
  }) {
    _draggingBookmarkOffsets[bookmark.slot] = Offset(
      bookmark.leftFor(displayWidth),
      bookmark.topFor(displayHeight),
    );
  }

  void _updateBookmarkDrag(
    BuildContext context,
    ReaderBookmark bookmark,
    DragUpdateDetails details, {
    required double displayWidth,
    required double displayHeight,
  }) {
    final currentBookmark = _bookmarks[bookmark.slot] ?? bookmark;
    final currentOffset =
        _draggingBookmarkOffsets[bookmark.slot] ??
        Offset(
          currentBookmark.leftFor(displayWidth),
          currentBookmark.topFor(displayHeight),
        );
    final badgeSize = _bookmarkBadgeSize(context);
    final maxLeft = (displayWidth - badgeSize.width).clamp(0.0, displayWidth);
    final maxTop = (displayHeight - badgeSize.height).clamp(0.0, displayHeight);
    final nextOffset = Offset(
      (currentOffset.dx + details.delta.dx).clamp(0.0, maxLeft),
      (currentOffset.dy + details.delta.dy).clamp(0.0, maxTop),
    );

    setState(() {
      _draggingBookmarkOffsets[bookmark.slot] = nextOffset;
      _bookmarks[bookmark.slot] = currentBookmark.copyWith(
        x: nextOffset.dx,
        y: nextOffset.dy,
        sourceWidth: displayWidth,
        sourceHeight: displayHeight,
      );
      _activeBookmarkSlot = bookmark.slot;
    });
  }

  void _endBookmarkDrag(int slot) {
    _draggingBookmarkOffsets.remove(slot);
    unawaited(_persistBookmarks());
  }

  Future<void> _loadBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bookmarksPrefKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final bookmarks = <int, ReaderBookmark>{};
      for (final item in decoded) {
        final bookmark = ReaderBookmark.fromJson(Map<String, dynamic>.from(item));
        bookmarks[bookmark.slot] = bookmark;
      }
      if (!mounted) return;
      final firstSlot = bookmarks.keys.isEmpty
          ? null
          : (bookmarks.keys.toList()..sort()).first;
      setState(() {
        _bookmarks = bookmarks;
        _activeBookmarkSlot = firstSlot;
      });
    } catch (_) {
      // Ignore malformed bookmark data.
    }
  }

  Future<void> _loadBookmarkGuidePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_bookmarkGuideDismissedPrefKey) ?? false;
    if (!mounted || dismissed) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showBookmarkGuide = true;
      });
    });
  }

  Future<void> _dismissBookmarkGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bookmarkGuideDismissedPrefKey, true);
    if (!mounted) return;
    setState(() {
      _showBookmarkGuide = false;
      _hideBookmarkGuideForeverChecked = false;
    });
  }

  void _closeBookmarkGuideForNow() {
    if (!mounted) return;
    setState(() {
      _showBookmarkGuide = false;
      _hideBookmarkGuideForeverChecked = false;
    });
  }

  Future<void> _handleBookmarkGuideDone() async {
    if (_hideBookmarkGuideForeverChecked) {
      await _dismissBookmarkGuide();
      return;
    }
    _closeBookmarkGuideForNow();
  }

  void _goToPage(int page, {double yOffsetRatio = 0.0}) {
    final targetIndex = page - 1;
    final usePortraitScrolling =
        (_supportsPortraitScrollMode(context) &&
            (_showAutoScrollBar || _isPortraitScrollMode)) ||
        !_portraitController.hasClients;

    if (_isPhoneLandscape(context)) {
      setState(() {
        _showIndex = false;
        _showSurahs = false;
        _isSearching = false;
      });

      _setCurrentPage(targetIndex, showHizbPopup: true);
      _updateSystemUI();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _continuousViewKey.currentState?.scrollToPage(targetIndex, yOffsetRatio: yOffsetRatio);
      });
      return;
    }

    if (usePortraitScrolling) {
      final controller = _portraitAutoScrollController;
      final pageExtent = _portraitAutoScrollViewportHeight;
      final targetViewIndex = _getViewIndexForPage(targetIndex, context);

      setState(() {
        _showIndex = false;
        _showSurahs = false;
        _isSearching = false;
      });

      _setCurrentPage(targetIndex, showHizbPopup: true);
      _portraitScrollCurrentPage = targetIndex;
      _updateSystemUI();

      if (controller != null && controller.hasClients && pageExtent != null) {
        controller.jumpTo(targetViewIndex * pageExtent);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final readyController = _portraitAutoScrollController;
          final readyExtent = _portraitAutoScrollViewportHeight;
          if (!mounted ||
              readyController == null ||
              !readyController.hasClients ||
              readyExtent == null) {
            return;
          }
          readyController.jumpTo(targetViewIndex * readyExtent);
        });
      }
      return;
    }

    final targetViewIndex = _getViewIndexForPage(targetIndex, context);
    _portraitController.jumpToPage(targetViewIndex);

    setState(() {
      _showIndex = false;
      _showSurahs = false;
      _isSearching = false;
    });

    _setCurrentPage(targetIndex, showHizbPopup: true);
    _updateSystemUI();
  }

  void _goToBookmark() {
    _goToBookmarkWithPicker();
  }

  Future<void> _goToBookmarkWithPicker() async {
    final slotResult = await _pickBookmarkSlot(
      title: 'اختر رقم العلامة للانتقال',
      onlySaved: true,
    );
    if (slotResult?.deletedSlot != null || !mounted) return;
    final slot = slotResult?.selectedSlot;
    if (slot == null || !mounted) return;
    final bookmark = _bookmarks[slot];
    if (bookmark == null) return;
    setState(() {
      _activeBookmarkSlot = slot;
    });
    final usePortraitScrolling =
        (_supportsPortraitScrollMode(context) &&
            (_showAutoScrollBar || _isPortraitScrollMode)) ||
        !_portraitController.hasClients;

    if (_isPhoneLandscape(context)) {
      setState(() {
        _showIndex = false;
        _showSurahs = false;
        _isSearching = false;
      });

      _setCurrentPage(bookmark.page, showHizbPopup: true);
      _updateSystemUI();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _continuousViewKey.currentState?.scrollToBookmark(bookmark);
      });

      return;
    }

    if (usePortraitScrolling) {
      final controller = _portraitAutoScrollController;
      final pageExtent = _portraitAutoScrollViewportHeight;
      final targetViewIndex = _getViewIndexForPage(bookmark.page, context);

      setState(() {
        _showIndex = false;
        _showSurahs = false;
        _isSearching = false;
      });

      _setCurrentPage(bookmark.page, showHizbPopup: true);
      _portraitScrollCurrentPage = bookmark.page;
      _updateSystemUI();

      if (controller != null && controller.hasClients && pageExtent != null) {
        controller.jumpTo(targetViewIndex * pageExtent);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final readyController = _portraitAutoScrollController;
          final readyExtent = _portraitAutoScrollViewportHeight;
          if (!mounted ||
              readyController == null ||
              !readyController.hasClients ||
              readyExtent == null) {
            return;
          }
          readyController.jumpTo(targetViewIndex * readyExtent);
        });
      }
      return;
    }

    final targetViewIndex = _getViewIndexForPage(bookmark.page, context);
    _portraitController.jumpToPage(targetViewIndex);

    setState(() {
      _showIndex = false;
      _showSurahs = false;
      _isSearching = false;
    });

    _setCurrentPage(bookmark.page, showHizbPopup: true);
    _updateSystemUI();
  }

  void _updateSystemUI() {
    final isTablet = TabletLayoutHelper.isTabletDevice(context);
    if (_isPhoneLandscape(context)) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return;
    }

    final bool keepStablePortraitInsets =
        _supportsPortraitScrollMode(context) &&
        (_isPortraitScrollMode || _showAutoScrollBar || _isAutoScrollEnabled);

    if (keepStablePortraitInsets) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      return;
    }

    if (_showIndex) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(
        isTablet ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
      );
    }
  }

  double _currentAutoScrollPixelsPerSecond() {
    if (AudioService.instance.isPlaying.value) return 0.0;
    
    switch (_autoScrollSpeedMultiplier) {
      case 0.5:
        return 9;
      case 0.75:
        return 11;
      case 1.0:
        return 14;
      case 1.5:
        return 20;
      case 2.0:
        return 28;
      case 2.5:
        return 36;
      case 3.0:
        return 44;
      default:
        return 14;
    }
  }

  void _setAutoScrollEnabled(bool value) {
    if (_isAutoScrollEnabled == value) return;
    setState(() {
      _isAutoScrollEnabled = value;
    });
    if (!value && !_isPhoneLandscape(context)) {
      _stopPortraitAutoScroll();
    }
  }

  void _setAutoScrollSpeedMultiplier(double value) {
    if (_autoScrollSpeedMultiplier == value) return;
    setState(() {
      _autoScrollSpeedMultiplier = value;
    });
  }

  static const List<double> _allowedSpeeds = [0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0];

  void _increaseAutoScrollSpeed() {
    int currentIndex = _allowedSpeeds.indexOf(_autoScrollSpeedMultiplier);
    if (currentIndex == -1) {
      currentIndex = _allowedSpeeds.indexWhere((s) => s >= _autoScrollSpeedMultiplier);
      if (currentIndex == -1) currentIndex = _allowedSpeeds.length - 1;
    }
    if (currentIndex < _allowedSpeeds.length - 1) {
      _setAutoScrollSpeedMultiplier(_allowedSpeeds[currentIndex + 1]);
    }
  }

  void _decreaseAutoScrollSpeed() {
    int currentIndex = _allowedSpeeds.indexOf(_autoScrollSpeedMultiplier);
    if (currentIndex == -1) {
      currentIndex = _allowedSpeeds.lastIndexWhere((s) => s <= _autoScrollSpeedMultiplier);
      if (currentIndex == -1) currentIndex = 0;
    }
    if (currentIndex > 0) {
      _setAutoScrollSpeedMultiplier(_allowedSpeeds[currentIndex - 1]);
    }
  }

  String _formatAutoScrollSpeed(double speed) {
    if (speed == 0.75) return "0.75";
    if (speed % 1 == 0) {
      return speed.toStringAsFixed(0);
    }
    return speed.toStringAsFixed(1);
  }

  void _toggleAutoScrollBarCollapsed() {
    setState(() {
      _isAutoScrollBarCollapsed = !_isAutoScrollBarCollapsed;
    });
  }

  void _setPortraitScrollMode(bool value) {
    if (value && !_supportsPortraitScrollMode(context)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('وضع التمرير غير متاح في وضع الصفحتين على الشاشات العريضة'),
        ),
      );
      return;
    }
    if (!value && _showAutoScrollBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('التمرير التلقائي لا يعمل إلا في وضع التمرير'),
        ),
      );
      return;
    }
    if (_isPortraitScrollMode == value) return;

    _preferredPortraitScrollMode = value;
    _saveReadingPreferences();

    setState(() {
      _isPortraitScrollMode = value;
    });
    if (!value && !_showAutoScrollBar) {
      _recreatePortraitController(initialPage: _currentPage);
      _stopPortraitAutoScroll();
      _portraitScrollCurrentPage = null;
    }
  }

  void _closeAutoScrollBar() {
    _portraitAutoScrollResumeTimer?.cancel();
    _stopPortraitAutoScroll();

    setState(() {
      _isAutoScrollEnabled = false;
      _showAutoScrollBar = false;
      _isAutoScrollBarCollapsed = false;
    });
  }

  Future<void> _loadReadingPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedPortraitScrollMode =
        prefs.getBool(_portraitScrollModePrefKey) ?? false;
    final bool isTablet = TabletLayoutHelper.isTabletDevice(context);
    final savedTabletLayoutMode =
        prefs.getBool(_tabletLayoutModePrefKey) ?? isTablet;

    _preferredPortraitScrollMode = savedPortraitScrollMode;
    _isTabletLayoutMode = savedTabletLayoutMode;

    if (_supportsPortraitScrollMode(context)) {
      setState(() {
        _isPortraitScrollMode = savedPortraitScrollMode;
      });
    } else {
      _isPortraitScrollMode = false;
    }
  }

  Future<void> _saveReadingPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _portraitScrollModePrefKey,
      _preferredPortraitScrollMode,
    );
    await prefs.setBool(
      _tabletLayoutModePrefKey,
      _isTabletLayoutMode,
    );
  }

  void _setTabletLayoutMode(bool value) {
    if (!_shouldShowTabletLayoutSetting(context)) return;
    if (_isTabletLayoutMode == value) return;

    final targetPage = value ? (_currentPage ~/ 2) * 2 : _currentPage;

    _portraitAutoScrollResumeTimer?.cancel();
    _stopPortraitAutoScroll();
    _portraitAutoScrollController?.dispose();
    _portraitAutoScrollController = null;
    _portraitAutoScrollViewportHeight = null;
    _portraitScrollCurrentPage = null;

    setState(() {
      _isTabletLayoutMode = value;
      _isAutoScrollEnabled = false;
      _showAutoScrollBar = false;
      _isAutoScrollBarCollapsed = false;
      _isPortraitScrollMode = value ? false : _preferredPortraitScrollMode;
    });

    _readingCoordinator.setCurrentPage(targetPage);
    _syncCurrentSurahForPage(targetPage);
    _recreatePortraitController(initialPage: targetPage);
    _saveReadingPreferences();
    _updateSystemUI();
  }

  void _stopPortraitAutoScroll() {
    _portraitAutoScrollTimer?.cancel();
    _portraitAutoScrollTimer = null;
  }

  void _schedulePortraitAutoScrollResume(double viewportHeight) {
    _portraitAutoScrollResumeTimer?.cancel();
    if (!_isAutoScrollEnabled) return;
    _portraitAutoScrollResumeTimer = Timer(
      const Duration(milliseconds: 80),
      () {
        if (!mounted || !_isAutoScrollEnabled) return;
        _syncPortraitAutoScroll(viewportHeight);
      },
    );
  }

  void _syncPortraitAutoScroll(double viewportHeight) {
    _portraitAutoScrollViewportHeight = viewportHeight;
    final controller = _portraitAutoScrollController;
    if (controller == null) return;

    _stopPortraitAutoScroll();
    if (!_isAutoScrollEnabled) return;

    const frameInterval = Duration(milliseconds: 16);
    final deltaPerTick =
        _currentAutoScrollPixelsPerSecond() *
        (frameInterval.inMilliseconds / 1000);

    _portraitAutoScrollTimer = Timer.periodic(frameInterval, (_) {
      final controller = _portraitAutoScrollController;
      if (!mounted ||
          controller == null ||
          !_isAutoScrollEnabled ||
          !controller.hasClients) {
        _stopPortraitAutoScroll();
        return;
      }

      final maxScroll = controller.position.maxScrollExtent;
      final nextOffset = (controller.offset + deltaPerTick).clamp(0.0, maxScroll);

      if ((nextOffset - controller.offset).abs() < 0.1 || nextOffset >= maxScroll) {
        _setAutoScrollEnabled(false);
        return;
      }

      controller.jumpTo(nextOffset);
    });
  }

  void _handlePortraitAutoScrollOffset(double viewportHeight) {
    if (viewportHeight <= 0) {
      return;
    }

    final page = _getPortraitScrollPageFromOffset(
      _portraitAutoScrollViewportHeight ?? viewportHeight,
    );
    _portraitScrollCurrentPage = page;
    if (page != _currentPage) {
      _setCurrentPage(page, showHizbPopup: true);
    }
  }

  int _getPortraitScrollPageFromOffset(double pageExtent) {
    final controller = _portraitAutoScrollController;
    if (controller == null || !controller.hasClients || pageExtent <= 0) {
      return _currentPage;
    }

    final maxViewIndex = _useTwoPageView(context)
        ? (pages.length / 2).ceil() - 1
        : pages.length - 1;
    final viewIndex = (controller.offset / pageExtent)
        .floor()
        .clamp(0, maxViewIndex);

    return _getFirstPageIndexForView(viewIndex, context).clamp(0, pages.length - 1);
  }

  int _getHizbNumber(int pageIndex) {
    final realPage = pageIndex + 1;

    for (int i = 0; i < hizbStartPages.length; i++) {
      final start = hizbStartPages[i];
      final end = (i < hizbStartPages.length - 1)
          ? hizbStartPages[i + 1] - 1
          : 602;

      if (realPage >= start && realPage <= end) {
        return i + 1;
      }
    }

    return 1;
  }

  String _getSurahName(int pageIndex) {
    final realPage = pageIndex + 1;

    // Collect all surahs that start on this page
    final List<String> surahsOnPage = [];

    for (int i = 0; i < surahList.length; i++) {
      final surahPage = surahList[i]['page'] as int;

      // Surah starts on this page
      if (surahPage == realPage) {
        surahsOnPage.add(surahList[i]['name'] as String);
      }
    }

    // If multiple surahs start on this page, show first and last
    if (surahsOnPage.length >= 2) {
      return '${surahsOnPage.first} - ${surahsOnPage.last}';
    }

    // Otherwise, find which surah this page belongs to
    if (surahsOnPage.length == 1) {
      return surahsOnPage.first;
    }

    // Page doesn't start a new surah — find the surah it belongs to
    for (int i = surahList.length - 1; i >= 0; i--) {
      final surahPage = surahList[i]['page'] as int;
      if (surahPage <= realPage) {
        return surahList[i]['name'] as String;
      }
    }

    return '';
  }


  void _openSearchPage() {
    setState(() {
      _showIndex = false;
      _showSurahs = false;
      _isSearching = false;
    });
    _updateSystemUI();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchPage(
          onGoToPage: (page) {
            _goToPage(page);
          },
        ),
      ),
    );
  }

  void _openSettings() {
    setState(() {
      _showIndex = false;
      _showSurahs = false;
      _isSearching = false;
    });
    _updateSystemUI();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          isDarkMode: ThemeService.themeMode.value == ThemeMode.dark,
          onToggleDarkMode: (value) {
            ThemeService.setDarkMode(value);
          },
          isAutoScrollEnabled: _showAutoScrollBar,
          onToggleAutoScroll: (value) {
            setState(() {
              if (value) {
                if (AudioService.instance.isRecitationBarVisible.value) {
                  AudioService.instance.isRecitationBarVisible.value = false;
                }
                _isAutoScrollEnabled = true;
                _showAutoScrollBar = true;
                _isAutoScrollBarCollapsed = false;
              } else {
                _isAutoScrollEnabled = false;
                _showAutoScrollBar = false;
                _isAutoScrollBarCollapsed = false;
              }
            });
          },
          isPortraitScrollMode: _isPortraitScrollMode,
          allowPortraitScrollMode: _supportsPortraitScrollMode(context),
          showTabletLayoutSetting: _shouldShowTabletLayoutSetting(context),
          isTabletLayoutMode: _isTabletLayoutMode,
          onToggleTabletLayoutMode: _setTabletLayoutMode,
          onTogglePortraitScrollMode: _setPortraitScrollMode,
        ),
      ),
    );
  }

  String _getSurahNameForBookmark(ReaderBookmark bookmark) {
    final realPage = bookmark.page + 1;
    final ratio = (bookmark.sourceHeight != null && bookmark.sourceHeight! > 0)
        ? bookmark.y / bookmark.sourceHeight!
        : 0.0;

    String currentSurah = '';

    for (int i = 0; i < surahList.length; i++) {
      final surahPage = surahList[i]['page'] as int;
      final surahRatio = (surahList[i]['yOffsetRatio'] as num?)?.toDouble() ?? 0.0;

      if (surahPage < realPage) {
        currentSurah = surahList[i]['name'] as String;
      } else if (surahPage == realPage) {
        if (ratio >= surahRatio) {
          currentSurah = surahList[i]['name'] as String;
        } else {
          break;
        }
      } else {
        break;
      }
    }

    return currentSurah.isNotEmpty
        ? currentSurah
        : (surahList.isNotEmpty ? surahList[0]['name'] as String : '');
  }

  void _setCurrentSurahNumber(int surahNumber) {
    if (_currentSurahNumber == surahNumber) return;
    setState(() {
      _currentSurahNumber = surahNumber;
    });
  }

  void _syncCurrentSurahForPage(int pageIndex) {
    final realPage = pageIndex + 1;
    final surahsOnPage = surahList
        .where((surah) => surah['page'] == realPage)
        .toList();

    if (surahsOnPage.isEmpty) {
      final derivedIndex = _getCurrentSurahIndexFromPage(pageIndex);
      _currentSurahNumber = surahList[derivedIndex]['number'] as int;
      return;
    }

    final currentStillOnPage = surahsOnPage.any(
      (surah) => surah['number'] == _currentSurahNumber,
    );
    if (currentStillOnPage) return;

    _currentSurahNumber = surahsOnPage.first['number'] as int;
  }

  int _getCurrentSurahIndexFromPage(int pageIndex) {
    final realPage = pageIndex + 1;

    for (int i = 0; i < surahList.length; i++) {
      final start = surahList[i]['page'] as int;
      final end = (i < surahList.length - 1)
          ? (surahList[i + 1]['page'] as int) - 1
          : 602;

      if (realPage >= start && realPage <= end) {
        return i;
      }
    }

    return 0;
  }

  Widget _buildSinglePage(
    String imagePath,
    int pageIndex, {
    double? customHorizontalPadding,
    Alignment alignment = Alignment.center,
    bool enableZoom = true,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTwoPagesTablet = _useTwoPageView(context);
        final isTabletPortrait =
            TabletLayoutHelper.isTabletDevice(context) &&
            !TabletLayoutHelper.isTabletLandscape(context);
        final isPhonePortrait =
            !TabletLayoutHelper.isTabletDevice(context) &&
            MediaQuery.of(context).orientation == Orientation.portrait;
        final useMarginSafeInset = isPhonePortrait && _isMarginImagesEnabled;

        return Align(
          alignment: alignment,
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box != null) {
                    final local = box.globalToLocal(details.globalPosition);
                    _promptSaveBookmark(
                      pageIndex,
                      local.dx,
                      local.dy,
                      sourceWidth: box.size.width,
                      sourceHeight: box.size.height,
                    );
                  }
                },
                child: Padding(
                  padding: useMarginSafeInset
                      ? const EdgeInsets.fromLTRB(4, 2, 4, 4)
                      : EdgeInsets.zero,
                  child: SizedBox.expand(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF6EE),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image(
                        image: _imageProviderForPage(pageIndex, imagePath),
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.fill, // مهم جداً — fill بدل fitWidth
                        filterQuality: FilterQuality.low,
                      ),
                    ),
                  ),
                ),
              ),
              for (final bookmark in _bookmarks.values
                  .where((bookmark) => bookmark.page == pageIndex))
                Positioned(
                  left: _draggingBookmarkOffsets[bookmark.slot]?.dx ??
                      bookmark.leftFor(constraints.maxWidth),
                  top: _draggingBookmarkOffsets[bookmark.slot]?.dy ??
                      bookmark.topFor(constraints.maxHeight),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) => _startBookmarkDrag(
                      bookmark,
                      displayWidth: constraints.maxWidth,
                      displayHeight: constraints.maxHeight,
                    ),
                    onPanUpdate: (details) => _updateBookmarkDrag(
                      context,
                      bookmark,
                      details,
                      displayWidth: constraints.maxWidth,
                      displayHeight: constraints.maxHeight,
                    ),
                    onPanEnd: (_) => _endBookmarkDrag(bookmark.slot),
                    onPanCancel: () => _endBookmarkDrag(bookmark.slot),
                    child: _buildBookmarkBadge(bookmark.slot),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTwoPageSpread(int viewIndex, {bool topAlign = false}) {
    final bool isTabletPortrait =
        TabletLayoutHelper.isTabletDevice(context) &&
        !TabletLayoutHelper.isTabletLandscape(context);
    return _buildTwoPageSpreadContent(
      viewIndex,
      enableZoom: true,
      topAlign: topAlign || isTabletPortrait,
    );
  }

  Widget _buildScrollingSinglePage(String imagePath, int pageIndex) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (details) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final local = box.globalToLocal(details.globalPosition);
                  _promptSaveBookmark(
                    pageIndex,
                    local.dx,
                    local.dy,
                    sourceWidth: box.size.width,
                    sourceHeight: box.size.height,
                  );
                }
              },
              child: SizedBox.expand(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF6EE),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image(
                    image: _imageProviderForPage(pageIndex, imagePath),
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
            ),
            for (final bookmark in _bookmarks.values
                .where((bookmark) => bookmark.page == pageIndex))
              Positioned(
                left: _draggingBookmarkOffsets[bookmark.slot]?.dx ??
                    bookmark.leftFor(constraints.maxWidth),
                top: _draggingBookmarkOffsets[bookmark.slot]?.dy ??
                    bookmark.topFor(constraints.maxHeight),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (_) => _startBookmarkDrag(
                    bookmark,
                    displayWidth: constraints.maxWidth,
                    displayHeight: constraints.maxHeight,
                  ),
                  onPanUpdate: (details) => _updateBookmarkDrag(
                    context,
                    bookmark,
                    details,
                    displayWidth: constraints.maxWidth,
                    displayHeight: constraints.maxHeight,
                  ),
                  onPanEnd: (_) => _endBookmarkDrag(bookmark.slot),
                  onPanCancel: () => _endBookmarkDrag(bookmark.slot),
                  child: _buildBookmarkBadge(bookmark.slot),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildScrollingTwoPageSpread(int viewIndex) {
    final firstPageIndex = viewIndex * 2;
    final secondPageIndex = firstPageIndex + 1;
    final hasSecondPage = secondPageIndex < pages.length;
    final horizontalPadding = _isMarginImagesEnabled ? 2.0 : 8.0;
    final pageGap = _isMarginImagesEnabled ? 0.0 : 2.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          Expanded(
            child: hasSecondPage
                ? _buildScrollingSinglePage(
                    pages[secondPageIndex],
                    secondPageIndex,
                  )
                : const SizedBox(),
          ),
          SizedBox(width: pageGap),
          Expanded(
            child: _buildScrollingSinglePage(
              pages[firstPageIndex],
              firstPageIndex,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTwoPageSpreadContent(
    int viewIndex, {
    required bool enableZoom,
    bool topAlign = false,
  }) {
    final firstPageIndex = viewIndex * 2;
    final secondPageIndex = firstPageIndex + 1;
    final hasSecondPage = secondPageIndex < pages.length;
    final horizontalPadding = _isMarginImagesEnabled ? 2.0 : 8.0;
    final pageGap = _isMarginImagesEnabled ? 0.0 : 2.0;

    final spread = Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        crossAxisAlignment: topAlign
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: hasSecondPage
                ? _buildSinglePage(
                    pages[secondPageIndex],
                    secondPageIndex,
                    customHorizontalPadding: 0,
                    alignment: topAlign
                        ? Alignment.topRight
                        : Alignment.centerRight,
                    enableZoom: enableZoom,
                  )
                : const SizedBox(),
          ),
          SizedBox(width: pageGap),
          Expanded(
            child: _buildSinglePage(
              pages[firstPageIndex],
              firstPageIndex,
              customHorizontalPadding: 0,
              alignment: topAlign ? Alignment.topLeft : Alignment.centerLeft,
              enableZoom: enableZoom,
            ),
          ),
        ],
      ),
    );

    if (topAlign) {
      return SizedBox.expand(child: spread);
    }

    return Center(child: spread);
  }

  Widget _buildLandscapeReader(bool isPhoneLandscape) {
    return LayoutBuilder(
        builder: (context, constraints) {
          return ColorFiltered(
            colorFilter: Theme.of(context).brightness == Brightness.dark
                ? const ColorFilter.matrix([
                    -1, 0, 0, 0, 255,
                     0,-1, 0, 0, 255,
                     0, 0,-1, 0, 255,
                     0, 0, 0, 1,   0,
                  ])
                : const ColorFilter.mode(
                    Color(0xFFFAF6EE),
                    BlendMode.multiply,
                  ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleReaderTap,
              child: ContinuousQuranView(
                key: _continuousViewKey,
                pages: pages,
                pageImageProviderBuilder: (pageIndex) =>
                    _imageProviderForPage(pageIndex, pages[pageIndex]),
                initialPage: _currentPage,
                viewportWidth: constraints.maxWidth,
                pageAspectRatio: _activePageAspectRatio,
                autoScrollEnabled: _isAutoScrollEnabled,
                autoScrollPixelsPerSecond: _currentAutoScrollPixelsPerSecond(),
                bookmarks: _bookmarks.values.toList(growable: false),
                onPageChanged: (page) {
                  _setCurrentPage(page, showHizbPopup: true);
                  _showTopBarOnNavigation();
                  _hideTopBarAfterNavigation();
                },
                onSaveBookmark: (page, x, y, width, height) {
                  _promptSaveBookmark(
                    page,
                    x,
                    y,
                    sourceWidth: width,
                    sourceHeight: height,
                  );
                },
                onMoveBookmark: (slot, page, x, y, width, height) {
                  final bookmark = _bookmarks[slot];
                  if (bookmark == null) return;
                  setState(() {
                    _bookmarks[slot] = bookmark.copyWith(
                      page: page,
                      x: x,
                      y: y,
                      sourceWidth: width,
                      sourceHeight: height,
                    );
                    _activeBookmarkSlot = slot;
                  });
                },
                onMoveBookmarkEnd: _persistBookmarks,
                onAutoScrollInterrupted: () {
                  _setAutoScrollEnabled(false);
                },
                onTap: _handleReaderTap,
              ),
            ),
          );
        },
      );
  }

  Widget _buildPortraitReader(bool useTwoPages) {
    final bool isPhonePortrait =
        !TabletLayoutHelper.isTabletDevice(context) &&
        MediaQuery.of(context).orientation == Orientation.portrait;
    final bool effectiveUseTwoPages = isPhonePortrait ? false : useTwoPages;

    return LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = constraints.maxHeight;
          final usePortraitScrolling =
              _supportsPortraitScrollMode(context) &&
              (_showAutoScrollBar || _isPortraitScrollMode);

          Widget readerContent;
          if (usePortraitScrolling) {
            final fixedPageExtent =
                _portraitAutoScrollViewportHeight ?? viewportHeight;

            if (_portraitAutoScrollController == null) {
              _portraitAutoScrollTimer?.cancel();
              _portraitAutoScrollViewportHeight = fixedPageExtent;
              _portraitScrollCurrentPage = _currentPage;
              _portraitAutoScrollController = ScrollController(
                initialScrollOffset:
                    _getViewIndexForPage(_currentPage, context) *
                    fixedPageExtent,
                keepScrollOffset: false,
              );
            } else if (_portraitAutoScrollViewportHeight == null) {
              _portraitAutoScrollViewportHeight = fixedPageExtent;
              _portraitScrollCurrentPage ??= _currentPage;
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _syncPortraitAutoScroll(fixedPageExtent);
            });

            readerContent = Listener(
              onPointerDown: (_) {
                if (_isAutoScrollEnabled) {
                  _portraitAutoScrollResumeTimer?.cancel();
                  _stopPortraitAutoScroll();
                }
              },
              onPointerUp: (_) {
                if (_isAutoScrollEnabled) {
                  _schedulePortraitAutoScrollResume(fixedPageExtent);
                }
              },
              onPointerCancel: (_) {
                if (_isAutoScrollEnabled) {
                  _schedulePortraitAutoScrollResume(fixedPageExtent);
                }
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) {
                    _showTopBarOnNavigation();
                  } else if (notification is ScrollUpdateNotification) {
                    _showTopBarOnNavigation();
                    _handlePortraitAutoScrollOffset(fixedPageExtent);
                  } else if (notification is ScrollEndNotification) {
                    _handlePortraitAutoScrollOffset(fixedPageExtent);
                    _hideTopBarAfterNavigation();
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _portraitAutoScrollController,
                  reverse: false,
                  addRepaintBoundaries: true,
                  addAutomaticKeepAlives: false,
                  cacheExtent: 0,
                  physics: const ClampingScrollPhysics(),
                  itemCount: effectiveUseTwoPages
                      ? (pages.length / 2).ceil()
                      : pages.length,
                  itemBuilder: (context, index) {
                    final Widget pageContent = effectiveUseTwoPages
                        ? _buildScrollingTwoPageSpread(index)
                        : _buildScrollingSinglePage(pages[index], index);
                    final Widget page = SizedBox(
                      height: fixedPageExtent,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: pageContent,
                      ),
                    );

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleReaderTap,
                      child: page,
                    );
                  },
                ),
              ),
            );
          } else {
            _stopPortraitAutoScroll();

            readerContent = NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification) {
                  _showTopBarOnNavigation();
                } else if (notification is ScrollUpdateNotification) {
                  _showTopBarOnNavigation();
                } else if (notification is ScrollEndNotification) {
                  _hideTopBarAfterNavigation();
                }
                return false;
              },
              child: PageView.builder(
                controller: _portraitController,
                reverse: true,
                allowImplicitScrolling: false,
                itemCount: effectiveUseTwoPages
                    ? (pages.length / 2).ceil()
                    : pages.length,
                onPageChanged: (index) {
                  final firstPageIndex = _getFirstPageIndexForView(index, context);
                  _hideHizbPopup();
                  _setCurrentPage(
                    firstPageIndex,
                    persist: false,
                    showHizbPopup: true,
                  );
                  _savePage(firstPageIndex);
                  _showTopBarOnNavigation();
                  _hideTopBarAfterNavigation();
                },
                itemBuilder: (context, index) {
                  final Widget page = InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: AudioService.instance.isRecitationBarVisible,
                      builder: (context, isVisible, _) {
                        return effectiveUseTwoPages
                            ? _buildTwoPageSpread(index, topAlign: isVisible)
                            : _buildSinglePage(
                                pages[index],
                                index,
                                alignment: isVisible ? Alignment.topCenter : Alignment.center,
                              );
                      },
                    ),
                  );

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleReaderTap,
                    child: page,
                  );
                },
              ),
            );
          }

          return ColorFiltered(
            colorFilter: Theme.of(context).brightness == Brightness.dark
                ? const ColorFilter.matrix([
                    -1, 0, 0, 0, 255,
                     0,-1, 0, 0, 255,
                     0, 0,-1, 0, 255,
                     0, 0, 0, 1,   0,
                  ])
                : const ColorFilter.mode(
                    Color(0xFFFAF6EE),
                    BlendMode.multiply,
                  ),
            child: readerContent,
          );
        },
      );
  }

  Widget _buildSharedOverlay(bool isPhoneLandscape) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bool isWideScreen = TabletLayoutHelper.isTabletDevice(context);
    final bool isPhonePortrait = !isPhoneLandscape && !isWideScreen;
    final mediaQuery = MediaQuery.of(context);
    final double safeBottom = mediaQuery.padding.bottom;
    final double menuHeight = isPhoneLandscape ? 122 : (isPhonePortrait ? 130 : 260);
    final double autoScrollBottom = (_showIndex && !_hideBottomMenuTemporarily)
        ? menuHeight + safeBottom + 18
        : (isPhoneLandscape ? 14 : safeBottom + 14);
    final double bookmarkNoticeBottom = _showIndex
        ? menuHeight + safeBottom + 20
        : safeBottom + 20;
    final double bookmarkHorizontalMargin = isWideScreen
        ? ((mediaQuery.size.width - 520.0) / 2).clamp(24.0, 160.0).toDouble()
        : 16.0;
    final Color hizbPopupBackground = isDarkMode
        ? const Color(0xFF20170B).withValues(alpha: 0.96)
        : Colors.black.withValues(alpha: 0.78);
    final Border? hizbPopupBorder = isDarkMode
        ? Border.all(
            color: const Color(0xFFD6B35D).withValues(alpha: 0.72),
            width: 1.2,
          )
        : null;
    final Color hizbPopupTextColor =
        isDarkMode ? const Color(0xFFFFF4D6) : Colors.white;

    return Stack(
      children: [
        if (_isMarginImagesEnabled)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _showMarginTopBar ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !_showMarginTopBar,
                child: Container(
                  color: const Color(0xFF1C1C1E).withOpacity(0.85),
                  padding: EdgeInsets.only(
                    top: mediaQuery.padding.top + 10,
                    bottom: 10,
                    left: 16,
                    right: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 48), // Spacer to keep text centered
                      const Text(
                        'وضع الهوامش',
                        style: TextStyle(
                          color: Color(0xFFD2B97E),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined, color: Color(0xFFD2B97E)),
                        onPressed: _openSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          left: bookmarkHorizontalMargin,
          right: bookmarkHorizontalMargin,
          bottom: bookmarkNoticeBottom,
          child: IgnorePointer(
            ignoring: !_showBookmarkNotice,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _showBookmarkNotice ? 1 : 0,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWideScreen ? 24 : 18,
                    vertical: isWideScreen ? 20 : 16,
                  ),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF15120B).withValues(alpha: 0.97)
                        : Colors.white.withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDarkMode
                          ? const Color(0xFFD6B35D).withValues(alpha: 0.65)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bookmark_added_rounded,
                        color: isDarkMode
                            ? const Color(0xFFD6B35D)
                            : Colors.black87,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _bookmarkNoticeTitle,
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w700,
                            fontSize: isWideScreen ? 20 : 16,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _undoBookmarkSave,
                        child: Text(
                          'تراجع',
                          style: TextStyle(
                            color: isDarkMode
                                ? const Color(0xFFD6B35D)
                                : const Color(0xFF7A4F00),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_showBookmarkGuide,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _showBookmarkGuide ? 1 : 0,
              child: Material(
                color: Colors.black.withValues(alpha: 0.62),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 22),
                      padding: EdgeInsets.symmetric(
                        horizontal: isWideScreen ? 24 : 18,
                        vertical: isWideScreen ? 22 : 18,
                      ),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF15120B).withValues(alpha: 0.98)
                            : Colors.white.withValues(alpha: 0.98),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isDarkMode
                              ? const Color(0xFFD6B35D).withValues(alpha: 0.70)
                              : const Color(0xFF8D6E3F).withValues(alpha: 0.18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.24),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'إرشاد العلامات',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                color:
                                    isDarkMode ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w800,
                                fontSize: isWideScreen ? 20 : 17,
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 120,
                              child: AnimatedBuilder(
                                animation: _bookmarkGuideAnimationController,
                                builder: (context, child) {
                                  final value =
                                      _bookmarkGuideAnimationController.value;
                                  final pressOffset = 10 - (value * 10);
                                  final scale = 1 - (value * 0.08);
                                  return Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Positioned(
                                        bottom: 20,
                                        child: Container(
                                          width: 170,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8F3E8),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                              color: const Color(0xFF8D6E3F)
                                                  .withValues(alpha: 0.16),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 12 + pressOffset,
                                        child: Transform.scale(
                                          scale: scale,
                                          child: Icon(
                                            Icons.touch_app_rounded,
                                            size: 62,
                                            color: isDarkMode
                                                ? const Color(0xFFD6B35D)
                                                : const Color(0xFF8D6E3F),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'لإضافة علامة في موضع قراءتك، اضغط مطولًا على الآية المطلوبة. ويمكنك الرجوع إليها لاحقًا من زر العلامات.',
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    isDarkMode ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w700,
                                fontSize: isWideScreen ? 17 : 14,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      setState(() {
                                        _hideBookmarkGuideForeverChecked =
                                            !_hideBookmarkGuideForeverChecked;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        textDirection: TextDirection.rtl,
                                        children: [
                                          Checkbox(
                                            value:
                                                _hideBookmarkGuideForeverChecked,
                                            onChanged: (value) {
                                              setState(() {
                                                _hideBookmarkGuideForeverChecked =
                                                    value ?? false;
                                              });
                                            },
                                            activeColor: isDarkMode
                                                ? const Color(0xFFD6B35D)
                                                : const Color(0xFF8D6E3F),
                                          ),
                                          Text(
                                            'لا تظهر مرة أخرى',
                                            style: TextStyle(
                                              color: isDarkMode
                                                  ? const Color(0xFFD6B35D)
                                                  : const Color(0xFF8D6E3F),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                FilledButton(
                                  onPressed: _handleBookmarkGuideDone,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: isDarkMode
                                        ? const Color(0xFFD6B35D)
                                        : const Color(0xFF8D6E3F),
                                    foregroundColor: isDarkMode
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                  child: const Text('فهمت'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        if (!_isMarginImagesEnabled &&
            _showSajdaPopup &&
            _visibleSajdaText != null)
          Positioned(
            top: isPhoneLandscape
                ? MediaQuery.of(context).padding.top + 70
                : MediaQuery.of(context).padding.top + 92,
            left: 20,
            right: 20,
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _showSajdaPopup ? 1 : 0,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _showSajdaDuaDialog,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWideScreen ? 30 : 18,
                        vertical: isWideScreen ? 22 : 12,
                      ),
                      decoration: BoxDecoration(
                        color: hizbPopupBackground,
                        border: hizbPopupBorder,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _visibleSajdaText!,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: hizbPopupTextColor,
                              fontSize: isWideScreen ? 27 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'اضغط لعرض دعاء السجود',
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: hizbPopupTextColor.withValues(alpha: 0.88),
                              fontSize: isWideScreen ? 18 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (!_isMarginImagesEnabled &&
            _showHizbPopup &&
            _visibleHizbText != null)
          Positioned(
            top: isPhoneLandscape
                ? MediaQuery.of(context).padding.top + 70
                : MediaQuery.of(context).padding.top + 92,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _showHizbPopup ? 1 : 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWideScreen ? 30 : 18,
                      vertical: isWideScreen ? 22 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: hizbPopupBackground,
                      border: hizbPopupBorder,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _visibleHizbText!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: hizbPopupTextColor,
                        fontSize: isWideScreen ? 27 : 18,
                        fontWeight: FontWeight.bold,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_showAutoScrollBar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            bottom: autoScrollBottom,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, animation) {
                    final beginOffset = _isAutoScrollBarCollapsed
                        ? const Offset(0.25, 0)
                        : const Offset(0.15, 0);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: beginOffset,
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _isAutoScrollBarCollapsed
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            key: const ValueKey('auto-scroll-mini'),
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isDarkMode
                                    ? const [
                                        Color(0xFFD6B35D),
                                        Color(0xFFB78D2D),
                                      ]
                                    : const [
                                        Color(0xFF2D2A24),
                                        Color(0xFF15120B),
                                      ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: IconButton(
                              onPressed: _toggleAutoScrollBarCollapsed,
                              iconSize: 34,
                              padding: const EdgeInsets.all(12),
                              color: isDarkMode
                                  ? const Color(0xFF15120B)
                                  : Colors.white,
                              icon: Icon(
                                _isAutoScrollEnabled
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              tooltip: 'إظهار الشريط',
                            ),
                          ),
                        )
                      : ConstrainedBox(
                          key: const ValueKey('auto-scroll-full'),
                          constraints: BoxConstraints(
                            maxWidth: isPhoneLandscape
                                ? 560
                                : (isPhonePortrait ? 372 : 420),
                          ),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            padding: EdgeInsets.symmetric(
                              horizontal: isPhonePortrait ? 10 : 16,
                              vertical: isPhonePortrait ? 10 : 12,
                            ),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? const Color(0xFF15120B)
                                      .withValues(alpha: 0.97)
                                  : Colors.white.withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isDarkMode
                                    ? const Color(0xFFD6B35D)
                                        .withValues(alpha: 0.72)
                                    : Colors.black.withValues(alpha: 0.08),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.04),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    onPressed: _closeAutoScrollBar,
                                    icon: const Icon(Icons.close_rounded),
                                    tooltip: 'إغلاق الشريط',
                                  ),
                                ),
                                SizedBox(width: isPhonePortrait ? 4 : 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.04),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    onPressed: _toggleAutoScrollBarCollapsed,
                                    icon: const Icon(
                                      Icons.keyboard_arrow_right_rounded,
                                    ),
                                    padding: EdgeInsets.all(
                                      isPhonePortrait ? 6 : 8,
                                    ),
                                    constraints: BoxConstraints.tightFor(
                                      width: isPhonePortrait ? 36 : 48,
                                      height: isPhonePortrait ? 36 : 48,
                                    ),
                                    tooltip: 'تصغير',
                                  ),
                                ),
                                SizedBox(width: isPhonePortrait ? 6 : 12),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isDarkMode
                                          ? const [
                                              Color(0xFFD6B35D),
                                              Color(0xFFB78D2D),
                                            ]
                                          : const [
                                              Color(0xFF2D2A24),
                                              Color(0xFF15120B),
                                            ],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.2),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    onPressed: () {
                                      _setAutoScrollEnabled(
                                        !_isAutoScrollEnabled,
                                      );
                                    },
                                    iconSize: isPhonePortrait ? 28 : 34,
                                    padding: EdgeInsets.all(
                                      isPhonePortrait ? 8 : 10,
                                    ),
                                    color: isDarkMode
                                        ? const Color(0xFF15120B)
                                        : Colors.white,
                                    icon: Icon(
                                      _isAutoScrollEnabled
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                    ),
                                    tooltip: _isAutoScrollEnabled
                                        ? 'إيقاف'
                                        : 'تشغيل',
                                  ),
                                ),
                                SizedBox(width: isPhonePortrait ? 8 : 16),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: isDarkMode
                                              ? Colors.white.withValues(
                                                  alpha: 0.08,
                                                )
                                              : Colors.black.withValues(
                                                  alpha: 0.04,
                                                ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: IconButton(
                                          onPressed: _increaseAutoScrollSpeed,
                                          icon: const Icon(
                                            Icons.keyboard_arrow_up_rounded,
                                          ),
                                          padding: EdgeInsets.all(
                                            isPhonePortrait ? 6 : 8,
                                          ),
                                          constraints: BoxConstraints.tightFor(
                                            width: isPhonePortrait ? 36 : 48,
                                            height: isPhonePortrait ? 36 : 48,
                                          ),
                                          tooltip: 'زيادة السرعة',
                                        ),
                                      ),
                                      SizedBox(width: isPhonePortrait ? 6 : 10),
                                      Container(
                                        constraints: BoxConstraints(
                                          minWidth: isPhonePortrait ? 42 : 54,
                                        ),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isPhonePortrait ? 8 : 12,
                                          vertical: isPhonePortrait ? 8 : 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDarkMode
                                              ? const Color(0xFFD6B35D)
                                                  .withValues(alpha: 0.16)
                                              : Colors.black.withValues(
                                                  alpha: 0.04,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: isDarkMode
                                                ? const Color(0xFFD6B35D)
                                                    .withValues(alpha: 0.35)
                                                : Colors.black.withValues(
                                                    alpha: 0.1,
                                                  ),
                                          ),
                                        ),
                                        child: Text(
                                          _formatAutoScrollSpeed(
                                            _autoScrollSpeedMultiplier,
                                          ),
                                          style: TextStyle(
                                            fontSize: isPhonePortrait ? 14 : 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      SizedBox(width: isPhonePortrait ? 6 : 10),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: isDarkMode
                                              ? Colors.white.withValues(
                                                  alpha: 0.08,
                                                )
                                              : Colors.black.withValues(
                                                  alpha: 0.04,
                                                ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: IconButton(
                                          onPressed: _decreaseAutoScrollSpeed,
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                          ),
                                          padding: EdgeInsets.all(
                                            isPhonePortrait ? 6 : 8,
                                          ),
                                          constraints: BoxConstraints.tightFor(
                                            width: isPhonePortrait ? 36 : 48,
                                            height: isPhonePortrait ? 36 : 48,
                                          ),
                                          tooltip: 'تنقيص السرعة',
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
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isPhonePortrait =
        !TabletLayoutHelper.isTabletDevice(context) &&
        MediaQuery.of(context).orientation == Orientation.portrait;
    final useTwoPages = isPhonePortrait ? false : _useTwoPageView(context);
    final isPhoneLandscape = _isPhoneLandscape(context);

    final double safeBottom = MediaQuery.of(context).padding.bottom;
    final double menuHeight = isPhoneLandscape ? 122 : (isPhonePortrait ? 130 : 260);

    return ValueListenableBuilder<bool>(
      valueListenable: AudioService.instance.isRecitationBarVisible,
      builder: (context, isRecitationVisible, _) {
        final scaffold = Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1A1A1F)
              : const Color(0xFFFAF6EE),
          resizeToAvoidBottomInset: false,
          // Recitation bar → pushes body up, no overlay on ayat
          bottomNavigationBar: isRecitationVisible
              ? _buildRecitationBottomBar()
              : null,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: Stack(
              children: [
                // 1 — Reader fills available space (minus bottomNavigationBar)
                Positioned.fill(
                  child: isPhoneLandscape
                      ? _buildLandscapeReader(isPhoneLandscape)
                      : _buildPortraitReader(useTwoPages),
                ),

                // 2 — Shared Overlays (bookmarks, index, etc.)
                Positioned.fill(
                  child: _buildSharedOverlay(isPhoneLandscape),
                ),

                // 3 — Top bar (slides in/out, respects camera notch)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  top: (!_hideTopBarTemporarily && !_isMarginImagesEnabled && (_showIndex || _showTopBarWhilePaging || _showControls)) ? 0 : -120,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () {}, // Block tap propagation
                    onVerticalDragUpdate: (details) {
                      if (details.primaryDelta! < -5) {
                        setState(() {
                          _hideTopBarTemporarily = true;
                          if (_hideTopBarTemporarily && _hideBottomMenuTemporarily) {
                            _showIndex = false;
                            _showTopBarWhilePaging = false;
                            _showControls = false;
                          }
                        });
                        _updateSystemUI();
                      }
                    },
                    child: TopOverlayBar(
                      show: !_hideTopBarTemporarily && !_isMarginImagesEnabled && (_showIndex || _showTopBarWhilePaging || _showControls),
                      isSearching: _isSearching,
                      currentPage: _topBarCurrentPage,
                      isTwoPageView: useTwoPages,
                      getHizbNumber: _getHizbNumber,
                      getSurahName: _getSurahName,
                      onSettingsPressed: _openSettings,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        return Stack(
          children: [
            scaffold,
            if (_showIndex)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    setState(() {
                      _showIndex = false;
                      _showSurahs = false;
                      _isSearching = false;
                      _hideTopBarTemporarily = false;
                      _hideBottomMenuTemporarily = false;
                    });
                    _updateSystemUI();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            if (_showIndex && !_hideBottomMenuTemporarily)
              BottomOverlayMenu(
                showIndex: _showIndex,
                showSurahs: _showSurahs,
                surahs: surahList,
                isDarkMode: Theme.of(context).brightness == Brightness.dark,
                isAutoScrollEnabled: _showAutoScrollBar,
                isPortraitScrollMode: _isPortraitScrollMode,
                allowPortraitScrollMode: _supportsPortraitScrollMode(context),
                showTabletLayoutSetting: _shouldShowTabletLayoutSetting(context),
                isTabletLayoutMode: _isTabletLayoutMode,
                bottomOffset: isRecitationVisible ? 82 : 0,
                onToggleSurahs: () async {
                  setState(() {
                    _showIndex = false;
                    _showSurahs = false;
                    _isSearching = false;
                  });
                  _updateSystemUI();

                  await Future.delayed(const Duration(milliseconds: 260));
                  if (!mounted) return;

                  _openQuranIndexPage();
                },
                onGoToPage: _goToPage,
                onGoToBookmark: _goToBookmark,
                onOpenTafsir: () => _showTafsirDialog(_topBarCurrentPage),
                onDismiss: () {
                  setState(() {
                    _hideBottomMenuTemporarily = true;
                    if (_hideTopBarTemporarily && _hideBottomMenuTemporarily) {
                      _showIndex = false;
                      _showControls = false;
                      _showTopBarWhilePaging = false;
                    }
                  });
                  _updateSystemUI();
                },
                onPlayTapped: () {
                  setState(() {
                    _showIndex = false;
                    _showSurahs = false;
                  });
                  _updateSystemUI();
                  AudioService.instance.playPage(_topBarCurrentPage, autoPlay: false);
                },
                onToggleDarkMode: (value) {
                  ThemeService.setDarkMode(value);
                },
                onToggleAutoScroll: (value) {
                  if (value && AudioService.instance.isRecitationBarVisible.value) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'لا يمكن تشغيل التمرير التلقائي أثناء التلاوة',
                        ),
                      ),
                    );
                    return;
                  }
                  if (value && !_supportsPortraitScrollMode(context)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'التمرير غير متاح في وضع الصفحتين على الشاشات العريضة',
                        ),
                      ),
                    );
                    return;
                  }
                  final bool shouldSwitchPortraitMode =
                      value &&
                      _supportsPortraitScrollMode(context) &&
                      !_isPortraitScrollMode;
                  setState(() {
                    if (value) {
                      if (AudioService.instance.isRecitationBarVisible.value) {
                        AudioService.instance.isRecitationBarVisible.value = false;
                      }
                      _showIndex = false;
                      _showSurahs = false;
                      _isSearching = false;
                      _isAutoScrollEnabled = true;
                      _showAutoScrollBar = true;
                      _isAutoScrollBarCollapsed = false;
                    } else {
                      _isAutoScrollEnabled = false;
                      _showAutoScrollBar = false;
                      _isAutoScrollBarCollapsed = false;
                    }
                    if (shouldSwitchPortraitMode) {
                      _isPortraitScrollMode = true;
                    }
                  });
                  _updateSystemUI();
                  if (shouldSwitchPortraitMode) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'تم تغيير الوضع من صفحات إلى تمرير',
                        ),
                      ),
                    );
                  }
                },
                onTogglePortraitScrollMode: (value) {
                  _setPortraitScrollMode(value);
                },
                onToggleTabletLayoutMode: (value) {
                  _setTabletLayoutMode(value);
                },
                onSearchStateChanged: (value) {
                  setState(() {
                    _isSearching = value;
                  });
                },
                onSearchTapped: _openSearchPage,
              ),
          ],
        );
      },
    );
  }

  void _showRecitationBarGuide() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode ? const Color(0xFF1E1A12) : const Color(0xFFF8F1DE);
    final titleColor = isDarkMode ? const Color(0xFFD6B35D) : const Color(0xFF8D6E3F);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
    final borderColor = isDarkMode ? const Color(0xFF53401F) : const Color(0xFFE2D2A5);
    bool doNotShowAgain = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.help_outline_rounded, color: titleColor, size: 24),
            const SizedBox(width: 8),
            Text(
              'شرح أزرار شريط التلاوة',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: titleColor),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _guideRow(Icons.close_rounded, 'إغلاق شريط التلاوة', textColor, borderColor),
              _guideRow(Icons.skip_next_rounded, 'الآية السابقة', textColor, borderColor),
              _guideRow(Icons.play_arrow_rounded, 'تشغيل / إيقاف مؤقت', textColor, borderColor),
              _guideRow(Icons.skip_previous_rounded, 'الآية التالية', textColor, borderColor),
              _guideRow(Icons.replay_rounded, 'تكرار الصفحة (اضغط للتبديل)', textColor, borderColor),
              _guideRow(Icons.repeat_rounded, 'تكرار الآية (اضغط عدة مرات للتبديل)', textColor, borderColor),
              const SizedBox(height: 16),
              Directionality(
                textDirection: TextDirection.rtl,
                child: CheckboxListTile(
                  value: doNotShowAgain,
                  onChanged: (value) {
                    setState(() {
                      doNotShowAgain = value ?? false;
                    });
                  },
                  title: Text(
                    'لا تظهر هذه الرسالة مرة أخرى',
                    style: TextStyle(color: textColor, fontSize: 14),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: titleColor,
                  checkColor: bgColor,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (doNotShowAgain) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('recitation_guide_dismissed', true);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('فهمت', style: TextStyle(color: titleColor, fontWeight: FontWeight.w800)),
          ),
        ],
      );
    }),
    );
  }

  Widget _guideRow(IconData icon, String label, Color textColor, Color borderColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: borderColor.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: textColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showAyahSelectionDialog(QuranAyahData currentAyah) async {
    if (_allQuranPages == null) {
      final data = await QuranJsonService.loadQuranPages();
      if (mounted) {
        setState(() => _allQuranPages = data);
      } else {
        return;
      }
    }
    
    if (_allQuranPages == null) return;
    
    final pageData = _allQuranPages!.firstWhere(
      (p) => p.page == _currentPage + 1,
      orElse: () => QuranPageData(page: _currentPage + 1, ayahs: []),
    );
    final pageAyahs = pageData.ayahs;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'اختر الآية - صفحة ${_currentPage + 1}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: pageAyahs.length,
                  itemBuilder: (context, index) {
                    final ayah = pageAyahs[index];
                    final isCurrent = ayah.ayah == currentAyah.ayah && ayah.surah == currentAyah.surah;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        AudioService.instance.jumpToAyah(ayah.surah, ayah.ayah);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isCurrent 
                              ? const Color(0xFFD6B35D).withValues(alpha: 0.2) 
                              : Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent 
                                ? const Color(0xFFD6B35D) 
                                : Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${ayah.ayah}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent ? const Color(0xFFD6B35D) : Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ),
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

  Widget _buildRecitationBottomBar() {
    const accentColor = Color(0xFFD2B97E);
    final audio = AudioService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([
        audio.isPlaying,
        audio.currentAyah,
        audio.pageRepeatMode,
        audio.repeatMode,
        audio.isLoadingAudio,
      ]),
      builder: (context, _) {
        final isPlaying = audio.isPlaying.value;
        final currentAyah = audio.currentAyah.value;
        final repeatModeVal = audio.repeatMode.value;
        final pageRepeatModeVal = audio.pageRepeatMode.value;
        final isRepeating = repeatModeVal != AyahRepeatMode.off;
        final repeatLabel = audio.repeatLabel;
        final isPageRepeating = pageRepeatModeVal != AyahRepeatMode.off;
        final pageRepeatLabel = audio.pageRepeatLabel;

        return Container(
          color: const Color(0xFF1C1C1E),
          padding: const EdgeInsets.only(
            left: 6,
            right: 6,
            top: 10,
            bottom: 24, // Fixed padding to prevent jitter when system bars appear
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // تكرار الصفحة
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  _resetHideTimer();
                  audio.cyclePageRepeatMode();
                },
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.replay_rounded, 
                      color: isPageRepeating ? accentColor : Colors.white.withValues(alpha: 0.7), 
                      size: 24),
                    if (isPageRepeating && pageRepeatLabel.isNotEmpty)
                      Positioned(
                        bottom: -2,
                        child: Text(pageRepeatLabel, style: const TextStyle(fontSize: 7, color: accentColor, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                tooltip: 'تكرار الصفحة',
              ),

              // السابق
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.skip_previous_rounded,
                    color: accentColor.withValues(alpha: 0.9), size: 28),
                onPressed: () {
                  _resetHideTimer();
                  audio.previousAyah();
                },
                tooltip: 'الآية السابقة',
              ),

              // رقم الآية
              GestureDetector(
                onTap: () {
                  _resetHideTimer();
                  if (currentAyah != null) {
                    _showAyahSelectionDialog(currentAyah);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    currentAyah != null ? 'آية ${currentAyah.ayah}' : 'آية 1',
                    style: const TextStyle(
                      color: accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // إيقاف/تشغيل
              GestureDetector(
                onTap: () {
                  _resetHideTimer();
                  if (isPlaying) {
                    audio.pause();
                  } else {
                    audio.resume();
                  }
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                  ),
                  child: audio.isLoadingAudio.value
                      ? Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accentColor,
                          ),
                        )
                      : Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: accentColor,
                          size: 32,
                        ),
                ),
              ),

              // التالي
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.skip_next_rounded,
                    color: accentColor.withValues(alpha: 0.9), size: 28),
                onPressed: () {
                  _resetHideTimer();
                  audio.nextAyah();
                },
                tooltip: 'الآية التالية',
              ),

              // تكرار الآية
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  _resetHideTimer();
                  audio.cycleAyahRepeatMode();
                },
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.repeat_rounded, 
                      color: isRepeating ? accentColor : Colors.white.withValues(alpha: 0.7), 
                      size: 24),
                    if (isRepeating && repeatLabel.isNotEmpty)
                      Positioned(
                        bottom: -2,
                        child: Text(repeatLabel, style: const TextStyle(fontSize: 7, color: accentColor, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                tooltip: 'تكرار الآية',
              ),

              // إغلاق
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.grey, size: 24),
                onPressed: () {
                  _resetHideTimer();
                  audio.stop();
                },
                tooltip: 'إغلاق',
              ),

              // مساعدة
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.help_outline_rounded,
                    color: Colors.grey, size: 20),
                onPressed: () {
                  _resetHideTimer();
                  _showRecitationBarGuide();
                },
                tooltip: 'إرشادات',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Stateful Tafsir sheet with page navigation.
class _TafsirSheetContent extends StatefulWidget {
  final int initialPageIndex;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final Color titleColor;
  final Color accentColor;
  final ValueChanged<int> onPageChanged;

  const _TafsirSheetContent({
    required this.initialPageIndex,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.titleColor,
    required this.accentColor,
    required this.onPageChanged,
  });

  @override
  State<_TafsirSheetContent> createState() => _TafsirSheetContentState();
}

class _TafsirSheetContentState extends State<_TafsirSheetContent> {
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
                    // Close button
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: widget.accentColor),
                        iconSize: 22,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                        tooltip: 'إغلاق',
                      ),
                    ),
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

import 'dart:async'; // Quran Pages View

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent, RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'widgets/quran/bookmark_picker_dialog.dart';
import 'widgets/quran/hifz_reveal_view.dart';
import 'continuous_quran_view.dart';
import 'models/reader_bookmark.dart';
import 'quran_constants.dart';
import 'quran_reading_coordinator.dart';
import 'services/background_playback_service.dart';
import 'services/margin_images_service.dart';
import 'services/high_quality_images_service.dart';
import 'services/page_quality_service.dart';
import 'services/recitation_bar_opacity_service.dart';

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
import 'widgets/hifz_lens_icon.dart';
import 'widgets/settings/settings_page.dart';
import 'search_page.dart';

class QuranPages extends StatefulWidget {
  final int initialPage;
  final bool initialPortraitScrollMode;
  const QuranPages({
    super.key,
    this.initialPage = 0,
    this.initialPortraitScrollMode = false,
  });

  @override
  State<QuranPages> createState() => _QuranPagesState();
}

class _QuranPagesState extends State<QuranPages>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _defaultPageAspectRatio = 720 / 1640;
  static const double _marginPageAspectRatio = 1178 / 1878;
  static const String _portraitScrollModePrefKey = 'portraitScrollMode';
  static const String _tabletLayoutModePrefKey = 'tabletLayoutMode';
  static const String _hifzModePrefKey = 'enableHifzMode';
  static const String _fullScreenModePrefKey = 'fullScreenMode';
  static const String _bookmarkGuideDismissedPrefKey = 'bookmarkGuideDismissed';
  static const String _hifzLensGuideDismissedPrefKey = 'hifzLensGuideDismissed';
  static const String _hideBarReaderGuideDismissedPrefKey =
      'hideBarReaderGuideDismissed';
  static const String _fullScreenGuideDismissedPrefKey =
      'fullScreenGuideDismissed';
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
  final MarginImagesService _marginImagesService = MarginImagesService.instance;
  final HighQualityImagesService _highQualityImagesService =
      HighQualityImagesService.instance;
  final PageQualityService _pageQualityService = PageQualityService.instance;

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
  bool _isHideBarEnabled = false;
  // false = reveal mode (page hidden, the bar is a window onto the text);
  // true = blocker mode (page visible, the bar is an opaque block over text).
  bool _isHideBarReversed = false;
  double _hideBarRatio = 0.15;
  bool _isHifzModeEnabled = false;
  bool _isFullScreenMode = false;

  int? _activeBookmarkSlot;
  bool _showBookmarkNotice = false;
  bool _showAudioPlaybackNotice = false;
  bool _showBookmarkGuide = false;
  bool _hideBookmarkGuideForeverChecked = false;
  String? _visibleHizbText;
  String? _visibleSajdaText;
  String _audioPlaybackNoticeText = '';
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
  Timer? _audioPlaybackNoticeTimer;
  late final AnimationController _bookmarkGuideAnimationController;
  Timer? _savePageTimer;
  Timer? _portraitAutoScrollTimer;
  Timer? _portraitAutoScrollResumeTimer;

  double? _portraitAutoScrollViewportHeight;
  int? _portraitScrollCurrentPage;
  bool _isRecitationTopBarMinimized = false;
  Timer? _recitationBarHideTimer;
  List<QuranPageData>? _allQuranPages;
  Timer? _hideControlsTimer;

  // Measured height of the recitation (audio playback) bar. The action bar is
  // anchored exactly this many pixels above the stack bottom so it sits flush
  // on top of the recitation bar in every screen state (full screen, standard,
  // and during transitions) with no gap or overlap. Defaults to a sensible
  // estimate until the first layout pass measures the real height.
  double _recitationBarHeight = 90.0;

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
    // No setState needed — the recitation bar uses its own ValueListenableBuilder.
  }

  void _handleAudioPlaybackNotice() {
    final notice = AudioService.instance.playbackNotice.value;
    if (!mounted || notice == null) return;

    _audioPlaybackNoticeTimer?.cancel();
    setState(() {
      _audioPlaybackNoticeText = notice.message;
      _showAudioPlaybackNotice = true;
    });

    _audioPlaybackNoticeTimer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      setState(() {
        _showAudioPlaybackNotice = false;
      });
    });
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          // The top bar and bottom menu are one piece of chrome — auto-hide
          // them together after a period of inactivity.
          _showIndex = false;
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
    // Animation is started only when the bookmark guide is shown (see below)
    _readingCoordinator = QuranReadingCoordinator(pageCount: pages.length);
    _readingCoordinator.addListener(_handleReadingCoordinatorChanged);
    _marginImagesService.state.addListener(_handleMarginImagesChanged);
    _highQualityImagesService.state.addListener(
      _handleHighQualityImagesChanged,
    );
    _pageQualityService.level.addListener(_handlePageQualityChanged);
    // Use the page passed from SplashScreen so we never flash Al-Fatiha
    if (widget.initialPage > 0) {
      _readingCoordinator.setCurrentPage(widget.initialPage);
      _syncCurrentSurahForPage(widget.initialPage);
    }
    _portraitController = PageController(initialPage: widget.initialPage);
    _marginImagesService.initialize();
    _highQualityImagesService.initialize();
    _pageQualityService.load();

    // Set scroll mode immediately from SplashScreen to avoid delayed setState blank flash
    _isPortraitScrollMode = widget.initialPortraitScrollMode;
    _preferredPortraitScrollMode = widget.initialPortraitScrollMode;

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
    AudioService.instance.playbackNotice.addListener(
      _handleAudioPlaybackNotice,
    );
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
    _hizbPopupTimer?.cancel();
    _sajdaPopupTimer?.cancel();
    _savePageTimer?.cancel();
    _audioPlaybackNoticeTimer?.cancel();
    _recitationBarHideTimer?.cancel();
    _portraitAutoScrollTimer?.cancel();
    _portraitAutoScrollResumeTimer?.cancel();
    _portraitAutoScrollController?.dispose();
    AudioService.instance.isPlaying.removeListener(_handleAudioPlaybackChanged);
    AudioService.instance.playbackNotice.removeListener(
      _handleAudioPlaybackNotice,
    );
    AudioService.instance.stop();
    _setReadingMode(false);
    _marginImagesService.state.removeListener(_handleMarginImagesChanged);
    _highQualityImagesService.state.removeListener(
      _handleHighQualityImagesChanged,
    );
    _pageQualityService.level.removeListener(_handlePageQualityChanged);
    _readingCoordinator.removeListener(_handleReadingCoordinatorChanged);
    _readingCoordinator.dispose();
    _bookmarkGuideAnimationController.dispose();
    _portraitController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Pause audio instead of stopping — so user can resume when they return.
      // Unless the user enabled background playback, in which case the recitation
      // keeps going and is controlled from the system media notification.
      if (!BackgroundPlaybackService.instance.enabled.value) {
        AudioService.instance.pause();
      }
      // Stop auto-scroll timer to save battery in background.
      _stopPortraitAutoScroll();
      // Pause any active downloads so they can resume later
      _marginImagesService.pauseDownload();
    } else if (state == AppLifecycleState.resumed) {
      // Resume auto-scroll if it was enabled.
      if (_isAutoScrollEnabled && _portraitAutoScrollViewportHeight != null) {
        _syncPortraitAutoScroll(_portraitAutoScrollViewportHeight!);
      }
      // Auto-resume paused downloads when app returns to foreground
      if (_marginImagesService.state.value.isPaused) {
        _marginImagesService.downloadAndEnable();
      }
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

  // Track previous state to avoid unnecessary rebuilds during downloads.
  bool _prevMarginEnabled = false;
  String? _prevMarginDir;

  void _handleMarginImagesChanged() {
    if (!mounted) return;
    final s = _marginImagesService.state.value;
    if (s.isEnabled == _prevMarginEnabled &&
        s.imagesDirectoryPath == _prevMarginDir) {
      return; // Only download progress changed — skip rebuild.
    }
    _prevMarginEnabled = s.isEnabled;
    _prevMarginDir = s.imagesDirectoryPath;
    _downloadedPageFileCache.clear();
    _cachedDirectories.clear();
    final isEnabled = s.isEnabled;
    setState(() {
      if (isEnabled) {
        _showHizbPopup = false;
        _showSajdaPopup = false;
        _visibleHizbText = null;
        _visibleSajdaText = null;
      }
    });
  }

  void _handlePageQualityChanged() {
    if (!mounted) return;
    // Re-evaluate image providers and filterQuality for the new level.
    setState(() {});
  }

  bool _prevHqEnabled = false;
  String? _prevHqDir;

  void _handleHighQualityImagesChanged() {
    if (!mounted) return;
    final s = _highQualityImagesService.state.value;
    if (s.isEnabled == _prevHqEnabled && s.imagesDirectoryPath == _prevHqDir) {
      return; // Only download progress changed — skip rebuild.
    }
    _prevHqEnabled = s.isEnabled;
    _prevHqDir = s.imagesDirectoryPath;
    _downloadedPageFileCache.clear();
    _cachedDirectories.clear();
    setState(() {});
  }

  bool get _isMarginImagesEnabled => _marginImagesService.state.value.isEnabled;
  double get _activePageAspectRatio =>
      _isMarginImagesEnabled ? _marginPageAspectRatio : _defaultPageAspectRatio;

  final Map<String, File> _downloadedPageFileCache = {};
  final Set<String> _cachedDirectories = {};

  File? _downloadedPageFileForIndex(String directoryPath, int pageNumber) {
    if (!_cachedDirectories.contains(directoryPath)) {
      try {
        final dir = Directory(directoryPath);
        if (dir.existsSync()) {
          for (final entity in dir.listSync()) {
            if (entity is File) {
              _downloadedPageFileCache[entity.path] = entity;
            }
          }
        }
      } catch (e) {
        debugPrint('Error populating dir cache: $e');
      }
      _cachedDirectories.add(directoryPath);
    }

    // Zero disk I/O memory lookup for all supported extensions
    for (final ext in const ['webp', 'jpg', 'jpeg', 'png']) {
      final path =
          '$directoryPath${Platform.pathSeparator}page_$pageNumber.$ext';
      if (_downloadedPageFileCache.containsKey(path)) {
        return _downloadedPageFileCache[path];
      }
    }
    return null;
  }

  Widget _buildBookmarkBadge(int slot) {
    return Container(
      width: 26,
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF8B7355), // ذهبي بدل أحمر
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: const Icon(Icons.bookmark, color: Colors.white, size: 16),
    );
  }

  ImageProvider _imageProviderForPage(int pageIndex, String assetPath) {
    // Levels 2 & 3 decode at native size (all sources are 720px wide, so this
    // is the same memory as the old ResizeImage(720)) and pair with a high
    // filterQuality for smoother upscaling. Level 1 keeps the original resize.
    final int level = _pageQualityService.level.value;
    final bool nativeDecode = level != PageQualityService.standard;

    ImageProvider wrap(ImageProvider provider) =>
        nativeDecode ? provider : ResizeImage(provider, width: 720);

    // Margin display, when enabled, overrides the source image.
    final marginState = _marginImagesService.state.value;
    if (marginState.isEnabled && marginState.imagesDirectoryPath != null) {
      final file = _downloadedPageFileForIndex(
        marginState.imagesDirectoryPath!,
        pageIndex + 1,
      );
      if (file != null) {
        return wrap(FileImage(file));
      }
    }

    // Level 3: use the downloaded high-fidelity pack when it is ready, else
    // fall through to the bundled asset (rendered with level-2 smoothing).
    if (level >= PageQualityService.highFidelity) {
      final hqState = _highQualityImagesService.state.value;
      if (hqState.isEnabled && hqState.imagesDirectoryPath != null) {
        final file = _downloadedPageFileForIndex(
          hqState.imagesDirectoryPath!,
          pageIndex + 1,
        );
        if (file != null) {
          return wrap(FileImage(file));
        }
      }
    }

    return wrap(AssetImage(assetPath));
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

    if (_isHideBarEnabled) {
      setState(() {
        _hideBarRatio = 0.05;
      });
    }
  }

  void _openQuranIndexPage({QuranIndexTab initialTab = QuranIndexTab.surahs}) {
    if (_isAutoScrollEnabled) {
      _setAutoScrollEnabled(false);
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

  // Page navigation no longer reveals the top bar on its own — the top bar and
  // the bottom menu are one piece of chrome that only appears when the screen
  // is tapped. These are kept as no-ops so the many page-change call sites stay
  // simple.
  void _showTopBarOnNavigation() {}

  void _hideTopBarAfterNavigation() {}

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
              color: isDarkMode
                  ? const Color(0xFFFFF4D6)
                  : const Color(0xFF35250E),
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
              child: const Text('إغلاق', textDirection: TextDirection.rtl),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showTafsirDialog(int pageIndex) async {
    if (!mounted) return;

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode
        ? const Color(0xFF19130A)
        : const Color(0xFFF8F1DE);
    final borderColor = isDarkMode
        ? const Color(0xFFD6B35D).withValues(alpha: 0.55)
        : const Color(0xFFE2D2A5);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
    final titleColor = isDarkMode
        ? const Color(0xFFFFF4D6)
        : const Color(0xFF35250E);
    final accentColor = isDarkMode
        ? const Color(0xFFD6B35D)
        : const Color(0xFF8D6E3F);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Center(child: CircularProgressIndicator(color: borderColor));
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

    // If initialPage already matches (set in initState from SplashScreen),
    // skip ALL state changes to avoid triggering rebuilds that cause blank flash.
    if (page == widget.initialPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showHizbPopupIfNeeded(page);
        _showSajdaPopupIfNeeded(page);
      });
      return;
    }

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
    // The top bar and the bottom menu are a single piece of chrome: one tap
    // toggles both together.
    final bool willShow = !_showIndex;
    setState(() {
      _showIndex = willShow;
      _hideTopBarTemporarily = false;
      _hideBottomMenuTemporarily = false;
    });
    _updateSystemUI();
    if (willShow) {
      _resetHideTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
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

    // null / empty input clears the custom name (back to "العلامة N").
    final normalized = newLabel?.trim() ?? '';
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
    if (!mounted) return;
    await _promptBookmarkName(slot);
  }

  /// Offers to name a freshly saved bookmark. Leaving it blank (or skipping)
  /// keeps the default "العلامة N" name, so naming is entirely optional.
  Future<void> _promptBookmarkName(int slot) async {
    final controller = TextEditingController(
      text: _bookmarks[slot]?.label ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'تسمية ${_bookmarkDisplayName(slot)}',
          textDirection: TextDirection.rtl,
        ),
        content: TextField(
          controller: controller,
          textDirection: TextDirection.rtl,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(hintText: 'اسم مختصر (اختياري)'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('تخطٍّ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    // null → skipped; empty → keep the default name.
    if (result == null || result.trim().isEmpty || !mounted) return;
    await _renameBookmarkSlot(slot, result.trim());
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
      // Re-saving a slot keeps the user's custom name for it.
      label: previousBookmark?.label,
    );

    setState(() {
      _bookmarks[slot] = bookmark;
      _activeBookmarkSlot = slot;
    });
    await _persistBookmarks();

    if (!mounted) return;
    _previousBookmarkSlot = slot;
    _previousBookmark = previousBookmark;
    _showBookmarkNoticeOverlay();
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
        final bookmark = ReaderBookmark.fromJson(
          Map<String, dynamic>.from(item),
        );
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
      _bookmarkGuideAnimationController.repeat(reverse: true);
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
    _bookmarkGuideAnimationController.stop();
    _bookmarkGuideAnimationController.reset();
  }

  void _closeBookmarkGuideForNow() {
    if (!mounted) return;
    setState(() {
      _showBookmarkGuide = false;
      _hideBookmarkGuideForeverChecked = false;
    });
    _bookmarkGuideAnimationController.stop();
    _bookmarkGuideAnimationController.reset();
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
        _continuousViewKey.currentState?.scrollToPage(
          targetIndex,
          yOffsetRatio: yOffsetRatio,
        );
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    if (_isFullScreenMode) {
      // Full screen mode: hide both system bars; the whole screen shows the
      // page (the body SafeArea collapses because insets become zero).
      //
      // Keep the bars transparent as well. When the bars are temporarily
      // revealed (immersiveSticky) — or on the cold-start frame before the
      // hide takes effect — an opaque/black bar would otherwise be painted in
      // the status-bar slot, leaving a black strip at the top of the screen.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          statusBarIconBrightness: isDarkMode
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarIconBrightness: isDarkMode
              ? Brightness.light
              : Brightness.dark,
        ),
      );
      return;
    }
    // Normal mode: keep both system bars visible; the reader body is wrapped
    // in SafeArea so the page content shrinks to avoid them.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: isDarkMode
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarIconBrightness: isDarkMode
            ? Brightness.light
            : Brightness.dark,
      ),
    );
  }

  Future<void> _toggleFullScreenMode(bool value) async {
    setState(() {
      _isFullScreenMode = value;
    });
    if (value) unawaited(_maybeShowFullScreenGuide());
    if (!value) {
      // Leaving immersive mode: explicitly re-show both system bars and wait
      // for the platform to process it before applying edgeToEdge. On many
      // Android versions switching straight from immersiveSticky to
      // edgeToEdge leaves the bars hidden (the sticky flags are not cleared
      // by the mode change alone).
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      if (!mounted) return;
    }
    _updateSystemUI();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fullScreenModePrefKey, value);
  }

  Future<void> _maybeShowFullScreenGuide() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_fullScreenGuideDismissedPrefKey) ?? false;
    if (!dismissed && mounted) _showFullScreenGuide();
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

  void _toggleAutoScrollFromMenu(bool value) {
    if (value) {
      _setAutoScrollEnabled(true);
    } else {
      _closeAutoScrollBar();
    }
  }

  void _setAutoScrollEnabled(bool value) {
    if (_isAutoScrollEnabled == value) return;

    if (value) {
      _toggleHideBar(false);
      if (!_isPortraitScrollMode) {
        _portraitAutoScrollController?.dispose();
        _portraitAutoScrollController = null;
        _portraitAutoScrollViewportHeight = null;
        _portraitScrollCurrentPage = null;
      }
    }

    setState(() {
      _isAutoScrollEnabled = value;
      if (value) {
        _showAutoScrollBar = true;
        _isAutoScrollBarCollapsed = false;
      }
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

  static const List<double> _allowedSpeeds = [
    0.5,
    0.75,
    1.0,
    1.5,
    2.0,
    2.5,
    3.0,
  ];

  void _increaseAutoScrollSpeed() {
    int currentIndex = _allowedSpeeds.indexOf(_autoScrollSpeedMultiplier);
    if (currentIndex == -1) {
      currentIndex = _allowedSpeeds.indexWhere(
        (s) => s >= _autoScrollSpeedMultiplier,
      );
      if (currentIndex == -1) currentIndex = _allowedSpeeds.length - 1;
    }
    if (currentIndex < _allowedSpeeds.length - 1) {
      _setAutoScrollSpeedMultiplier(_allowedSpeeds[currentIndex + 1]);
    }
  }

  void _decreaseAutoScrollSpeed() {
    int currentIndex = _allowedSpeeds.indexOf(_autoScrollSpeedMultiplier);
    if (currentIndex == -1) {
      currentIndex = _allowedSpeeds.lastIndexWhere(
        (s) => s <= _autoScrollSpeedMultiplier,
      );
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
          content: Text(
            'وضع التمرير غير متاح في وضع الصفحتين على الشاشات العريضة',
          ),
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

    // Hide bar and scroll mode are mutually exclusive (both use vertical gestures)
    if (value && _isHideBarEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب إيقاف شريط الإخفاء أولاً')),
      );
      // Force rebuild so the settings toggle reverts visually
      setState(() {});
      return;
    }

    _preferredPortraitScrollMode = value;
    _saveReadingPreferences();

    // Pre-warm the image cache for the current page and neighbors
    // BEFORE switching modes, so images appear instantly.
    if (value) {
      for (int i = _currentPage - 1; i <= _currentPage + 1; i++) {
        if (i >= 0 && i < pages.length) {
          precacheImage(_imageProviderForPage(i, pages[i]), context);
        }
      }
    }

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

    if (!_isPortraitScrollMode) {
      // Capture the page the user actually scrolled to from the live scroll
      // offset BEFORE tearing the scroll controller down, then reopen paged
      // mode anchored there. Without this the PageView would fall back to its
      // stale initial page (the last bookmark or surah start it was created
      // with), instead of staying on the page where auto-scroll was stopped.
      final int landingPage = _resolveCurrentPortraitScrollPage();

      _portraitAutoScrollController?.dispose();
      _portraitAutoScrollController = null;
      _portraitAutoScrollViewportHeight = null;
      _portraitScrollCurrentPage = null;

      _setCurrentPage(landingPage);
      _recreatePortraitController(initialPage: landingPage);
    }

    setState(() {
      _isAutoScrollEnabled = false;
      _showAutoScrollBar = false;
      _isAutoScrollBarCollapsed = false;
    });
  }

  /// Resolves the page currently shown in portrait scroll mode from the live
  /// scroll offset, falling back to the tracked page and finally the reading
  /// coordinator's page when the controller is unavailable.
  int _resolveCurrentPortraitScrollPage() {
    final controller = _portraitAutoScrollController;
    final extent = _portraitAutoScrollViewportHeight;
    if (controller != null &&
        controller.hasClients &&
        extent != null &&
        extent > 0) {
      return _getPortraitScrollPageFromOffset(extent);
    }
    return _portraitScrollCurrentPage ?? _currentPage;
  }

  void _toggleHideBar(bool value) {
    if (value) {
      _closeAutoScrollBar();
      // Hide bar and scroll mode are mutually exclusive (both use vertical gestures)
      if (_isPortraitScrollMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب إيقاف وضع التمرير أولاً')),
        );
        return;
      }
    }
    setState(() {
      _isHideBarEnabled = value;
      // Always start a fresh session in reveal mode.
      if (!value) {
        _isHideBarReversed = false;
      }
      // Hide bar and Hifz mode both obscure the page text — keep one active.
      if (value) {
        _isHifzModeEnabled = false;
      }
    });
    if (value) {
      _saveHifzModePreference();
      _maybeShowHideBarReaderGuide();
    }
  }

  Future<void> _maybeShowHideBarReaderGuide() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed =
        prefs.getBool(_hideBarReaderGuideDismissedPrefKey) ?? false;
    if (!dismissed && mounted) _showHideBarReaderGuide();
  }

  Widget _hideBarCircleButton(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF6EE),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFD4A946).withValues(alpha: 0.8),
        ),
      ),
      child: Icon(icon, size: 14, color: const Color(0xFF8D7A50)),
    );
  }

  /// Builds the "شريط الإخفاء" curtain overlay. [baseHalf] sets the size of the
  /// reading window for the current reader variant. The drag, clamping and
  /// touch-isolation are identical in both modes; only the rendering differs:
  ///   • reveal  (_isHideBarReversed == false): the page is masked except for
  ///     the window the user drags over the line they want to read.
  ///   • blocker (_isHideBarReversed == true):  the page is fully visible and
  ///     the window itself is an opaque beige block hiding the text under it.
  List<Widget> _buildHideBarOverlay(
    BoxConstraints constraints, {
    required double baseHalf,
  }) {
    final isPlaying = AudioService.instance.isPlaying.value;
    final scale = isPlaying ? 2.0 : 1.0;
    final halfHeight = baseHalf * scale;
    final frameOffset = (baseHalf + 4) * scale;
    final frameHeight = 2 * frameOffset;
    final maxH = constraints.maxHeight;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coverColor = isDark
        ? const Color(0xFF1A1A1F)
        : const Color(0xFFFAF6EE);
    const blockerColor = Color(0xFFEDE3CC);

    final center = _hideBarRatio * maxH;
    final windowTop = (center - halfHeight).clamp(0.0, maxH).toDouble();
    final windowBottom = (center + halfHeight).clamp(0.0, maxH).toDouble();
    final frameTop = (center - frameOffset)
        .clamp(-frameOffset, maxH)
        .toDouble();

    return [
      if (!_isHideBarReversed) ...[
        // Reveal mode: solid covers above and below the reading window.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: windowTop,
          child: IgnorePointer(child: Container(color: coverColor)),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: windowBottom,
          bottom: 0,
          child: IgnorePointer(child: Container(color: coverColor)),
        ),
      ] else
        // Blocker mode: a single opaque block over the window region.
        Positioned(
          left: 0,
          right: 0,
          top: windowTop,
          height: (windowBottom - windowTop).clamp(0.0, maxH).toDouble(),
          child: IgnorePointer(child: Container(color: blockerColor)),
        ),
      // The draggable window frame with its handle and buttons.
      Positioned(
        left: -5,
        right: -5,
        top: frameTop,
        height: frameHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            setState(() {
              _hideBarRatio = ((_hideBarRatio * maxH + details.delta.dy) / maxH)
                  .clamp(0.05, 0.95);
            });
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: const Color(0xFFD4A946).withValues(alpha: 0.8),
                  width: 3,
                ),
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFD4A946).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                  ),
                ),
                // Close (X) button on the left edge.
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => _toggleHideBar(false),
                      child: _hideBarCircleButton(Icons.close_rounded),
                    ),
                  ),
                ),
                // Invert/reverse toggle on the right edge (opposite the close
                // button) — flips between reveal and blocker modes.
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => setState(
                        () => _isHideBarReversed = !_isHideBarReversed,
                      ),
                      child: _hideBarCircleButton(
                        _isHideBarReversed
                            ? Icons.flip_to_front_rounded
                            : Icons.flip_to_back_rounded,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  void _toggleHifzMode(bool value) {
    setState(() {
      _isHifzModeEnabled = value;
      if (value) {
        // Hide bar and Hifz mode both obscure the page text — keep one active.
        _isHideBarEnabled = false;
        // Dismiss the overlay menus so the blurred page is shown clean.
        _showIndex = false;
        _showSurahs = false;
        _isSearching = false;
      }
    });
    _saveHifzModePreference();
    if (value) _maybeShowHifzLensGuide();
  }

  Future<void> _maybeShowHifzLensGuide() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_hifzLensGuideDismissedPrefKey) ?? false;
    if (!dismissed && mounted) _showHifzLensGuide();
  }

  Future<void> _saveHifzModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hifzModePrefKey, _isHifzModeEnabled);
  }

  /// Restores every setting to its default. Bookmarks, the last-read page
  /// and downloaded image packages are user data and are kept.
  Future<void> _resetAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    const settingsKeys = [
      _portraitScrollModePrefKey,
      _tabletLayoutModePrefKey,
      _hifzModePrefKey,
      _fullScreenModePrefKey,
      'isDarkMode',
      'recitation_guide_dismissed',
      'hideBarGuideDismissed',
      'marginGuideDismissed',
      'autoScrollGuideDismissed',
      'browseModeGuideDismissed',
      'bookmarkGuideDismissed',
      _hifzLensGuideDismissedPrefKey,
      _hideBarReaderGuideDismissedPrefKey,
      _fullScreenGuideDismissedPrefKey,
    ];
    for (final key in settingsKeys) {
      await prefs.remove(key);
    }

    await ThemeService.setDarkMode(false);
    await _marginImagesService.setEnabled(false);

    if (!mounted) return;
    _closeAutoScrollBar();
    setState(() {
      _isHideBarEnabled = false;
      _isHideBarReversed = false;
      _isHifzModeEnabled = false;
      _autoScrollSpeedMultiplier = 1.0;
      _preferredPortraitScrollMode = false;
      _isTabletLayoutMode = TabletLayoutHelper.isTabletDevice(context);
    });
    if (_isPortraitScrollMode) {
      _setPortraitScrollMode(false);
    }
    await _toggleFullScreenMode(false);
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
    _isHideBarEnabled = false;

    final savedHifzMode = prefs.getBool(_hifzModePrefKey) ?? false;
    if (savedHifzMode != _isHifzModeEnabled) {
      setState(() {
        _isHifzModeEnabled = savedHifzMode;
      });
    }

    final savedFullScreenMode = prefs.getBool(_fullScreenModePrefKey) ?? false;
    if (savedFullScreenMode != _isFullScreenMode) {
      setState(() {
        _isFullScreenMode = savedFullScreenMode;
      });
      _updateSystemUI();
    }

    // If scroll mode was already set from widget.initialPortraitScrollMode
    // in initState, skip the delayed setState to avoid blank flash.
    if (_isPortraitScrollMode == savedPortraitScrollMode) return;

    if (_supportsPortraitScrollMode(context) && savedPortraitScrollMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() {
        _isPortraitScrollMode = true;
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
    await prefs.setBool(_tabletLayoutModePrefKey, _isTabletLayoutMode);
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
      final nextOffset = (controller.offset + deltaPerTick).clamp(
        0.0,
        maxScroll,
      );

      if ((nextOffset - controller.offset).abs() < 0.1 ||
          nextOffset >= maxScroll) {
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
    final viewIndex = (controller.offset / pageExtent).floor().clamp(
      0,
      maxViewIndex,
    );

    return _getFirstPageIndexForView(
      viewIndex,
      context,
    ).clamp(0, pages.length - 1);
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
    if (_isAutoScrollEnabled) {
      _setAutoScrollEnabled(false);
    }
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
    if (_isAutoScrollEnabled) {
      _setAutoScrollEnabled(false);
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          isDarkMode: ThemeService.themeMode.value == ThemeMode.dark,
          onToggleDarkMode: (value) {
            ThemeService.setDarkMode(value);
          },
          isAutoScrollEnabled: _showAutoScrollBar,
          onToggleAutoScroll: _toggleAutoScrollFromMenu,
          isPortraitScrollMode: _isPortraitScrollMode,
          allowPortraitScrollMode: _supportsPortraitScrollMode(context),
          showTabletLayoutSetting: _shouldShowTabletLayoutSetting(context),
          isTabletLayoutMode: _isTabletLayoutMode,
          onToggleTabletLayoutMode: _setTabletLayoutMode,
          onTogglePortraitScrollMode: _setPortraitScrollMode,
          isHideBarEnabled: _isHideBarEnabled,
          onToggleHideBar: _toggleHideBar,
          isHifzModeEnabled: _isHifzModeEnabled,
          onToggleHifzMode: _toggleHifzMode,
          isFullScreenMode: _isFullScreenMode,
          onToggleFullScreenMode: _toggleFullScreenMode,
          onResetAllSettings: _resetAllSettings,
        ),
      ),
    ).then((_) {
      if (mounted) {
        _updateSystemUI();
      }
    });
  }

  String _getSurahNameForBookmark(ReaderBookmark bookmark) {
    final realPage = bookmark.page + 1;
    final ratio = (bookmark.sourceHeight != null && bookmark.sourceHeight! > 0)
        ? bookmark.y / bookmark.sourceHeight!
        : 0.0;

    String currentSurah = '';

    for (int i = 0; i < surahList.length; i++) {
      final surahPage = surahList[i]['page'] as int;
      final surahRatio =
          (surahList[i]['yOffsetRatio'] as num?)?.toDouble() ?? 0.0;

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
                // In Hifz mode the long press drives the reveal window
                // instead of the bookmark prompt.
                onLongPressStart: _isHifzModeEnabled
                    ? null
                    : (details) {
                        final box = context.findRenderObject() as RenderBox?;
                        if (box != null) {
                          final local = box.globalToLocal(
                            details.globalPosition,
                          );
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
                    child: HifzRevealView(
                      enabled: _isHifzModeEnabled,
                      child: ColoredBox(
                        color: const Color(0xFFFAF6EE),
                        child: Image(
                          image: _imageProviderForPage(pageIndex, imagePath),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          filterQuality: _pageQualityService.filterQuality,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              for (final bookmark in _bookmarks.values.where(
                (bookmark) => bookmark.page == pageIndex,
              ))
                Positioned(
                  left:
                      _draggingBookmarkOffsets[bookmark.slot]?.dx ??
                      bookmark.leftFor(constraints.maxWidth),
                  top:
                      _draggingBookmarkOffsets[bookmark.slot]?.dy ??
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
              // ---- Hide Bar Overlay (Reading Window) ----
              if (_isHideBarEnabled)
                ..._buildHideBarOverlay(constraints, baseHalf: 38),
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
              // In Hifz mode the long press drives the reveal window
              // instead of the bookmark prompt.
              onLongPressStart: _isHifzModeEnabled
                  ? null
                  : (details) {
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
                child: HifzRevealView(
                  enabled: _isHifzModeEnabled,
                  child: ColoredBox(
                    color: const Color(0xFFFAF6EE),
                    child: Image(
                      image: _imageProviderForPage(pageIndex, imagePath),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      filterQuality: _pageQualityService.filterQuality,
                    ),
                  ),
                ),
              ),
            ),
            for (final bookmark in _bookmarks.values.where(
              (bookmark) => bookmark.page == pageIndex,
            ))
              Positioned(
                left:
                    _draggingBookmarkOffsets[bookmark.slot]?.dx ??
                    bookmark.leftFor(constraints.maxWidth),
                top:
                    _draggingBookmarkOffsets[bookmark.slot]?.dy ??
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
            // ---- Hide Bar Overlay (Reading Window) ----
            if (_isHideBarEnabled)
              ..._buildHideBarOverlay(constraints, baseHalf: 38),
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
                  -1,
                  0,
                  0,
                  0,
                  255,
                  0,
                  -1,
                  0,
                  0,
                  255,
                  0,
                  0,
                  -1,
                  0,
                  255,
                  0,
                  0,
                  0,
                  1,
                  0,
                ])
              : const ColorFilter.mode(Color(0xFFFAF6EE), BlendMode.multiply),
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleReaderTap,
                child: ContinuousQuranView(
                  key: _continuousViewKey,
                  hifzModeEnabled: _isHifzModeEnabled,
                  pages: pages,
                  filterQuality: _pageQualityService.filterQuality,
                  pageImageProviderBuilder: (pageIndex) =>
                      _imageProviderForPage(pageIndex, pages[pageIndex]),
                  initialPage: _currentPage,
                  viewportWidth: constraints.maxWidth,
                  pageAspectRatio: _activePageAspectRatio,
                  autoScrollEnabled: _isAutoScrollEnabled,
                  autoScrollPixelsPerSecond:
                      _currentAutoScrollPixelsPerSecond(),
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
              if (_isHideBarEnabled)
                ..._buildHideBarOverlay(constraints, baseHalf: 60),
            ],
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
                  _getViewIndexForPage(_currentPage, context) * fixedPageExtent,
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
                scrollCacheExtent: ScrollCacheExtent.pixels(
                  fixedPageExtent * 2,
                ),
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
                final firstPageIndex = _getFirstPageIndexForView(
                  index,
                  context,
                );
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
                    valueListenable:
                        AudioService.instance.isRecitationBarVisible,
                    builder: (context, isVisible, _) {
                      return effectiveUseTwoPages
                          ? _buildTwoPageSpread(index, topAlign: isVisible)
                          : _buildSinglePage(
                              pages[index],
                              index,
                              alignment: isVisible
                                  ? Alignment.topCenter
                                  : Alignment.center,
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
                  -1,
                  0,
                  0,
                  0,
                  255,
                  0,
                  -1,
                  0,
                  0,
                  255,
                  0,
                  0,
                  -1,
                  0,
                  255,
                  0,
                  0,
                  0,
                  1,
                  0,
                ])
              : const ColorFilter.mode(Color(0xFFFAF6EE), BlendMode.multiply),
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
    final double menuHeight = isPhoneLandscape
        ? 122
        : (isPhonePortrait ? 130 : 260);
    final double autoScrollBottom = (_showIndex && !_hideBottomMenuTemporarily)
        ? menuHeight + safeBottom + 18
        : (isPhoneLandscape ? 14 : safeBottom + 14);
    final double bookmarkNoticeBottom = _showIndex
        ? menuHeight + safeBottom + 20
        : safeBottom + 20;
    final bool isRecitationBarVisible =
        AudioService.instance.isRecitationBarVisible.value;
    final double audioNoticeBottom = isRecitationBarVisible
        ? _recitationBarHeight + safeBottom + 14
        : bookmarkNoticeBottom;
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
    final Color hizbPopupTextColor = isDarkMode
        ? const Color(0xFFFFF4D6)
        : Colors.white;

    return Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: bookmarkHorizontalMargin,
          right: bookmarkHorizontalMargin,
          bottom: audioNoticeBottom,
          child: IgnorePointer(
            ignoring: !_showAudioPlaybackNotice,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _showAudioPlaybackNotice ? 1 : 0,
              child: Material(
                color: Colors.transparent,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWideScreen ? 22 : 16,
                        vertical: isWideScreen ? 16 : 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF15120B).withValues(alpha: 0.96)
                            : Colors.black.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDarkMode
                              ? const Color(0xFFD6B35D).withValues(alpha: 0.65)
                              : Colors.white.withValues(alpha: 0.18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            color: isDarkMode
                                ? const Color(0xFFD6B35D)
                                : Colors.white,
                            size: isWideScreen ? 24 : 20,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _audioPlaybackNoticeText,
                              textAlign: TextAlign.right,
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isWideScreen ? 18 : 14,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
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
                                color: isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
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
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: const Color(
                                                0xFF8D6E3F,
                                              ).withValues(alpha: 0.16),
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
                                color: isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
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
                ? MediaQuery.of(context).padding.top +
                      70 +
                      (_showHizbPopup ? 60 : 0)
                : MediaQuery.of(context).padding.top +
                      92 +
                      (_showHizbPopup ? 60 : 0),
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
                                  ? const Color(
                                      0xFF15120B,
                                    ).withValues(alpha: 0.97)
                                  : Colors.white.withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isDarkMode
                                    ? const Color(
                                        0xFFD6B35D,
                                      ).withValues(alpha: 0.72)
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
                                    style: IconButton.styleFrom(
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
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
                                    style: IconButton.styleFrom(
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
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
                                        color: Colors.black.withValues(
                                          alpha: 0.2,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    style: IconButton.styleFrom(
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
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
                                          style: IconButton.styleFrom(
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
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
                                          vertical: isPhonePortrait ? 6 : 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDarkMode
                                              ? const Color(
                                                  0xFFD6B35D,
                                                ).withValues(alpha: 0.16)
                                              : Colors.black.withValues(
                                                  alpha: 0.04,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: isDarkMode
                                                ? const Color(
                                                    0xFFD6B35D,
                                                  ).withValues(alpha: 0.35)
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
                                          style: IconButton.styleFrom(
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
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

    return ValueListenableBuilder<bool>(
      valueListenable: AudioService.instance.isRecitationBarVisible,
      builder: (context, isRecitationVisible, _) {
        final bgColor = Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A1A1F)
            : const Color(0xFFFAF6EE);

        final scaffold = Scaffold(
          backgroundColor: bgColor,
          resizeToAvoidBottomInset: false,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleReaderTap,
            child: Stack(
              children: [
                // 1 — Reader fills the whole screen
                Positioned.fill(
                  child: isPhoneLandscape
                      ? _buildLandscapeReader(isPhoneLandscape)
                      : _buildPortraitReader(useTwoPages),
                ),

                // 2 — Shared Overlays (bookmarks, index, etc.)
                Positioned.fill(child: _buildSharedOverlay(isPhoneLandscape)),

                // 3 — Recitation controls float over the page (the page stays
                // full-size and visible behind the translucent bar) instead of
                // being a bottomNavigationBar that shrinks the page.
                if (isRecitationVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _MeasureSize(
                      onChange: (size) {
                        if (_recitationBarHeight != size.height) {
                          setState(() => _recitationBarHeight = size.height);
                        }
                      },
                      child: _buildRecitationBottomBar(),
                    ),
                  ),
              ],
            ),
          ),
        );

        // SafeArea keeps the app clear of the system bars when they are
        // visible. In full screen mode the bars are hidden and the insets
        // are disabled so the whole screen shows the page.
        return Container(
          color: bgColor,
          child: SafeArea(
            left: !_isFullScreenMode,
            top: !_isFullScreenMode,
            right: !_isFullScreenMode,
            bottom: !_isFullScreenMode,
            child: Stack(
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
                // 3 — Top bar (slides in/out, respects camera notch)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  top: (!_hideTopBarTemporarily && _showIndex) ? 0 : -120,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {}, // Block tap propagation
                    onVerticalDragUpdate: (details) {
                      // Swiping up on the top bar hides the whole chrome (both
                      // bars move together).
                      if (details.primaryDelta! < -5) {
                        setState(() {
                          _showIndex = false;
                          _hideTopBarTemporarily = false;
                          _hideBottomMenuTemporarily = false;
                        });
                        _hideControlsTimer?.cancel();
                        _updateSystemUI();
                      }
                    },
                    child: TopOverlayBar(
                      show: !_hideTopBarTemporarily && _showIndex,
                      isSearching: _isSearching,
                      currentPage: _topBarCurrentPage,
                      isTwoPageView: useTwoPages,
                      getHizbNumber: _getHizbNumber,
                      getSurahName: _getSurahName,
                      onSettingsPressed: _openSettings,
                      isHideBarEnabled: _isHideBarEnabled,
                      onToggleHideBar: _toggleHideBar,
                      isFullScreenMode: _isFullScreenMode,
                      onToggleFullScreenMode: _toggleFullScreenMode,
                    ),
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
                    allowPortraitScrollMode: _supportsPortraitScrollMode(
                      context,
                    ),
                    showTabletLayoutSetting: _shouldShowTabletLayoutSetting(
                      context,
                    ),
                    isTabletLayoutMode: _isTabletLayoutMode,
                    // Anchor the action bar exactly on top of the recitation bar
                    // using its real measured height, so they stay perfectly flush
                    // (no gap, no overlap) in full screen, standard, and during
                    // transitions.
                    bottomOffset: isRecitationVisible
                        ? _recitationBarHeight
                        : 0,
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
                      // Dismissing the bottom menu hides the whole chrome (both
                      // bars move together).
                      setState(() {
                        _showIndex = false;
                        _hideTopBarTemporarily = false;
                        _hideBottomMenuTemporarily = false;
                      });
                      _hideControlsTimer?.cancel();
                      _updateSystemUI();
                    },
                    onPlayTapped: () {
                      _closeAutoScrollBar();
                      setState(() {
                        _showIndex = false;
                        _showSurahs = false;
                      });
                      _updateSystemUI();
                      AudioService.instance.playPage(
                        _topBarCurrentPage,
                        autoPlay: false,
                      );
                    },
                    onToggleDarkMode: (value) {
                      ThemeService.setDarkMode(value);
                    },
                    onToggleAutoScroll: (value) {
                      if (value &&
                          AudioService.instance.isRecitationBarVisible.value) {
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
                          _showIndex = false;
                          _showSurahs = false;
                          _isSearching = false;
                        }
                        if (shouldSwitchPortraitMode) {
                          _isPortraitScrollMode = true;
                        }
                      });
                      if (value) {
                        _setAutoScrollEnabled(true);
                      } else {
                        _closeAutoScrollBar();
                      }
                      _updateSystemUI();
                      if (shouldSwitchPortraitMode) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم تغيير الوضع من صفحات إلى تمرير'),
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
            ),
          ),
        );
      },
    );
  }

  void _showRecitationBarGuide() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode
        ? const Color(0xFF1E1A12)
        : const Color(0xFFF8F1DE);
    final titleColor = isDarkMode
        ? const Color(0xFFD6B35D)
        : const Color(0xFF8D6E3F);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
    final borderColor = isDarkMode
        ? const Color(0xFF53401F)
        : const Color(0xFFE2D2A5);
    bool doNotShowAgain = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.help_outline_rounded, color: titleColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  'شرح أزرار شريط التلاوة',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _guideRow(
                    Icons.close_rounded,
                    'إغلاق شريط التلاوة',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.skip_next_rounded,
                    'الآية السابقة',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.play_arrow_rounded,
                    'تشغيل / إيقاف مؤقت',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.skip_previous_rounded,
                    'الآية التالية',
                    textColor,
                    borderColor,
                  ),
                  _guideAssetRow(
                    'assets/images/icon_repeat_page.png',
                    'تكرار الصفحة (اضغط للتبديل)',
                    textColor,
                    borderColor,
                    iconScale: 1.3,
                  ),
                  _guideAssetRow(
                    'assets/images/icon_repeat_ayah.png',
                    'تكرار الآية (اضغط عدة مرات للتبديل)',
                    textColor,
                    borderColor,
                  ),
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
                child: Text(
                  'فهمت',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showHifzLensGuide() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode
        ? const Color(0xFF1E1A12)
        : const Color(0xFFF8F1DE);
    final titleColor = isDarkMode
        ? const Color(0xFFD6B35D)
        : const Color(0xFF8D6E3F);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
    final borderColor = isDarkMode
        ? const Color(0xFF53401F)
        : const Color(0xFFE2D2A5);
    bool doNotShowAgain = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                HifzLensIcon(color: titleColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  'شرح عدسة الإخفاء',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _guideRow(
                    Icons.touch_app_rounded,
                    'مرر إصبعك على الصفحة لكشف النص تحته فقط',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.psychology_rounded,
                    'اختبر حفظك سطراً سطراً دون رؤية النص كاملاً',
                    textColor,
                    borderColor,
                    iconWidget: HifzLensIcon(color: textColor, size: 18),
                  ),
                  _guideRow(
                    Icons.visibility_off_rounded,
                    'شريط الإخفاء يتوقف تلقائياً عند تفعيل العدسة',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.tap_and_play_rounded,
                    'المس الصفحة لمرة واحدة لإظهار قائمة الإعدادات',
                    textColor,
                    borderColor,
                  ),
                  const SizedBox(height: 16),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: CheckboxListTile(
                      value: doNotShowAgain,
                      onChanged: (value) =>
                          setState(() => doNotShowAgain = value ?? false),
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
                    await prefs.setBool(_hifzLensGuideDismissedPrefKey, true);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(
                  'فهمت',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showHideBarReaderGuide() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode
        ? const Color(0xFF1E1A12)
        : const Color(0xFFF8F1DE);
    final titleColor = isDarkMode
        ? const Color(0xFFD6B35D)
        : const Color(0xFF8D6E3F);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
    final borderColor = isDarkMode
        ? const Color(0xFF53401F)
        : const Color(0xFFE2D2A5);
    bool doNotShowAgain = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.visibility_off_rounded, color: titleColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  'شرح شريط الإخفاء',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _guideRow(
                    Icons.drag_handle_rounded,
                    'اسحب الإطار الذهبي لتحريك نافذة القراءة أعلى وأسفل',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.close_rounded,
                    'زر X لإغلاق شريط الإخفاء',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.flip_to_back_rounded,
                    'زر التبديل يعكس الوضع بين الإخفاء والكشف',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.headphones_rounded,
                    'أثناء التلاوة يتحرك الشريط تلقائياً ويتسع لسطرين',
                    textColor,
                    borderColor,
                  ),
                  const SizedBox(height: 16),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: CheckboxListTile(
                      value: doNotShowAgain,
                      onChanged: (value) =>
                          setState(() => doNotShowAgain = value ?? false),
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
                    await prefs.setBool(
                      _hideBarReaderGuideDismissedPrefKey,
                      true,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(
                  'فهمت',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFullScreenGuide() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode
        ? const Color(0xFF1E1A12)
        : const Color(0xFFF8F1DE);
    final titleColor = isDarkMode
        ? const Color(0xFFD6B35D)
        : const Color(0xFF8D6E3F);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
    final borderColor = isDarkMode
        ? const Color(0xFF53401F)
        : const Color(0xFFE2D2A5);
    bool doNotShowAgain = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.fullscreen_rounded, color: titleColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  'شرح وضع ملء الشاشة',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _guideRow(
                    Icons.fullscreen_rounded,
                    'يخفي شريط الحالة وأزرار التنقل للقراءة بلا تشتيت',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.swipe_rounded,
                    'اسحب من حافة الشاشة لإظهار أشرطة النظام مؤقتاً',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.touch_app_rounded,
                    'المس الصفحة لإظهار قائمة الأدوات والإعدادات',
                    textColor,
                    borderColor,
                  ),
                  _guideRow(
                    Icons.settings_rounded,
                    'للخروج: افتح الإعدادات وأوقف وضع ملء الشاشة',
                    textColor,
                    borderColor,
                  ),
                  const SizedBox(height: 16),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: CheckboxListTile(
                      value: doNotShowAgain,
                      onChanged: (value) =>
                          setState(() => doNotShowAgain = value ?? false),
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
                    await prefs.setBool(_fullScreenGuideDismissedPrefKey, true);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(
                  'فهمت',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _guideRow(
    IconData icon,
    String label,
    Color textColor,
    Color borderColor, {
    Widget? iconWidget,
  }) {
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
            child: iconWidget ?? Icon(icon, color: textColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Same as [_guideRow] but uses a PNG asset (tinted to match the text colour)
  /// instead of a built-in [IconData]. [iconScale] compensates for PNGs that
  /// carry extra transparent padding so they match the other rows visually.
  Widget _guideAssetRow(
    String asset,
    String label,
    Color textColor,
    Color borderColor, {
    double iconScale = 1.0,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: borderColor.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              asset,
              width: 20 * iconScale,
              height: 20 * iconScale,
              fit: BoxFit.contain,
              color: textColor,
              colorBlendMode: BlendMode.srcATop,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: pageAyahs.length,
                  itemBuilder: (context, index) {
                    final ayah = pageAyahs[index];
                    final isCurrent =
                        ayah.ayah == currentAyah.ayah &&
                        ayah.surah == currentAyah.surah;
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
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isCurrent
                                ? const Color(0xFFD6B35D)
                                : Theme.of(context).textTheme.bodyLarge?.color,
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
    final opacityService = RecitationBarOpacityService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([
        audio.isPlaying,
        audio.currentAyah,
        audio.pageRepeatMode,
        audio.pageRepeatCount,
        audio.repeatMode,
        audio.repeatCount,
        opacityService.opacity,
        opacityService.backgroundOpacity,
      ]),
      builder: (context, _) {
        // Single knob for all bar icon/button opacity: 1.0 = fully white, 0.0 = fully transparent.
        final iconOpacity = opacityService.opacity.value;
        final iconColor = Color.fromRGBO(255, 255, 255, iconOpacity);
        final backgroundOpacity = opacityService.backgroundOpacity.value;
        final isPlaying = audio.isPlaying.value;
        final currentAyah = audio.currentAyah.value;
        final repeatModeVal = audio.repeatMode.value;
        final pageRepeatModeVal = audio.pageRepeatMode.value;
        final isRepeating = repeatModeVal != AyahRepeatMode.off;
        final repeatLabel = audio.repeatLabel;
        final isPageRepeating = pageRepeatModeVal != AyahRepeatMode.off;
        final pageRepeatLabel = audio.pageRepeatLabel;

        final double systemBottom = MediaQuery.of(context).padding.bottom;
        // The bar floats over the page: a transparent backdrop keeps the
        // page text readable through it while the controls stay legible. The
        // GestureDetector absorbs taps so touching the bar doesn't toggle the
        // page chrome underneath.
        return GestureDetector(
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: backgroundOpacity),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
              border: const Border(
                top: BorderSide(color: Color(0xFFD4A946), width: 2.0),
              ),
            ),
            child: Stack(
              children: [
                // Subtle inner decorative line
                Positioned(
                  top: 3,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 0.5,
                    color: const Color(0xFFD4A946).withValues(alpha: 0.3),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: 6,
                    right: 6,
                    top: 16,
                    bottom: systemBottom > 0 ? systemBottom : 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // تكرار الصفحة
                      IconButton(
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          _resetHideTimer();
                          audio.cyclePageRepeatMode();
                        },
                        icon: SizedBox(
                          width: 42,
                          height: 34,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              // The icon stays white in every state; the badge below
                              // signals that page-repeat is active and how many times.
                              // This PNG has ~24% transparent padding around its glyph
                              // (unlike the ayah icon), so scale it up to match the
                              // visual size of the other bar icons.
                              Transform.scale(
                                scale: 1.3,
                                child: Image.asset(
                                  'assets/images/icon_repeat_page.png',
                                  width: 34,
                                  height: 30,
                                  fit: BoxFit.contain,
                                  color: iconColor,
                                  colorBlendMode: BlendMode.modulate,
                                ),
                              ),
                              if (isPageRepeating && pageRepeatLabel.isNotEmpty)
                                Positioned(
                                  right: -4,
                                  bottom: -5,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      pageRepeatLabel,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        tooltip: 'تكرار الصفحة',
                      ),

                      // السابق
                      IconButton(
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.skip_previous_rounded,
                          color: iconColor,
                          size: 36,
                        ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            currentAyah != null
                                ? 'آية ${currentAyah.ayah}'
                                : 'آية 1',
                            style: TextStyle(
                              color: iconColor,
                              fontSize: 15,
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
                            // Check if the user navigated to a different page while paused
                            if (!audio.isAudioOnPage(_topBarCurrentPage)) {
                              audio.playPage(_topBarCurrentPage);
                            } else {
                              audio.resume();
                            }
                          }
                        },
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: iconColor,
                            size: 40,
                          ),
                        ),
                      ),

                      // التالي
                      IconButton(
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.skip_next_rounded,
                          color: iconColor,
                          size: 36,
                        ),
                        onPressed: () {
                          _resetHideTimer();
                          audio.nextAyah();
                        },
                        tooltip: 'الآية التالية',
                      ),

                      // تكرار الآية
                      IconButton(
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          _resetHideTimer();
                          audio.cycleAyahRepeatMode();
                        },
                        icon: SizedBox(
                          width: 42,
                          height: 34,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              // The icon stays white in every state; the badge below
                              // signals that ayah-repeat is active and how many times.
                              Image.asset(
                                'assets/images/icon_repeat_ayah.png',
                                width: 34,
                                height: 30,
                                fit: BoxFit.contain,
                                color: iconColor,
                                colorBlendMode: BlendMode.modulate,
                              ),
                              if (isRepeating && repeatLabel.isNotEmpty)
                                Positioned(
                                  right: -4,
                                  bottom: -5,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      repeatLabel,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        tooltip: 'تكرار الآية',
                      ),

                      // إغلاق
                      IconButton(
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: iconColor,
                          size: 28,
                        ),
                        onPressed: () {
                          _resetHideTimer();
                          audio.stop();
                        },
                        tooltip: 'إغلاق',
                      ),

                      // مساعدة
                      IconButton(
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.help_outline_rounded,
                          color: iconColor,
                          size: 24,
                        ),
                        onPressed: () {
                          _resetHideTimer();
                          _showRecitationBarGuide();
                        },
                        tooltip: 'إرشادات',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Reports its child's rendered size after every layout pass so callers can
/// anchor sibling widgets flush against it. Used to keep the action bar exactly
/// on top of the recitation bar regardless of safe-area / full-screen changes.
class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;

  const _MeasureSize({required this.onChange, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_oldSize == newSize) return;
    _oldSize = newSize;
    // Defer the callback to avoid mutating widget state during layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
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
            border: Border(
              top: BorderSide(color: widget.borderColor, width: 2),
            ),
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
                        onPressed: _currentPage < 603
                            ? () => _goToPage(_currentPage + 1)
                            : null,
                        icon: Icon(
                          Icons.chevron_left_rounded,
                          color: widget.accentColor,
                        ),
                        iconSize: 22,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
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
                        onPressed: _currentPage > 0
                            ? () => _goToPage(_currentPage - 1)
                            : null,
                        icon: Icon(
                          Icons.chevron_right_rounded,
                          color: widget.accentColor,
                        ),
                        iconSize: 22,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
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
                        child: CircularProgressIndicator(
                          color: widget.borderColor,
                        ),
                      )
                    : _tafsirData.isEmpty
                    ? Center(
                        child: Text(
                          'لا يوجد تفسير لهذه الصفحة',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: widget.textColor,
                            fontSize: 18,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: _tafsirData.length,
                        separatorBuilder: (_, _) => const Divider(height: 32),
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

import 'dart:async'; // Quran Pages View

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent, RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart' show openFile, XTypeGroup;
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'widgets/quran/bookmark_picker_dialog.dart';
import 'widgets/quran/hifz_reveal_view.dart';
import 'continuous_quran_view.dart';
import 'models/reader_bookmark.dart';
import 'quran_constants.dart';
import 'quran_reading_coordinator.dart';
import 'services/background_playback_service.dart';
import 'services/page_color_service.dart';
import 'services/page_zoom_service.dart';
import 'services/keep_screen_awake_service.dart';
import 'services/margin_images_service.dart';
import 'services/high_quality_images_service.dart';
import 'services/page_quality_service.dart';
import 'services/recitation_bar_opacity_service.dart';

import 'services/app_update_service.dart';
import 'services/update_notification_service.dart';
import 'services/whats_new_service.dart';
import 'services/theme_service.dart';
import 'services/tafsir_service.dart';
import 'services/tafsir_edition_service.dart';
import 'services/audio_service.dart';
import 'services/reciter_service.dart';
import 'services/quran_json_service.dart';
import 'models/quran_page_data.dart';
import 'models/reciter.dart';
import 'thumn_data.dart';
import 'surah_data.dart';
import 'quran_index_page.dart';
import 'utils/copy_helper.dart';
import 'utils/responsive_helper.dart';
import 'utils/tablet_layout_helper.dart';
import 'widgets/menu/bottom_overlay_menu.dart';
import 'widgets/top_overlay_bar.dart';
import 'widgets/hifz_lens_icon.dart';
import 'widgets/settings/settings_page.dart';
import 'widgets/update_available_dialog.dart';
import 'widgets/whats_new_dialog.dart';
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
  static const ColorFilter _darkPageColorFilter = ColorFilter.matrix([
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
  ]);
  static const double _defaultPageAspectRatio = 720 / 1640;
  static const double _marginPageAspectRatio = 1178 / 1878;
  static const String _portraitScrollModePrefKey = 'portraitScrollMode';
  static const String _tabletLayoutModePrefKey = 'tabletLayoutMode';
  static const String _hifzModePrefKey = 'enableHifzMode';
  static const String _autoScrollSpeedPrefKey = 'autoScrollSpeed';
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
  // Pinch-to-zoom for the paged (flip) reader. While a page is zoomed in we lock
  // horizontal page-flipping so panning the zoomed page doesn't accidentally turn
  // the page; flipping resumes once the user pinches back to fit (scale 1).
  final TransformationController _pageZoomController =
      TransformationController();
  bool _isPageZoomed = false;
  // Hover state for the edge page-turn arrows (desktop/web only).
  bool _hoverLeftEdge = false;
  bool _hoverRightEdge = false;
  Offset? _lastDoubleTapPosition;
  ScrollController? _portraitAutoScrollController;
  late final QuranReadingCoordinator _readingCoordinator;
  final KeepScreenAwakeService _keepScreenAwakeService =
      KeepScreenAwakeService.instance;
  final MarginImagesService _marginImagesService = MarginImagesService.instance;
  final HighQualityImagesService _highQualityImagesService =
      HighQualityImagesService.instance;
  final PageQualityService _pageQualityService = PageQualityService.instance;
  final PageColorService _pageColorService = PageColorService.instance;

  /// The recitation bar's transport buttons (repeat/previous/next/close) are
  /// zero-padding, shrink-wrapped icon buttons — their tap target is exactly
  /// the icon's visual size (~24px), which is fine for a fingertip but very
  /// easy to miss with a mouse cursor on desktop web. Widen the invisible hit
  /// box on web only; native touch targets are unaffected.
  BoxConstraints get _barIconConstraints => kIsWeb
      ? const BoxConstraints(minWidth: 40, minHeight: 40)
      : const BoxConstraints();

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
  // True while the reader is gliding back into sync with the recitation. The
  // auto-scroll timer stays parked for the duration, otherwise its 16 ms
  // jumpTo would cancel the animation on the very next tick.
  bool _isCatchingUpToRecitation = false;
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
    HardwareKeyboard.instance.addHandler(_handleReaderKey);
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
    _pageColorService.selected.addListener(_handlePageColorChanged);
    // Use the page passed from SplashScreen so we never flash Al-Fatiha
    if (widget.initialPage > 0) {
      _readingCoordinator.setCurrentPage(widget.initialPage);
      _syncCurrentSurahForPage(widget.initialPage);
    }
    _portraitController = PageController(initialPage: widget.initialPage);
    _pageZoomController.addListener(_handlePageZoomChanged);
    PageZoomService.instance.enabled.addListener(_handlePageZoomSettingChanged);
    _marginImagesService.initialize();
    _highQualityImagesService.initialize();
    _pageQualityService.load();
    _pageColorService.load();

    // Set scroll mode immediately from SplashScreen to avoid delayed setState blank flash
    _isPortraitScrollMode = widget.initialPortraitScrollMode;
    _preferredPortraitScrollMode = widget.initialPortraitScrollMode;

    _loadReadingPreferences();
    _loadLastPage();
    _loadBookmark();
    _loadBookmarkGuidePreference();
    _checkForUpdate();
    _keepScreenAwakeService.enabled.addListener(_handleKeepScreenAwakeChanged);
    _setReadingMode(true);
    _keepScreenAwakeService.load().then((_) {
      if (!mounted) return;
      _handleKeepScreenAwakeChanged();
    });
    _resetHideTimer();

    QuranJsonService.loadQuranPages().then((data) {
      if (mounted) setState(() => _allQuranPages = data);
    });

    AudioService.instance.init();
    AudioService.instance.onPageChangeRequired = (pageIndex) {
      if (mounted) {
        _followRecitationToPage(pageIndex);
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
    HardwareKeyboard.instance.removeHandler(_handleReaderKey);
    _hideControlsTimer?.cancel();
    _hizbPopupTimer?.cancel();
    _sajdaPopupTimer?.cancel();
    _savePageTimer?.cancel();
    _audioPlaybackNoticeTimer?.cancel();
    _recitationBarHideTimer?.cancel();
    _portraitAutoScrollTimer?.cancel();
    _portraitAutoScrollResumeTimer?.cancel();
    _portraitAutoScrollController?.dispose();
    _pageZoomController.removeListener(_handlePageZoomChanged);
    _pageZoomController.dispose();
    PageZoomService.instance.enabled.removeListener(
      _handlePageZoomSettingChanged,
    );
    AudioService.instance.isPlaying.removeListener(_handleAudioPlaybackChanged);
    AudioService.instance.playbackNotice.removeListener(
      _handleAudioPlaybackNotice,
    );
    AudioService.instance.stop();
    _keepScreenAwakeService.enabled.removeListener(
      _handleKeepScreenAwakeChanged,
    );
    _setReadingMode(false);
    _marginImagesService.state.removeListener(_handleMarginImagesChanged);
    _highQualityImagesService.state.removeListener(
      _handleHighQualityImagesChanged,
    );
    _pageQualityService.level.removeListener(_handlePageQualityChanged);
    _pageColorService.selected.removeListener(_handlePageColorChanged);
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
      //
      // Never on the web: there "hidden" fires simply because the browser tab
      // lost focus (switching tabs, or another window covering it). Browsers
      // deliberately keep <audio> playing in a background tab and expose their
      // own media controls for it, so pausing here would break the normal,
      // expected behaviour of a web player. The background-playback opt-in
      // exists for the mobile media-notification flow and has no web analogue.
      if (!kIsWeb && !BackgroundPlaybackService.instance.enabled.value) {
        AudioService.instance.pause();
      }
      // Stop auto-scroll timer to save battery in background.
      _stopPortraitAutoScroll();
      // Pause any active downloads so they can resume later
      _marginImagesService.pauseDownload();
      // Decoded page bitmaps are by far the largest allocation in the app
      // (~4.7 MB each, ~8.8 MB in margin view; up to 150 MB retained). Holding
      // them while backgrounded — which happens for long stretches whenever
      // background recitation is on — makes the app a prime target for
      // Android's low-memory killer and iOS jetsam, and being killed mid-
      // recitation reads to the user as playback randomly stopping.
      //
      // clear() drops the retention pool only; pages currently on screen are
      // live images and survive, so resuming doesn't flash the blank page
      // background. Do NOT use clearLiveImages() here — that would force the
      // visible page to re-decode on every resume.
      PaintingBinding.instance.imageCache.clear();
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
    // Browsers require a user gesture before granting the Screen Wake Lock
    // API, so an automatic call here (e.g. right on page load) routinely
    // throws NotAllowedError on web — and wakelock_plus's web implementation
    // can additionally throw from a detached callback that a try/catch around
    // this await never sees. Skip it there entirely; keeping the screen awake
    // is a native-only nicety.
    if (kIsWeb) return;
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {}
  }

  void _handleKeepScreenAwakeChanged() {
    _setReadingMode(_keepScreenAwakeService.enabled.value);
  }

  bool _isPhoneLandscape(BuildContext context) {
    // On the web a desktop browser window is almost always wider than tall, so
    // its orientation reports as landscape. On a phone that means "held
    // sideways" and we force continuous-scroll, but on the web it's just a
    // normal window — don't force scroll there, let the reader stay in paged
    // mode (the user can still turn scroll on from settings).
    if (kIsWeb) return false;
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

  void _handlePageColorChanged() {
    if (!mounted) return;
    setState(() {});
  }

  ColorFilter _pageColorFilter(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return _darkPageColorFilter;
    }
    return _pageColorService.selected.value.lightModeFilter;
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

  /// True when the reader is serving page images from disk (`FileImage`) rather
  /// than bundled assets — i.e. margin view, or the level-3 high-fidelity pack.
  /// Disk-backed images decode noticeably slower, so the continuous view widens
  /// its auto-scroll look-ahead to keep them decoded before they scroll in.
  bool get _isServingDiskBackedPages {
    if (_isMarginImagesEnabled) return true;
    final hqState = _highQualityImagesService.state.value;
    return _pageQualityService.level.value >= PageQualityService.highFidelity &&
        hqState.isEnabled &&
        hqState.imagesDirectoryPath != null;
  }

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
    if (marginState.isEnabled) {
      if (kIsWeb) {
        // No local pack on web — stream the page from the R2 mirror.
        return wrap(
          NetworkImage(MarginImagesService.webPageUrl(pageIndex + 1)),
        );
      }
      if (marginState.imagesDirectoryPath != null) {
        final file = _downloadedPageFileForIndex(
          marginState.imagesDirectoryPath!,
          pageIndex + 1,
        );
        if (file != null) {
          return wrap(FileImage(file));
        }
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

  // Backups are a versioned JSON envelope so a future format change can be
  // detected instead of silently mis-parsed.
  static const String _bookmarkBackupApp = 'quran_reader_bookmarks';
  static const String _bookmarkBackupFileName = 'quran-bookmarks-backup.json';

  String _buildBookmarksBackupJson(Iterable<ReaderBookmark> items) {
    final envelope = {
      'app': _bookmarkBackupApp,
      'v': 1,
      'bookmarks': items.map((item) => item.toJson()).toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(envelope);
    // Escape non-ASCII (Arabic labels) as \uXXXX so the file is pure ASCII:
    // some share targets / save dialogs re-save the file assuming a
    // single-byte charset (Windows-1252) instead of UTF-8, which garbles raw
    // Arabic bytes. ASCII bytes decode identically under every charset, so
    // this makes the file immune to that regardless of where it happens.
    final buffer = StringBuffer();
    for (final unit in jsonStr.codeUnits) {
      if (unit > 126) {
        buffer.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }

  List<ReaderBookmark>? _parseBookmarksBackupJson(String raw) {
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      if (envelope['app'] != _bookmarkBackupApp) return null;
      final rawList = envelope['bookmarks'] as List<dynamic>;
      final result = <ReaderBookmark>[];
      for (final item in rawList) {
        try {
          result.add(ReaderBookmark.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // Skip a single malformed entry rather than failing the whole import.
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  int? _lowestFreeBookmarkSlot(Map<int, ReaderBookmark> bookmarks) {
    for (int slot = 1; slot <= BookmarkPickerDialog.maxSlots; slot++) {
      if (!bookmarks.containsKey(slot)) return slot;
    }
    return null;
  }

  /// Imported bookmarks never overwrite an existing slot: a slot that's
  /// already taken gets the imported bookmark re-numbered into the next free
  /// slot instead, so importing a friend's backup can't clobber your own.
  ({Map<int, ReaderBookmark> bookmarks, int added, int skipped})
  _mergeImportedBookmarks(List<ReaderBookmark> incoming) {
    final merged = Map<int, ReaderBookmark>.from(_bookmarks);
    int added = 0;
    int skipped = 0;
    for (final bookmark in incoming) {
      final fitsOwnSlot =
          bookmark.slot >= 1 &&
          bookmark.slot <= BookmarkPickerDialog.maxSlots &&
          !merged.containsKey(bookmark.slot);
      if (fitsOwnSlot) {
        merged[bookmark.slot] = bookmark;
        added++;
        continue;
      }
      final freeSlot = _lowestFreeBookmarkSlot(merged);
      if (freeSlot == null) {
        skipped++;
        continue;
      }
      merged[freeSlot] = bookmark.copyWith(slot: freeSlot);
      added++;
    }
    return (bookmarks: merged, added: added, skipped: skipped);
  }

  /// [XFile.fromData]'s `name` is ignored outside web (the file's `.name`
  /// getter derives from its path instead), so a real file with the desired
  /// name has to be written to disk there; web has no filesystem, so it must
  /// use `fromData` directly.
  Future<XFile> _writeBookmarksBackupFile(String jsonStr) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));
    if (kIsWeb) {
      return XFile.fromData(
        bytes,
        name: _bookmarkBackupFileName,
        mimeType: 'application/json',
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$_bookmarkBackupFileName');
    await file.writeAsBytes(bytes);
    return XFile(file.path, mimeType: 'application/json');
  }

  Future<void> _exportBookmarks() async {
    if (_bookmarks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد علامات لمشاركتها')));
      return;
    }
    final jsonStr = _buildBookmarksBackupJson(_bookmarks.values);
    final file = await _writeBookmarksBackupFile(jsonStr);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          subject: 'نسخة احتياطية لعلامات القرآن',
          downloadFallbackEnabled: true,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّرت مشاركة النسخة الاحتياطية')),
      );
    }
  }

  /// Saves the backup straight to a location the user picks (via the OS
  /// "Save As" dialog) instead of routing through a share target. Unlike
  /// [_writeBookmarksBackupFile]'s temp file, this lands outside the app's
  /// own storage, so — unlike the app's sandboxed storage — it survives an
  /// uninstall/reinstall.
  Future<void> _saveBookmarksLocally() async {
    if (_bookmarks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد علامات لحفظها')));
      return;
    }
    final jsonStr = _buildBookmarksBackupJson(_bookmarks.values);
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));
    try {
      final savedPath = await FileSaver.instance.saveAs(
        name: 'quran-bookmarks-backup',
        bytes: bytes,
        fileExtension: 'json',
        mimeType: MimeType.json,
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ النسخة الاحتياطية')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذّر حفظ الملف')));
    }
  }

  Future<Map<int, ReaderBookmark>?> _importBookmarksFlow() async {
    XFile? picked;
    try {
      picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Quran Bookmarks',
            extensions: ['json'],
            // iOS/macOS filter by UTI, not extension; without this,
            // file_selector_ios throws ArgumentError and the picker never
            // opens (surfaced as "تعذّر فتح الملف"). 'public.text' matches
            // file_selector's own example for opening .json files.
            uniformTypeIdentifiers: ['public.text'],
          ),
        ],
      );
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذّر فتح الملف')));
      return null;
    }
    if (picked == null || !mounted) return null;

    final incoming = _parseBookmarksBackupJson(await picked.readAsString());
    if (incoming == null || incoming.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ملف النسخة الاحتياطية غير صالح')),
      );
      return null;
    }

    final result = _mergeImportedBookmarks(incoming);
    setState(() {
      _bookmarks = result.bookmarks;
      _activeBookmarkSlot ??= result.bookmarks.keys.isEmpty
          ? null
          : (result.bookmarks.keys.toList()..sort()).first;
    });
    await _persistBookmarks();
    if (!mounted) return result.bookmarks;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.skipped == 0
              ? 'تم استيراد ${result.added} علامة'
              : 'تم استيراد ${result.added} علامة، وتخطي ${result.skipped} (لا توجد أماكن فارغة)',
        ),
      ),
    );
    return result.bookmarks;
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
        onExport: _exportBookmarks,
        onSaveLocally: _saveBookmarksLocally,
        onImport: _importBookmarksFlow,
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

  /// Keyboard page-turning (desktop/web). The mushaf reads right-to-left, so
  /// the LEFT arrow advances to the next (higher-numbered) page and the RIGHT
  /// arrow goes back — matching the chevron directions used elsewhere in the
  /// UI. PageUp/PageDown and space are accepted as aliases.
  /// Registered on [HardwareKeyboard] rather than a [Focus] node: the reader's
  /// PageView owns focus, so a wrapping Focus widget never sees these keys.
  /// Returns true when the key was consumed.
  bool _handleReaderKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // Don't steal keys while a search field, the surah list, or a dialog is up.
    // (_showIndex only controls chrome visibility, so it must NOT block keys.)
    if (_isSearching || _showSurahs) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    final key = event.logicalKey;

    // While the recitation bar is up, Up/Down step through ayat — the
    // keyboard equivalent of the bar's skip buttons.
    if (AudioService.instance.isRecitationBarVisible.value) {
      if (key == LogicalKeyboardKey.arrowDown) {
        AudioService.instance.nextAyah();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        AudioService.instance.previousAyah();
        return true;
      }
    }

    int delta;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      delta = 1;
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageUp) {
      delta = -1;
    } else {
      return false;
    }

    _stepPage(delta);
    return true;
  }

  /// Moves [delta] views forward (+1) or back (-1).
  ///
  /// Steps by one *view*, not one page: in the two-page spread a single page
  /// step lands on the same spread, and _setCurrentPage snaps back to that
  /// spread's first page — so paging by 1 would never move.
  void _stepPage(int delta) {
    final current = _readingCoordinator.currentPage;
    final targetView = _getViewIndexForPage(current, context) + delta;
    if (targetView < 0) return;
    final targetPage = _getFirstPageIndexForView(targetView, context);
    if (targetPage < 0 || targetPage > pages.length - 1) return;
    if (targetPage != current) _goToPage(targetPage + 1);
  }

  /// Whether stepping [delta] views from here would actually move — used to
  /// hide the hover arrow at the first/last page instead of showing a dud.
  bool _canStepPage(int delta) {
    final current = _readingCoordinator.currentPage;
    final targetView = _getViewIndexForPage(current, context) + delta;
    if (targetView < 0) return false;
    final targetPage = _getFirstPageIndexForView(targetView, context);
    return targetPage >= 0 &&
        targetPage <= pages.length - 1 &&
        targetPage != current;
  }

  /// Edge hover-zone that reveals a page-turn arrow (desktop/web only — there
  /// is no hover on touch, so these never appear on phones). [delta] is +1 for
  /// the next page and -1 for the previous one; in this right-to-left mushaf
  /// that puts "next" on the LEFT edge, matching the arrow keys and the
  /// chevrons used elsewhere in the UI.
  Widget _buildHoverPageArrow({required bool isLeftEdge}) {
    final int delta = isLeftEdge ? 1 : -1;
    final bool hovered = isLeftEdge ? _hoverLeftEdge : _hoverRightEdge;
    final bool enabled = _canStepPage(delta);

    return Positioned(
      left: isLeftEdge ? 0 : null,
      right: isLeftEdge ? null : 0,
      top: 0,
      bottom: 0,
      width: 96,
      child: MouseRegion(
        opaque: false,
        onEnter: (_) => setState(
          () => isLeftEdge ? _hoverLeftEdge = true : _hoverRightEdge = true,
        ),
        onExit: (_) => setState(
          () => isLeftEdge ? _hoverLeftEdge = false : _hoverRightEdge = false,
        ),
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: IgnorePointer(
          // Only the arrow itself is clickable; the rest of the strip must let
          // taps through to the page (bookmarks, ayah selection, …).
          ignoring: !enabled,
          child: Align(
            alignment: Alignment.center,
            child: AnimatedOpacity(
              opacity: hovered && enabled ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                onTap: enabled ? () => _stepPage(delta) : null,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.38),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(
                    isLeftEdge
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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

  /// Every selectable auto-scroll speed, slowest first, mapped to its scroll
  /// rate in logical pixels per second.
  ///
  /// The steps below 0.5 exist for recitation: a murattal reciter can spend
  /// several minutes on one page, and readers following along had to keep
  /// stopping the scroll by hand because even the old slowest step outran
  /// them. 0.2 crawls a phone page in roughly three and a half minutes.
  // Not const: Dart rejects double keys in a const map.
  static final Map<double, double> _autoScrollSpeeds = {
    0.2: 4,
    0.3: 5.5,
    0.4: 7,
    0.5: 9,
    0.75: 11,
    1.0: 14,
    1.5: 20,
    2.0: 28,
    2.5: 36,
    3.0: 44,
  };

  double _currentAutoScrollPixelsPerSecond() =>
      _autoScrollSpeeds[_autoScrollSpeedMultiplier] ?? 14;

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

    // Auto-scroll must keep the screen on regardless of the user's wakelock
    // preference — a dimmed/locked screen would interrupt continuous reading.
    if (value) {
      _setReadingMode(true);
    } else {
      _setReadingMode(_keepScreenAwakeService.enabled.value);
    }
  }

  void _setAutoScrollSpeedMultiplier(double value) {
    if (_autoScrollSpeedMultiplier == value) return;
    setState(() {
      _autoScrollSpeedMultiplier = value;
    });
    _saveAutoScrollSpeed();
  }

  Future<void> _saveAutoScrollSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_autoScrollSpeedPrefKey, _autoScrollSpeedMultiplier);
  }

  static final List<double> _allowedSpeeds = _autoScrollSpeeds.keys.toList();

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
      _autoScrollSpeedPrefKey,
      _fullScreenModePrefKey,
      KeepScreenAwakeService.prefKey,
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
    await _pageColorService.reset();
    await _keepScreenAwakeService.setEnabled(true);
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

    // Finding the speed that matches your reciter takes a few taps, so it is
    // remembered instead of resetting to 1× every launch.
    final savedSpeed = prefs.getDouble(_autoScrollSpeedPrefKey);
    if (savedSpeed != null && _autoScrollSpeeds.containsKey(savedSpeed)) {
      _autoScrollSpeedMultiplier = savedSpeed;
    }

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
    if (!_isAutoScrollEnabled || _isCatchingUpToRecitation) return;
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
    if (!_isAutoScrollEnabled || _isCatchingUpToRecitation) return;

    const frameInterval = Duration(milliseconds: 16);
    final deltaPerTick =
        _currentAutoScrollPixelsPerSecond() *
        (frameInterval.inMilliseconds / 1000);

    // The target offset is carried across ticks rather than re-read from the
    // controller as "offset + delta". At the slow speeds a tick advances a
    // fraction of a pixel, and the old code read that as "the list refused to
    // move" and stopped the scroll outright.
    double target = controller.hasClients ? controller.offset : 0.0;

    _portraitAutoScrollTimer = Timer.periodic(frameInterval, (_) {
      final controller = _portraitAutoScrollController;
      if (!mounted ||
          controller == null ||
          !_isAutoScrollEnabled ||
          !controller.hasClients) {
        _stopPortraitAutoScroll();
        return;
      }

      // Re-anchor when something else moved the list — a drag, or the
      // recitation jumping to the page it just reached.
      if ((target - controller.offset).abs() > 1.0) {
        target = controller.offset;
      }

      final maxScroll = controller.position.maxScrollExtent;
      if (controller.offset >= maxScroll) {
        _setAutoScrollEnabled(false);
        return;
      }

      target = (target + deltaPerTick).clamp(0.0, maxScroll);
      controller.jumpTo(target);
    });
  }

  /// Moves the reader onto the page the recitation just reached.
  ///
  /// Without auto-scroll this is a plain page turn. With auto-scroll running
  /// the reader is already gliding through the mushaf and tends to hold the
  /// ayah being recited near the middle of the screen — so snapping the new
  /// page's top edge to the top of the viewport throws that framing away at
  /// every single page boundary. Instead the scroll is left completely alone
  /// while the new page's first line is anywhere on screen (half a screen of
  /// slack either side of centre), and only a real desync — a full page or
  /// more adrift — is corrected, by gliding that first line back to the middle
  /// rather than by jumping.
  void _followRecitationToPage(int pageIndex) {
    if (!_isAutoScrollEnabled) {
      _goToPage(pageIndex + 1);
      return;
    }

    if (_isPhoneLandscape(context)) {
      final handled =
          _continuousViewKey.currentState?.followRecitationToPage(pageIndex) ??
          false;
      if (!handled) {
        _goToPage(pageIndex + 1);
        return;
      }
      _setCurrentPage(pageIndex, showHizbPopup: true);
      return;
    }

    final controller = _portraitAutoScrollController;
    final pageExtent = _portraitAutoScrollViewportHeight;
    if (controller == null ||
        !controller.hasClients ||
        pageExtent == null ||
        pageExtent <= 0) {
      _goToPage(pageIndex + 1);
      return;
    }

    final double pageTop =
        _getViewIndexForPage(pageIndex, context) * pageExtent;
    final double offset = controller.offset;

    _setCurrentPage(pageIndex, showHizbPopup: true);
    _portraitScrollCurrentPage = pageIndex;

    // The page's first line is somewhere on screen — the reader can see where
    // the recitation is, so don't touch the scroll.
    if (offset >= pageTop - pageExtent && offset <= pageTop) return;

    _catchUpToRecitation(
      controller,
      (pageTop - pageExtent / 2).clamp(
        0.0,
        controller.position.maxScrollExtent,
      ),
    );
  }

  void _catchUpToRecitation(ScrollController controller, double target) {
    _portraitAutoScrollResumeTimer?.cancel();
    _stopPortraitAutoScroll();
    _isCatchingUpToRecitation = true;

    controller
        .animateTo(
          target,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        )
        .whenComplete(() {
          _isCatchingUpToRecitation = false;
          if (!mounted || !_isAutoScrollEnabled) return;
          final extent = _portraitAutoScrollViewportHeight;
          if (extent != null) _syncPortraitAutoScroll(extent);
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

  /// Startup update check. Runs off the critical launch path (fire-and-forget),
  /// stays silent when up to date / offline, and surfaces a given version only
  /// once unless it's marked mandatory. Honors the user's in-app vs.
  /// notification delivery preference (default: in-app only).
  ///
  /// Shows at most one popup per launch: the local "what's new" for changes
  /// bundled in the currently installed build takes priority; the network
  /// "update available" check (for a *newer*, not-yet-installed release) only
  /// runs afterwards, and only if "what's new" didn't already show, so the two
  /// never stack on top of each other.
  Future<void> _checkForUpdate() async {
    try {
      final shownWhatsNew = await _maybeShowWhatsNew();
      if (shownWhatsNew || !mounted) return;
      await _maybeShowUpdateAvailable();
    } catch (_) {
      // An update check must never disrupt the app; swallow any failure.
    }
  }

  /// Shows the local "what's new" popup once per build. Returns true if it was
  /// shown (so the caller can skip the network update check this launch).
  Future<bool> _maybeShowWhatsNew() async {
    if (!await WhatsNewService.instance.shouldShow()) return false;
    if (!mounted) return false;

    // Let the splash→reader transition finish before interrupting with a
    // dialog, so it doesn't fight the animation.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;

    await WhatsNewService.instance.markSeen();
    if (!mounted) return false;
    await WhatsNewDialog.show(context, WhatsNewService.currentReleaseChanges);
    return true;
  }

  Future<void> _maybeShowUpdateAvailable() async {
    final info = await AppUpdateService.instance.fetchIfUpdateAvailable();
    if (info == null || !mounted) return;
    if (!await AppUpdateService.instance.shouldSurface(info)) return;
    if (!mounted) return;

    // Let the splash→reader transition finish so the dialog lands on a
    // settled screen instead of fighting the animation.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

    await AppUpdateService.instance.markSurfaced(info);

    if (AppUpdateService.instance.notifyMode.value ==
        UpdateNotifyMode.notification) {
      await UpdateNotificationService.instance.showUpdateNotification(
        title: 'يوجد تحديث جديد',
        body: 'الإصدار ${info.latestVersion} متوفر الآن. اضغط للتحديث.',
        storeUrl: info.storeUrl,
      );
    }

    if (!mounted) return;
    await UpdateAvailableDialog.show(context, info);
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
          colorFilter: _pageColorFilter(context),
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
                  diskBackedImages: _isServingDiskBackedPages,
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

  /// Tracks whether the paged reader is currently zoomed in (scale > 1) so we can
  /// lock/unlock page-flipping accordingly.
  void _handlePageZoomChanged() {
    final zoomed = _pageZoomController.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _isPageZoomed && mounted) {
      setState(() => _isPageZoomed = zoomed);
    }
  }

  /// Resets any active page zoom back to fit (scale 1).
  void _resetPageZoom() {
    if (_pageZoomController.value != Matrix4.identity()) {
      _pageZoomController.value = Matrix4.identity();
    }
  }

  /// If the user disables zoom from Advanced Settings while a page is zoomed
  /// in, snap back to fit so page-flipping (which locks while zoomed) isn't
  /// left stuck.
  void _handlePageZoomSettingChanged() {
    if (!PageZoomService.instance.enabled.value) {
      _resetPageZoom();
    }
  }

  /// Double-tap: zoom out to fit if already zoomed, otherwise zoom in to 2.5×
  /// centred on the tapped point (like a photo viewer). InteractiveViewer clamps
  /// the result so the page keeps covering the viewport.
  void _togglePageZoom() {
    if (_isPageZoomed) {
      _resetPageZoom();
      return;
    }
    const double scale = 2.5;
    final Offset p = _lastDoubleTapPosition ?? Offset.zero;
    _pageZoomController.value = Matrix4.identity()
      ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
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
              // Lock flipping while a page is zoomed in so panning the zoomed
              // page doesn't turn the page; pinch back to fit to flip again.
              physics: _isPageZoomed
                  ? const NeverScrollableScrollPhysics()
                  : null,
              itemCount: effectiveUseTwoPages
                  ? (pages.length / 2).ceil()
                  : pages.length,
              onPageChanged: (index) {
                // Any lingering zoom is dropped when the page actually changes.
                _resetPageZoom();
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
                final Widget pageContent = ValueListenableBuilder<bool>(
                  valueListenable: AudioService.instance.isRecitationBarVisible,
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
                );

                return ValueListenableBuilder<bool>(
                  valueListenable: PageZoomService.instance.enabled,
                  builder: (context, zoomEnabled, child) {
                    if (!zoomEnabled) {
                      // Zoom disabled in Advanced Settings: plain page, no pinch,
                      // no double-tap-zoom, flipping never gets locked.
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _handleReaderTap,
                        child: child!,
                      );
                    }
                    final Widget page = InteractiveViewer(
                      // Shared controller: only the on-screen page is
                      // interactive, and flipping is locked while zoomed, so a
                      // single controller is safe and lets us track scale to
                      // lock/unlock the PageView.
                      transformationController: _pageZoomController,
                      minScale: 1,
                      maxScale: 5,
                      // Pan ONLY while actually zoomed in. At scale 1 there is
                      // nothing to pan, and leaving pan enabled makes
                      // InteractiveViewer's recognizer claim horizontal drags
                      // before the PageView can — which silently breaks
                      // page-flipping with a mouse on the web. Pinch/double-tap
                      // zoom still work (scaleEnabled stays on).
                      panEnabled: _isPageZoomed,
                      child: child!,
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleReaderTap,
                      // Double-tap toggles zoom (out to fit, or in to 2.5×)
                      // like a photo viewer. Kept lightweight so single-tap
                      // stays responsive.
                      onDoubleTapDown: (details) =>
                          _lastDoubleTapPosition = details.localPosition,
                      onDoubleTap: _togglePageZoom,
                      child: page,
                    );
                  },
                  child: pageContent,
                );
              },
            ),
          );
        }

        return ColorFiltered(
          colorFilter: _pageColorFilter(context),
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
    final bool isRecitationBarVisible =
        AudioService.instance.isRecitationBarVisible.value;
    // Auto-scroll and the recitation run independently, so both bars can be up
    // at once. The auto-scroll bar stacks on top of the recitation bar (which
    // already covers the system inset) instead of hiding behind it.
    final double autoScrollInset = isRecitationBarVisible ? 0.0 : safeBottom;
    final double autoScrollBottom =
        (isRecitationBarVisible ? _recitationBarHeight : 0.0) +
        ((_showIndex && !_hideBottomMenuTemporarily)
            ? menuHeight + autoScrollInset + 18
            : (isPhoneLandscape ? 14 : autoScrollInset + 14));
    final double bookmarkNoticeBottom = _showIndex
        ? menuHeight + safeBottom + 20
        : safeBottom + 20;
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
              // The recitation bar below already clears the system inset.
              bottom: !isRecitationBarVisible,
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
                      // Auto-scroll is deliberately left running: the two are
                      // independent, and readers pair them to follow along.
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

                // Edge hover arrows for page turning. Last in the Stack so
                // they sit above the page, but they are only visible while the
                // pointer is over the edge — and never on touch devices, which
                // have no hover. Suppressed in scroll mode (no pages to flip),
                // while zoomed (flipping is locked), and behind overlays.
                if (!_isPortraitScrollMode &&
                    !_showAutoScrollBar &&
                    !_isPageZoomed &&
                    !_isSearching &&
                    !_showSurahs) ...[
                  _buildHoverPageArrow(isLeftEdge: true),
                  _buildHoverPageArrow(isLeftEdge: false),
                ],
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
                  _guideRow(
                    Icons.tune_rounded,
                    'خيارات التلاوة: اختيار القارئ، تكرار الثمن كاملاً، تكرار مقطع تختاره، وسرعة التلاوة',
                    textColor,
                    borderColor,
                    highlightColor: titleColor,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showTilawahOptionsSheet();
                    },
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

  /// Decides what a tap on the تكرار الثمن tile does:
  ///   * If thumn repeat is already active, just cycle it (2×→3×→∞→off).
  ///   * If engaging while paused AND the visible page has more than one thumn
  ///     start, show the "اختر الثمن" chooser so the user picks which one.
  ///   * Otherwise engage directly (the service picks by playing ayah / the
  ///     visible page's single thumn).
  void _handleThumnRepeatTap() {
    final audio = AudioService.instance;
    final engaging = audio.thumnRepeatMode.value == AyahRepeatMode.off;
    final paused = !audio.isPlaying.value;
    if (engaging && paused) {
      final onPage = audio.thumnsStartingOnPage(_topBarCurrentPage);
      if (onPage.length > 1) {
        _showThumnChooser(onPage);
        return;
      }
    }
    audio.cycleThumnRepeatMode(visiblePageIndex: _topBarCurrentPage);
  }

  /// Small chooser shown when the visible page has two thumn starts. Picking
  /// one engages repeat for that exact thumn.
  void _showThumnChooser(List<ThumnEntry> options) {
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
    const accentColor = Color(0xFFD2B97E);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.repeat_rounded, color: titleColor, size: 22),
              const SizedBox(width: 8),
              Text(
                'اختر الثمن',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.pop(ctx);
                      _resetHideTimer();
                      AudioService.instance.startThumnRepeatAt(entry);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: Text(
                        entry.text,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _surahName(int surah) => surahList[surah - 1]['name'] as String;

  /// Live one-line status of the active repeat section — which ayat, and which
  /// pass is playing now. Reads «البقرة 1-5 · التكرار 2/3» inside one surah, or
  /// «الفاتحة 3 ← البقرة 4 · التكرار 2/3» when the section crosses surahs.
  String _rangeStatusLabel(AyahRange range) {
    final audio = AudioService.instance;
    final pass = audio.rangeRepeatDone.value + 1;
    final total = audio.rangeRepeatMode.value == AyahRepeatMode.infinite
        ? '∞'
        : '${audio.rangeRepeatCount.value}';
    final where = range.isSingleSurah
        ? '${_surahName(range.startSurah)} '
              '${range.startAyah}-${range.endAyah}'
        : '${_surahName(range.startSurah)} ${range.startAyah}'
              ' ← ${_surahName(range.endSurah)} ${range.endAyah}';
    return '$where · التكرار $pass/$total';
  }

  /// Highest ayah number available for [surah]. Read from the page data (the
  /// mushaf's own numbering); falls back to the index table if it isn't loaded.
  int _maxAyahForSurah(int surah) {
    final fromPages = AudioService.instance.ayahCountForSurah(surah);
    if (fromPages > 0) return fromPages;
    return surahList[surah - 1]['ayahs'] as int;
  }

  /// The last ayah of [surah] printed on [pageIndex] at or after [fromAyah] —
  /// used to default a section to "the rest of this surah on this page".
  int _sectionEndOnPage(int pageIndex, int surah, int fromAyah) {
    final onPage = AudioService.instance
        .getAyahsForPage(pageIndex)
        .where((a) => a.surah == surah && a.ayah >= fromAyah)
        .toList();
    return onPage.isEmpty ? fromAyah : onPage.last.ayah;
  }

  /// The "تكرار مقطع" picker: choose where the section starts (surah + ayah) and
  /// where it ends (surah + ayah), pick how many times it should repeat, and the
  /// reader jumps there and recites only that section. The two ends may sit in
  /// different surahs (e.g. الفاتحة 3 → البقرة 4).
  ///
  /// The ordering is enforced by what the lists *offer*, not by validation after
  /// the fact: the "إلى" surah list starts at the chosen "من" surah, and its ayah
  /// list starts at the chosen "من" ayah whenever both ends are in the same
  /// surah. So an end that precedes the start can't be selected at all, and
  /// there is no error state to explain.
  ///
  /// It opens pre-filled with what's on screen — the surah being recited (or the
  /// visible page's first surah) and that page's portion of it — so the common
  /// case is one tap on تشغيل المقطع. [onStarted] lets the caller close the
  /// options sheet once a section is armed, revealing the page underneath.
  void _showRangeRepeatPicker({VoidCallback? onStarted}) {
    final audio = AudioService.instance;
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
    final subTextColor = textColor.withValues(alpha: 0.6);
    const accentColor = Color(0xFFD2B97E);

    // ── Seed the picker ──
    // An armed section wins (so re-opening shows what's running); otherwise
    // start from the ayah being recited on the visible page, falling back to
    // that page's first ayah when nothing is playing.
    final active = audio.repeatRange.value;
    int fromSurah;
    int fromAyah;
    if (active != null) {
      fromSurah = active.startSurah;
      fromAyah = active.startAyah;
    } else {
      final playing = audio.currentAyah.value;
      final pageAyahs = audio.getAyahsForPage(_topBarCurrentPage);
      if (playing != null && audio.isAudioOnPage(_topBarCurrentPage)) {
        fromSurah = playing.surah;
        fromAyah = playing.ayah;
      } else if (pageAyahs.isNotEmpty) {
        fromSurah = pageAyahs.first.surah;
        fromAyah = pageAyahs.first.ayah;
      } else {
        fromSurah = 1;
        fromAyah = 1;
      }
    }
    if (fromAyah > _maxAyahForSurah(fromSurah)) {
      fromAyah = _maxAyahForSurah(fromSurah);
    }
    // Default end: the rest of this surah on the visible page — a section the
    // size of what the reader can actually see.
    int toSurah = active?.endSurah ?? fromSurah;
    int toAyah =
        active?.endAyah ??
        _sectionEndOnPage(_topBarCurrentPage, fromSurah, fromAyah);

    final wasActive = audio.rangeRepeatMode.value != AyahRepeatMode.off;
    AyahRepeatMode mode = audio.rangeRepeatMode.value == AyahRepeatMode.infinite
        ? AyahRepeatMode.infinite
        : AyahRepeatMode.count;
    int count = wasActive ? audio.rangeRepeatCount.value : 3;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setPickerState) {
          Widget label(String text) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              text,
              style: TextStyle(
                color: subTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          );

          Widget dropdownFrame({required Widget child}) => Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: DropdownButtonHideUnderline(child: child),
          );

          // Keeps the four selections a valid forward-running section. Called
          // after every change, so the invariant «end >= start» holds at all
          // times and the dropdowns below always contain their own value.
          void normalize() {
            fromAyah = fromAyah.clamp(1, _maxAyahForSurah(fromSurah));
            if (toSurah < fromSurah) toSurah = fromSurah;
            toAyah = toAyah.clamp(1, _maxAyahForSurah(toSurah));
            if (toSurah == fromSurah && toAyah < fromAyah) toAyah = fromAyah;
          }

          Widget ayahDropdown({
            required int value,
            required int min,
            required int max,
            required ValueChanged<int> onChanged,
          }) => dropdownFrame(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              menuMaxHeight: 320,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: titleColor,
                size: 20,
              ),
              dropdownColor: bgColor,
              borderRadius: BorderRadius.circular(12),
              items: [
                for (int n = min; n <= max; n++)
                  DropdownMenuItem(
                    value: n,
                    child: Text(
                      '$n',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          );

          // [min] is 1 for the "من" side and the chosen start surah for the
          // "إلى" side, so earlier surahs simply aren't in the list.
          Widget surahDropdown({
            required int value,
            required int min,
            required ValueChanged<int> onChanged,
          }) => dropdownFrame(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              menuMaxHeight: 320,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: titleColor,
                size: 20,
              ),
              dropdownColor: bgColor,
              borderRadius: BorderRadius.circular(12),
              items: [
                for (int n = min; n <= 114; n++)
                  DropdownMenuItem(
                    value: n,
                    child: Text(
                      '$n. ${_surahName(n)}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          );

          // One labelled surah+ayah pair — the "من" and "إلى" rows are identical
          // in shape, only their allowed minimums differ.
          Widget endpointRow({
            required String heading,
            required int surah,
            required int ayah,
            required int minSurah,
            required int minAyah,
            required ValueChanged<int> onSurahChanged,
            required ValueChanged<int> onAyahChanged,
          }) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label(heading),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: surahDropdown(
                      value: surah,
                      min: minSurah,
                      onChanged: onSurahChanged,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ayahDropdown(
                      value: ayah,
                      min: minAyah,
                      max: _maxAyahForSurah(surah),
                      onChanged: onAyahChanged,
                    ),
                  ),
                ],
              ),
            ],
          );

          Widget countChip(String text, bool selected, VoidCallback onTap) =>
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: onTap,
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? accentColor.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: selected ? accentColor : borderColor,
                        width: selected ? 1.6 : 1,
                      ),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        color: selected ? accentColor : subTextColor,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.segment_rounded, color: titleColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'تكرار مقطع',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      endpointRow(
                        heading: 'من: السورة والآية',
                        surah: fromSurah,
                        ayah: fromAyah,
                        minSurah: 1,
                        minAyah: 1,
                        onSurahChanged: (v) => setPickerState(() {
                          // A new start surah re-seeds the section to that
                          // surah's opening page, so both ends stay sensible.
                          final firstPage = audio.pageIndexForAyah(v, 1);
                          fromSurah = v;
                          fromAyah = 1;
                          toSurah = v;
                          toAyah = firstPage >= 0
                              ? _sectionEndOnPage(firstPage, v, 1)
                              : 1;
                          normalize();
                        }),
                        onAyahChanged: (v) => setPickerState(() {
                          fromAyah = v;
                          normalize();
                        }),
                      ),
                      const SizedBox(height: 14),
                      endpointRow(
                        heading: 'إلى: السورة والآية',
                        surah: toSurah,
                        ayah: toAyah,
                        minSurah: fromSurah,
                        // Within the same surah the end can't precede the start;
                        // in a later surah every ayah is fair game.
                        minAyah: toSurah == fromSurah ? fromAyah : 1,
                        onSurahChanged: (v) => setPickerState(() {
                          toSurah = v;
                          normalize();
                        }),
                        onAyahChanged: (v) => setPickerState(() {
                          toAyah = v;
                          normalize();
                        }),
                      ),
                      const SizedBox(height: 14),
                      label('عدد مرات التكرار'),
                      Row(
                        children: [
                          for (final option in const [2, 3, 5, 7]) ...[
                            countChip(
                              '$option×',
                              mode == AyahRepeatMode.count && count == option,
                              () => setPickerState(() {
                                mode = AyahRepeatMode.count;
                                count = option;
                              }),
                            ),
                            const SizedBox(width: 6),
                          ],
                          countChip(
                            '∞',
                            mode == AyahRepeatMode.infinite,
                            () => setPickerState(
                              () => mode = AyahRepeatMode.infinite,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'يُنتقل إلى صفحة بداية المقطع ويُتلى وحده، ثم تتابع '
                        'التلاوة بعد انتهاء التكرار.',
                        style: TextStyle(color: subTextColor, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                if (wasActive)
                  TextButton(
                    onPressed: () {
                      audio.cancelRangeRepeat();
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'إيقاف التكرار',
                      style: TextStyle(
                        color: subTextColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'إلغاء',
                    style: TextStyle(
                      color: subTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: accentColor.withValues(alpha: 0.18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: accentColor, width: 1.4),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _resetHideTimer();
                    onStarted?.call();
                    audio.startRangeRepeat(
                      startSurah: fromSurah,
                      startAyah: fromAyah,
                      endSurah: toSurah,
                      endAyah: toAyah,
                      mode: mode,
                      count: count,
                    );
                  },
                  child: Text(
                    'تشغيل المقطع',
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The Tilawah options sheet reached from the tune (⋯) button on the
  /// recitation bar. Groups the "set-and-forget" choices — reciter (القارئ),
  /// repeat-whole-thumn (تكرار الثمن), repeat a chosen passage (تكرار مقطع) and
  /// playback speed (سرعة التلاوة) — plus a link to the button guide, so the
  /// frequently-tapped transport controls on the bar itself stay uncluttered.
  void _showTilawahOptionsSheet() {
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
    final subTextColor = textColor.withValues(alpha: 0.6);
    const accentColor = Color(0xFFD2B97E);

    final audio = AudioService.instance;
    final reciterService = ReciterService.instance;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        // Anchors the pop-up vertical speed picker to the speed tile.
        final speedTileKey = GlobalKey();
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Grab handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: borderColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Sheet title, with an explicit close (X) button. Closing
                      // the sheet only pops this route — it never touches audio,
                      // so Tilawah mode stays active (only the إغلاق button on
                      // the recitation bar ends it).
                      Row(
                        children: [
                          IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.close_rounded,
                              color: subTextColor,
                              size: 22,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'إغلاق',
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                'خيارات التلاوة',
                                style: TextStyle(
                                  color: titleColor,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          // Balances the X button width so the title stays centered.
                          const SizedBox(width: 32),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── القارئ (reciter dropdown) ──
                      _sheetSectionLabel(
                        Icons.record_voice_over_rounded,
                        'القارئ',
                        titleColor,
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<Reciter>(
                        valueListenable: reciterService.selected,
                        builder: (context, selected, _) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selected.id,
                                isExpanded: true,
                                icon: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: titleColor,
                                ),
                                dropdownColor: bgColor,
                                borderRadius: BorderRadius.circular(12),
                                items: [
                                  for (final reciter in reciterService.reciters)
                                    DropdownMenuItem(
                                      value: reciter.id,
                                      child: Text(
                                        '${reciter.shortName} — ${reciter.riwaya}',
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                selectedItemBuilder: (context) => [
                                  for (final reciter in reciterService.reciters)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        reciter.shortName,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (id) {
                                  if (id == null) return;
                                  _resetHideTimer();
                                  reciterService.select(
                                    reciterService.reciters.firstWhere(
                                      (r) => r.id == id,
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // ── تكرار الثمن + تكرار مقطع + سرعة التلاوة (side by side) ──
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ListenableBuilder(
                                listenable: Listenable.merge([
                                  audio.thumnRepeatMode,
                                  audio.thumnRepeatCount,
                                ]),
                                builder: (context, _) {
                                  final isActive =
                                      audio.thumnRepeatMode.value !=
                                      AyahRepeatMode.off;
                                  return _optionTile(
                                    icon: Icons.repeat_rounded,
                                    title: 'تكرار الثمن',
                                    valueLabel: isActive
                                        ? audio.thumnRepeatLabel
                                        : 'بدون',
                                    isActive: isActive,
                                    accentColor: accentColor,
                                    borderColor: borderColor,
                                    textColor: textColor,
                                    subTextColor: subTextColor,
                                    onTap: () {
                                      _resetHideTimer();
                                      _handleThumnRepeatTap();
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ListenableBuilder(
                                listenable: Listenable.merge([
                                  audio.rangeRepeatMode,
                                  audio.rangeRepeatCount,
                                ]),
                                builder: (context, _) {
                                  final isActive =
                                      audio.rangeRepeatMode.value !=
                                      AyahRepeatMode.off;
                                  return _optionTile(
                                    icon: Icons.segment_rounded,
                                    title: 'تكرار مقطع',
                                    valueLabel: isActive
                                        ? audio.rangeRepeatLabel
                                        : 'بدون',
                                    isActive: isActive,
                                    accentColor: accentColor,
                                    borderColor: borderColor,
                                    textColor: textColor,
                                    subTextColor: subTextColor,
                                    onTap: () {
                                      _resetHideTimer();
                                      _showRangeRepeatPicker(
                                        // Starting a section closes the sheet so
                                        // the user lands straight on the page it
                                        // begins at.
                                        onStarted: () {
                                          if (ctx.mounted) Navigator.pop(ctx);
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ListenableBuilder(
                                listenable: audio.playbackSpeed,
                                builder: (context, _) {
                                  final isActive =
                                      audio.playbackSpeed.value != 1.0;
                                  return _optionTile(
                                    key: speedTileKey,
                                    icon: Icons.speed_rounded,
                                    title: 'سرعة التلاوة',
                                    valueLabel: audio.playbackSpeedLabel,
                                    isActive: isActive,
                                    accentColor: accentColor,
                                    borderColor: borderColor,
                                    textColor: textColor,
                                    subTextColor: subTextColor,
                                    onTap: () {
                                      _resetHideTimer();
                                      _showSpeedPopup(speedTileKey);
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Live status of the running section — the only text under
                      // the row, and only while a section is actually armed.
                      ListenableBuilder(
                        listenable: Listenable.merge([
                          audio.repeatRange,
                          audio.rangeRepeatDone,
                          audio.rangeRepeatCount,
                          audio.rangeRepeatMode,
                        ]),
                        builder: (context, _) {
                          final range = audio.repeatRange.value;
                          if (range == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'المقطع: ${_rangeStatusLabel(range)}',
                              style: const TextStyle(
                                color: accentColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 20),
                      Divider(color: borderColor, height: 1),
                      const SizedBox(height: 4),

                      // ── الإرشادات (open the button guide) ──
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showRecitationBarGuide();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.help_outline_rounded,
                                color: titleColor,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'شرح أزرار شريط التلاوة',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.chevron_left_rounded,
                                color: subTextColor,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// One row of the vertical playback-speed picker.
  /// Pops up a compact vertical "level bar" of playback speeds floating just
  /// above the speed tile ([anchorKey]) — the sheet itself doesn't move or
  /// reflow. Tapping a value applies it instantly; tapping outside dismisses.
  void _showSpeedPopup(GlobalKey anchorKey) {
    final render = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (render == null || overlay == null) return;

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode
        ? const Color(0xFF262016)
        : const Color(0xFFFBF6E8);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF35250E);
    final borderColor = isDarkMode
        ? const Color(0xFF53401F)
        : const Color(0xFFE2D2A5);
    final subTextColor = textColor.withValues(alpha: 0.6);
    const accentColor = Color(0xFFD2B97E);

    // Tile position/size in overlay coordinates.
    final topLeft = render.localToGlobal(Offset.zero, ancestor: overlay);
    final tileWidth = render.size.width;
    final tileTop = topLeft.dy;
    final tileLeft = topLeft.dx;

    // Fastest at the top, slowest at the bottom (like a level meter).
    final speeds = AudioService.allowedPlaybackSpeeds.reversed.toList();
    const rowHeight = 40.0;
    final popupHeight = speeds.length * rowHeight + 12;

    // Prefer floating above the tile; if there isn't room (tall sheet), drop
    // it below instead so it never clips off the top of the screen.
    final topSafe = MediaQuery.of(context).padding.top + 8;
    final aboveTop = tileTop - popupHeight - 8;
    final popupTop = aboveTop >= topSafe
        ? aboveTop
        : tileTop + render.size.height + 8;

    final audio = AudioService.instance;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Tap-outside barrier.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => entry.remove(),
              ),
            ),
            Positioned(
              left: tileLeft,
              width: tileWidth,
              top: popupTop,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ValueListenableBuilder<double>(
                    valueListenable: audio.playbackSpeed,
                    builder: (context, currentSpeed, _) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final speed in speeds)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                _resetHideTimer();
                                audio.setPlaybackSpeed(speed);
                                entry.remove();
                              },
                              child: Container(
                                height: rowHeight,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: speed == currentSpeed
                                      ? accentColor.withValues(alpha: 0.22)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  AudioService.speedLabel(speed),
                                  style: TextStyle(
                                    color: speed == currentSpeed
                                        ? accentColor
                                        : (speed == 1.0
                                              ? textColor
                                              : subTextColor),
                                    fontSize: 15,
                                    fontWeight: speed == currentSpeed
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(entry);
  }

  Widget _sheetSectionLabel(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  /// A compact square-ish tile used for the thumn-repeat, section-repeat and
  /// playback-speed controls in the Tilawah options sheet — three to a row, so
  /// the title scales down rather than ellipsising on narrow phones.
  Widget _optionTile({
    Key? key,
    required IconData icon,
    required String title,
    required String valueLabel,
    required bool isActive,
    required Color accentColor,
    required Color borderColor,
    required Color textColor,
    required Color subTextColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? accentColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? accentColor : borderColor,
            width: isActive ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: isActive ? accentColor : textColor, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      title,
                      maxLines: 1,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              valueLabel,
              style: TextStyle(
                color: isActive ? accentColor : subTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
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
    Color? highlightColor,
    VoidCallback? onTap,
  }) {
    final bool highlighted = highlightColor != null;

    final Widget iconChip = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlighted
            ? highlightColor
            : borderColor.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child:
          iconWidget ??
          Icon(icon, color: highlighted ? Colors.white : textColor, size: 18),
    );

    final row = Row(
      textDirection: TextDirection.rtl,
      children: [
        iconChip,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 14,
              fontWeight: highlighted ? FontWeight.w800 : FontWeight.w700,
              color: highlighted ? highlightColor : textColor,
            ),
          ),
        ),
        if (highlighted) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: highlightColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'جديد',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );

    if (!highlighted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: row,
      );
    }

    // Highlighted rows get a tinted card so the feature clearly stands out
    // from the plain button-explanation rows above it.
    final borderRadius = BorderRadius.circular(12);
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlightColor.withValues(alpha: 0.12),
        borderRadius: borderRadius,
        border: Border.all(color: highlightColor.withValues(alpha: 0.55)),
      ),
      child: row,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: onTap == null
          ? card
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: card,
              ),
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
        // Landscape has limited vertical room, so the recitation bar uses a
        // tighter top/bottom padding to give the page more space.
        final bool isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final double barTopPadding = isLandscape ? 6 : 16;
        final double barBottomPadding = isLandscape ? 4 : 12;
        // Control sizes also shrink in landscape so the whole bar is shorter.
        final double repeatIconBoxW = isLandscape ? 34 : 42;
        final double repeatIconBoxH = isLandscape ? 26 : 34;
        final double repeatIconW = isLandscape ? 27 : 34;
        final double repeatIconH = isLandscape ? 24 : 30;
        final double skipIconSize = isLandscape ? 28 : 36;
        final double playCircleSize = isLandscape ? 46 : 60;
        final double playIconSize = isLandscape ? 30 : 40;
        final double ayahFontSize = isLandscape ? 13 : 15;
        final double closeIconSize = isLandscape ? 22 : 28;
        final double helpIconSize = isLandscape ? 19 : 24;
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
                    top: barTopPadding,
                    bottom: systemBottom > 0 ? systemBottom : barBottomPadding,
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
                        constraints: _barIconConstraints,
                        onPressed: () {
                          _resetHideTimer();
                          audio.cyclePageRepeatMode();
                        },
                        icon: SizedBox(
                          width: repeatIconBoxW,
                          height: repeatIconBoxH,
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
                                  width: repeatIconW,
                                  height: repeatIconH,
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
                        constraints: _barIconConstraints,
                        icon: Icon(
                          Icons.skip_previous_rounded,
                          color: iconColor,
                          size: skipIconSize,
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
                              fontSize: ayahFontSize,
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
                          width: playCircleSize,
                          height: playCircleSize,
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
                            size: playIconSize,
                          ),
                        ),
                      ),

                      // التالي
                      IconButton(
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: _barIconConstraints,
                        icon: Icon(
                          Icons.skip_next_rounded,
                          color: iconColor,
                          size: skipIconSize,
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
                        constraints: _barIconConstraints,
                        onPressed: () {
                          _resetHideTimer();
                          audio.cycleAyahRepeatMode();
                        },
                        icon: SizedBox(
                          width: repeatIconBoxW,
                          height: repeatIconBoxH,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              // The icon stays white in every state; the badge below
                              // signals that ayah-repeat is active and how many times.
                              Image.asset(
                                'assets/images/icon_repeat_ayah.png',
                                width: repeatIconW,
                                height: repeatIconH,
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
                        constraints: _barIconConstraints,
                        icon: Icon(
                          Icons.close_rounded,
                          color: iconColor,
                          size: closeIconSize,
                        ),
                        onPressed: () {
                          _resetHideTimer();
                          audio.stop();
                        },
                        tooltip: 'إغلاق',
                      ),

                      // خيارات (القارئ، سرعة التلاوة، تكرار الثمن، تكرار مقطع، الإرشادات)
                      // Wrapped in a gold accent chip so it stands apart from
                      // the plain-white transport icons and reads as "options".
                      GestureDetector(
                        onTap: () {
                          _resetHideTimer();
                          _showTilawahOptionsSheet();
                        },
                        child: Tooltip(
                          message: 'خيارات التلاوة',
                          child: Container(
                            padding: EdgeInsets.all(isLandscape ? 6 : 7),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(
                                alpha: 0.22 * iconOpacity,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: accentColor.withValues(
                                  alpha: 0.55 * iconOpacity,
                                ),
                                width: 1.2,
                              ),
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              color: iconColor,
                              size: helpIconSize,
                            ),
                          ),
                        ),
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

/// What a per-ayah copy action in the tafsir sheet puts on the clipboard.
enum _TafsirCopyMode { ayah, tafsir, both }

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
    // Switching tafsir edition from the header picker reloads the current page.
    TafsirEditionService.instance.selected.addListener(_onEditionChanged);
    _loadTafsir(_currentPage);
  }

  @override
  void dispose() {
    TafsirEditionService.instance.selected.removeListener(_onEditionChanged);
    super.dispose();
  }

  void _onEditionChanged() => _loadTafsir(_currentPage);

  Future<void> _openEditionPicker() async {
    final service = TafsirEditionService.instance;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: widget.backgroundColor,
      // Size the sheet to its content instead of the default ~half-screen cap,
      // so every edition is visible at once without scrolling.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final selectedId = service.selected.value.id;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 10),
              Text(
                'اختر التفسير',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: widget.titleColor,
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    for (final edition in service.editions)
                      ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -1),
                        onTap: () {
                          service.select(edition);
                          Navigator.of(sheetContext).pop();
                        },
                        leading: Icon(
                          edition.id == selectedId
                              ? Icons.check_circle_rounded
                              : Icons.menu_book_outlined,
                          color: edition.id == selectedId
                              ? widget.accentColor
                              : widget.borderColor,
                        ),
                        title: Text(
                          edition.name,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: widget.titleColor,
                          ),
                        ),
                        subtitle: Text(
                          edition.isBundled
                              ? edition.subtitle
                              : '${edition.subtitle} • يتطلب إنترنت لأول مرة',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.titleColor.withValues(alpha: 0.6),
                          ),
                        ),
                        trailing: Icon(
                          edition.isBundled
                              ? Icons.offline_pin_outlined
                              : Icons.cloud_outlined,
                          size: 18,
                          color: widget.titleColor.withValues(alpha: 0.45),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
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
    if (newPage < 0 || newPage >= 602) return;
    setState(() => _currentPage = newPage);
    widget.onPageChanged(newPage);
    _loadTafsir(newPage);
  }

  /// One-tap copy for a whole block. Free-form partial selection is handled by
  /// the `SelectionArea` around the list; this is the shortcut for grabbing the
  /// verse, its commentary, or both without dragging handles around.
  Widget _buildCopyMenu(Map<String, dynamic> data) {
    return SizedBox(
      width: 40,
      height: 40,
      child: PopupMenuButton<_TafsirCopyMode>(
        tooltip: 'نسخ',
        icon: const Icon(Icons.copy_rounded),
        iconSize: 19,
        iconColor: widget.accentColor,
        padding: EdgeInsets.zero,
        color: widget.backgroundColor,
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 190),
        onSelected: (mode) => _copyEntry(data, mode),
        itemBuilder: (_) => [
          _buildCopyMenuItem(
            _TafsirCopyMode.ayah,
            Icons.menu_book_rounded,
            'نسخ الآية',
          ),
          _buildCopyMenuItem(
            _TafsirCopyMode.tafsir,
            Icons.article_outlined,
            'نسخ التفسير',
          ),
          _buildCopyMenuItem(
            _TafsirCopyMode.both,
            Icons.copy_all_rounded,
            'نسخ الآية والتفسير',
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_TafsirCopyMode> _buildCopyMenuItem(
    _TafsirCopyMode mode,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_TafsirCopyMode>(
      value: mode,
      height: 44,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            Icon(icon, size: 18, color: widget.accentColor),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: widget.titleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyEntry(
    Map<String, dynamic> data,
    _TafsirCopyMode mode,
  ) async {
    final surahName = (data['surahName'] ?? '').toString();
    final ayahNumber = (data['ayahNumber'] as num?)?.toInt() ?? 0;
    final ayahText = (data['ayahText'] ?? '').toString();
    final tafsirText = (data['tafsir'] ?? '').toString();
    final editionName = TafsirEditionService.instance.selected.value.name;

    final (text, message) = switch (mode) {
      _TafsirCopyMode.ayah => (
        CopyHelper.formatAyah(
          surahName: surahName,
          ayahNumber: ayahNumber,
          text: ayahText,
        ),
        'تم نسخ الآية',
      ),
      _TafsirCopyMode.tafsir => (tafsirText.trim(), 'تم نسخ التفسير'),
      _TafsirCopyMode.both => (
        CopyHelper.formatAyahWithTafsir(
          surahName: surahName,
          ayahNumber: ayahNumber,
          ayahText: ayahText,
          tafsirText: tafsirText,
          editionName: editionName,
        ),
        'تم نسخ الآية والتفسير',
      ),
    };

    await CopyHelper.copy(context, text, message: message);
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
                        onPressed: _currentPage < 601
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Tap-to-change-tafsir affordance: a filled, bordered
                          // pill with the ⇕ glyph so it clearly reads as a
                          // selector with other options, not a plain title.
                          Center(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _openEditionPicker,
                                borderRadius: BorderRadius.circular(22),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    6,
                                    12,
                                    6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: widget.accentColor.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: widget.accentColor.withValues(
                                        alpha: 0.55,
                                      ),
                                      width: 1.3,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.unfold_more_rounded,
                                        size: 20,
                                        color: widget.accentColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          TafsirEditionService
                                              .instance
                                              .selected
                                              .value
                                              .name,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: widget.titleColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'الصفحة ${_currentPage + 1} • اضغط لاختيار تفسير آخر',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: widget.accentColor.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
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
                    // A smooth, always-visible position indicator. It is NOT
                    // interactive on purpose: an interactive/draggable scrollbar
                    // fights the DraggableScrollableSheet (they share a scroll
                    // controller whose extent changes as the sheet resizes),
                    // which caused the thumb to snap and jump to the ends.
                    // Scrolling is done by dragging the content, which is smooth.
                    // SelectionArea gives free-form text selection on every
                    // platform: long-press + handles on Android/iOS, mouse
                    // drag + Ctrl/Cmd-C on the web build.
                    : SelectionArea(
                        child: RawScrollbar(
                          controller: scrollController,
                          thumbVisibility: true,
                          thickness: 5,
                          radius: const Radius.circular(4),
                          thumbColor: widget.accentColor.withValues(alpha: 0.5),
                          child: ListView.separated(
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
                                  Row(
                                    children: [
                                      _buildCopyMenu(data),
                                      Expanded(
                                        child: Text(
                                          '${data['surahName']} - آية ${data['ayahNumber']}',
                                          textAlign: TextAlign.center,
                                          textDirection: TextDirection.rtl,
                                          style: TextStyle(
                                            color: widget.borderColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      // Balances the copy button so the heading
                                      // stays optically centred.
                                      const SizedBox(width: 40),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
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
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

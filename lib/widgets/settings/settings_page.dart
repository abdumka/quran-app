import 'dart:async';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'settings_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/reciter.dart';
import '../../services/app_update_service.dart';
import '../../services/update_notification_service.dart';
import '../update_available_dialog.dart';
import '../../services/audio_download_service.dart';
import '../../services/background_playback_service.dart';
import '../../services/page_zoom_service.dart';
import '../../services/keep_screen_awake_service.dart';
import '../../services/margin_images_service.dart';
import '../../services/high_quality_images_service.dart';
import '../../services/page_quality_service.dart';
import '../../services/reciter_service.dart';
import '../../services/recitation_bar_opacity_service.dart';
import '../../utils/responsive_helper.dart';

import 'settings_components.dart';
import 'settings_coach_overlay.dart';
import '../hifz_lens_icon.dart';
import 'downloads_management_page.dart';
import '../menu/about_content.dart';
import '../menu/contact_content.dart';
import '../menu/fullscreen_menu_page.dart';

class SettingsPage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onToggleDarkMode;
  final bool isAutoScrollEnabled;
  final ValueChanged<bool> onToggleAutoScroll;
  final bool isPortraitScrollMode;
  final bool allowPortraitScrollMode;
  final bool showTabletLayoutSetting;
  final bool isTabletLayoutMode;
  final ValueChanged<bool> onToggleTabletLayoutMode;
  final ValueChanged<bool> onTogglePortraitScrollMode;
  final bool isHideBarEnabled;
  final ValueChanged<bool> onToggleHideBar;
  final bool isHifzModeEnabled;
  final ValueChanged<bool> onToggleHifzMode;
  final bool isFullScreenMode;
  final ValueChanged<bool> onToggleFullScreenMode;
  final Future<void> Function() onResetAllSettings;

  const SettingsPage({
    super.key,
    required this.isDarkMode,
    required this.onToggleDarkMode,
    required this.isAutoScrollEnabled,
    required this.onToggleAutoScroll,
    required this.isPortraitScrollMode,
    required this.allowPortraitScrollMode,
    required this.showTabletLayoutSetting,
    required this.isTabletLayoutMode,
    required this.onToggleTabletLayoutMode,
    required this.onTogglePortraitScrollMode,
    required this.isHideBarEnabled,
    required this.onToggleHideBar,
    required this.isHifzModeEnabled,
    required this.onToggleHifzMode,
    required this.isFullScreenMode,
    required this.onToggleFullScreenMode,
    required this.onResetAllSettings,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const String _settingsTitle =
      '\u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a';
  static const String _marginGuideDismissedPrefKey = 'marginGuideDismissed';
  static const String _autoScrollGuideDismissedPrefKey =
      'autoScrollGuideDismissed';
  static const String _browseModeGuideDismissedPrefKey =
      'browseModeGuideDismissed';
  static const String _bookmarkGuideDismissedPrefKey = 'bookmarkGuideDismissed';
  static const String _hifzLensSettingsGuideDismissedPrefKey =
      'hifzLensSettingsGuideDismissed';
  static const String _fullScreenSettingsGuideDismissedPrefKey =
      'fullScreenSettingsGuideDismissed';
  static const String _backgroundPlaybackGuideDismissedPrefKey =
      'backgroundPlaybackGuideDismissed';

  late bool _localAutoScrollEnabled;
  late bool _localPortraitScrollMode;
  late bool _localTabletLayoutMode;
  late bool _localFullScreenMode;
  bool _showBrowseModeGuide = false;
  bool _showMarginGuide = false;
  bool _showAutoScrollGuide = false;
  bool _showHideBarGuide = false;
  bool _showHifzLensGuide = false;
  bool _showBackgroundPlaybackGuide = false;
  bool _showFullScreenGuide = false;
  final AudioDownloadService _audioDownloadService =
      AudioDownloadService.instance;
  final ReciterService _reciterService = ReciterService.instance;
  final BackgroundPlaybackService _backgroundPlaybackService =
      BackgroundPlaybackService.instance;
  final PageZoomService _pageZoomService = PageZoomService.instance;
  final KeepScreenAwakeService _keepScreenAwakeService =
      KeepScreenAwakeService.instance;
  final MarginImagesService _marginImagesService = MarginImagesService.instance;
  final HighQualityImagesService _highQualityImagesService =
      HighQualityImagesService.instance;
  final PageQualityService _pageQualityService = PageQualityService.instance;
  final RecitationBarOpacityService _recitationBarOpacityService =
      RecitationBarOpacityService.instance;
  final AppUpdateService _appUpdateService = AppUpdateService.instance;
  bool _isCheckingForUpdate = false;

  final GlobalKey _settingsOverlayKey = GlobalKey();
  final GlobalKey _browseModeCardKey = GlobalKey();
  final GlobalKey _autoScrollCardKey = GlobalKey();
  final GlobalKey _marginImagesCardKey = GlobalKey();
  final GlobalKey _hideBarCardKey = GlobalKey();
  // Targets for the on-demand (ℹ️) instructions added to the remaining settings.
  final GlobalKey _brightnessKey = GlobalKey();
  final GlobalKey _darkModeKey = GlobalKey();
  final GlobalKey _hifzLensKey = GlobalKey();
  final GlobalKey _fullScreenKey = GlobalKey();
  final GlobalKey _twoPageKey = GlobalKey();
  final GlobalKey _resetGuidesKey = GlobalKey();
  final GlobalKey _reciterKey = GlobalKey();
  final GlobalKey _backgroundPlaybackKey = GlobalKey();
  final GlobalKey _pageQualityKey = GlobalKey();
  final GlobalKey _audioDownloadKey = GlobalKey();
  final GlobalKey _downloadsManagementKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  Offset? _lastTapPosition;
  Offset? _noticePosition;
  String? _settingsNoticeText;
  Timer? _settingsNoticeTimer;
  double _brightness = 0.5;
  SettingsCoachStep? _activeCoachStep;
  Rect? _activeCoachRect;
  bool _isManualCoachPresentation = false;

  bool get _localAllowPortraitScrollMode => !_localTabletLayoutMode;

  @override
  void initState() {
    super.initState();
    _localAutoScrollEnabled = widget.isAutoScrollEnabled;
    _localPortraitScrollMode = widget.isPortraitScrollMode;
    _localTabletLayoutMode = widget.isTabletLayoutMode;
    _localFullScreenMode = widget.isFullScreenMode;
    _audioDownloadService.initialize();
    _keepScreenAwakeService.load();
    _marginImagesService.initialize();
    _highQualityImagesService.initialize();
    _pageQualityService.load();
    _recitationBarOpacityService.load();
    _loadGuidePreferences();
    _loadCurrentBrightness();
  }

  Future<void> _loadCurrentBrightness() async {
    try {
      final value = await ScreenBrightness().application;
      if (!mounted) return;
      setState(() {
        _brightness = value.clamp(0.0, 1.0);
      });
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isAutoScrollEnabled != widget.isAutoScrollEnabled) {
      _localAutoScrollEnabled = widget.isAutoScrollEnabled;
    }
    if (oldWidget.isPortraitScrollMode != widget.isPortraitScrollMode) {
      _localPortraitScrollMode = widget.isPortraitScrollMode;
    }
    if (oldWidget.isTabletLayoutMode != widget.isTabletLayoutMode) {
      _localTabletLayoutMode = widget.isTabletLayoutMode;
    }
  }

  @override
  void dispose() {
    _settingsNoticeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadGuidePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showBrowseModeGuide =
          !(prefs.getBool(_browseModeGuideDismissedPrefKey) ?? false);
      _showMarginGuide =
          !(prefs.getBool(_marginGuideDismissedPrefKey) ?? false);
      _showAutoScrollGuide =
          !(prefs.getBool(_autoScrollGuideDismissedPrefKey) ?? false);
      _showHideBarGuide = !(prefs.getBool('hideBarGuideDismissed') ?? false);
      _showHifzLensGuide =
          !(prefs.getBool(_hifzLensSettingsGuideDismissedPrefKey) ?? false);
      _showFullScreenGuide =
          !(prefs.getBool(_fullScreenSettingsGuideDismissedPrefKey) ?? false);
      _showBackgroundPlaybackGuide =
          !(prefs.getBool(_backgroundPlaybackGuideDismissedPrefKey) ?? false);
    });
    // Note: the first-time auto-tour (formerly triggered here) was removed so
    // the settings screen no longer pops up a chain of coach marks on open.
    // Each setting's guidance is now available on demand via its ℹ️ button,
    // which calls [_presentCoachManually] / [_showInfoNotice].
  }

  Future<void> _dismissGuide(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
    if (!mounted) return;
    setState(() {
      if (key == _browseModeGuideDismissedPrefKey) {
        _showBrowseModeGuide = false;
      } else if (key == _marginGuideDismissedPrefKey) {
        _showMarginGuide = false;
      } else if (key == _autoScrollGuideDismissedPrefKey) {
        _showAutoScrollGuide = false;
      } else if (key == 'hideBarGuideDismissed') {
        _showHideBarGuide = false;
      } else if (key == _hifzLensSettingsGuideDismissedPrefKey) {
        _showHifzLensGuide = false;
      } else if (key == _fullScreenSettingsGuideDismissedPrefKey) {
        _showFullScreenGuide = false;
      } else if (key == _backgroundPlaybackGuideDismissedPrefKey) {
        _showBackgroundPlaybackGuide = false;
      }
    });
  }

  void _closeActiveCoachForNow() {
    final previousStep = _activeCoachStep;
    setState(() {
      _activeCoachStep = null;
      _activeCoachRect = null;
    });

    if (_isManualCoachPresentation) {
      _isManualCoachPresentation = false;
      return;
    }

    final nextStep = _nextCoachStep(previousStep, manual: false);

    if (nextStep != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _activateCoachStep(nextStep);
      });
      return;
    }

    _isManualCoachPresentation = false;
  }

  void _showNextCoachStep() {
    if (_activeCoachStep != null) return;
    if (_showBrowseModeGuide) {
      _activateCoachStep(SettingsCoachStep.browseMode);
      return;
    }
    if (_showAutoScrollGuide) {
      _activateCoachStep(SettingsCoachStep.autoScroll);
      return;
    }
    if (_showMarginGuide) {
      _activateCoachStep(SettingsCoachStep.marginImages);
      return;
    }
    if (_showHideBarGuide) {
      _activateCoachStep(SettingsCoachStep.hideBar);
      return;
    }
    if (_showHifzLensGuide) {
      _activateCoachStep(SettingsCoachStep.hifzLens);
      return;
    }
    if (_showFullScreenGuide) {
      _activateCoachStep(SettingsCoachStep.fullScreen);
      return;
    }
    if (_showBackgroundPlaybackGuide) {
      _activateCoachStep(SettingsCoachStep.backgroundPlayback);
    }
  }

  GlobalKey _coachTargetKey(SettingsCoachStep step) {
    return switch (step) {
      SettingsCoachStep.browseMode => _browseModeCardKey,
      SettingsCoachStep.autoScroll => _autoScrollCardKey,
      SettingsCoachStep.marginImages => _marginImagesCardKey,
      SettingsCoachStep.hideBar => _hideBarCardKey,
      SettingsCoachStep.screenBrightness => _brightnessKey,
      SettingsCoachStep.darkMode => _darkModeKey,
      SettingsCoachStep.hifzLens => _hifzLensKey,
      SettingsCoachStep.fullScreen => _fullScreenKey,
      SettingsCoachStep.twoPage => _twoPageKey,
      SettingsCoachStep.resetGuides => _resetGuidesKey,
      SettingsCoachStep.reciter => _reciterKey,
      SettingsCoachStep.backgroundPlayback => _backgroundPlaybackKey,
      SettingsCoachStep.pageQuality => _pageQualityKey,
      SettingsCoachStep.audioDownload => _audioDownloadKey,
      SettingsCoachStep.downloadsManagement => _downloadsManagementKey,
    };
  }

  /// Shows a single setting's instruction on demand (tapping its ℹ️ button),
  /// reusing the coach overlay but presented as a centred dialog.
  void _presentCoachManually(SettingsCoachStep step) {
    if (_activeCoachStep != null) return;
    setState(() {
      _isManualCoachPresentation = true;
    });
    _activateCoachStep(step);
  }

  void _activateCoachStep(SettingsCoachStep step) {
    final targetContext = _coachTargetKey(step).currentContext;

    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ).then((_) {
        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 50), () {
          if (!mounted) return;
          final rect = _measureCoachRect(step);
          if (rect != null) {
            setState(() {
              _activeCoachStep = step;
              _activeCoachRect = rect;
            });
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _activateCoachStep(step);
            });
          }
        });
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _activateCoachStep(step);
      });
    }
  }

  Rect? _measureCoachRect(SettingsCoachStep step) {
    final overlayContext = _settingsOverlayKey.currentContext;
    if (overlayContext == null) return null;
    final overlayBox = overlayContext.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return null;

    final targetContext = _coachTargetKey(step).currentContext;
    if (targetContext == null) return null;
    final targetBox = targetContext.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize) return null;

    final topLeft = targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    return topLeft & targetBox.size;
  }

  Future<void> _dismissActiveCoachForever() async {
    final step = _activeCoachStep;
    if (step == null) return;
    // Only the original auto-tour steps can be permanently dismissed; the
    // on-demand (ℹ️) steps never show the "don't show again" button.
    final key = switch (step) {
      SettingsCoachStep.browseMode => _browseModeGuideDismissedPrefKey,
      SettingsCoachStep.autoScroll => _autoScrollGuideDismissedPrefKey,
      SettingsCoachStep.marginImages => _marginGuideDismissedPrefKey,
      SettingsCoachStep.hideBar => 'hideBarGuideDismissed',
      SettingsCoachStep.hifzLens => _hifzLensSettingsGuideDismissedPrefKey,
      SettingsCoachStep.fullScreen => _fullScreenSettingsGuideDismissedPrefKey,
      SettingsCoachStep.backgroundPlayback =>
        _backgroundPlaybackGuideDismissedPrefKey,
      _ => null,
    };
    if (key == null) return;
    await _dismissGuide(key);
    if (!mounted) return;
    final nextStep = _nextCoachStep(step, manual: _isManualCoachPresentation);
    setState(() {
      _activeCoachStep = null;
      _activeCoachRect = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (nextStep != null) {
        _activateCoachStep(nextStep);
        return;
      }
      _isManualCoachPresentation = false;
      _showNextCoachStep();
    });
  }

  String get _activeCoachTitle {
    switch (_activeCoachStep) {
      case SettingsCoachStep.browseMode:
        return 'إرشاد وضع التصفح';
      case SettingsCoachStep.autoScroll:
        return 'إرشاد التمرير التلقائي';
      case SettingsCoachStep.marginImages:
        return 'إرشاد عرض الهوامش';
      case SettingsCoachStep.hideBar:
        return 'إرشاد شريط الإخفاء';
      case SettingsCoachStep.screenBrightness:
        return 'إرشاد إضاءة الشاشة';
      case SettingsCoachStep.darkMode:
        return 'إرشاد الوضع الليلي';
      case SettingsCoachStep.hifzLens:
        return 'إرشاد عدسة الإخفاء';
      case SettingsCoachStep.fullScreen:
        return 'إرشاد وضع ملء الشاشة';
      case SettingsCoachStep.twoPage:
        return 'إرشاد عرض الصفحتين';
      case SettingsCoachStep.resetGuides:
        return 'إرشاد إعادة الإرشادات';
      case SettingsCoachStep.reciter:
        return 'إرشاد اختيار القارئ';
      case SettingsCoachStep.backgroundPlayback:
        return 'إرشاد التشغيل في الخلفية';
      case SettingsCoachStep.pageQuality:
        return 'إرشاد جودة عرض الصفحات';
      case SettingsCoachStep.audioDownload:
        return 'إرشاد تحميل الصوتيات';
      case SettingsCoachStep.downloadsManagement:
        return 'إرشاد إدارة الملفات';
      case null:
        return '';
    }
  }

  String get _activeCoachMessage {
    switch (_activeCoachStep) {
      case SettingsCoachStep.browseMode:
        return 'من هنا تختار بين وضع الصفحات للتقليب صفحة صفحة، أو وضع التمرير للقراءة المستمرة. الرسم يوضح الفرق بين الطريقتين بشكل بصري.';
      case SettingsCoachStep.autoScroll:
        return 'شغّل التمرير التلقائي من هنا، وسيحوّل التطبيق القراءة إلى وضع التمرير تلقائيًا ثم يمكنك التحكم في السرعة من الشريط المخصص.';
      case SettingsCoachStep.marginImages:
        return 'من هذا القسم يمكنك تنزيل عرض الهوامش ثم تفعيله لاحقًا. عند التفعيل ستظهر الصفحة كاملة بإطارها ويختفي الشريط العلوي في هذا العرض.';
      case SettingsCoachStep.hideBar:
        return 'شريط الإخفاء يُغطي نص الصفحة ويترك نافذة صغيرة قابلة للسحب لكشف السطور تدريجياً. مفيد لمراجعة الحفظ. أثناء التلاوة، يتحرك الشريط تلقائياً مع سرعة القراءة ويتسع ليشمل سطرين.';
      case SettingsCoachStep.screenBrightness:
        return 'اسحب الشريط لضبط سطوع الشاشة داخل التطبيق فقط دون تغيير سطوع النظام، لقراءة مريحة في مختلف الإضاءات.';
      case SettingsCoachStep.darkMode:
        return 'يبدّل ألوان التطبيق إلى مظهر داكن مريح للعين في الإضاءة المنخفضة، ويعرض صفحات المصحف بخلفية داكنة.';
      case SettingsCoachStep.hifzLens:
        return 'تُغطّي عدسة الإخفاء نص الصفحة، وتكشف ما يمر تحت إصبعك فقط لتختبر حفظك سطراً سطراً. عند تفعيلها يتوقف شريط الإخفاء تلقائياً.';
      case SettingsCoachStep.fullScreen:
        return 'يُخفي شريط الحالة وأزرار النظام ليملأ المصحف الشاشة بالكامل. اسحب من حافة الشاشة لإظهار أشرطة النظام مؤقتاً.';
      case SettingsCoachStep.twoPage:
        return 'يعرض صفحتين جنباً إلى جنب كالمصحف المفتوح. يناسب الأجهزة اللوحية والشاشات الكبيرة، ويوقف وضع التمرير عند تفعيله.';
      case SettingsCoachStep.resetGuides:
        return 'يعيد إظهار جميع الرسائل الإرشادية داخل التطبيق من جديد، كأنك تستخدمه لأول مرة.';
      case SettingsCoachStep.reciter:
        return 'اختر التلاوة التي تستمع إليها من القائمة. لكل قارئ ملفاته الصوتية الخاصة، وعند التبديل يتوقف التشغيل الحالي ثم يبدأ بصوت القارئ الجديد.';
      case SettingsCoachStep.backgroundPlayback:
        return 'عند تفعيله تستمر التلاوة في العمل حتى لو خرجت من التطبيق أو أقفلت الشاشة، ويمكنك التحكم بها من إشعار التشغيل. أوقفه إن أردت أن تتوقف التلاوة تلقائياً عند مغادرة التطبيق.';
      case SettingsCoachStep.pageQuality:
        return 'يتيح لك تجربة ثلاثة مستويات لعرض الصفحة واختيار الأنسب لجهازك. جميع الصور بنفس الأبعاد، والفرق في نعومة العرض وجودة الضغط فقط.';
      case SettingsCoachStep.audioDownload:
        return 'نزّل ملفات الصوت كاملة للقارئ المختار لتستمع للتلاوة بدون اتصال بالإنترنت. يمكنك إيقاف التحميل مؤقتاً واستئنافه لاحقاً.';
      case SettingsCoachStep.downloadsManagement:
        return 'من هنا تستعرض كل الملفات الإضافية التي حمّلتها وحجمها الحالي، وتحذف ما لا تحتاجه لتوفير مساحة التخزين.';
      case null:
        return '';
    }
  }

  SettingsCoachStep? _nextCoachStep(
    SettingsCoachStep? step, {
    required bool manual,
  }) {
    if (step == null) return null;

    if (manual) {
      // On-demand (ℹ️) steps are shown one at a time, so they never chain.
      return switch (step) {
        SettingsCoachStep.browseMode => SettingsCoachStep.autoScroll,
        SettingsCoachStep.autoScroll => SettingsCoachStep.marginImages,
        SettingsCoachStep.marginImages => SettingsCoachStep.hideBar,
        SettingsCoachStep.hideBar => null,
        _ => null,
      };
    }

    return switch (step) {
      SettingsCoachStep.browseMode when _showAutoScrollGuide =>
        SettingsCoachStep.autoScroll,
      SettingsCoachStep.browseMode when _showMarginGuide =>
        SettingsCoachStep.marginImages,
      SettingsCoachStep.browseMode when _showHideBarGuide =>
        SettingsCoachStep.hideBar,
      SettingsCoachStep.browseMode when _showHifzLensGuide =>
        SettingsCoachStep.hifzLens,
      SettingsCoachStep.browseMode when _showFullScreenGuide =>
        SettingsCoachStep.fullScreen,
      SettingsCoachStep.autoScroll when _showMarginGuide =>
        SettingsCoachStep.marginImages,
      SettingsCoachStep.autoScroll when _showHideBarGuide =>
        SettingsCoachStep.hideBar,
      SettingsCoachStep.autoScroll when _showHifzLensGuide =>
        SettingsCoachStep.hifzLens,
      SettingsCoachStep.autoScroll when _showFullScreenGuide =>
        SettingsCoachStep.fullScreen,
      SettingsCoachStep.marginImages when _showHideBarGuide =>
        SettingsCoachStep.hideBar,
      SettingsCoachStep.marginImages when _showHifzLensGuide =>
        SettingsCoachStep.hifzLens,
      SettingsCoachStep.marginImages when _showFullScreenGuide =>
        SettingsCoachStep.fullScreen,
      SettingsCoachStep.hideBar when _showHifzLensGuide =>
        SettingsCoachStep.hifzLens,
      SettingsCoachStep.hideBar when _showFullScreenGuide =>
        SettingsCoachStep.fullScreen,
      SettingsCoachStep.hifzLens when _showFullScreenGuide =>
        SettingsCoachStep.fullScreen,
      // Background playback is the last auto-tour step, reached once the
      // earlier guides (if any) have been shown.
      SettingsCoachStep.browseMode when _showBackgroundPlaybackGuide =>
        SettingsCoachStep.backgroundPlayback,
      SettingsCoachStep.autoScroll when _showBackgroundPlaybackGuide =>
        SettingsCoachStep.backgroundPlayback,
      SettingsCoachStep.marginImages when _showBackgroundPlaybackGuide =>
        SettingsCoachStep.backgroundPlayback,
      SettingsCoachStep.hideBar when _showBackgroundPlaybackGuide =>
        SettingsCoachStep.backgroundPlayback,
      SettingsCoachStep.hifzLens when _showBackgroundPlaybackGuide =>
        SettingsCoachStep.backgroundPlayback,
      SettingsCoachStep.fullScreen when _showBackgroundPlaybackGuide =>
        SettingsCoachStep.backgroundPlayback,
      _ => null,
    };
  }

  bool get _hasAnotherCoachStep {
    if (_isManualCoachPresentation) return false;
    return _nextCoachStep(_activeCoachStep, manual: false) != null;
  }

  void _rememberTapPosition(Offset globalPosition) {
    final overlayContext = _settingsOverlayKey.currentContext;
    if (overlayContext == null) return;
    final box = overlayContext.findRenderObject() as RenderBox?;
    if (box == null) return;
    _lastTapPosition = box.globalToLocal(globalPosition);
  }

  void _showSettingsNotice(String text) {
    final overlayContext = _settingsOverlayKey.currentContext;
    if (overlayContext == null) return;
    final box = overlayContext.findRenderObject() as RenderBox?;
    if (box == null) return;

    final size = box.size;
    final tapPosition =
        _lastTapPosition ?? Offset(size.width / 2, size.height / 2);
    const noticeWidth = 260.0;
    const noticeHeight = 46.0;
    const margin = 14.0;

    final dx = (tapPosition.dx - (noticeWidth / 2))
        .clamp(margin, size.width - noticeWidth - margin)
        .toDouble();
    final dy = (tapPosition.dy - noticeHeight - 12)
        .clamp(margin, size.height - noticeHeight - margin)
        .toDouble();

    _settingsNoticeTimer?.cancel();
    setState(() {
      _settingsNoticeText = text;
      _noticePosition = Offset(dx, dy);
    });
    _settingsNoticeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _settingsNoticeText = null;
      });
    });
  }

  Future<bool> _confirmDownload({
    required String title,
    required String body,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, textDirection: TextDirection.rtl),
        content: Text(body, textDirection: TextDirection.rtl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تحميل'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _handleMarginImagesDownload() async {
    final shouldContinue = await _confirmDownload(
      title: 'تحميل عرض الهوامش',
      body:
          'سيتم تنزيل ملف عرض الهوامش بحجم تقريبي ${_marginImagesService.state.value.packageSizeLabel}. بعد اكتمال التحميل يمكنك التبديل بين العرض العادي وعرض الهوامش. هل تريد المتابعة؟',
    );
    if (!shouldContinue || !mounted) return;

    try {
      await _marginImagesService.downloadAndEnable();
    } catch (error) {
      if (!mounted) return;
      _showSettingsNotice(_describeMarginImagesError(error));
    }
  }

  String _describeMarginImagesError(Object error) {
    final text = error.toString();

    if (text.contains('SHA-256 mismatch')) {
      return 'تم تنزيل الملف لكن التحقق فشل. الملف المرفوع لا يطابق البصمة الحالية.';
    }

    if (text.contains('Extracted pages are incomplete')) {
      return 'ملف عرض الهوامش ناقص. يجب أن يحتوي على جميع الصفحات من 1 إلى 602.';
    }

    if (text.contains('status 404')) {
      return 'رابط ملف عرض الهوامش غير صحيح أو أن الملف غير موجود في GitHub Release.';
    }

    if (text.contains('status 403')) {
      return 'تم رفض الوصول إلى ملف عرض الهوامش. تحقق من أن الملف مرفوع بشكل عام.';
    }

    if (text.contains('SocketException')) {
      return 'تعذر الاتصال بالإنترنت أثناء تحميل عرض الهوامش.';
    }

    if (text.contains('HttpException')) {
      return 'تعذر تنزيل ملف عرض الهوامش من الرابط الحالي.';
    }

    return 'تعذر تحميل صور الهوامش. حاول مرة أخرى، وإذا تكرر الخطأ فالغالب أن الملف المرفوع فيه مشكلة.';
  }

  void _openFullscreenMenuPage({required String title, required Widget child}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenMenuPage(
          title: title,
          isDarkMode: Theme.of(context).brightness == Brightness.dark,
          child: child,
        ),
      ),
    );
  }

  Future<void> _openUsefulLink(String url) async {
    try {
      final uri = Uri.parse(url);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
      }
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
    }
  }

  Future<void> _handleReciterSelect(Reciter reciter) async {
    if (_reciterService.selected.value.id == reciter.id) return;
    await _reciterService.select(reciter);
    if (!mounted) return;
    _showSettingsNotice('تم اختيار تلاوة ${reciter.name}.');
  }

  void _openDownloadsManagementPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DownloadsManagementPage(
          audioDownloadService: _audioDownloadService,
          marginImagesService: _marginImagesService,
          highQualityImagesService: _highQualityImagesService,
        ),
      ),
    );
  }

  void _showInfoNotice(String text) {
    _showSettingsNotice(text);
  }

  String get _marginImagesInfoText =>
      _marginImagesService.state.value.isAvailable
          ? 'بعد تنزيل صور الهوامش يمكنك التبديل بين العرض بالهوامش والعرض العادي.'
          : 'نزّل حزمة صور الهوامش أولًا، ثم اختر لاحقًا تفعيل عرض الهوامش أو إيقافه.';

  String get _audioDownloadInfoText {
    final audioState = _audioDownloadService.state.value;
    return audioState.isComplete
        ? 'جميع ملفات الصوت للقارئ المختار محمّلة، ويمكن الاستماع للتلاوة بدون إنترنت.'
        : 'نزّل ملفات الصوت كاملة للقارئ المختار فقط للاستماع بدون اتصال بالإنترنت. الحجم التقريبي نحو 500 MB.';
  }

  String get _downloadsManagementInfoText =>
      'اعرض الملفات الإضافية التي حملتها، وحجمها الحالي، واحذف ما لا تحتاجه لاحقًا.';

  String get _reciterInfoText =>
      'اختر التلاوة. عند التبديل يتوقف التشغيل الحالي، ولكل قارئ ملفاته المحمّلة الخاصة.';

  String get _updateNotifyInfoText =>
      'عند تفعيله ستصلك رسالة التحديث كإشعار من النظام أيضًا. عند إيقافه تظهر الرسالة داخل التطبيق فقط عند فتحه.';

  /// Manual "check for updates" from Settings. Unlike the startup check, this
  /// always tells the user the result — including "you're up to date".
  Future<void> _handleCheckForUpdate() async {
    if (_isCheckingForUpdate) return;
    setState(() => _isCheckingForUpdate = true);
    try {
      final info = await _appUpdateService.fetchIfUpdateAvailable();
      if (!mounted) return;
      if (info == null) {
        _showSettingsNotice('أنت تستخدم أحدث إصدار من التطبيق.');
        return;
      }
      await _appUpdateService.markSurfaced(info);
      if (!mounted) return;
      await UpdateAvailableDialog.show(context, info);
    } catch (_) {
      if (mounted) {
        _showSettingsNotice('تعذر التحقق من التحديثات. تحقق من اتصالك بالإنترنت.');
      }
    } finally {
      if (mounted) setState(() => _isCheckingForUpdate = false);
    }
  }

  Future<void> _handleToggleUpdateNotifications(bool useNotifications) async {
    final mode = useNotifications
        ? UpdateNotifyMode.notification
        : UpdateNotifyMode.inApp;
    // Ask for the OS notification permission the moment the user opts in, so a
    // later update actually reaches them.
    if (useNotifications) {
      final granted =
          await UpdateNotificationService.instance.requestPermission();
      if (!mounted) return;
      if (!granted) {
        _showSettingsNotice(
          'لم يتم منح إذن الإشعارات. فعّله من إعدادات النظام لاستقبال إشعار التحديث.',
        );
        // Still persist the choice; the message will appear in-app regardless.
      }
    }
    await _appUpdateService.setNotifyMode(mode);
  }

  String get _recitationBarButtonsOpacityInfoText =>
      'تتحكم في وضوح أيقونات شريط التلاوة مثل التشغيل والتالي والتكرار. كلما اتجهت لليمين زاد الوضوح.';

  String get _recitationBarBackgroundOpacityInfoText =>
      'تتحكم في وضوح خلفية شريط التلاوة نفسه. كلما اتجهت لليمين زاد الوضوح.';

  String get _systemScreenTimeoutInfoText =>
      'عند تفعيل هذا الخيار يلتزم التطبيق بإعدادات الهاتف لقفل وإطفاء الشاشة. عند إيقافه تبقى الشاشة مستيقظة أثناء القراءة داخل التطبيق.';

  String get _pageZoomInfoText =>
      'يتيح لك تكبير صفحة المصحف بتقريب أصابعك (Pinch) مثل الصور. عند إيقاف هذا الخيار لا يمكن تكبير الصفحة.';

  Future<void> _resetGuides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_marginGuideDismissedPrefKey);
    await prefs.remove(_autoScrollGuideDismissedPrefKey);
    await prefs.remove(_browseModeGuideDismissedPrefKey);
    await prefs.remove(_bookmarkGuideDismissedPrefKey);
    await prefs.remove('hifzLensGuideDismissed');
    await prefs.remove('hideBarReaderGuideDismissed');
    await prefs.remove('fullScreenGuideDismissed');
    await prefs.remove(_hifzLensSettingsGuideDismissedPrefKey);
    await prefs.remove(_fullScreenSettingsGuideDismissedPrefKey);
    await prefs.remove(_backgroundPlaybackGuideDismissedPrefKey);
    if (!mounted) return;

    setState(() {
      _showBrowseModeGuide = true;
      _showMarginGuide = true;
      _showAutoScrollGuide = true;
      _showHifzLensGuide = true;
      _showFullScreenGuide = true;
      _showBackgroundPlaybackGuide = true;
      _activeCoachStep = null;
      _activeCoachRect = null;
    });

    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _showNextCoachStep();
      });
    });

    _showSettingsNotice(
      'تمت إعادة تفعيل الإرشادات. سيظهر إرشاد العلامات مرة أخرى داخل القارئ.',
    );
  }

  void _ensureLandscapeScrollMode(bool isLandscape) {
    if (!isLandscape || _localPortraitScrollMode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _localPortraitScrollMode) return;
      setState(() {
        _localPortraitScrollMode = true;
      });
      widget.onTogglePortraitScrollMode(true);
    });
  }

  /// Collapsed "advanced settings" section, shown just below the audio
  /// download tile. To add a new advanced setting later, append its widget to
  /// [advancedChildren] — a thin divider is inserted automatically between
  /// entries, so no further layout wiring is needed.
  Widget _buildAdvancedSettingsSection() {
    final advancedChildren = <Widget>[
      // The "جودة عرض الصفحات" quality picker was removed: page images now
      // always render at the highest fidelity ("فائق الجودة"), which is bundled
      // in the app, so there is nothing left for the user to choose or download.
      ValueListenableBuilder<double>(
        valueListenable: _recitationBarOpacityService.opacity,
        builder: (context, opacity, _) {
          return RecitationBarOpacityTile(
            title: 'شفافية أزرار شريط التلاوة',
            icon: Icons.opacity_rounded,
            opacity: opacity,
            onChanged: _recitationBarOpacityService.setOpacity,
            onInfo: () => _showInfoNotice(_recitationBarButtonsOpacityInfoText),
          );
        },
      ),
      ValueListenableBuilder<double>(
        valueListenable: _recitationBarOpacityService.backgroundOpacity,
        builder: (context, backgroundOpacity, _) {
          return RecitationBarOpacityTile(
            title: 'شفافية خلفية شريط التلاوة',
            icon: Icons.gradient_rounded,
            opacity: backgroundOpacity,
            onChanged: _recitationBarOpacityService.setBackgroundOpacity,
            onInfo:
                () => _showInfoNotice(_recitationBarBackgroundOpacityInfoText),
          );
        },
      ),
      ValueListenableBuilder<bool>(
        valueListenable: _keepScreenAwakeService.enabled,
        builder: (context, keepAwakeEnabled, _) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: CompactSwitchTile(
              title: 'استخدام إعدادات الهاتف لقفل وإطفاء الشاشة',
              icon: Icons.screen_lock_portrait_rounded,
              onInfo: () => _showInfoNotice(_systemScreenTimeoutInfoText),
              value: !keepAwakeEnabled,
              onChanged: (useSystemScreenTimeout) {
                _keepScreenAwakeService.setEnabled(!useSystemScreenTimeout);
              },
            ),
          );
        },
      ),
      ValueListenableBuilder<bool>(
        valueListenable: _pageZoomService.enabled,
        builder: (context, zoomEnabled, _) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: CompactSwitchTile(
              title: 'تكبير الصفحة بتقريب الأصابع',
              icon: Icons.zoom_in_rounded,
              onInfo: () => _showInfoNotice(_pageZoomInfoText),
              value: zoomEnabled,
              onChanged: _pageZoomService.setEnabled,
            ),
          );
        },
      ),
    ];

    return SettingsCard(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: EdgeInsets.zero,
            iconColor: const Color(0xFF8B7355),
            collapsedIconColor: const Color(0xFF8B7355),
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Row(
              children: [
                Icon(Icons.tune_rounded, color: Color(0xFF8B7355), size: 20),
                SizedBox(width: 8),
                Text(
                  'إعدادات متقدمة',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2C2C2C),
                  ),
                ),
              ],
            ),
            children: [
              for (var i = 0; i < advancedChildren.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 12,
                    endIndent: 12,
                    color: Color(0xFFE8DCC8),
                  ),
                advancedChildren[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    _ensureLandscapeScrollMode(isLandscape);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F1E5),
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFFF6F1E5),
        foregroundColor: const Color(0xFF2C2C2C),
        title: const Text(
          _settingsTitle,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) => _rememberTapPosition(event.position),
          child: Stack(
            key: _settingsOverlayKey,
            children: [
              AnimationLimiter(
                child: ListView(
                  physics: _activeCoachStep != null
                      ? const NeverScrollableScrollPhysics()
                      : const AlwaysScrollableScrollPhysics(),
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    isTablet ? 20 : 14,
                    10,
                    isTablet ? 20 : 14,
                    16,
                  ),
                  children: AnimationConfiguration.toStaggeredList(
                    duration: const Duration(milliseconds: 400),
                    childAnimationBuilder: (widget) => SlideAnimation(
                      verticalOffset: 50.0,
                      child: FadeInAnimation(child: widget),
                    ),
                    children: [
                      const SizedBox(height: 4),
                      SettingsCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Screen brightness on a single compact line:
                              // label, slider and percentage side by side.
                              Container(
                                key: _brightnessKey,
                                child: Row(
                                  textDirection: TextDirection.rtl,
                                  children: [
                                    const Icon(
                                      Icons.wb_sunny_rounded,
                                      color: Color(0xFF8B7355),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'إضاءة الشاشة',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2C2C2C),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    InfoHintButton(
                                      onTap: () => _presentCoachManually(
                                        SettingsCoachStep.screenBrightness,
                                      ),
                                    ),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 3,
                                          activeTrackColor: const Color(
                                            0xFF8D6E3F,
                                          ),
                                          thumbColor: const Color(0xFF8D6E3F),
                                          overlayColor: const Color(
                                            0xFF8D6E3F,
                                          ).withValues(alpha: 0.1),
                                          inactiveTrackColor: const Color(
                                            0xFF8D6E3F,
                                          ).withValues(alpha: 0.1),
                                        ),
                                        child: Slider(
                                          value: _brightness,
                                          onChanged: (v) async {
                                            setState(() => _brightness = v);
                                            await ScreenBrightness()
                                                .setApplicationScreenBrightness(
                                                  v,
                                                );
                                          },
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 38,
                                      child: Text(
                                        '${(_brightness * 100).round()}%',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF8D6E3F),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 12),
                              Container(
                                key: _darkModeKey,
                                child: Row(
                                  textDirection: TextDirection.rtl,
                                  children: [
                                    const Icon(
                                      Icons.dark_mode_rounded,
                                      color: Color(0xFF8B7355),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'الوضع الليلي',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2C2C2C),
                                      ),
                                    ),
                                    const Spacer(),
                                    InfoHintButton(
                                      onTap: () => _presentCoachManually(
                                        SettingsCoachStep.darkMode,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Switch(
                                      value: widget.isDarkMode,
                                      onChanged: widget.onToggleDarkMode,
                                      activeThumbColor: const Color(0xFF8D6E3F),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Every setting on its own full-width line; no sections.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              key: _hideBarCardKey,
                              child: CompactSwitchTile(
                                title: 'شريط الإخفاء',
                                icon: Icons.visibility_off_rounded,
                                onInfo: () => _presentCoachManually(
                                  SettingsCoachStep.hideBar,
                                ),
                                value: widget.isHideBarEnabled,
                                onChanged: (value) {
                                  widget.onToggleHideBar(value);
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              key: _hifzLensKey,
                              child: CompactSwitchTile(
                                title: 'عدسة الإخفاء',
                                icon: Icons.psychology_rounded,
                                iconOverride: const HifzLensIcon(
                                  size: 20,
                                  color: Color(0xFF8B7355),
                                ),
                                onInfo: () => _presentCoachManually(
                                  SettingsCoachStep.hifzLens,
                                ),
                                value: widget.isHifzModeEnabled,
                                onChanged: (value) {
                                  widget.onToggleHifzMode(value);
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              key: _browseModeCardKey,
                              child: CompactSwitchTile(
                                title: 'وضع التمرير',
                                icon: Icons.swap_calls_rounded,
                                onInfo: () => _presentCoachManually(
                                  SettingsCoachStep.browseMode,
                                ),
                                value: isLandscape
                                    ? true
                                    : _localPortraitScrollMode,
                                onChanged:
                                    (isLandscape
                                        ? false
                                        : _localAllowPortraitScrollMode)
                                    ? (value) {
                                        setState(() {
                                          _localPortraitScrollMode = value;
                                        });
                                        widget.onTogglePortraitScrollMode(
                                          value,
                                        );
                                      }
                                    : (_) => _showSettingsNotice(
                                        isLandscape
                                            ? 'في الوضع الأفقي يكون التصفح دائمًا على التمرير.'
                                            : scrollUnavailableInTabletNotice,
                                      ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              key: _autoScrollCardKey,
                              child: CompactSwitchTile(
                                title: autoScrollTitle,
                                icon: Icons.swap_vert_rounded,
                                onInfo: () => _presentCoachManually(
                                  SettingsCoachStep.autoScroll,
                                ),
                                value: _localAutoScrollEnabled,
                                onChanged: (value) {
                                  if (value &&
                                      (_localTabletLayoutMode ||
                                          !_localAllowPortraitScrollMode)) {
                                    _showSettingsNotice(
                                      autoScrollUnavailableNotice,
                                    );
                                    return;
                                  }

                                  setState(() {
                                    if (value && !_localPortraitScrollMode) {
                                      _localPortraitScrollMode = true;
                                    }
                                    _localAutoScrollEnabled = value;
                                  });
                                  widget.onToggleAutoScroll(value);
                                  if (value) {
                                    Navigator.pop(context);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              key: _fullScreenKey,
                              child: CompactSwitchTile(
                                title: 'وضع ملء الشاشة',
                                icon: Icons.fullscreen_rounded,
                                onInfo: () => _presentCoachManually(
                                  SettingsCoachStep.fullScreen,
                                ),
                                value: _localFullScreenMode,
                                onChanged: (value) {
                                  setState(() => _localFullScreenMode = value);
                                  widget.onToggleFullScreenMode(value);
                                },
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              key: _twoPageKey,
                              child: Opacity(
                                opacity: widget.showTabletLayoutSetting
                                    ? 1
                                    : 0.5,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: widget.showTabletLayoutSetting
                                      ? null
                                      : () => _showSettingsNotice(
                                          tabletOnlyNotice,
                                        ),
                                  child: CompactSwitchTile(
                                    title: 'عرض الصفحتين',
                                    icon: Icons.auto_stories_rounded,
                                    onInfo: () => _presentCoachManually(
                                      SettingsCoachStep.twoPage,
                                    ),
                                    value: _localTabletLayoutMode,
                                    onChanged: widget.showTabletLayoutSetting
                                        ? (value) {
                                            setState(() {
                                              _localTabletLayoutMode = value;
                                              if (value) {
                                                _localAutoScrollEnabled = false;
                                                _localPortraitScrollMode =
                                                    false;
                                              }
                                            });
                                            widget.onToggleTabletLayoutMode(
                                              value,
                                            );
                                          }
                                        : (_) {},
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        key: _marginImagesCardKey,
                        child: SettingsCard(
                          child: ValueListenableBuilder<MarginImagesState>(
                            valueListenable: _marginImagesService.state,
                            builder: (context, marginState, _) {
                              return MarginImagesTile(
                                state: marginState,
                                onDownload: _handleMarginImagesDownload,
                                onCancelDownload:
                                    _marginImagesService.cancelDownload,
                                onPauseDownload:
                                    _marginImagesService.pauseDownload,
                                onToggleEnabled:
                                    _marginImagesService.setEnabled,
                                onInfo: () => _showInfoNotice(
                                  _marginImagesInfoText,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        key: _reciterKey,
                        child: SettingsCard(
                          child: ValueListenableBuilder<Reciter>(
                            valueListenable: _reciterService.selected,
                            builder: (context, selectedReciter, _) {
                              return ReciterTile(
                                reciters: _reciterService.reciters,
                                selected: selectedReciter,
                                onSelect: _handleReciterSelect,
                                onInfo: () => _showInfoNotice(_reciterInfoText),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          key: _backgroundPlaybackKey,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _backgroundPlaybackService.enabled,
                            builder: (context, enabled, _) {
                              return CompactSwitchTile(
                                title: 'تشغيل التلاوة في الخلفية',
                                icon: Icons.headset_rounded,
                                onInfo: () => _presentCoachManually(
                                  SettingsCoachStep.backgroundPlayback,
                                ),
                                value: enabled,
                                onChanged:
                                    _backgroundPlaybackService.setEnabled,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        key: _audioDownloadKey,
                        child: SettingsCard(
                          child: ValueListenableBuilder<AudioDownloadState>(
                            valueListenable: _audioDownloadService.state,
                            builder: (context, audioState, _) {
                              return AudioDownloadTile(
                                state: audioState,
                                onDownload: _audioDownloadService.downloadAll,
                                onCancelDownload:
                                    _audioDownloadService.cancelDownload,
                                onPauseDownload:
                                    _audioDownloadService.pauseDownload,
                                onInfo: () => _showInfoNotice(
                                  _audioDownloadInfoText,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildAdvancedSettingsSection(),
                      if (!isLandscape) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            key: _resetGuidesKey,
                            child: CompactActionTile(
                              title: 'إعادة الإرشادات',
                              icon: Icons.tips_and_updates_rounded,
                              onInfo: () => _presentCoachManually(
                                SettingsCoachStep.resetGuides,
                              ),
                              onTap: _resetGuides,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        key: _downloadsManagementKey,
                        child: SettingsCard(
                          child: DownloadsManagementTile(
                            onOpen: _openDownloadsManagementPage,
                            onInfo: () => _showInfoNotice(
                              _downloadsManagementInfoText,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // App update: manual check + delivery preference
                      // (in-app by default, or a system notification too).
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CompactActionTile(
                              title: _isCheckingForUpdate
                                  ? 'جارٍ التحقق...'
                                  : 'التحقق من وجود تحديث',
                              icon: Icons.system_update_rounded,
                              onTap: _handleCheckForUpdate,
                            ),
                            const SizedBox(height: 6),
                            ValueListenableBuilder<UpdateNotifyMode>(
                              valueListenable: _appUpdateService.notifyMode,
                              builder: (context, mode, _) {
                                return CompactSwitchTile(
                                  title: 'إشعار عند توفر تحديث',
                                  icon: Icons.notifications_active_rounded,
                                  onInfo: () =>
                                      _showInfoNotice(_updateNotifyInfoText),
                                  value: mode == UpdateNotifyMode.notification,
                                  onChanged: _handleToggleUpdateNotifications,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Navigation entries paired two-per-row to keep the
                      // section compact.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: CompactActionTile(
                                    title: 'حول التطبيق',
                                    icon: Icons.info_outline_rounded,
                                    onTap: () => _openFullscreenMenuPage(
                                      title: 'حول التطبيق',
                                      child: const AboutContent(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: CompactActionTile(
                                    title: 'تواصل معنا',
                                    icon: Icons.alternate_email_rounded,
                                    onTap: () => _openFullscreenMenuPage(
                                      title: 'تواصل معنا',
                                      child: ContactContent(
                                        onOpenLink: _openUsefulLink,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_settingsNoticeText != null && _noticePosition != null)
                Positioned(
                  left: _noticePosition!.dx,
                  top: _noticePosition!.dy,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: 1,
                      child: Container(
                        width: 260,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _settingsNoticeText!,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // The auto-tour is portrait-only, but an on-demand (ℹ️)
              // instruction is a centred dialog that works in either
              // orientation.
              if ((!isLandscape || _isManualCoachPresentation) &&
                  _activeCoachStep != null &&
                  _activeCoachRect != null)
                SettingsCoachOverlay(
                  step: _activeCoachStep!,
                  targetRect: _activeCoachRect!,
                  centerDialog: _isManualCoachPresentation,
                  showDontShowAgain: !_isManualCoachPresentation,
                  title: _activeCoachTitle,
                  message: _activeCoachMessage,
                  actionLabel: _hasAnotherCoachStep ? 'التالي' : 'فهمت',
                  onAction: _closeActiveCoachForNow,
                  onDontShowAgain: _dismissActiveCoachForever,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

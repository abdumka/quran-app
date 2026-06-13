import 'dart:async';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'settings_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../search_page.dart';

import '../../services/high_quality_images_service.dart';
import '../../services/margin_images_service.dart';
import '../../utils/responsive_helper.dart';

import 'settings_components.dart';
import 'settings_coach_overlay.dart';
import 'downloads_management_page.dart';
import '../menu/about_content.dart';
import '../menu/support_content.dart';
import '../menu/contact_content.dart';
import '../menu/useful_links_content.dart';
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
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}



class _SettingsPageState extends State<SettingsPage> {
  static const String _settingsTitle =
      '\u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a';
  static const String _marginGuideDismissedPrefKey =
      'marginGuideDismissed';
  static const String _autoScrollGuideDismissedPrefKey =
      'autoScrollGuideDismissed';
  static const String _browseModeGuideDismissedPrefKey =
      'browseModeGuideDismissed';
  static const String _bookmarkGuideDismissedPrefKey =
      'bookmarkGuideDismissed';

  late bool _localAutoScrollEnabled;
  late bool _localPortraitScrollMode;
  late bool _localTabletLayoutMode;
  bool _showBrowseModeGuide = false;
  bool _showMarginGuide = false;
  bool _showAutoScrollGuide = false;
  final HighQualityImagesService _highQualityImagesService =
      HighQualityImagesService.instance;
  final MarginImagesService _marginImagesService = MarginImagesService.instance;

  final GlobalKey _settingsOverlayKey = GlobalKey();
  final GlobalKey _browseModeCardKey = GlobalKey();
  final GlobalKey _autoScrollCardKey = GlobalKey();
  final GlobalKey _marginImagesCardKey = GlobalKey();
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
    _highQualityImagesService.initialize();
    _marginImagesService.initialize();
    _loadGuidePreferences();
    _loadCurrentBrightness();
  }

  Future<void> _loadCurrentBrightness() async {
    try {
      final value = await ScreenBrightness().current;
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
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Wait for staggered list animations (SlideAnimation) to fully complete
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _showNextCoachStep();
      });
    });
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

    final nextStep = _nextCoachStep(
      previousStep,
      manual: false,
    );

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
    }
  }

  void _showCoachStepOnDemand(SettingsCoachStep step) {
    setState(() {
      _isManualCoachPresentation = true;
      _activeCoachStep = null;
      _activeCoachRect = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _activateCoachStep(step);
    });
  }

  void _activateCoachStep(SettingsCoachStep step) {
    final targetContext = switch (step) {
      SettingsCoachStep.browseMode => _browseModeCardKey.currentContext,
      SettingsCoachStep.autoScroll => _autoScrollCardKey.currentContext,
      SettingsCoachStep.marginImages => _marginImagesCardKey.currentContext,
    };

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

    final targetContext = switch (step) {
      SettingsCoachStep.browseMode => _browseModeCardKey.currentContext,
      SettingsCoachStep.autoScroll => _autoScrollCardKey.currentContext,
      SettingsCoachStep.marginImages => _marginImagesCardKey.currentContext,
    };
    if (targetContext == null) return null;
    final targetBox = targetContext.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize) return null;

    final topLeft = targetBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    return topLeft & targetBox.size;
  }

  Future<void> _dismissActiveCoachForever() async {
    final step = _activeCoachStep;
    if (step == null) return;
    final key = switch (step) {
      SettingsCoachStep.browseMode => _browseModeGuideDismissedPrefKey,
      SettingsCoachStep.autoScroll => _autoScrollGuideDismissedPrefKey,
      SettingsCoachStep.marginImages => _marginGuideDismissedPrefKey,
    };
    await _dismissGuide(key);
    if (!mounted) return;
    final nextStep = _nextCoachStep(
      step,
      manual: _isManualCoachPresentation,
    );
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
      return switch (step) {
        SettingsCoachStep.browseMode => SettingsCoachStep.autoScroll,
        SettingsCoachStep.autoScroll => SettingsCoachStep.marginImages,
        SettingsCoachStep.marginImages => null,
      };
    }

    return switch (step) {
      SettingsCoachStep.browseMode when _showAutoScrollGuide =>
        SettingsCoachStep.autoScroll,
      SettingsCoachStep.browseMode when _showMarginGuide =>
        SettingsCoachStep.marginImages,
      SettingsCoachStep.autoScroll when _showMarginGuide =>
        SettingsCoachStep.marginImages,
      _ => null,
    };
  }

  bool get _hasAnotherCoachStep {
    if (_isManualCoachPresentation) return false;
    return _nextCoachStep(
          _activeCoachStep,
          manual: false,
        ) !=
        null;
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

  Future<void> _handleHighQualityDownload() async {
    final shouldContinue = await _confirmDownload(
      title: 'تحميل الجودة العالية',
      body:
          'سيتم تنزيل ملف الصور عالية الجودة بحجم تقريبي ${_highQualityImagesService.state.value.packageSizeLabel}. بعد اكتمال التحميل سيستخدمها التطبيق تلقائيًا. هل تريد المتابعة؟',
    );
    if (!shouldContinue || !mounted) return;

    try {
      await _highQualityImagesService.downloadAndEnable();
    } catch (_) {
      if (!mounted) return;
      _showSettingsNotice(
        'تعذر تحميل الصور عالية الجودة. تأكد من اتصال الإنترنت ثم حاول مرة أخرى.',
      );
    }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الرابط')),
        );
      }
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الرابط')),
      );
    }
  }

  void _openDownloadsManagementPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DownloadsManagementPage(
          highQualityImagesService: _highQualityImagesService,
          marginImagesService: _marginImagesService,
        ),
      ),
    );
  }

  Future<void> _resetGuides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_marginGuideDismissedPrefKey);
    await prefs.remove(_autoScrollGuideDismissedPrefKey);
    await prefs.remove(_browseModeGuideDismissedPrefKey);
    await prefs.remove(_bookmarkGuideDismissedPrefKey);
    if (!mounted) return;

    setState(() {
      _showBrowseModeGuide = true;
      _showMarginGuide = true;
      _showAutoScrollGuide = true;
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
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
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
                      const SectionHeader(title: 'أدوات سريعة'),
                      const SizedBox(height: 4),
                      SettingsCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                textDirection: TextDirection.rtl,
                                children: [
                                  const Icon(Icons.wb_sunny_rounded, color: Color(0xFF8D6E3F), size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'إضاءة الشاشة',
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF3D3122),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${(_brightness * 100).round()}%',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF8D6E3F),
                                    ),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: const Color(0xFF8D6E3F),
                                  thumbColor: const Color(0xFF8D6E3F),
                                  overlayColor: const Color(0xFF8D6E3F).withValues(alpha: 0.1),
                                  inactiveTrackColor: const Color(0xFF8D6E3F).withValues(alpha: 0.1),
                                ),
                                child: Slider(
                                  value: _brightness,
                                  onChanged: (v) async {
                                    setState(() => _brightness = v);
                                    await ScreenBrightness().setScreenBrightness(v);
                                  },
                                ),
                              ),
                              const Divider(height: 24),
                              Row(
                                textDirection: TextDirection.rtl,
                                children: [
                                  const Icon(Icons.dark_mode_rounded, color: Color(0xFF8D6E3F), size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'الوضع الليلي',
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF3D3122),
                                    ),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: widget.isDarkMode,
                                    onChanged: widget.onToggleDarkMode,
                                    activeThumbColor: const Color(0xFF8D6E3F),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SectionHeader(title: 'العرض والتصفح'),
                      const SizedBox(height: 4),
                      const SizedBox(height: 12),
                      Container(
                        key: _autoScrollCardKey,
                        child: SettingsCard(
                          child: SwitchTile(
                            title: autoScrollTitle,
                            subtitle: autoScrollSubtitle,
                            icon: Icons.vertical_align_bottom_rounded,
                            value: _localAutoScrollEnabled,
                            onHelp: () =>
                                _showCoachStepOnDemand(SettingsCoachStep.autoScroll),
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
                      ),
                      const SizedBox(height: 10),
                      Opacity(
                        opacity: widget.showTabletLayoutSetting ? 1 : 0.5,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.showTabletLayoutSetting
                              ? null
                              : () => _showSettingsNotice(
                                    tabletOnlyNotice,
                                  ),
                          child: SettingsCard(
                            child: TabletLayoutTile(
                              value: _localTabletLayoutMode,
                              enabled: widget.showTabletLayoutSetting,
                              onChanged: (value) {
                                setState(() {
                                  _localTabletLayoutMode = value;
                                  if (value) {
                                    _localAutoScrollEnabled = false;
                                    _localPortraitScrollMode = false;
                                  }
                                });
                                widget.onToggleTabletLayoutMode(value);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        key: _browseModeCardKey,
                        child: SettingsCard(
                          child: ModeTile(
                            isTablet: isTablet,
                            isPortraitScrollMode: isLandscape
                                ? true
                                : _localPortraitScrollMode,
                            allowPortraitScrollMode: isLandscape
                                ? false
                                : _localAllowPortraitScrollMode,
                            lockToScrollMode: isLandscape,
                            onHelp: () =>
                                _showCoachStepOnDemand(SettingsCoachStep.browseMode),
                            onDisabledTap: () => _showSettingsNotice(
                              isLandscape
                                  ? 'في الوضع الأفقي يكون التصفح دائمًا على التمرير.'
                                  : scrollUnavailableInTabletNotice,
                            ),
                            onTogglePortraitScrollMode: (value) {
                              setState(() {
                                _localPortraitScrollMode = value;
                              });
                              widget.onTogglePortraitScrollMode(value);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
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
                                onToggleEnabled: _marginImagesService.setEnabled,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SettingsCard(
                        child: ValueListenableBuilder<HighQualityImagesState>(
                          valueListenable: _highQualityImagesService.state,
                          builder: (context, highQualityState, _) {
                            return HighQualityImagesTile(
                              state: highQualityState,
                              onDownload: _handleHighQualityDownload,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      SettingsCard(
                        child: DownloadsManagementTile(
                          onOpen: _openDownloadsManagementPage,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!isLandscape)
                        SettingsCard(
                          child: ActionTile(
                            title: 'إعادة عرض الإرشادات',
                            subtitle:
                                'يعيد إظهار إرشادات التمرير التلقائي وعرض الهوامش، ويعيد تفعيل إرشاد العلامات داخل القارئ.',
                            icon: Icons.tips_and_updates_rounded,
                            onTap: _resetGuides,
                          ),
                        ),
                      const SizedBox(height: 24),
                      const SectionHeader(title: 'حول'),
                      const SizedBox(height: 4),
                      SettingsCard(
                        child: ActionTile(
                          title: 'حول التطبيق',
                          subtitle: 'معلومات عن التطبيق والإصدار الحالي',
                          icon: Icons.info_outline_rounded,
                          onTap: () {
                            _openFullscreenMenuPage(
                              title: 'حول التطبيق',
                              child: const AboutContent(),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      SettingsCard(
                        child: ActionTile(
                          title: 'ادعمنا',
                          subtitle: 'ادعم التطبيق بتقييمك ودعائك',
                          icon: Icons.favorite_border_rounded,
                          onTap: () {
                            _openFullscreenMenuPage(
                              title: 'ادعمنا',
                              child: const SupportContent(),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      SettingsCard(
                        child: ActionTile(
                          title: 'تواصل معنا',
                          subtitle: 'ملاحظاتك واقتراحاتك تهمنا',
                          icon: Icons.alternate_email_rounded,
                          onTap: () {
                            _openFullscreenMenuPage(
                              title: 'تواصل معنا',
                              child: ContactContent(onOpenLink: _openUsefulLink),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      SettingsCard(
                        child: ActionTile(
                          title: 'روابط مفيدة',
                          subtitle: 'روابط لمواقع وتطبيقات إسلامية مفيدة',
                          icon: Icons.link_rounded,
                          onTap: () {
                            _openFullscreenMenuPage(
                              title: 'روابط مفيدة',
                              child: UsefulLinksContent(onOpenLink: _openUsefulLink),
                            );
                          },
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
              if (!isLandscape &&
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

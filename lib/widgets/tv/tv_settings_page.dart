import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/reciter.dart';
import '../../models/tafsir_edition.dart';
import '../../services/audio_download_service.dart';
import '../../services/reciter_service.dart';
import '../../services/recitation_bar_auto_hide_service.dart';
import '../../services/tafsir_edition_service.dart';
import '../../services/theme_service.dart';
import '../../services/tv_service.dart';
import 'tv_remote_guide.dart';
import '../../surah_data.dart';

/// Android TV settings. Deliberately NOT the phone settings page.
///
/// Material's Switch and Slider consume arrow keys to change their own value,
/// so walking the phone list with a D-pad silently flips settings on the way
/// past (observed: brightness dragged 55% -> 0%, شريط الإخفاء switched on).
/// Here the arrows only ever move the highlight; Select is the sole control
/// that changes anything. Nothing in this file is reachable off-TV.
class TvSettingsPage extends StatefulWidget {
  const TvSettingsPage({super.key});

  @override
  State<TvSettingsPage> createState() => _TvSettingsPageState();
}

class _TvSettingsPageState extends State<TvSettingsPage> {
  static const Color _gold = Color(0xFFD2B97E);
  static const Color _goldDark = Color(0xFF8D6E3F);

  int _index = 0;

  // Two-page and full-screen live as plain prefs that QuranPages reads, so the
  // TV screen can flip them without holding a handle on the reader's state.
  static const String _twoPagePrefKey = 'tabletLayoutMode';
  static const String _fullScreenPrefKey = 'fullScreenMode';
  bool _twoPage = true;
  bool _fullScreen = false;

  /// The list outgrew the screen once the extra settings were added, so the
  /// highlight has to drag the viewport with it -- a remote cannot scroll.
  final ScrollController _scroll = ScrollController();

  void _ensureVisible() {
    if (!_scroll.hasClients) return;
    const double rowExtent = 74;
    final double target =
        (_index * rowExtent) -
        (_scroll.position.viewportDimension / 2) +
        (rowExtent / 2);
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _twoPage = prefs.getBool(_twoPagePrefKey) ?? true;
      _fullScreen = prefs.getBool(_fullScreenPrefKey) ?? false;
    });
  }

  Future<void> _setPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _loadPrefs();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _scroll.dispose();
    super.dispose();
  }

  List<_Row> get _rows => [
    _Row(
      icon: Icons.record_voice_over_rounded,
      title: 'التلاوة',
      subtitle: ReciterService.instance.selected.value.name,
      onSelect: _openReciterPicker,
    ),
    _Row(
      icon: Icons.download_rounded,
      title: 'تنزيل السور للاستماع دون إنترنت',
      subtitle: 'اختر السور التي تريد حفظها على الجهاز',
      onSelect: _openDownloads,
    ),
    _Row(
      icon: Icons.menu_book_rounded,
      title: 'التفسير',
      subtitle: TafsirEditionService.instance.selected.value.name,
      onSelect: _openTafsirPicker,
    ),
    _Row(
      icon: Icons.timer_off_rounded,
      title: 'إخفاء شريط التلاوة تلقائيًا',
      subtitle: RecitationBarAutoHideService.instance.enabled.value
          ? 'بعد ${RecitationBarAutoHideService.instance.delaySeconds.value} ثانية من عدم الاستخدام'
          : 'مُعطَّل',
      onSelect: _openAutoHidePicker,
    ),
    _Row(
      icon: Icons.auto_stories_rounded,
      title: 'عرض الصفحتين',
      subtitle: _twoPage ? 'مُفعَّل' : 'مُعطَّل',
      onSelect: () {
        _twoPage = !_twoPage;
        _setPref(_twoPagePrefKey, _twoPage);
      },
    ),
    _Row(
      icon: Icons.fullscreen_rounded,
      title: 'وضع ملء الشاشة',
      subtitle: _fullScreen ? 'مُفعَّل' : 'مُعطَّل',
      onSelect: () {
        _fullScreen = !_fullScreen;
        _setPref(_fullScreenPrefKey, _fullScreen);
      },
    ),
    _Row(
      icon: Icons.settings_remote_rounded,
      title: 'التنقل بجهاز التحكم',
      subtitle: 'عرض إرشادات استخدام الريموت',
      onSelect: _showRemoteGuide,
    ),
    _Row(
      icon: Icons.dark_mode_rounded,
      title: 'الوضع الليلي',
      subtitle: ThemeService.themeMode.value == ThemeMode.dark
          ? 'مُفعَّل'
          : 'مُعطَّل',
      onSelect: () {
        ThemeService.setDarkMode(
          ThemeService.themeMode.value != ThemeMode.dark,
        );
        setState(() {});
      },
    ),
  ];

  bool _onKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    final key = event.logicalKey;
    final rows = _rows;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (_index + 1) % rows.length);
      _ensureVisible();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _index = (_index - 1 + rows.length) % rows.length);
      _ensureVisible();
      return true;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      rows[_index].onSelect();
      return true;
    }
    // Left/Right are swallowed so they cannot leak to the reader underneath.
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  Future<void> _openReciterPicker() async {
    final reciters = ReciterService.instance.reciters;
    final picked = await Navigator.of(context).push<Reciter>(
      MaterialPageRoute(
        builder: (_) => _TvPickerPage<Reciter>(
          title: 'اختيار التلاوة',
          items: reciters,
          labelOf: (r) => r.name,
          selectedIndex: reciters.indexWhere(
            (r) => r.id == ReciterService.instance.selected.value.id,
          ),
        ),
      ),
    );
    if (picked != null) {
      await ReciterService.instance.select(picked);
      if (mounted) setState(() {});
    }
  }

  /// The guide is shown once on first launch, but it has to stay reachable --
  /// a TV is often used by someone who did not set it up and never saw it.
  Future<void> _showRemoteGuide() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TvGuidePage(
          isDarkMode: ThemeService.themeMode.value == ThemeMode.dark,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Off, or one of a handful of idle delays. A picker rather than a toggle
  /// so the remote can change the delay too (the phone page has a stepper).
  static const List<int> _autoHideChoices = [
    0,
    5,
    10,
    15,
    20,
    30,
    45,
    60,
    90,
    120,
  ];

  Future<void> _openAutoHidePicker() async {
    final service = RecitationBarAutoHideService.instance;
    final current = service.enabled.value ? service.delaySeconds.value : 0;
    final picked = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => _TvPickerPage<int>(
          title: 'إخفاء شريط التلاوة تلقائيًا',
          items: _autoHideChoices,
          labelOf: (s) => s == 0 ? 'مُعطَّل' : 'بعد $s ثانية',
          selectedIndex: _autoHideChoices.indexOf(current),
        ),
      ),
    );
    if (picked == null) return;
    if (picked == 0) {
      await service.setEnabled(false);
    } else {
      await service.setDelaySeconds(picked);
      await service.setEnabled(true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _openTafsirPicker() async {
    final editions = TafsirEditionService.instance.editions;
    final picked = await Navigator.of(context).push<TafsirEdition>(
      MaterialPageRoute(
        builder: (_) => _TvPickerPage<TafsirEdition>(
          title: 'اختيار التفسير',
          items: editions,
          labelOf: (e) => e.name,
          selectedIndex: editions.indexWhere(
            (e) => e.id == TafsirEditionService.instance.selected.value.id,
          ),
        ),
      ),
    );
    if (picked != null) {
      await TafsirEditionService.instance.select(picked);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openDownloads() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TvDownloadsPage()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final rows = _rows;

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF15120B) : const Color(0xFFFAF6EE),
      body: SafeArea(
        child: Padding(
          // TV overscan: keep everything well inside the panel edges.
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 27),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'الإعدادات',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: rows.length,
                    itemBuilder: (context, i) =>
                        _rowTile(rows[i], i == _index, dark),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  kTvBuildStamp,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: (dark ? Colors.white : Colors.black87).withValues(
                      alpha: 0.45,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'استخدم السهمين أعلى وأسفل للتنقل، وزر الاختيار (OK) للفتح، وزر الرجوع للخروج',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: (dark ? Colors.white : Colors.black87).withValues(
                      alpha: 0.65,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowTile(_Row row, bool focused, bool dark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: focused
            ? _gold.withValues(alpha: 0.20)
            : (dark ? Colors.white : Colors.black).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? _gold : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(row.icon, color: focused ? _gold : _goldDark, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  row.subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: (dark ? Colors.white : Colors.black87).withValues(
                      alpha: 0.68,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onSelect;
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onSelect,
  });
}

/// Generic single-choice list driven entirely by Up/Down + Select.
class _TvPickerPage<T> extends StatefulWidget {
  const _TvPickerPage({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.selectedIndex,
  });

  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final int selectedIndex;

  @override
  State<_TvPickerPage<T>> createState() => _TvPickerPageState<T>();
}

class _TvPickerPageState<T> extends State<_TvPickerPage<T>> {
  late int _index = widget.selectedIndex < 0 ? 0 : widget.selectedIndex;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _scroll.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (_index + 1) % widget.items.length);
      _ensureVisible();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _index = (_index - 1 + widget.items.length) % widget.items.length,
      );
      _ensureVisible();
      return true;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      Navigator.of(context).pop(widget.items[_index]);
      return true;
    }
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  /// The list is taller than the screen, so keep the highlight on-screen.
  void _ensureVisible() {
    if (!_scroll.hasClients) return;
    const double rowExtent = 60;
    final double target =
        (_index * rowExtent) -
        (_scroll.position.viewportDimension / 2) +
        (rowExtent / 2);
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF15120B) : const Color(0xFFFAF6EE),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 27),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: widget.items.length,
                    itemBuilder: (context, i) {
                      final focused = i == _index;
                      return Container(
                        height: 52,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: AlignmentDirectional.centerStart,
                        decoration: BoxDecoration(
                          color: focused
                              ? const Color(0xFFD2B97E).withValues(alpha: 0.20)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: focused
                                ? const Color(0xFFD2B97E)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          widget.labelOf(widget.items[i]),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: focused
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: dark ? Colors.white : Colors.black87,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Per-surah offline download list for TV. Select downloads the highlighted
/// surah for the currently selected reciter; already-cached surahs say so.
class TvDownloadsPage extends StatefulWidget {
  const TvDownloadsPage({super.key});

  @override
  State<TvDownloadsPage> createState() => _TvDownloadsPageState();
}

class _TvDownloadsPageState extends State<TvDownloadsPage> {
  static const Color _gold = Color(0xFFD2B97E);

  int _index = 0;
  List<SurahDownloadStatus> _statuses = const [];
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    AudioDownloadService.instance.surahState.addListener(_onProgress);
    _refresh();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    AudioDownloadService.instance.surahState.removeListener(_onProgress);
    _scroll.dispose();
    super.dispose();
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final statuses = await AudioDownloadService.instance.computeSurahStatuses();
    if (mounted) setState(() => _statuses = statuses);
  }

  bool _onKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (_index + 1) % surahList.length);
      _ensureVisible();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _index = (_index - 1 + surahList.length) % surahList.length,
      );
      _ensureVisible();
      return true;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _downloadFocused();
      return true;
    }
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  void _ensureVisible() {
    if (!_scroll.hasClients) return;
    const double rowExtent = 60;
    final double target =
        (_index * rowExtent) -
        (_scroll.position.viewportDimension / 2) +
        (rowExtent / 2);
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  Future<void> _downloadFocused() async {
    final surah = surahList[_index]['number'] as int;
    final live = AudioDownloadService.instance.surahState.value;
    // One at a time; the service enforces this too.
    if (live.isDownloading) return;
    await AudioDownloadService.instance.downloadSurah(surah);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final live = AudioDownloadService.instance.surahState.value;

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF15120B) : const Color(0xFFFAF6EE),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 27),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تنزيل السور',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: dark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  ReciterService.instance.selected.value.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: (dark ? Colors.white : Colors.black87).withValues(
                      alpha: 0.65,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: surahList.length,
                    itemBuilder: (context, i) => _surahTile(i, dark, live),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  live.isDownloading
                      ? 'جارٍ التنزيل… ${(live.progressFraction * 100).round()}%'
                      : 'اضغط زر الاختيار (OK) لتنزيل السورة المحددة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: (dark ? Colors.white : Colors.black87).withValues(
                      alpha: 0.65,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _surahTile(int i, bool dark, SurahDownloadState live) {
    final focused = i == _index;
    final number = surahList[i]['number'] as int;
    final name = surahList[i]['name'] as String;
    final status = i < _statuses.length ? _statuses[i] : null;
    final bool downloading = live.isDownloading && live.surah == number;

    String trailing;
    Color trailingColor = _gold;
    if (downloading) {
      trailing = '${(live.progressFraction * 100).round()}%';
    } else if (status?.isComplete == true) {
      trailing = 'محفوظة';
      trailingColor = const Color(0xFF6FAE6F);
    } else if (status?.isPartial == true) {
      trailing = 'جزئية';
    } else {
      trailing = '';
    }

    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: focused ? _gold.withValues(alpha: 0.20) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused ? _gold : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 15,
                color: (dark ? Colors.white : Colors.black87).withValues(
                  alpha: 0.55,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 17,
                fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
                color: dark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Text(
            trailing,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: trailingColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hosts [TvRemoteGuide] as its own route so it can be reopened from settings.
/// Any of Select/Back closes it -- the same keys the guide itself tells the
/// user about, so there is no way to get stuck on the help screen.
class _TvGuidePage extends StatefulWidget {
  const _TvGuidePage({required this.isDarkMode});

  final bool isDarkMode;

  @override
  State<_TvGuidePage> createState() => _TvGuidePageState();
}

class _TvGuidePageState extends State<_TvGuidePage> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      Navigator.of(context).maybePop();
      return true;
    }
    // Swallow the arrows so they cannot drive the reader behind this screen.
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TvRemoteGuide(isDarkMode: widget.isDarkMode),
    );
  }
}

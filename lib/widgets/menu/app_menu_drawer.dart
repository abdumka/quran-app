import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_update_service.dart';
import '../../services/chat_service.dart';
import '../../utils/share_app.dart';
import 'about_content.dart';
import 'contact_content.dart';
import 'fullscreen_menu_page.dart';
import '../../theme/app_surfaces.dart';
import '../../utils/rate_app.dart';
import '../athkar/athkar_home_page.dart';
import '../usul/usul_pages.dart';

/// What the reader does for the drawer rows that act on the reader itself
/// (the current page, its Settings route). The app rows (contact, share,
/// rate, about) are handled by the drawer.
class AppMenuActions {
  const AppMenuActions({
    required this.openSettings,
    required this.openTafsir,
    required this.openReciter,
    required this.openDownloads,
    required this.openReminders,
    required this.openReports,
    required this.openWhatsNew,
  });

  final VoidCallback openSettings;
  final VoidCallback openTafsir;
  final VoidCallback openReciter;
  final VoidCallback openDownloads;
  final VoidCallback openReminders;
  final VoidCallback openReports;
  final VoidCallback openWhatsNew;
}

/// The side drawer behind the three gold lines in the reader's top bar
/// (phones and tablets; Android TV keeps its own bars). It slides in from the
/// right. الإعدادات is pinned under the header; the rest are shortcuts to
/// things the app already has, grouped once there are enough of them.
///
/// Future features join as rows the day they ship. Never add a placeholder,
/// a greyed row or «قريبًا»: users must not see what is coming.
class AppMenuDrawer extends StatelessWidget {
  const AppMenuDrawer({super.key, required this.actions});

  final AppMenuActions actions;

  /// From this many rows (الإعدادات not counted) the rows get small group
  /// labels; below it they are one plain list.
  static const int groupLabelsFrom = 8;

  // Colours come from AppChrome: charcoal by default, light with «فاتح
  // بالكامل» or with «إبقاء الأشرطة والقائمة داكنة» off.
  static const Curve _ease = Cubic(0.22, 1, 0.36, 1);

  static Future<void> show(
    BuildContext context, {
    required AppMenuActions actions,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق القائمة',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => AppMenuDrawer(actions: actions),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: _ease,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  List<_MenuGroup> _groups(BuildContext context) {
    void closeThen(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    void openPage(String title, Widget child) {
      final navigator = Navigator.of(context);
      final dark = Theme.of(context).brightness == Brightness.dark;
      navigator.pop();
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              FullscreenMenuPage(title: title, isDarkMode: dark, child: child),
        ),
      );
    }

    return [
      _MenuGroup('القراءة', [
        _MenuRow(
          'التفسير',
          Icons.auto_stories_outlined,
          onTap: () => closeThen(actions.openTafsir),
        ),
        _MenuRow(
          'القارئ',
          Icons.record_voice_over_outlined,
          onTap: () => closeThen(actions.openReciter),
        ),
        _MenuRow(
          'التحميلات',
          Icons.file_download_outlined,
          onTap: () => closeThen(actions.openDownloads),
        ),
      ]),
      _MenuGroup('الحفظ', [
        _MenuRow(
          'الإحصاءات والتقارير',
          Icons.bar_chart_rounded,
          onTap: () => closeThen(actions.openReports),
        ),
      ]),
      // The reminders are notifications, which the web build does not have
      // (Settings hides the same section there).
      if (!kIsWeb)
        _MenuGroup('التذكير', [
          _MenuRow(
            'صفحة اليوم وسورة الكهف',
            Icons.notifications_none_rounded,
            onTap: () => closeThen(actions.openReminders),
          ),
        ]),
      _MenuGroup('التطبيق', [
        _MenuRow(
          'ما الجديد',
          Icons.update_rounded,
          onTap: () => closeThen(actions.openWhatsNew),
        ),
        _MenuRow(
          'تواصل معنا',
          Icons.chat_bubble_outline_rounded,
          showsUnread: true,
          onTap: () => openPage(
            'تواصل معنا',
            ContactContent(onOpenLink: (url) => _openLink(context, url)),
          ),
        ),
        _MenuRow(
          'شارك التطبيق',
          Icons.share_outlined,
          onTapWithContext: (rowContext) async {
            await shareApp(rowContext);
            if (context.mounted) Navigator.of(context).maybePop();
          },
        ),
        _MenuRow(
          'قيّم التطبيق',
          Icons.star_outline_rounded,
          // one tap, straight to the store's stars (owner, 2026-11-12)
          onTap: () {
            Navigator.of(context).pop();
            rateApp();
          },
        ),
        _MenuRow(
          'حول التطبيق',
          Icons.info_outline_rounded,
          onTap: () => openPage('حول التطبيق', const AboutContent()),
        ),
      ]),
    ];
  }

  static Future<void> _openLink(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('تعذر فتح الرابط')),
        );
      }
    } on PlatformException {
      messenger?.showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final double width = size.width * 0.86 < 320 ? size.width * 0.86 : 320;
    final groups = _groups(context);
    final int rowCount = groups.fold(0, (n, g) => n + g.rows.length);
    final bool labelled = rowCount >= groupLabelsFrom;
    final version = AppUpdateService.instance.currentVersion;
    final c = AppChrome.of(context);

    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        // a flick to the right closes it, like pulling a drawer shut
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 300) {
            Navigator.of(context).maybePop();
          }
        },
        child: Material(
          color: c.drawer,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: size.height,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                left: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المصحف الجامع',
                            style: TextStyle(
                              color: c.drawerTitle,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'برواية قالون',
                            style: TextStyle(color: c.drawerIcon, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    _MenuRowView(
                      row: _MenuRow(
                        'الإعدادات',
                        Icons.settings_outlined,
                        onTap: () {
                          Navigator.of(context).pop();
                          actions.openSettings();
                        },
                      ),
                      trailing: Icon(
                        Icons.chevron_left_rounded,
                        color: c.drawerMuted,
                        size: 20,
                      ),
                    ),
                    // «الأذكار» sits on top with الإعدادات (owner,
                    // 2026-11-17) and opens as its own window.
                    _MenuRowView(
                      row: _MenuRow(
                        'الأذكار',
                        Icons.wb_twilight_rounded,
                        onTap: () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          navigator.push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AthkarHomePage(),
                            ),
                          );
                        },
                      ),
                      trailing: Icon(
                        Icons.chevron_left_rounded,
                        color: c.drawerMuted,
                        size: 20,
                      ),
                    ),
                    // «أحكام وأصول الرواية» right under الأذكار (owner,
                    // 2026-11-18), its own window too.
                    _MenuRowView(
                      row: _MenuRow(
                        'أحكام وأصول الرواية',
                        Icons.menu_book_rounded,
                        onTap: () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          navigator.push(
                            MaterialPageRoute<void>(
                              builder: (_) => const UsulHomePage(),
                            ),
                          );
                        },
                      ),
                      trailing: Icon(
                        Icons.chevron_left_rounded,
                        color: c.drawerMuted,
                        size: 20,
                      ),
                    ),
                    Divider(
                      height: 9,
                      thickness: 1,
                      indent: 20,
                      endIndent: 20,
                      color: c.drawerHair,
                    ),
                    Expanded(
                      child: _FadingList(
                        children: [
                          for (final group in groups) ...[
                            if (labelled)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  2,
                                ),
                                child: Text(
                                  group.label,
                                  style: TextStyle(
                                    color: c.drawerMuted,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            for (final row in group.rows)
                              _MenuRowView(row: row),
                          ],
                        ],
                      ),
                    ),
                    if (version.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Text(
                          // the version kept left-to-right («1.5.6-dev» came
                          // out as «dev-1.5.6» in the Arabic line)
                          'الإصدار \u2066$version\u2069',
                          style: TextStyle(
                            color: c.drawerMuted,
                            fontSize: 12.5,
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
    );
  }
}

class _MenuGroup {
  const _MenuGroup(this.label, this.rows);
  final String label;
  final List<_MenuRow> rows;
}

class _MenuRow {
  const _MenuRow(
    this.label,
    this.icon, {
    this.onTap,
    this.onTapWithContext,
    this.showsUnread = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  /// For a row whose action needs its own position (the share sheet is
  /// anchored to the row on iPad).
  final Future<void> Function(BuildContext rowContext)? onTapWithContext;

  /// Shows the gold dot while the owner has replied and it is unread.
  final bool showsUnread;
}

class _MenuRowView extends StatelessWidget {
  const _MenuRowView({required this.row, this.trailing});

  final _MenuRow row;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppChrome.of(context);
    Widget? end = trailing;
    if (row.showsUnread) {
      end = ValueListenableBuilder<int>(
        valueListenable: ChatService.instance.unread,
        builder: (_, unread, _) => unread > 0
            ? Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: c.drawerTitle,
                  shape: BoxShape.circle,
                ),
              )
            : const SizedBox.shrink(),
      );
    }
    return Builder(
      builder: (rowContext) => InkWell(
        onTap: () {
          if (row.onTapWithContext != null) {
            row.onTapWithContext!(rowContext);
          } else {
            row.onTap?.call();
          }
        },
        child: Semantics(
          button: true,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(row.icon, color: c.drawerIcon, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    row.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.drawerText,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ?end,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The drawer's rows. When they are more than fit, the bottom edge fades out
/// (so the list reads as going on, not cut off by the footer); when they all
/// fit, or the end is reached, nothing is faded.
class _FadingList extends StatefulWidget {
  const _FadingList({required this.children});

  final List<Widget> children;

  @override
  State<_FadingList> createState() => _FadingListState();
}

class _FadingListState extends State<_FadingList> {
  bool _moreBelow = false;

  bool _update(ScrollMetrics metrics) {
    final more = metrics.extentAfter > 1;
    if (more != _moreBelow) setState(() => _moreBelow = more);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final drawer = AppChrome.of(context).drawer;
    // The list keeps one place in the tree whether the fade shows or not.
    // It used to be wrapped in a ShaderMask only while there was more below,
    // so reaching the last row rebuilt the list and threw it back to the
    // top (owner, 2026-11-13). The fade is now a strip painted over the
    // bottom edge, which is also cheaper than masking the whole list.
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => _update(n.metrics),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => _update(n.metrics),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: widget.children,
            ),
          ),
        ),
        if (_moreBelow)
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            height: 28,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [drawer.withValues(alpha: 0), drawer],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

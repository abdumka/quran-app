import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/app_update_service.dart';
import 'services/background_playback_service.dart';
import 'services/daily_page_service.dart';
import 'services/kahf_reminder_service.dart';
import 'services/page_color_service.dart';
import 'services/page_zoom_service.dart';
import 'services/spine_shadow_service.dart';
import 'services/surah_index_view_service.dart';
import 'services/debug_log_service.dart';
import 'services/reciter_service.dart';
import 'services/tafsir_edition_service.dart';
import 'services/recitation_bar_auto_hide_service.dart';
import 'services/recitation_bar_opacity_service.dart';
import 'services/theme_service.dart';
import 'services/tv_popup_observer.dart';
import 'services/tv_service.dart';
import 'services/update_notification_service.dart';
import 'splash_screen.dart';
import 'widgets/tv/tv_focus_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolved first, not in the parallel batch below, because two things set up
  // before that batch need to know whether this is a television: the media
  // service's foreground behaviour just below, and the background-playback
  // default. It is one MethodChannel round trip with a 2 s cap.
  await TvService.instance.initialize();

  // Enables background playback + system media controls (notification / lock
  // screen / headset / Bluetooth) for the recitation. Hardware volume buttons
  // control playback volume whenever the media session is active.
  //
  // Only supported on Android/iOS; on other platforms (desktop/web) it throws,
  // so guard + catch so a failure can never block app startup.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.quran.app.audio',
        androidNotificationChannelName: 'تلاوة القرآن',
        androidNotificationOngoing: true,
        // Phones drop the service out of the foreground while paused, which
        // is the tidy thing to do there.
        //
        // NOT on TV. Every pause demotes the service to an ordinary
        // background one, and ActivityManager then reaps it: caught in the
        // act on a TV emulator, "Stopping service due to app idle:
        // com.ryanheise.audioservice.AudioService", followed a few seconds
        // later by the system destroying the app's TCP sockets and the
        // recitation dying mid-surah. Keeping the service foreground for the
        // whole session is what stops the idle sweep touching it.
        androidStopForegroundOnPause: !TvService.instance.isTv,
      ).timeout(const Duration(seconds: 5));
    } catch (error, stack) {
      debugPrint('JustAudioBackground.init failed: $error\n$stack');
    }
  }

  // Raise the image cache above Flutter's 100 MB default so pages aren't
  // constantly evicted while scrolling in Continuous mode.
  //
  // Sized against the worst case: auto-scroll precaches 11 pages
  // (centerPage-2 .. centerPage+8), and every page is the full هوامش scan,
  // median 1390x1925 = ~10.7 MB decoded, so the precache window alone needs
  // ~118 MB. Precached pages have no listeners yet, so they count against
  // this cap — going below the window makes the cache evict its own precache
  // and shows the blank page background mid-scroll. 150 MB covers the window
  // plus ~3 pages of real scrollback.
  //
  // Note this bounds retention only: pages currently on screen are tracked
  // separately as live images and are not charged against it. The cache is
  // also dropped when the app is backgrounded (see quran_pages.dart), which
  // is what keeps us off the LMK/jetsam radar during background recitation.
  PaintingBinding.instance.imageCache.maximumSize = 60;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 150 * 1024 * 1024;

  try {
    await DebugLogService.instance.initialize();
  } catch (error, stack) {
    debugPrint('DebugLogService initialize failed: $error\n$stack');
  }
  FlutterError.onError = (details) {
    try {
      DebugLogService.instance.log(
        '[FlutterError] ${details.exceptionAsString()}\n${details.stack}',
      );
    } catch (_) {}
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    try {
      DebugLogService.instance.log('[PlatformError] $error\n$stack');
    } catch (_) {}
    return false;
  };
  try {
    DebugLogService.instance.log('[App] main() start');
  } catch (_) {}
  // All of these only read SharedPreferences — load them in parallel instead
  // of serially so startup pays for one prefs read, not five.
  await Future.wait([
    ThemeService.loadTheme(),
    ReciterService.instance.load(),
    TafsirEditionService.instance.load(),
    AppUpdateService.instance.load(),
    // Prefs-only, like the rest of this batch: the notification plugin and the
    // timezone database stay untouched until the reader tops the reminder
    // queue up after its first frame (see QuranPages).
    DailyPageService.instance.load(),
    // Same deal: prefs only, and it claims its tap-payload prefix so a tap that
    // cold-started the app is routed once the plugin is up.
    KahfReminderService.instance.load(),
    PageColorService.instance.load(),
    PageZoomService.instance.load(),
    SpineShadowService.instance.load(),
    SurahIndexViewService.instance.load(),
    RecitationBarAutoHideService.instance.load(),
    RecitationBarOpacityService.instance.load(),
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]),
  ]);
  await BackgroundPlaybackService.instance.load();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  // Full screen mode hides both system bars; otherwise they stay visible
  // and the reader insets its content around them (see _updateSystemUI in
  // quran_pages.dart, which applies the same rule when the setting changes).
  final prefs = await SharedPreferences.getInstance();
  final isFullScreenMode = prefs.getBool('fullScreenMode') ?? false;
  SystemChrome.setEnabledSystemUIMode(
    isFullScreenMode ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
  );
  // Claiming the notification payload prefixes is a map insert, not plugin
  // initialization — but it has to happen before a tap that cold-started the
  // app can be delivered, so it belongs here rather than at first use.
  UpdateNotificationService.instance.registerTapHandler();
  runApp(const QuranApp());
}

// Flutter's default ScrollBehavior excludes PointerDeviceKind.mouse from
// dragDevices (to keep mouse drags free for text selection), which on web
// means a desktop user can't click-drag to turn pages — only touch/trackpad
// gestures work. The reader has no separate tap-to-flip zones, so page
// turning depends entirely on this drag gesture.
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

class QuranApp extends StatelessWidget {
  const QuranApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeMode,
      builder: (context, themeMode, _) {
        final bool isTv = TvService.instance.isTv;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          scrollBehavior: _AppScrollBehavior(),
          // Android TV only. The observer says when a dialog or a modal sheet
          // is on top, and the driver above the navigator operates it -- see
          // TvPopupObserver. The key is how the driver reaches the overlay to
          // paint its ring, since it sits above the Navigator that owns it.
          navigatorKey: isTv ? kAppNavigatorKey : null,
          navigatorObservers: isTv ? [TvPopupObserver.instance] : const [],
          builder: isTv
              ? (context, child) => TvFocusScope.popupDriver(
                  child: child ?? const SizedBox.shrink(),
                )
              : null,
          // Android TV: stop Select/Enter from ALSO being delivered to whatever
          // widget holds Flutter focus. Every TV screen drives the D-pad
          // explicitly through a HardwareKeyboard handler, and returning true
          // from one of those stops the raw-key path but NOT the
          // Shortcuts/Actions path -- so a single DPAD_CENTER fired our handler
          // AND "clicked" the focused widget. That double-activation pushed two
          // routes at once in the reader, and double-popped out of the index
          // into a black screen. Declared app-wide because it bit on two
          // separate routes; empty on every other platform.
          shortcuts: TvService.instance.isTv
              ? <ShortcutActivator, Intent>{
                  ...WidgetsApp.defaultShortcuts,
                  const SingleActivator(LogicalKeyboardKey.select):
                      const DoNothingAndStopPropagationIntent(),
                  const SingleActivator(LogicalKeyboardKey.enter):
                      const DoNothingAndStopPropagationIntent(),
                  const SingleActivator(LogicalKeyboardKey.gameButtonA):
                      const DoNothingAndStopPropagationIntent(),
                  // NOTE: the arrows are deliberately NOT blocked here.
                  // Blocking them app-wide stopped Switch/Slider from mutating
                  // during traversal, but it also left every screen without an
                  // explicit handler (البحث, the tafsir sheet, bookmark
                  // dialogs) with a completely dead D-pad. TvFocusScope instead
                  // excludes focus in its own subtree, which achieves the same
                  // protection locally because it drives by semantics rather
                  // than focus.
                }
              : null,
          themeMode: themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF6F1D7),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFB08010),
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF15120B),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFD6B45A),
              brightness: Brightness.dark,
            ),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}

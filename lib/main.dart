import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/debug_log_service.dart';
import 'services/theme_service.dart';
import 'splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Increase image cache limits to prevent high-quality/margin images from 
  // being constantly evicted when scrolling in Continuous mode.
  // 100 images or 300 MB — enough for smooth back-and-forth navigation.
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 300 * 1024 * 1024;
  
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
  await ThemeService.loadTheme();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
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
  runApp(const QuranApp());
}

class QuranApp extends StatelessWidget {
  const QuranApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
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

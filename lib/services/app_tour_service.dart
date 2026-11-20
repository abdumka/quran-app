import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_service.dart';
import 'tv_service.dart';
import 'whats_new_service.dart';

/// The two tours (owner, 2026-11-19):
///
///  * the welcome tour («جولة في التطبيق»): full-screen stories shown once,
///    BEFORE the mushaf, on a fresh install. Always replayable from the side
///    menu, and the replay is the full tour.
///  * the What's New card deck, shown once per build after an update (see
///    [WhatsNewService]); [WhatsNewService.tourCards] lists its cards.
class AppTourService {
  AppTourService._();
  static final AppTourService instance = AppTourService._();

  static const String _welcomeSeenPrefKey = 'welcomeTourSeen';

  /// Same key as the reader's long-press bookmark hint: the tour covers it.
  static const String _bookmarkGuidePrefKey = 'bookmarkGuideDismissed';

  /// Whether to show the welcome tour before the mushaf on this launch.
  ///
  /// Only a fresh install gets it. Someone updating from a build without
  /// the tour already has a reading position (or saw a What's New popup):
  /// they are marked as seen here and get the What's New deck instead.
  bool shouldShowWelcome(SharedPreferences prefs) {
    if (TvService.instance.isTv) return false;
    if (prefs.getBool(_welcomeSeenPrefKey) ?? false) return false;
    final existingUser = prefs.containsKey('lastPage') ||
        prefs.containsKey(WhatsNewService.lastSeenBuildPrefKey);
    if (existingUser) {
      prefs.setBool(_welcomeSeenPrefKey, true);
      return false;
    }
    return true;
  }

  /// Called when the first-launch tour ends (watched or skipped): the
  /// What's New deck is not shown on top of it, and the old bookmark hint
  /// is retired because the tour shows the long press.
  Future<void> markWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_welcomeSeenPrefKey, true);
    await prefs.setBool(_bookmarkGuidePrefKey, true);
    await AppUpdateService.instance.load();
    await WhatsNewService.instance.markSeen();
  }
}

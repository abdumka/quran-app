import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the user is told about an available update.
enum UpdateNotifyMode {
  /// Only inside the app (a dialog on startup / from Settings). This is the
  /// default and needs no OS permissions.
  inApp,

  /// A system notification in addition to the in-app dialog.
  notification,
}

/// A parsed update manifest describing the latest published release.
@immutable
class AppUpdateInfo {
  /// Marketing version of the latest release, e.g. "2.1.0".
  final String latestVersion;

  /// The version's `+build` number, used for a precise "is newer" comparison
  /// when two releases share the same marketing version. 0 when unspecified.
  final int latestBuild;

  /// Human-readable "what's new" lines shown to the user, in order.
  final List<String> changes;

  /// Store URL to open when the user taps "Update". Platform-specific:
  /// Play Store on Android, App Store on iOS.
  final String storeUrl;

  /// When true, the update is important enough that the "Later" option is
  /// hidden and the dialog is shown every launch until the user updates.
  final bool mandatory;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.changes,
    required this.storeUrl,
    required this.mandatory,
  });

  factory AppUpdateInfo.fromManifest(
    Map<String, dynamic> json, {
    required bool isIOS,
    required String fallbackStoreUrl,
  }) {
    final platform = isIOS ? 'ios' : 'android';
    final platformNode = json[platform];
    final node = platformNode is Map<String, dynamic> ? platformNode : json;

    int readBuild(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value.trim()) ?? 0;
      return 0;
    }

    final rawChanges = (node['changes'] ?? json['changes']) as List<dynamic>?;
    final changes = rawChanges
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];

    final storeUrl =
        (node['storeUrl'] ?? json['storeUrl'] ?? '').toString().trim();

    return AppUpdateInfo(
      latestVersion:
          (node['version'] ?? json['version'] ?? '').toString().trim(),
      latestBuild: readBuild(node['build'] ?? json['build']),
      changes: changes,
      storeUrl: storeUrl.isNotEmpty ? storeUrl : fallbackStoreUrl,
      mandatory: (node['mandatory'] ?? json['mandatory'] ?? false) == true,
    );
  }
}

/// Checks a small JSON manifest on GitHub to decide whether a newer version of
/// the app is available, and remembers the user's notification preference plus
/// which version they were last told about (so the same update isn't nagged
/// repeatedly).
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// The manifest lives in the same GitHub repo already used for downloadable
  /// asset packages. Edit `update.json` there once per release.
  /// `raw.githubusercontent` serves the file directly, and `main` is the
  /// default branch.
  static const String manifestUrl =
      'https://raw.githubusercontent.com/mahfodqr/quran-app-files/main/update.json';

  /// Store pages, used as a fallback when the manifest omits `storeUrl` so the
  /// "Update" button always has somewhere to go.
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.mahfodqr.qalon_mushaf';
  static const String appStoreUrl =
      'https://apps.apple.com/us/app/id6783147903';

  static const String _notifyModePrefKey = 'updateNotifyMode';
  static const String _lastNotifiedVersionPrefKey = 'updateLastNotifiedVersion';

  /// The app's own installed version/build, read at runtime from the platform
  /// so it's always exactly the shipped binary (no hardcoded number to keep in
  /// sync). Populated in [load]; empty/0 until then.
  String currentVersion = '';
  int currentBuild = 0;

  /// User's preferred delivery for update messages. Defaults to in-app only.
  final ValueNotifier<UpdateNotifyMode> notifyMode =
      ValueNotifier<UpdateNotifyMode>(UpdateNotifyMode.inApp);

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_notifyModePrefKey);
    notifyMode.value = stored == 'notification'
        ? UpdateNotifyMode.notification
        : UpdateNotifyMode.inApp;
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = info.version;
      currentBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // If the platform lookup fails, leave version empty; the check then
      // no-ops (see fetchIfUpdateAvailable) rather than showing a bogus update.
    }
  }

  Future<void> setNotifyMode(UpdateNotifyMode mode) async {
    if (notifyMode.value == mode) return;
    notifyMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _notifyModePrefKey,
      mode == UpdateNotifyMode.notification ? 'notification' : 'inApp',
    );
  }

  /// Fetches the manifest and returns update info when a newer version exists,
  /// or null when up to date / offline / manifest missing. Never throws.
  Future<AppUpdateInfo?> fetchIfUpdateAvailable() async {
    if (kIsWeb) return null;
    await load();
    // Without a known installed version we can't compare, so don't guess.
    if (currentVersion.isEmpty) return null;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    // The manifest only carries Play/App Store links, so it's meaningless on
    // other platforms.
    if (!isIOS && defaultTargetPlatform != TargetPlatform.android) return null;

    try {
      final response = await http
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final info = AppUpdateInfo.fromManifest(
        decoded,
        isIOS: isIOS,
        fallbackStoreUrl: isIOS ? appStoreUrl : playStoreUrl,
      );
      if (info.latestVersion.isEmpty) return null;
      if (!_isNewer(info)) return null;
      return info;
    } on SocketException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Whether [info] should still be surfaced given what the user was last told.
  /// Mandatory updates always surface; otherwise a version is shown only once.
  Future<bool> shouldSurface(AppUpdateInfo info) async {
    if (info.mandatory) return true;
    final prefs = await SharedPreferences.getInstance();
    final lastNotified = prefs.getString(_lastNotifiedVersionPrefKey);
    return lastNotified != _versionKey(info);
  }

  /// Records that the user has now been shown [info], so it isn't repeated.
  Future<void> markSurfaced(AppUpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastNotifiedVersionPrefKey, _versionKey(info));
  }

  String _versionKey(AppUpdateInfo info) =>
      '${info.latestVersion}+${info.latestBuild}';

  bool _isNewer(AppUpdateInfo info) {
    final cmp = _compareVersions(info.latestVersion, currentVersion);
    if (cmp != 0) return cmp > 0;
    // Same marketing version: fall back to build number when the manifest
    // supplies one.
    if (info.latestBuild > 0) return info.latestBuild > currentBuild;
    return false;
  }

  /// Compares dotted numeric versions (e.g. "2.1.0" vs "2.0.3"). Returns
  /// positive when [a] is newer, negative when older, 0 when equal.
  static int _compareVersions(String a, String b) {
    final pa = _parseParts(a);
    final pb = _parseParts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final na = i < pa.length ? pa[i] : 0;
      final nb = i < pb.length ? pb[i] : 0;
      if (na != nb) return na > nb ? 1 : -1;
    }
    return 0;
  }

  static List<int> _parseParts(String v) {
    return v
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }
}

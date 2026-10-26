import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_service.dart';

/// Data the app can refresh from our server without a store release:
///
///   * `tanzilat`   — the whole «تنزيلات ومتشابهات» data (places, counts,
///                    titles, the Danfasi verses, the «صه» marks), the same
///                    file as `assets/data/tanzilat.json`;
///   * `word_masks` — corrections to the word boxes of `word_masks.json`,
///                    as a cumulative list of ayat whose boxes are replaced;
///   * `reciters`   — reciters added after this build shipped (timed-surah
///                    scheme only, with their page-turn cues) and small
///                    overrides for the bundled ones (a timings revision).
///
/// Layout on `quran-content.mushaf-qaloon.com` (the R2 bucket the tafsir
/// pages and timings already come from), published by
/// `tools/publish_content_updates.py`:
///
///     data/manifest.json                      (never cached for long)
///     data/tanzilat/tanzilat_v<N>.json        (immutable once published)
///     data/word_masks/patch_v<N>.json
///     data/reciters/reciters_v<N>.json
///
/// The manifest names each item's version, file, size and SHA-256. A file is
/// downloaded only when its version is newer than both the version bundled in
/// this build ([bundledVersions]) and the one already downloaded, and only if
/// this build is new enough to read it (`minBuild`). It is written next to
/// the app's other support files, verified, and kept until a newer one
/// replaces it. Nothing here runs before the first frame: the loaders read
/// whatever is on disk, and the network check happens later in the
/// background (once a day) or when the reader taps «التحقق من وجود تحديث».
class ContentUpdateService {
  ContentUpdateService._();
  static final ContentUpdateService instance = ContentUpdateService._();

  static const String baseUrl = 'https://quran-content.mushaf-qaloon.com/';
  static const String manifestUrl = '${baseUrl}data/manifest.json';

  /// The item names this build understands. Anything else in the manifest
  /// is ignored, so a future item never trips an old build.
  static const List<String> items = ['tanzilat', 'word_masks', 'reciters'];

  /// What the assets of THIS build carry. A download older than or equal to
  /// this is never used (an app update can ship newer data than a phone had
  /// downloaded). `tanzilat` matches the `ver` field of
  /// `assets/data/tanzilat.json` (a test keeps them in step);
  /// `word_masks` is the patch level folded into the bundled boxes; `reciters`
  /// is the list in `Reciter.all`.
  static const Map<String, int> bundledVersions = {
    'tanzilat': 1,
    'word_masks': 0,
    'reciters': 0,
  };

  static const Duration _checkInterval = Duration(hours: 24);
  static const Duration _manifestTimeout = Duration(seconds: 15);
  static const Duration _fileTimeout = Duration(seconds: 60);
  static const int _maxFileBytes = 8 * 1024 * 1024;

  static const String _lastCheckKey = 'contentUpdate.lastCheck';
  static String _verKey(String item) => 'contentUpdate.$item.ver';

  /// Bumped whenever an item was applied live (the tanzilat reloaded, the
  /// reciter list changed), so widgets that cache derived data drop it.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Items downloaded this run that only take effect at the next launch.
  final Set<String> pendingRestart = <String>{};

  Directory? _dir;
  final Map<String, int> _installed = {};
  Future<void>? _init;
  Future<ContentCheckResult>? _running;

  /// What the loaders register: how to apply a downloaded [item] at once
  /// ([apply]), or whether the data is already in memory ([isLoaded]) and so
  /// the new file shows only at the next launch. An item nobody registered is
  /// not loaded yet, and its next load simply reads the new file.
  /// `word_masks` registers no [apply] on purpose: the boxes are swapped only
  /// at launch, so a Tasmee session never changes under the reciter.
  final Map<String, Future<void> Function()> _appliers = {};
  final Map<String, bool Function()> _loadedChecks = {};

  void registerItem(
    String item, {
    Future<void> Function()? apply,
    bool Function()? isLoaded,
  }) {
    if (apply != null) _appliers[item] = apply;
    if (isLoaded != null) _loadedChecks[item] = isLoaded;
  }

  /// Reads which versions are on disk. Idempotent; the loaders await it, so
  /// it costs one prefs read and one directory lookup, nothing else.
  Future<void> init() => _init ??= _doInit();

  Future<void> _doInit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final support = await getApplicationSupportDirectory();
      _dir = Directory('${support.path}${Platform.pathSeparator}content');
      for (final item in items) {
        final ver = prefs.getInt(_verKey(item)) ?? 0;
        if (ver > (bundledVersions[item] ?? 0) &&
            await _fileOf(item, ver).exists()) {
          _installed[item] = ver;
        }
      }
    } catch (e) {
      debugPrint('ContentUpdateService: init failed: $e');
    }
  }

  File _fileOf(String item, int ver) {
    final name = switch (item) {
      'word_masks' => 'word_masks_patch_v$ver.json',
      _ => '${item}_v$ver.json',
    };
    return File('${_dir!.path}${Platform.pathSeparator}$name');
  }

  /// The version in use for [item]: the downloaded one when it is newer than
  /// the bundled one, else the bundled.
  int versionOf(String item) =>
      _installed[item] ?? (bundledVersions[item] ?? 0);

  /// The downloaded file for [item] when one newer than the bundle is on
  /// disk, else null (use the asset). Call after [init].
  File? fileFor(String item) {
    final ver = _installed[item];
    if (ver == null || _dir == null) return null;
    return _fileOf(item, ver);
  }

  /// Convenience for loaders: the downloaded file's text, or null.
  Future<String?> readFor(String item) async {
    await init();
    final f = fileFor(item);
    if (f == null) return null;
    try {
      return await f.readAsString();
    } catch (e) {
      debugPrint('ContentUpdateService: cannot read $item: $e');
      return null;
    }
  }

  /// A silent check some seconds after launch, at most once a day. Never
  /// throws, never shows anything.
  void scheduleBackgroundCheck({Duration delay = const Duration(seconds: 12)}) {
    Future<void>.delayed(delay, () async {
      try {
        await check();
      } catch (e) {
        debugPrint('ContentUpdateService: background check failed: $e');
      }
    });
  }

  /// Fetches the manifest and installs every item that is newer than what
  /// this phone has. [manual] skips the once-a-day throttle (the settings
  /// button). Concurrent calls share one run.
  Future<ContentCheckResult> check({bool manual = false, http.Client? client}) {
    final running = _running;
    if (running != null) return running;
    final run = _check(
      manual: manual,
      client: client,
    ).whenComplete(() => _running = null);
    _running = run;
    return run;
  }

  Future<ContentCheckResult> _check({
    required bool manual,
    http.Client? client,
  }) async {
    await init();
    if (_dir == null) return const ContentCheckResult.failed();
    final prefs = await SharedPreferences.getInstance();
    if (!manual) {
      final last = prefs.getInt(_lastCheckKey) ?? 0;
      final since = DateTime.now().millisecondsSinceEpoch - last;
      if (since >= 0 && since < _checkInterval.inMilliseconds) {
        return const ContentCheckResult.skipped();
      }
    }
    final own = client == null;
    final c = client ?? http.Client();
    try {
      final response = await c
          .get(
            Uri.parse(manifestUrl),
            headers: const {'Cache-Control': 'no-cache'},
          )
          .timeout(_manifestTimeout);
      if (response.statusCode != 200) {
        debugPrint(
          'ContentUpdateService: manifest HTTP ${response.statusCode}',
        );
        return const ContentCheckResult.failed();
      }
      final manifest = ContentManifest.parse(utf8.decode(response.bodyBytes));
      // A reachable manifest counts as a check, whatever it leads to.
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      final build = AppUpdateService.instance.currentBuild;
      final updated = <String>[];
      for (final item in items) {
        final entry = manifest.items[item];
        if (entry == null) continue;
        if (build > 0 && entry.minBuild > build) continue;
        if (entry.ver <= versionOf(item)) continue;
        try {
          await _install(item, entry, c, prefs);
          updated.add(item);
        } catch (e) {
          debugPrint('ContentUpdateService: $item v${entry.ver} failed: $e');
        }
      }
      for (final item in updated) {
        final apply = _appliers[item];
        if (apply == null) {
          if (_loadedChecks[item]?.call() ?? false) pendingRestart.add(item);
          continue;
        }
        try {
          await apply();
        } catch (e) {
          debugPrint('ContentUpdateService: applying $item failed: $e');
          pendingRestart.add(item);
        }
      }
      if (updated.isNotEmpty) revision.value++;
      return ContentCheckResult(
        updated: updated,
        pendingRestart: updated.where(pendingRestart.contains).toList(),
      );
    } on FormatException catch (e) {
      debugPrint('ContentUpdateService: bad manifest: $e');
      return const ContentCheckResult.failed();
    } on Exception catch (e) {
      debugPrint('ContentUpdateService: check failed: $e');
      return const ContentCheckResult.failed();
    } finally {
      if (own) c.close();
    }
  }

  Future<void> _install(
    String item,
    ContentManifestEntry entry,
    http.Client c,
    SharedPreferences prefs,
  ) async {
    if (entry.bytes > _maxFileBytes) {
      throw StateError('too large: ${entry.bytes} bytes');
    }
    final url = entry.url.startsWith('https://')
        ? Uri.parse(entry.url)
        : Uri.parse('$baseUrl${entry.url}');
    if (!url.host.endsWith('mushaf-qaloon.com')) {
      throw StateError('refused host ${url.host}');
    }
    final response = await c.get(url).timeout(_fileTimeout);
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final body = response.bodyBytes;
    if (body.length != entry.bytes) {
      throw StateError('size ${body.length} != ${entry.bytes}');
    }
    final digest = sha256.convert(body).toString();
    if (digest != entry.sha256.toLowerCase()) {
      throw StateError('checksum mismatch');
    }
    // It must at least be JSON of the right shape before it replaces the
    // bundled data; a bad file would otherwise brick the feature until the
    // next version.
    validate(item, utf8.decode(body));
    await _dir!.create(recursive: true);
    final target = _fileOf(item, entry.ver);
    final part = File('${target.path}.part');
    await part.writeAsBytes(body, flush: true);
    await part.rename(target.path);
    await prefs.setInt(_verKey(item), entry.ver);
    final old = _installed[item];
    _installed[item] = entry.ver;
    if (old != null && old != entry.ver) {
      try {
        await _fileOf(item, old).delete();
      } catch (_) {}
    }
  }

  /// Throws [FormatException] unless [text] is a plausible [item] file.
  static void validate(String item, String text) {
    final decoded = json.decode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('not an object');
    }
    switch (item) {
      case 'tanzilat':
        if (decoded['groups'] is! List) {
          throw const FormatException('tanzilat: no groups');
        }
      case 'word_masks':
        final patches = decoded['patches'];
        if (patches is! List) {
          throw const FormatException('word_masks: no patches');
        }
        for (final p in patches) {
          if (p is! Map ||
              p['page'] is! int ||
              p['surah'] is! int ||
              p['ayah'] is! int ||
              p['words'] is! List) {
            throw const FormatException('word_masks: bad patch');
          }
        }
      case 'reciters':
        if (decoded['reciters'] is! List) {
          throw const FormatException('reciters: no list');
        }
    }
  }

  /// Tests only: point the store at [dir] and forget what was installed.
  void debugReset({Directory? dir}) {
    _dir = dir;
    _installed.clear();
    _init = dir == null ? null : Future.value();
    _running = null;
    pendingRestart.clear();
  }
}

class ContentManifestEntry {
  const ContentManifestEntry({
    required this.ver,
    required this.url,
    required this.sha256,
    required this.bytes,
    this.minBuild = 0,
  });

  final int ver;
  final String url;
  final String sha256;
  final int bytes;
  final int minBuild;
}

class ContentManifest {
  const ContentManifest(this.items);

  final Map<String, ContentManifestEntry> items;

  /// Reads `{"v":1,"items":{name:{"ver":N,"url":…,"sha256":…,"bytes":N,
  /// "minBuild":N}}}`. Malformed entries are dropped, not fatal.
  static ContentManifest parse(String text) {
    final decoded = json.decode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('manifest is not an object');
    }
    final raw = decoded['items'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('manifest has no items');
    }
    final items = <String, ContentManifestEntry>{};
    raw.forEach((name, value) {
      if (value is! Map<String, dynamic>) return;
      final ver = value['ver'];
      final url = value['url'];
      final sha = value['sha256'];
      final bytes = value['bytes'];
      if (ver is! int || ver <= 0) return;
      if (url is! String || url.isEmpty || url.contains('..')) return;
      if (sha is! String || sha.length != 64) return;
      if (bytes is! int || bytes <= 0) return;
      final minBuild = value['minBuild'];
      items[name] = ContentManifestEntry(
        ver: ver,
        url: url,
        sha256: sha,
        bytes: bytes,
        minBuild: minBuild is int ? minBuild : 0,
      );
    });
    return ContentManifest(items);
  }
}

class ContentCheckResult {
  const ContentCheckResult({
    required this.updated,
    required this.pendingRestart,
    this.failed = false,
    this.skipped = false,
  });

  const ContentCheckResult.failed()
    : updated = const [],
      pendingRestart = const [],
      failed = true,
      skipped = false;

  const ContentCheckResult.skipped()
    : updated = const [],
      pendingRestart = const [],
      failed = false,
      skipped = true;

  /// Items installed by this check.
  final List<String> updated;

  /// Of those, the ones that show only after the app is opened again.
  final List<String> pendingRestart;

  /// The manifest could not be fetched or read.
  final bool failed;

  /// Nothing was fetched: checked less than a day ago.
  final bool skipped;

  static const Map<String, String> _labels = {
    'tanzilat': 'التنزيلات',
    'word_masks': 'تلوين الكلمات',
    'reciters': 'القرّاء',
  };

  /// One line for the settings notice, or null when nothing changed.
  String? get message {
    if (updated.isEmpty) return null;
    final live = updated.where((i) => !pendingRestart.contains(i)).toList();
    final later = pendingRestart;
    final parts = <String>[];
    if (live.isNotEmpty) {
      parts.add('تم تحديث ${live.map((i) => _labels[i] ?? i).join(' و')}.');
    }
    if (later.isNotEmpty) {
      parts.add(
        'نُزِّل تحديث ${later.map((i) => _labels[i] ?? i).join(' و')}، '
        'ويظهر عند فتح التطبيق من جديد.',
      );
    }
    return parts.join(' ');
  }
}

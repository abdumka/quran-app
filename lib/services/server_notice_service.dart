import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_service.dart';
import 'content_update_service.dart';

/// Messages from us to the readers, shown once each at launch, without a
/// store release: the `notices` item of [ContentUpdateService], from
/// `tools/content_updates/notices.json`:
///
///     {"ver": 2, "notices": [
///       {"id": "reciter-younsi", "title": "قارئ جديد",
///        "lines": ["أضفنا تلاوة الشيخ علي اليونسي برواية قالون."],
///        "from": "2026-11-20", "until": "2026-12-20",
///        "minBuild": 150, "maxBuild": 0, "platforms": ["android", "ios"],
///        "button": {"label": "افتح الصفحة", "action": "page:255"}}]}
///
/// A notice is shown at most once per install ([markSeen] by its `id`), one
/// per launch, and only after neither «ما الجديد» nor the update dialog
/// appeared that launch. `from` / `until` are local dates, both inclusive and
/// optional; `minBuild` / `maxBuild` (0 = no limit) and `platforms` narrow
/// who sees it. `button.action` is a notification payload (`page:<n>`,
/// `url:<https link>`, `store:`, `chat:`), routed like a push tap.
///
/// A file that breaks a rule of shape is refused as a whole ([parse]). A file
/// downloaded during a run is shown from the next launch.
class ServerNoticeService {
  ServerNoticeService._();
  static final ServerNoticeService instance = ServerNoticeService._();

  static const String _seenKey = 'serverNotices.seen';
  static const int maxNotices = 20;
  static const int maxLines = 8;
  static const int maxLineLength = 400;
  static const int maxTitleLength = 60;
  static const int maxButtonLength = 30;

  static final RegExp _id = RegExp(r'^[a-z0-9][a-z0-9_-]{0,39}$');
  static final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _action = RegExp(
    r'^(store:|chat:|page:([1-9]\d{0,2})|url:https://[^\s]+)$',
  );

  /// Reads and checks a notices file. Throws [FormatException] when anything
  /// is out of shape.
  static List<ServerNotice> parse(String source) {
    final d = json.decode(source);
    if (d is! Map<String, dynamic> || d['ver'] is! int) {
      throw const FormatException('notices: not a notices file');
    }
    final raw = d['notices'];
    if (raw is! List || raw.length > maxNotices) {
      throw const FormatException('notices: bad list');
    }
    final out = <ServerNotice>[];
    final ids = <String>{};
    for (final n in raw) {
      if (n is! Map) throw const FormatException('notices: bad notice');
      final id = n['id'];
      if (id is! String || !_id.hasMatch(id) || !ids.add(id)) {
        throw FormatException('notices: bad id $id');
      }
      final title = n['title'];
      if (title is! String ||
          title.trim().isEmpty ||
          title.length > maxTitleLength) {
        throw FormatException('notices: $id bad title');
      }
      final lines = n['lines'];
      if (lines is! List ||
          lines.isEmpty ||
          lines.length > maxLines ||
          !lines.every(
            (l) => l is String && l.trim().isNotEmpty && l.length <= maxLineLength,
          )) {
        throw FormatException('notices: $id bad lines');
      }
      DateTime? date(String key) {
        final v = n[key];
        if (v == null) return null;
        if (v is! String || !_date.hasMatch(v)) {
          throw FormatException('notices: $id bad $key');
        }
        final parsed = DateTime.tryParse(v);
        if (parsed == null) throw FormatException('notices: $id bad $key');
        return parsed;
      }

      final from = date('from');
      final until = date('until');
      if (from != null && until != null && until.isBefore(from)) {
        throw FormatException('notices: $id ends before it starts');
      }
      int build(String key) {
        final v = n[key] ?? 0;
        if (v is! int || v < 0) throw FormatException('notices: $id bad $key');
        return v;
      }

      final platforms = n['platforms'];
      Set<String>? platformSet;
      if (platforms != null) {
        if (platforms is! List ||
            platforms.isEmpty ||
            !platforms.every((p) => p == 'android' || p == 'ios')) {
          throw FormatException('notices: $id bad platforms');
        }
        platformSet = platforms.cast<String>().toSet();
      }
      String? label;
      String? action;
      final button = n['button'];
      if (button != null) {
        if (button is! Map) throw FormatException('notices: $id bad button');
        final l = button['label'], a = button['action'];
        if (l is! String ||
            l.trim().isEmpty ||
            l.length > maxButtonLength ||
            a is! String ||
            !_action.hasMatch(a)) {
          throw FormatException('notices: $id bad button');
        }
        final page = _action.firstMatch(a)!.group(2);
        if (page != null && int.parse(page) > 604) {
          throw FormatException('notices: $id bad page');
        }
        label = l.trim();
        action = a;
      }
      out.add(
        ServerNotice(
          id: id,
          title: title.trim(),
          lines: [for (final l in lines) (l as String).trim()],
          from: from,
          until: until,
          minBuild: build('minBuild'),
          maxBuild: build('maxBuild'),
          platforms: platformSet,
          buttonLabel: label,
          buttonAction: action,
        ),
      );
    }
    return out;
  }

  /// The first notice due now that this install has not seen, or null.
  Future<ServerNotice?> next({DateTime? now}) async {
    try {
      final text = await ContentUpdateService.instance.readFor('notices');
      if (text == null) return null;
      final notices = parse(text);
      final prefs = await SharedPreferences.getInstance();
      final seen = (prefs.getStringList(_seenKey) ?? const []).toSet();
      final build = AppUpdateService.instance.currentBuild;
      final platform = kIsWeb
          ? 'web'
          : defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : defaultTargetPlatform == TargetPlatform.android
          ? 'android'
          : 'other';
      for (final n in notices) {
        if (seen.contains(n.id)) continue;
        if (!n.dueFor(now ?? DateTime.now(), build: build, platform: platform)) {
          continue;
        }
        return n;
      }
    } catch (e) {
      debugPrint('ServerNoticeService: notices ignored: $e');
    }
    return null;
  }

  /// Remembers that [id] was shown (the last 100 ids are kept).
  Future<void> markSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = List<String>.of(prefs.getStringList(_seenKey) ?? const []);
    seen.remove(id);
    seen.add(id);
    while (seen.length > 100) {
      seen.removeAt(0);
    }
    await prefs.setStringList(_seenKey, seen);
  }

  @visibleForTesting
  static const String seenKey = _seenKey;
}

class ServerNotice {
  const ServerNotice({
    required this.id,
    required this.title,
    required this.lines,
    required this.from,
    required this.until,
    required this.minBuild,
    required this.maxBuild,
    required this.platforms,
    required this.buttonLabel,
    required this.buttonAction,
  });

  final String id;
  final String title;
  final List<String> lines;
  final DateTime? from;
  final DateTime? until;
  final int minBuild;
  final int maxBuild;
  final Set<String>? platforms;
  final String? buttonLabel;
  final String? buttonAction;

  /// Whether the notice is for a reader on [build] / [platform] at [now].
  /// [build] 0 (unknown) passes the build limits.
  bool dueFor(DateTime now, {required int build, required String platform}) {
    final today = DateTime(now.year, now.month, now.day);
    if (from != null && today.isBefore(from!)) return false;
    if (until != null && today.isAfter(until!)) return false;
    if (build > 0 && minBuild > 0 && build < minBuild) return false;
    if (build > 0 && maxBuild > 0 && build > maxBuild) return false;
    if (platforms != null && !platforms!.contains(platform)) return false;
    return true;
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/content_update_service.dart';

/// «أحكام وأصول الرواية»: Qalun's rules, opened from the side menu under
/// الأذكار. The content is `assets/data/usul.json` (written by
/// tools/build_usul_data.py from the reviewed mockup); a corrected file can
/// come from our server as the `usul` content item.
///
/// A chapter is a list of plain blocks (`t` names the kind). Kinds this build
/// does not know are skipped when drawing, so a later file can add one; a
/// change old builds must not read raises the format number `v`.
class UsulData {
  UsulData._({
    required this.ver,
    required this.title,
    required this.hero,
    required this.kinds,
    required this.groups,
  });

  /// The format this build reads.
  static const int format = 1;

  final int ver;
  final String title;
  final UsulHero hero;
  final List<UsulKind> kinds;
  final List<UsulGroup> groups;

  Iterable<UsulChapter> get chapters => groups.expand((g) => g.chapters);

  UsulChapter? chapter(String id) {
    for (final c in chapters) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Reads a whole file; throws [FormatException] on anything this build
  /// cannot show, so a bad download is refused before it replaces a good one.
  static UsulData parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('usul: not an object');
    }
    final ver = decoded['ver'];
    if (ver is! int || ver < 1) throw const FormatException('usul: no ver');
    if (decoded['v'] != format) {
      throw const FormatException('usul: a format this build cannot read');
    }
    final groups = decoded['groups'];
    if (groups is! List || groups.isEmpty) {
      throw const FormatException('usul: no groups');
    }
    final ids = <String>{};
    final parsed = <UsulGroup>[];
    for (final g in groups) {
      if (g is! Map<String, dynamic> || g['chapters'] is! List) {
        throw const FormatException('usul: bad group');
      }
      final chapters = <UsulChapter>[];
      for (final c in g['chapters'] as List) {
        final chapter = UsulChapter._parse(c);
        if (!ids.add(chapter.id)) {
          throw FormatException('usul: chapter ${chapter.id} twice');
        }
        chapters.add(chapter);
      }
      if (chapters.isEmpty) throw const FormatException('usul: empty group');
      parsed.add(UsulGroup(_str(g['name']), chapters));
    }
    final hero = decoded['hero'];
    if (hero is! Map<String, dynamic>) {
      throw const FormatException('usul: no hero');
    }
    final kinds = decoded['kinds'];
    return UsulData._(
      ver: ver,
      title: _str(decoded['title']).isEmpty
          ? 'أحكام وأصول الرواية'
          : _str(decoded['title']),
      hero: UsulHero(
        title: _str(hero['h']),
        text: _str(hero['x']),
        lines: _strings(hero['lines']),
        where: _str(hero['w']),
      ),
      kinds: [
        if (kinds is List)
          for (final k in kinds)
            if (k is Map<String, dynamic>)
              UsulKind(_str(k['h']), _str(k['x'])),
      ],
      groups: parsed,
    );
  }

  static Future<UsulData>? _loading;
  static bool _registered = false;

  /// The newest data: a fix downloaded from our server when there is one,
  /// else the bundled file. A downloaded fix is used from the next time the
  /// section is opened.
  static Future<UsulData> load() {
    if (!_registered) {
      _registered = true;
      ContentUpdateService.instance.registerItem(
        'usul',
        apply: () async => _loading = null,
        isLoaded: () => _loading != null,
      );
    }
    return _loading ??= _read();
  }

  static Future<UsulData> _read() async {
    final downloaded = await ContentUpdateService.instance.readFor('usul');
    if (downloaded != null) {
      try {
        return parse(downloaded);
      } catch (error) {
        debugPrint('UsulData: downloaded file refused: $error');
      }
    }
    return parse(await rootBundle.loadString('assets/data/usul.json'));
  }

  /// Tests only.
  @visibleForTesting
  static void debugReset() => _loading = null;
}

class UsulHero {
  const UsulHero({
    required this.title,
    required this.text,
    required this.lines,
    required this.where,
  });
  final String title;
  final String text;
  final List<String> lines;
  final String where;
}

class UsulKind {
  const UsulKind(this.name, this.text);
  final String name;
  final String text;
}

class UsulGroup {
  const UsulGroup(this.name, this.chapters);

  /// Empty for the last list (terms, sources), which has no heading.
  final String name;
  final List<UsulChapter> chapters;
}

class UsulTag {
  const UsulTag(this.text, {this.differs = false});
  final String text;

  /// «يخالف حفصًا».
  final bool differs;
}

class UsulChapter {
  const UsulChapter({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.blocks,
    this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<UsulTag> tags;

  /// The raw blocks, drawn by UsulBlocks.
  final List<Map<String, dynamic>> blocks;

  /// A Material icon name for the rows that carry one (terms, sources).
  final String? icon;

  static UsulChapter _parse(Object? c) {
    if (c is! Map<String, dynamic>) {
      throw const FormatException('usul: bad chapter');
    }
    final id = _str(c['id']);
    final title = _str(c['title']);
    final blocks = c['blocks'];
    if (id.isEmpty || title.isEmpty || blocks is! List || blocks.isEmpty) {
      throw FormatException('usul: chapter "$id" incomplete');
    }
    for (final b in blocks) {
      if (b is! Map<String, dynamic> || b['t'] is! String) {
        throw FormatException('usul: bad block in "$id"');
      }
    }
    final tags = c['tags'];
    return UsulChapter(
      id: id,
      title: title,
      subtitle: _str(c['sub']),
      tags: [
        if (tags is List)
          for (final t in tags)
            if (t is Map<String, dynamic> && _str(t['x']).isNotEmpty)
              UsulTag(_str(t['x']), differs: t['diff'] == true),
      ],
      blocks: blocks.cast<Map<String, dynamic>>(),
      icon: c['icon'] is String ? c['icon'] as String : null,
    );
  }
}

String _str(Object? v) => v is String ? v : '';

List<String> _strings(Object? v) => [
  if (v is List)
    for (final s in v)
      if (s is String) s,
];

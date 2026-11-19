import 'dart:convert';

import '../utils/arabic_text_normalizer.dart';
import '../utils/quran_display_text.dart';

/// One dhikr of «الأذكار».
class AthkarItem {
  AthkarItem({
    required this.id,
    required this.sectionId,
    required String text,
    required this.count,
    required this.source,
    this.audio,
    this.verses = const [],
  }) : text = _display(text);

  /// Stable across data updates: counters and favourites are keyed by it.
  final int id;
  final int sectionId;

  /// Ready to show: verses (between ﴿ ﴾, in the app's Qalun text) already
  /// went through [quranDisplayText].
  final String text;

  /// How many times it is said.
  final int count;

  /// Who narrated it; may be empty.
  final String source;

  /// The number of this dhikr in the printed book (some recordings online
  /// are numbered by it).
  final int? audio;

  /// The ayat it consists of, when it is recited Qur'an (آية الكرسي, the
  /// three Quls, السجدة…): it is then played from the app's own Qur'an
  /// reciters, not the athkar voices. Empty for every other dhikr.
  final List<AthkarVerses> verses;

  bool get isQuran => verses.isNotEmpty;

  late final String searchText = normalizeArabicText(text);

  static final RegExp _verse = RegExp('﴿[^﴾]*﴾');

  static String _display(String raw) =>
      raw.replaceAllMapped(_verse, (m) => quranDisplayText(m[0]!));
}

/// A run of ayat, in the app's own (output.json) numbering.
class AthkarVerses {
  const AthkarVerses(this.surah, this.from, this.to);
  final int surah;
  final int from;
  final int to;
}

class AthkarSection {
  AthkarSection({required this.id, required this.name, required this.items});

  final int id;
  final String name;
  final List<AthkarItem> items;

  late final String searchName = normalizeArabicText(name);
}

/// A themed group of sections on the home screen.
class AthkarGroup {
  const AthkarGroup({
    required this.id,
    required this.name,
    required this.sections,
  });

  final String id;
  final String name;
  final List<AthkarSection> sections;
}

/// A tile on top of the home screen.
class AthkarFeatured {
  const AthkarFeatured({
    required this.section,
    required this.label,
    required this.icon,
  });

  final AthkarSection section;
  final String label;

  /// sun, moon, prayer, bed or wake.
  final String icon;
}

/// One voice the athkar (other than the recited Qur'an) can be listened to
/// in. The list comes with the data, and so from the server: that is how
/// voices are added, reordered or replaced without a release.
///
/// ```json
/// {"id": "duraihem", "name": "حمد الدريهم",
///  "url": "https://audio.mushaf-qaloon.com/athkar/duraihem/{id}.mp3",
///  "items": [15, 16, 17], "files": {"118": "94.mp3"},
///  "spans": {"15": [6.0, 14.84], "118": [6.0, 21.3]}}
/// ```
///
/// `url` is the address of one recording; `{id}` is the dhikr's id (`{a}`,
/// the book's number padded to 4 digits, and `{n}`, unpadded, are also
/// understood). `items` lists the athkar this voice has (absent = all);
/// `files` points a dhikr at another file (a full address, or a name that
/// replaces the last part of `url`), e.g. an evening dhikr worded exactly
/// like a morning one. A voice without a dhikr is simply not used for it.
///
/// `spans` gives, per dhikr, where it starts and ends inside its file, in
/// seconds. The files keep a few seconds of the recording on both sides, so
/// a start or an end that is a little off is fixed by changing these numbers
/// in a server update: no new audio, no release. Without a span the whole
/// file plays.
class AthkarReciter {
  const AthkarReciter({
    required this.id,
    required this.name,
    this.url,
    this.items,
    this.files = const {},
    this.spans = const {},
  });

  final String id;
  final String name;
  final String? url;
  final Set<int>? items;
  final Map<int, String> files;
  final Map<int, (Duration, Duration)> spans;

  /// Where [item] starts and ends inside its file, or null for all of it.
  (Duration, Duration)? spanFor(AthkarItem item) => spans[item.id];

  bool has(AthkarItem item) => urlFor(item) != null;

  String? urlFor(AthkarItem item) {
    final file = files[item.id];
    if (file != null) {
      if (file.startsWith('https://')) return file;
      final base = url;
      if (base == null) return null;
      return '${base.substring(0, base.lastIndexOf('/') + 1)}$file';
    }
    final pattern = url;
    if (pattern == null) return null;
    if (items != null && !items!.contains(item.id)) return null;
    final a = item.audio;
    if (a == null && (pattern.contains('{a}') || pattern.contains('{n}'))) {
      return null;
    }
    return pattern
        .replaceAll('{a}', '${a ?? 0}'.padLeft(4, '0'))
        .replaceAll('{n}', '${a ?? 0}')
        .replaceAll('{id}', '${item.id}');
  }

  static AthkarReciter? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'], url = raw['url'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    if (url != null && (url is! String || !url.startsWith('https://'))) {
      return null;
    }
    final files = <int, String>{};
    final rawFiles = raw['files'];
    if (rawFiles is Map) {
      rawFiles.forEach((k, v) {
        final key = int.tryParse('$k');
        if (key != null && v is String && v.isNotEmpty) files[key] = v;
      });
    }
    final spans = <int, (Duration, Duration)>{};
    final rawSpans = raw['spans'];
    if (rawSpans is Map) {
      rawSpans.forEach((k, v) {
        final key = int.tryParse('$k');
        if (key == null || v is! List || v.length != 2) return;
        final a = v[0], b = v[1];
        if (a is! num || b is! num || a < 0 || b <= a) return;
        spans[key] = (
          Duration(milliseconds: (a * 1000).round()),
          Duration(milliseconds: (b * 1000).round()),
        );
      });
    }
    Set<int>? items;
    final rawItems = raw['items'];
    if (rawItems is List) {
      items = {
        for (final x in rawItems)
          if (x is int) x,
      };
    }
    if (url == null && files.isEmpty) return null;
    return AthkarReciter(
      id: id,
      name: name,
      url: url as String?,
      items: items,
      files: files,
      spans: spans,
    );
  }
}

/// Everything in `assets/data/athkar.json` (built by
/// tools/build_athkar_data.py).
class AthkarData {
  AthkarData({
    required this.version,
    required this.featured,
    required this.groups,
    required this.sections,
    required this.reciters,
    this.quranReciterId = defaultQuranReciterId,
    this.shareLine = defaultShareLine,
  }) {
    for (final s in sections) {
      _sections[s.id] = s;
      for (final i in s.items) {
        _items[i.id] = i;
      }
    }
  }

  static final AthkarData empty = AthkarData(
    version: 0,
    featured: const [],
    groups: const [],
    sections: const [],
    reciters: const [],
  );

  final int version;
  final List<AthkarFeatured> featured;
  final List<AthkarGroup> groups;
  final List<AthkarSection> sections;
  final List<AthkarReciter> reciters;

  /// The app reciter the athkar's verses play in until the reader picks
  /// another (owner, 2026-11-17: النهي). The data may name another one.
  final String quranReciterId;
  static const String defaultQuranReciterId = 'naihi_qaloun';

  /// The last line of a copied or shared dhikr; from the data, so the
  /// server can change it with everything else.
  final String shareLine;
  static const String defaultShareLine = 'من تطبيق المصحف الجامع';

  final Map<int, AthkarSection> _sections = {};
  final Map<int, AthkarItem> _items = {};

  bool get isEmpty => sections.isEmpty;
  AthkarSection? section(int id) => _sections[id];
  AthkarItem? item(int id) => _items[id];

  /// Throws [FormatException] on anything that is not a usable file, so a
  /// broken download is never installed over a good one.
  static AthkarData parse(String text) {
    final decoded = json.decode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('athkar: not an object');
    }
    final rawSections = decoded['sections'];
    if (rawSections is! List || rawSections.isEmpty) {
      throw const FormatException('athkar: no sections');
    }
    final sections = <AthkarSection>[];
    final byId = <int, AthkarSection>{};
    final seenItems = <int>{};
    for (final raw in rawSections) {
      if (raw is! Map ||
          raw['id'] is! int ||
          raw['name'] is! String ||
          raw['items'] is! List) {
        throw const FormatException('athkar: bad section');
      }
      final sectionId = raw['id'] as int;
      final items = <AthkarItem>[];
      for (final i in raw['items'] as List) {
        if (i is! Map ||
            i['id'] is! int ||
            i['t'] is! String ||
            (i['t'] as String).trim().isEmpty) {
          throw const FormatException('athkar: bad item');
        }
        if (!seenItems.add(i['id'] as int)) {
          throw const FormatException('athkar: item id used twice');
        }
        final n = i['n'];
        final verses = <AthkarVerses>[];
        final q = i['q'];
        if (q is List) {
          for (final r in q) {
            if (r is List &&
                r.length == 3 &&
                r.every((x) => x is int) &&
                (r[0] as int) >= 1 &&
                (r[0] as int) <= 114 &&
                (r[1] as int) >= 1 &&
                (r[2] as int) >= (r[1] as int)) {
              verses.add(AthkarVerses(r[0] as int, r[1] as int, r[2] as int));
            }
          }
        }
        items.add(
          AthkarItem(
            id: i['id'] as int,
            sectionId: sectionId,
            text: i['t'] as String,
            count: n is int && n > 0 ? n : 1,
            source: i['s'] is String ? i['s'] as String : '',
            audio: i['a'] is int ? i['a'] as int : null,
            verses: verses,
          ),
        );
      }
      if (items.isEmpty) continue;
      final section = AthkarSection(
        id: sectionId,
        name: raw['name'] as String,
        items: items,
      );
      if (byId.containsKey(sectionId)) {
        throw const FormatException('athkar: section id used twice');
      }
      byId[sectionId] = section;
      sections.add(section);
    }

    final groups = <AthkarGroup>[];
    final grouped = <int>{};
    final rawGroups = decoded['groups'];
    if (rawGroups is List) {
      for (final g in rawGroups) {
        if (g is! Map || g['name'] is! String || g['sections'] is! List) {
          continue;
        }
        final members = <AthkarSection>[
          for (final id in g['sections'] as List)
            if (byId[id] != null && grouped.add(id as int)) byId[id]!,
        ];
        if (members.isEmpty) continue;
        groups.add(
          AthkarGroup(
            id: '${g['id'] ?? g['name']}',
            name: g['name'] as String,
            sections: members,
          ),
        );
      }
    }
    // A section no group names is still reachable.
    final loose = [
      for (final s in sections)
        if (!grouped.contains(s.id)) s,
    ];
    if (loose.isNotEmpty) {
      groups.add(AthkarGroup(id: 'other', name: 'أذكار أخرى', sections: loose));
    }

    final featured = <AthkarFeatured>[];
    final rawFeatured = decoded['featured'];
    if (rawFeatured is List) {
      for (final f in rawFeatured) {
        if (f is! Map || f['label'] is! String) continue;
        final section = byId[f['section']];
        if (section == null) continue;
        featured.add(
          AthkarFeatured(
            section: section,
            label: f['label'] as String,
            icon: f['icon'] is String ? f['icon'] as String : '',
          ),
        );
      }
    }

    final reciters = <AthkarReciter>[];
    final rawReciters = decoded['reciters'];
    if (rawReciters is List) {
      for (final r in rawReciters) {
        final reciter = AthkarReciter.tryParse(r);
        if (reciter != null && reciters.every((x) => x.id != reciter.id)) {
          reciters.add(reciter);
        }
      }
    }

    final ver = decoded['ver'];
    final quranReciter = decoded['quranReciter'];
    final shareLine = decoded['shareLine'];
    return AthkarData(
      shareLine: shareLine is String && shareLine.trim().isNotEmpty
          ? shareLine.trim()
          : defaultShareLine,
      quranReciterId: quranReciter is String && quranReciter.isNotEmpty
          ? quranReciter
          : defaultQuranReciterId,
      version: ver is int ? ver : 0,
      featured: featured,
      groups: groups,
      sections: sections,
      reciters: reciters,
    );
  }
}

/// «مرة واحدة», «مرتان», «3 مرات», «100 مرة».
String athkarTimes(int n) =>
    arabicCount(n, one: 'مرة واحدة', two: 'مرتان', few: 'مرات', many: 'مرة');

/// «ذكر واحد», «ذكران», «5 أذكار», «24 ذكرًا».
String athkarCount(int n) =>
    arabicCount(n, one: 'ذكر واحد', two: 'ذكران', few: 'أذكار', many: 'ذكرًا');

/// What copy and share send: the dhikr, how many times, who narrated it, and
/// the app's line (owner, 2026-11-17; the line comes from the data).
String athkarShareText(
  AthkarItem item, {
  String shareLine = AthkarData.defaultShareLine,
}) {
  final b = StringBuffer(item.text);
  if (item.count > 1) b.write('\n(${athkarTimes(item.count)})');
  if (item.source.isNotEmpty) b.write('\n${item.source}');
  b.write('\n\n$shareLine');
  return b.toString();
}

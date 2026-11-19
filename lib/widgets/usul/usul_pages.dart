import 'package:flutter/material.dart';

import '../../models/usul.dart';
import '../../services/daily_page_service.dart';
import '../../utils/quran_display_text.dart';
import '../athkar/athkar_widgets.dart' show AthkarColors, athkarAppBar;

/// Colours of the section, from the app's surfaces (light, sepia, dark).
class _UsulColors {
  _UsulColors(BuildContext context)
    : base = AthkarColors.of(context),
      dark = Theme.of(context).brightness == Brightness.dark;

  final AthkarColors base;
  final bool dark;

  Color get page => base.page;
  Color get card => base.card;
  Color get text => base.text;
  Color get muted => base.muted;
  Color get accent => base.accent;
  Color get hair => base.hair;

  /// Notes and the small tags.
  Color get soft => base.accent.withValues(alpha: dark ? 0.16 : 0.10);

  /// The marked words inside an ayah.
  Color get mark => base.accent.withValues(alpha: dark ? 0.30 : 0.20);

  /// «يخالف حفصًا».
  Color get differs => dark ? const Color(0xFFE59A8C) : const Color(0xFF8C3B2E);
  Color get differsBg => differs.withValues(alpha: dark ? 0.18 : 0.12);

  /// The verse block: a dark card in the light looks, a raised card at night.
  Color get verseBg => dark ? base.tile : const Color(0xFF2B2116);
  Color get verseText => const Color(0xFFF7F3EA);
  Color get verseGold => const Color(0xFFD2B97E);
  Color get verseMuted => const Color(0xFFCFC3AA);
}

const double _quranSize = 20;

TextStyle _quranStyle(Color color, {double size = _quranSize}) =>
    TextStyle(color: color, fontSize: size, height: 1.9);

/// Prose with **bold** parts; KFGQPC marks inside it shown as the mushaf
/// shows them.
TextSpan _rich(String text, TextStyle style, {Color? bold}) {
  final parts = tafsirDisplayText(text).split('**');
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          TextSpan(
            text: parts[i],
            style: i.isOdd
                ? TextStyle(fontWeight: FontWeight.w700, color: bold)
                : null,
          ),
    ],
  );
}

/// Opens [page] in the reader: back to the mushaf, on that page. Uses the
/// same path as a tapped «صفحة اليوم» reminder, which already pops whatever
/// is over the reader first.
void _openPage(int page) =>
    DailyPageService.instance.handleReminderTapped('$page');

/// «أحكام وأصول الرواية», opened from the side menu as its own window.
class UsulHomePage extends StatefulWidget {
  const UsulHomePage({super.key});

  @override
  State<UsulHomePage> createState() => _UsulHomePageState();
}

class _UsulHomePageState extends State<UsulHomePage> {
  late final Future<UsulData> _data = UsulData.load();

  @override
  Widget build(BuildContext context) {
    final c = _UsulColors(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: c.page,
        appBar: athkarAppBar(context, 'أحكام وأصول الرواية'),
        body: FutureBuilder<UsulData>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text(
                  'تعذّر تحميل هذا القسم',
                  style: TextStyle(color: c.muted, fontSize: 15),
                ),
              );
            }
            final data = snap.data;
            if (data == null) {
              return Center(child: CircularProgressIndicator(color: c.accent));
            }
            return _body(c, data);
          },
        ),
      ),
    );
  }

  Widget _body(_UsulColors c, UsulData data) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 20 + bottom),
      children: [
        _hero(c, data.hero),
        if (data.kinds.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final k in data.kinds)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
              decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    k.name,
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    k.text,
                    style: TextStyle(color: c.muted, fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            ),
        ],
        for (final g in data.groups) ...[
          if (g.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
              child: Text(
                g.name,
                style: TextStyle(
                  color: c.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            const SizedBox(height: 14),
          _list(c, g.chapters),
        ],
      ],
    );
  }

  Widget _hero(_UsulColors c, UsulHero h) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: c.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.hair),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          h.title,
          style: TextStyle(
            color: c.accent,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          h.text,
          style: TextStyle(color: c.text, fontSize: 14.5, height: 1.75),
        ),
        if (h.lines.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                for (final l in h.lines)
                  Text(
                    l,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.text, fontSize: 15, height: 1.9),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            h.where,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
        ],
      ],
    ),
  );

  Widget _list(_UsulColors c, List<UsulChapter> chapters) => Material(
    color: c.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: c.hair),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < chapters.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: c.hair),
          _row(c, chapters[i]),
        ],
      ],
    ),
  );

  Widget _row(_UsulColors c, UsulChapter ch) => InkWell(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => UsulChapterPage(chapter: ch)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      child: Row(
        children: [
          if (ch.icon != null) ...[
            Icon(_iconOf(ch.icon!), color: c.accent, size: 20),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tafsirDisplayText(ch.title),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (ch.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tafsirDisplayText(ch.subtitle),
                    style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_left_rounded, color: c.muted, size: 20),
        ],
      ),
    ),
  );

  static IconData _iconOf(String name) => switch (name) {
    'translate' => Icons.translate_rounded,
    'library_books' => Icons.library_books_outlined,
    _ => Icons.menu_book_outlined,
  };
}

/// One chapter: the rule, its examples from the mushaf, the verse from
/// الشاطبية and the source.
class UsulChapterPage extends StatelessWidget {
  const UsulChapterPage({super.key, required this.chapter});

  final UsulChapter chapter;

  @override
  Widget build(BuildContext context) {
    final c = _UsulColors(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final title = tafsirDisplayText(chapter.title);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: c.page,
        appBar: athkarAppBar(context, title),
        body: SelectionArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 24 + bottom),
            children: [
              if (chapter.tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in chapter.tags)
                      _Pill(
                        t.text,
                        color: t.differs ? c.differs : c.accent,
                        background: t.differs ? c.differsBg : c.soft,
                      ),
                  ],
                ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: c.text,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              ..._UsulBlocks.build(c, chapter.blocks),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color, required this.background});
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

/// Draws a chapter's blocks. Unknown kinds are skipped.
class _UsulBlocks {
  _UsulBlocks._();

  static List<Widget> build(_UsulColors c, List<Map<String, dynamic>> blocks) {
    final out = <Widget>[];
    for (final b in blocks) {
      final w = _block(c, b);
      if (w != null) out.add(w);
    }
    return out;
  }

  static String _s(Object? v) => v is String ? v : '';

  static List<Map<String, dynamic>> _items(Map<String, dynamic> b) => [
    if (b['items'] is List)
      for (final i in b['items'] as List)
        if (i is Map<String, dynamic>) i,
  ];

  static Widget? _block(_UsulColors c, Map<String, dynamic> b) {
    switch (b['t']) {
      case 'lead':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text.rich(
            _rich(
              _s(b['x']),
              TextStyle(color: c.text, fontSize: 15, height: 1.8),
              bold: c.accent,
            ),
          ),
        );
      case 'para':
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(
            _rich(
              _s(b['x']),
              TextStyle(color: c.text, fontSize: 14, height: 1.75),
              bold: c.accent,
            ),
          ),
        );
      case 'sub':
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text.rich(
            _rich(
              _s(b['x']),
              TextStyle(color: c.text, fontSize: 14, height: 1.7),
              bold: c.accent,
            ),
          ),
        );
      case 'head':
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text(
            _s(b['x']),
            style: TextStyle(
              color: c.accent,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case 'note':
        final muted = b['mu'] == true;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          decoration: BoxDecoration(
            color: muted ? c.hair : c.soft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text.rich(
            _rich(
              _s(b['x']),
              TextStyle(
                color: muted ? c.muted : c.text,
                fontSize: 14,
                height: 1.8,
              ),
              bold: muted ? c.text : c.accent,
            ),
          ),
        );
      case 'minis':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final i in _items(b))
                _Example(
                  c: c,
                  word: _s(i['w']),
                  where: _s(i['r']),
                  page: i['p'] is int ? i['p'] as int : null,
                  what: _s(i['x']),
                ),
            ],
          ),
        );
      case 'words':
        final items = _items(b);
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.hair),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var k = 0; k < items.length; k++) ...[
                if (k > 0) Divider(height: 1, thickness: 1, color: c.hair),
                _WordRow(
                  c: c,
                  word: _s(items[k]['w']),
                  where: _s(items[k]['r']),
                  page: items[k]['p'] is int ? items[k]['p'] as int : null,
                ),
              ],
            ],
          ),
        );
      case 'ayah':
        return _AyahCard(c: c, b: b);
      case 'options':
        final items = _items(b);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var k = 0; k < items.length; k++) ...[
                  if (k > 0) const SizedBox(width: 8),
                  Expanded(child: _option(c, items[k])),
                ],
              ],
            ),
          ),
        );
      case 'steps':
        final items = _items(b);
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = 0; k < items.length; k++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text(
                        '${k + 1}. ${_s(items[k]['x'])}',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          height: 1.7,
                        ),
                      ),
                      if (items[k]['pref'] == true) _preferred(c),
                    ],
                  ),
                ),
            ],
          ),
        );
      case 'card':
        final inner = b['blocks'];
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.hair),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _s(b['h']),
                style: TextStyle(
                  color: c.accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (inner is List)
                ...build(c, [
                  for (final x in inner)
                    if (x is Map<String, dynamic>) x,
                ]),
            ],
          ),
        );
      case 'chips':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in (b['items'] is List ? b['items'] as List : []))
                if (w is String)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.hair),
                    ),
                    child: Text(
                      quranDisplayText(w),
                      style: _quranStyle(c.text, size: 18),
                    ),
                  ),
            ],
          ),
        );
      case 'verse':
        return _verse(c, b);
      case 'src':
        final items = b['items'] is List ? b['items'] as List : const [];
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.muted.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.library_books_outlined,
                    color: c.muted,
                    size: 17,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'المصدر',
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              for (final s in items)
                if (s is String)
                  Text.rich(
                    _rich(
                      s,
                      TextStyle(color: c.text, fontSize: 13.5, height: 1.75),
                    ),
                  ),
            ],
          ),
        );
      case 'book':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.hair),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.menu_book_outlined, color: c.accent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s(b['h']),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _s(b['by']),
                      style: TextStyle(color: c.accent, fontSize: 12.5),
                    ),
                    const SizedBox(height: 5),
                    Text.rich(
                      _rich(
                        _s(b['x']),
                        TextStyle(color: c.text, fontSize: 13.5, height: 1.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
    return null;
  }

  static Widget _preferred(_UsulColors c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7),
    decoration: BoxDecoration(
      color: c.mark,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      'المقدَّم',
      style: TextStyle(
        color: c.accent,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  static Widget _option(_UsulColors c, Map<String, dynamic> o) => Container(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
    decoration: BoxDecoration(
      color: c.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: c.hair),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _s(o['n']),
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (o['pref'] == true) _preferred(c),
          ],
        ),
        const SizedBox(height: 4),
        Text.rich(
          _rich(
            _s(o['x']),
            TextStyle(color: c.text, fontSize: 13.5, height: 1.7),
            bold: c.accent,
          ),
        ),
      ],
    ),
  );

  static Widget _verse(_UsulColors c, Map<String, dynamic> b) {
    final lines = [
      if (b['lines'] is List)
        for (final l in b['lines'] as List)
          if (l is String) l,
    ];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: c.verseBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote_rounded, color: c.verseGold, size: 18),
              const SizedBox(width: 4),
              Text(
                'من الشاطبية',
                style: TextStyle(color: c.verseGold, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final l in lines)
            Text(
              l,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.verseText, fontSize: 16, height: 1.9),
            ),
          if (_s(b['g']).isNotEmpty) ...[
            Divider(
              height: 14,
              thickness: 1,
              color: c.verseText.withValues(alpha: 0.14),
            ),
            Text.rich(
              _rich(
                _s(b['g']),
                TextStyle(color: c.verseMuted, fontSize: 13, height: 1.75),
                bold: c.verseGold,
              ),
            ),
          ],
          if (_s(b['w']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                _s(b['w']),
                style: TextStyle(
                  color: c.verseMuted.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// «… · صفحة N» that opens the page.
class _PageLink extends StatelessWidget {
  const _PageLink({required this.c, required this.where, this.page});
  final _UsulColors c;
  final String where;
  final int? page;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      page == null ? where : '$where · صفحة $page',
      style: TextStyle(color: c.muted, fontSize: 12.5),
    );
    if (page == null) return label;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openPage(page!),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            label,
            const SizedBox(width: 4),
            Icon(Icons.west_rounded, color: c.accent, size: 14),
          ],
        ),
      ),
    );
  }
}

class _Example extends StatelessWidget {
  const _Example({
    required this.c,
    required this.word,
    required this.where,
    required this.what,
    this.page,
  });
  final _UsulColors c;
  final String word;
  final String where;
  final String what;
  final int? page;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 9),
    decoration: BoxDecoration(
      color: c.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: c.hair),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          quranDisplayText(word),
          style: _quranStyle(c.accent, size: 21),
        ),
        _PageLink(c: c, where: where, page: page),
        if (what.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text.rich(
            _rich(
              what,
              TextStyle(color: c.text, fontSize: 14, height: 1.7),
              bold: c.accent,
            ),
          ),
        ],
      ],
    ),
  );
}

class _WordRow extends StatelessWidget {
  const _WordRow({
    required this.c,
    required this.word,
    required this.where,
    this.page,
  });
  final _UsulColors c;
  final String word;
  final String where;
  final int? page;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              quranDisplayText(word),
              style: _quranStyle(c.accent, size: 19),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            page == null ? where : '$where · صفحة $page',
            style: TextStyle(color: c.muted, fontSize: 12.5),
          ),
          if (page != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.west_rounded, color: c.accent, size: 14),
          ],
        ],
      ),
    );
    if (page == null) return row;
    return InkWell(onTap: () => _openPage(page!), child: row);
  }
}

class _AyahCard extends StatelessWidget {
  const _AyahCard({required this.c, required this.b});
  final _UsulColors c;
  final Map<String, dynamic> b;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (b['parts'] is List)
        for (final p in b['parts'] as List)
          if (p is List && p.length == 2 && p[0] is String) p,
    ];
    final ayah = b['a'] is int ? b['a'] as int : null;
    final page = b['p'] is int ? b['p'] as int : null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              style: _quranStyle(c.text),
              children: [
                for (final p in parts)
                  TextSpan(
                    text: quranDisplayText(p[0] as String),
                    style: p[1] == 1
                        ? TextStyle(
                            color: c.accent,
                            fontWeight: FontWeight.w700,
                            backgroundColor: c.mark,
                          )
                        : null,
                  ),
                if (ayah != null)
                  TextSpan(
                    text: ' ﴿$ayah﴾',
                    style: TextStyle(color: c.accent, fontSize: 16),
                  ),
              ],
            ),
          ),
          Divider(height: 12, thickness: 1, color: c.hair),
          Row(
            children: [
              Expanded(
                child: Text(
                  page == null
                      ? _s(b['r'])
                      : '${_s(b['r'])} · صفحة $page',
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ),
              if (page != null)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openPage(page),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'اذهب إلى الآية',
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.west_rounded,
                          color: c.accent,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _s(Object? v) => v is String ? v : '';
}

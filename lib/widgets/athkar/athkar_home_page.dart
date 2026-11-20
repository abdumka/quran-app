import 'package:flutter/material.dart';

import '../../models/athkar.dart';
import '../../services/athkar_service.dart';
import '../../utils/arabic_text_normalizer.dart';
import '../../utils/quran_display_text.dart' show arabicCount;
import 'athkar_reader_page.dart';
import 'athkar_reminder_widgets.dart';
import 'athkar_widgets.dart';

/// «الأذكار», opened from the side menu as its own window.
///
/// On top, the athkar most people come for (morning, evening, after the
/// prayer, sleep, waking up) and the reader's favourites, each with today's
/// progress. Under them, every other section, folded into themed groups.
class AthkarHomePage extends StatefulWidget {
  const AthkarHomePage({super.key});

  @override
  State<AthkarHomePage> createState() => _AthkarHomePageState();
}

class _AthkarHomePageState extends State<AthkarHomePage> {
  final AthkarService _service = AthkarService.instance;
  final AthkarStore _store = AthkarStore.instance;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _openGroup;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ready = _service.isLoaded;
    Future.wait([_service.load(), _store.load()]).then((_) {
      if (mounted) setState(() => _ready = true);
    });
    // the first opening says what the athkar reminders are and asks for
    // notifications and the place (once; never at app start)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowAthkarReminderIntro(context);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openSection(AthkarSection section, {String? title, int? itemId}) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AthkarReaderPage(
          title: title ?? section.name,
          items: section.items,
          initialItemId: itemId,
          section: section,
        ),
      ),
    );
  }

  /// The favourite athkar straight away; with favourite sections too, the
  /// favourites screen that lists the sections and the athkar.
  void _openFavourites() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _store.favouriteSections.isEmpty
            ? favouriteAthkarReader(_service.data, _store)
            : const AthkarFavouritesPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: c.page,
        appBar: athkarAppBar(
          context,
          'الأذكار',
          actions: [
            IconButton(
              tooltip: 'إعدادات الأذكار',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => showAthkarSettingsSheet(context),
            ),
          ],
        ),
        body: !_ready
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : ListenableBuilder(
                listenable: Listenable.merge([_store, _service.revision]),
                builder: (context, _) => _body(c),
              ),
      ),
    );
  }

  Widget _body(AthkarColors c) {
    final data = _service.data;
    if (data.isEmpty) {
      return Center(
        child: Text(
          'تعذّر تحميل الأذكار',
          style: TextStyle(color: c.muted, fontSize: 15),
        ),
      );
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    final searching = _query.isNotEmpty;
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 16 + bottom),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _searchField(c),
        const SizedBox(height: 12),
        if (searching)
          ..._results(c, data)
        else ...[
          _tiles(c, data),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
            child: Text(
              'كل الأذكار',
              style: TextStyle(
                color: c.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final group in data.groups) _group(c, group),
        ],
      ],
    );
  }

  Widget _searchField(AthkarColors c) => TextField(
    controller: _search,
    textInputAction: TextInputAction.search,
    style: TextStyle(color: c.text, fontSize: 15),
    cursorColor: c.accent,
    onChanged: (value) =>
        setState(() => _query = normalizeArabicText(value).trim()),
    decoration: InputDecoration(
      hintText: 'ابحث في الأذكار',
      hintStyle: TextStyle(color: c.muted, fontSize: 14.5),
      prefixIcon: Icon(Icons.search_rounded, color: c.muted, size: 20),
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              tooltip: 'مسح',
              icon: Icon(Icons.close_rounded, color: c.muted, size: 20),
              onPressed: () {
                _search.clear();
                setState(() => _query = '');
              },
            ),
      isDense: true,
      filled: true,
      fillColor: c.card,
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.hair),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.accent),
      ),
    ),
  );

  // ---- the tiles ----

  static IconData _iconOf(String name) => switch (name) {
    'sun' => Icons.wb_sunny_outlined,
    'moon' => Icons.nightlight_outlined,
    'prayer' => Icons.mosque_outlined,
    'bed' => Icons.bed_outlined,
    'wake' => Icons.wb_twilight_rounded,
    // more names the server's data may give tiles it adds later
    'star' => Icons.star_outline_rounded,
    'heart' => Icons.favorite_outline_rounded,
    'travel' => Icons.flight_outlined,
    'home' => Icons.home_outlined,
    'food' => Icons.restaurant_outlined,
    'rain' => Icons.water_drop_outlined,
    'quran' => Icons.auto_stories_outlined,
    'hands' => Icons.volunteer_activism_outlined,
    'night' => Icons.dark_mode_outlined,
    _ => Icons.menu_book_outlined,
  };

  Widget _tiles(AthkarColors c, AthkarData data) {
    final tiles = <Widget>[
      for (final f in data.featured)
        _tile(
          c,
          icon: _iconOf(f.icon),
          label: f.label,
          done: _store.doneIn(f.section.items),
          total: f.section.items.length,
          onTap: () => _openSection(f.section),
        ),
      _tile(
        c,
        icon: Icons.star_outline_rounded,
        label: 'المفضلة',
        caption: _favouritesCaption(),
        onTap: _openFavourites,
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        // two across on a phone, more on a tablet
        final columns = (box.maxWidth / 190).floor().clamp(2, 4);
        const gap = 10.0;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }

  String _favouritesCaption() {
    final sections = _store.favouriteSections
        .where((id) => _service.data.section(id) != null)
        .length;
    final items = _store.favourites.length;
    if (sections == 0 && items == 0) return 'أذكارك المختارة';
    return [
      if (sections > 0) athkarSectionCount(sections),
      if (items > 0) athkarCount(items),
    ].join('، ');
  }

  Widget _tile(
    AthkarColors c, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int done = 0,
    int total = 0,
    String? caption,
  }) {
    final complete = total > 0 && done >= total;
    final String sub =
        caption ??
        (complete
            ? 'تمّت اليوم'
            : done == 0
            ? athkarCount(total)
            : '$done من $total');
    return Material(
      color: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.tile,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: c.icon, size: 20),
                  ),
                  const Spacer(),
                  if (complete)
                    Icon(Icons.check_circle_rounded, color: c.accent, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: c.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 3,
                  backgroundColor: total == 0 ? Colors.transparent : c.tile,
                  color: c.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- the groups ----

  Widget _group(AthkarColors c, AthkarGroup group) {
    final open = _openGroup == group.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _openGroup = open ? null : group.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${group.sections.length}',
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: open ? -0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: c.muted,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Column(
                    children: [
                      for (final s in group.sections) _sectionRow(c, s),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _sectionRow(AthkarColors c, AthkarSection section) {
    final done = _store.doneIn(section.items) >= section.items.length;
    return InkWell(
      onTap: () => _openSection(section),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.hair)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 11, 14, 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                section.name,
                style: TextStyle(color: c.text, fontSize: 14.5, height: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            if (_store.isFavouriteSection(section)) ...[
              Icon(Icons.star_rounded, color: c.accent, size: 16),
              const SizedBox(width: 6),
            ],
            if (done)
              Icon(Icons.check_rounded, color: c.accent, size: 18)
            else
              Text(
                '${section.items.length}',
                style: TextStyle(color: c.muted, fontSize: 12.5),
              ),
          ],
        ),
      ),
    );
  }

  // ---- search ----

  List<Widget> _results(AthkarColors c, AthkarData data) {
    final sections = [
      for (final s in data.sections)
        if (s.searchName.contains(_query)) s,
    ];
    final items = <AthkarItem>[];
    for (final s in data.sections) {
      for (final i in s.items) {
        if (i.searchText.contains(_query)) items.add(i);
        if (items.length >= 60) break;
      }
      if (items.length >= 60) break;
    }
    if (sections.isEmpty && items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Center(
            child: Text(
              'لا توجد نتائج',
              style: TextStyle(color: c.muted, fontSize: 15),
            ),
          ),
        ),
      ];
    }
    Widget card(Widget child, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.hair),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            child: child,
          ),
        ),
      ),
    );
    return [
      for (final s in sections)
        card(
          Row(
            children: [
              Expanded(
                child: Text(
                  s.name,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                athkarCount(s.items.length),
                style: TextStyle(color: c.muted, fontSize: 12.5),
              ),
            ],
          ),
          () => _openSection(s),
        ),
      for (final i in items)
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i.text.replaceAll('\n', ' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.text, fontSize: 16, height: 1.8),
              ),
              const SizedBox(height: 2),
              Text(
                data.section(i.sectionId)?.name ?? '',
                style: TextStyle(color: c.muted, fontSize: 12.5),
              ),
            ],
          ),
          () {
            final section = data.section(i.sectionId);
            if (section != null) _openSection(section, itemId: i.id);
          },
        ),
    ];
  }
}

/// «عدد الأقسام»: «قسم واحد», «قسمان», «3 أقسام», «11 قسمًا».
String athkarSectionCount(int n) =>
    arabicCount(n, one: 'قسم واحد', two: 'قسمان', few: 'أقسام', many: 'قسمًا');

/// The favourite athkar, one after the other, each with its section's name.
AthkarReaderPage favouriteAthkarReader(AthkarData data, AthkarStore store) =>
    AthkarReaderPage(
      title: 'الأذكار المفضلة',
      items: [
        for (final id in store.favourites)
          if (data.item(id) != null) data.item(id)!,
      ],
      showSection: true,
      emptyHint:
          'لا توجد أذكار مفضلة بعد.\n'
          'اضغط النجمة على أي ذكر ليظهر هنا، أو النجمة أعلى صفحة القسم '
          'ليظهر القسم كاملًا.',
    );

/// «المفضلة» once a whole section is in it: the favourite sections (each
/// opens as itself, with today's progress) and, under them, the favourite
/// athkar as one entry.
class AthkarFavouritesPage extends StatelessWidget {
  const AthkarFavouritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    final service = AthkarService.instance;
    final store = AthkarStore.instance;
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
      child: Text(
        text,
        style: TextStyle(
          color: c.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    Widget card(List<Widget> rows) => Material(
      color: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: c.page,
        appBar: athkarAppBar(context, 'المفضلة'),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final data = service.data;
            final sections = [
              for (final id in store.favouriteSections)
                if (data.section(id) != null) data.section(id)!,
            ];
            final items = store.favourites.where((id) => data.item(id) != null);
            return ListView(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + bottom),
              children: [
                heading('أقسام كاملة'),
                if (sections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'اضغط النجمة أعلى صفحة أي قسم ليظهر هنا.',
                      style: TextStyle(color: c.muted, fontSize: 13.5),
                    ),
                  )
                else
                  card([
                    for (var i = 0; i < sections.length; i++)
                      _SectionRow(section: sections[i], first: i == 0),
                  ]),
                heading('أذكار مختارة'),
                card([
                  ListTile(
                    leading: Icon(Icons.star_rounded, color: c.accent),
                    title: Text(
                      'الأذكار المفضلة',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      items.isEmpty
                          ? 'اضغط النجمة على أي ذكر ليظهر هنا.'
                          : athkarCount(items.length),
                      style: TextStyle(color: c.muted, fontSize: 12.5),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => favouriteAthkarReader(data, store),
                      ),
                    ),
                  ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section, required this.first});

  final AthkarSection section;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    final store = AthkarStore.instance;
    final done = store.doneIn(section.items);
    final total = section.items.length;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AthkarReaderPage(
            title: section.name,
            items: section.items,
            section: section,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: c.hair)),
        ),
        padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.name,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  Text(
                    done >= total
                        ? 'تمّت اليوم'
                        : done == 0
                        ? athkarCount(total)
                        : '$done من $total',
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'إزالة القسم من المفضلة',
              icon: Icon(Icons.star_rounded, color: c.accent),
              onPressed: () => store.toggleFavouriteSection(section),
            ),
          ],
        ),
      ),
    );
  }
}

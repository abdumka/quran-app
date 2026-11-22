import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/athkar.dart';
import '../../services/athkar_audio.dart';
import '../../services/athkar_service.dart';
import '../../utils/copy_helper.dart';
import 'athkar_widgets.dart';

/// Reading a run of athkar (a section, or the favourites) in one of two
/// views the reader switches between from the top bar:
///
/// * the list: one after the other, each with its own counter bar;
/// * one dhikr a page: large text, a tap anywhere counts, and the page turns
///   by itself when the count is reached.
class AthkarReaderPage extends StatefulWidget {
  const AthkarReaderPage({
    super.key,
    required this.title,
    required this.items,
    this.initialItemId,
    this.showSection = false,
    this.emptyHint,
    this.section,
  });

  final String title;
  final List<AthkarItem> items;

  /// The section these athkar are, when they are one: its star in the top
  /// bar puts the whole section in the favourites.
  final AthkarSection? section;

  /// Opens on this dhikr (a search result).
  final int? initialItemId;

  /// Name each dhikr's section under it (the favourites).
  final bool showSection;

  /// Shown when [items] is empty.
  final String? emptyHint;

  @override
  State<AthkarReaderPage> createState() => _AthkarReaderPageState();
}

class _AthkarReaderPageState extends State<AthkarReaderPage> {
  final AthkarStore _store = AthkarStore.instance;
  final AthkarAudio _audio = AthkarAudio.instance;
  late final List<GlobalKey> _keys = [
    for (final _ in widget.items) GlobalKey(),
  ];
  late int _index;
  late PageController _pages;
  final ScrollController _scroll = ScrollController();
  Timer? _advance;
  Timer? _swiped;

  /// The single view's page is being turned by the app, not by a swipe:
  /// the turns under way (a second one cuts the first short, and the first
  /// one's end must not count the second one's pages as swipes; 2026-11-21,
  /// two quick «السابق» on the emulator sent the audio back one).
  int _turns = 0;
  bool get _turning => _turns > 0;
  int _seenFailures = 0;
  int _seenUnavailable = 0;
  int? _followed;

  List<AthkarItem> get _items => widget.items;

  @override
  void initState() {
    super.initState();
    final start = _items.indexWhere((i) => i.id == widget.initialItemId);
    _index = start < 0 ? 0 : start;
    _pages = PageController(initialPage: _index);
    _seenFailures = _audio.failures.value;
    _audio.failures.addListener(_onAudioFailure);
    _seenUnavailable = _audio.unavailable.value;
    _audio.unavailable.addListener(_onUnavailable);
    _audio.addListener(_followAudio);
    if (_index > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(_index));
    }
  }

  @override
  void dispose() {
    _advance?.cancel();
    _swiped?.cancel();
    _audio.failures.removeListener(_onAudioFailure);
    _audio.unavailable.removeListener(_onUnavailable);
    _audio.removeListener(_followAudio);
    // listening belongs to the page it was started on
    if (_audio.isActive) _audio.stop();
    _pages.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onUnavailable() {
    if (!mounted || _audio.unavailable.value == _seenUnavailable) return;
    _seenUnavailable = _audio.unavailable.value;
    CopyHelper.showToast(context, 'لا يوجد تسجيل صوتي لهذا الذكر');
  }

  void _onAudioFailure() {
    if (!mounted || _audio.failures.value == _seenFailures) return;
    _seenFailures = _audio.failures.value;
    CopyHelper.showToast(context, 'تعذّر تشغيل التلاوة، تحقق من الاتصال');
  }

  /// The view goes where the listening goes.
  void _followAudio() {
    final id = _audio.current?.id;
    if (id == null || id == _followed) {
      if (id == null) _followed = null;
      return;
    }
    _followed = id;
    final i = _items.indexWhere((x) => x.id == id);
    if (i >= 0 && mounted) _goTo(i);
  }

  String? _sectionName(AthkarItem item) => widget.showSection
      ? AthkarService.instance.data.section(item.sectionId)?.name
      : null;

  /// Brings dhikr [i] into view in the current view. [byReader]: the
  /// reader asked for it (an arrow, «التالي», a completed count), so a
  /// listening under way goes there too.
  void _goTo(int i, {bool byReader = false}) {
    if (i < 0 || i >= _items.length) return;
    _index = i;
    if (byReader) _listenTo(i);
    if (_store.view == AthkarView.single) {
      if (_pages.hasClients && _pages.page?.round() != i) {
        _turns++;
        _pages
            .animateToPage(
              i,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() => _turns--);
      }
    } else {
      _reveal(i);
    }
  }

  /// The listening follows the reader to dhikr [i] (owner, 2026-11-21: the
  /// page moved on and the old dhikr kept playing).
  void _listenTo(int i) {
    final id = _items[i].id;
    if (!_audio.isActive || _audio.current?.id == id) return;
    // already where the audio is going: [_followAudio] has nothing to do
    _followed = id;
    _audio.moveTo(_items, i);
  }

  /// A swipe in the single view settled on [page].
  void _onPageChanged(int page) {
    setState(() => _index = page);
    if (_turning) return;
    // a quick run of swipes starts only the dhikr it ends on
    _swiped?.cancel();
    _swiped = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _index == page) _listenTo(page);
    });
  }

  void _reveal(int i) {
    final target = _keys[i].currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.03,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// When a dhikr was just completed, and which: fast taps that run on past
  /// its last count must not land on the next one as the list moves to it.
  DateTime? _completedAt;
  int? _completedIndex;

  void _count(int i) {
    final item = _items[i];
    if (_store.isDone(item)) return;
    final at = _completedAt;
    if (at != null &&
        i != _completedIndex &&
        DateTime.now().difference(at) < const Duration(milliseconds: 900)) {
      return;
    }
    _index = i;
    final completed = _store.increment(item);
    if (!completed) {
      athkarBuzz();
      return;
    }
    _completedAt = DateTime.now();
    _completedIndex = i;
    athkarBuzz(strong: true);
    if (i + 1 >= _items.length) return;
    // the next one comes by itself, unless the reader moved meanwhile
    _advance?.cancel();
    _advance = Timer(const Duration(milliseconds: 550), () {
      if (!mounted || _index != i) return;
      // the one being heard was just completed: its audio moves on too
      _goTo(i + 1, byReader: _audio.current?.id == item.id);
    });
  }

  /// On to the next dhikr without finishing this one's count.
  void _skip(int i) {
    HapticFeedback.selectionClick();
    _advance?.cancel();
    // the listening, if any, goes on to it too (the owner pressed «التالي»
    // and it kept repeating)
    _goTo(i + 1, byReader: true);
  }

  void _play(int i) {
    _index = i;
    _audio.start(_items, i);
  }

  /// The dhikr at the top of the list as it is scrolled now (the owner
  /// scrolled to dhikr 5, switched views and landed on dhikr 1).
  int _topVisible() {
    final viewport = _scroll.hasClients
        ? _scroll.position.context.storageContext.findRenderObject()
        : null;
    if (viewport is! RenderBox) return _index;
    // the first card with a fair part of it still on screen
    final top = viewport.localToGlobal(Offset.zero).dy + 80;
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      if (bottom > top) return i;
    }
    return _index;
  }

  void _switchView() {
    final single = _store.view == AthkarView.single;
    final at = single ? _index : _topVisible();
    _index = at;
    _store.view = single ? AthkarView.list : AthkarView.single;
    if (single) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(at));
    } else {
      _pages.dispose();
      _turns = 0;
      _pages = PageController(initialPage: at);
    }
  }

  Widget _sectionStar(AthkarColors c, AthkarSection section) {
    final on = _store.isFavouriteSection(section);
    return IconButton(
      tooltip: on ? 'إزالة القسم من المفضلة' : 'إضافة القسم إلى المفضلة',
      icon: Icon(
        on ? Icons.star_rounded : Icons.star_outline_rounded,
        color: on ? c.accent : null,
      ),
      onPressed: () {
        final added = _store.toggleFavouriteSection(section);
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                added
                    ? 'أُضيف «${section.name}» كاملًا إلى المفضلة.'
                    : 'أُزيل «${section.name}» من المفضلة.',
                textDirection: TextDirection.rtl,
              ),
              duration: const Duration(seconds: 3),
            ),
          );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListenableBuilder(
        listenable: Listenable.merge([_store, _audio]),
        builder: (context, _) {
          final single = _store.view == AthkarView.single;
          return Scaffold(
            backgroundColor: c.page,
            appBar: athkarAppBar(
              context,
              widget.title,
              actions: [
                if (widget.section != null) _sectionStar(c, widget.section!),
                IconButton(
                  tooltip: 'إعدادات الأذكار',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () =>
                      showAthkarSettingsSheet(context, switchView: _switchView),
                ),
                if (_items.isNotEmpty)
                  IconButton(
                    tooltip: single
                        ? 'عرض الكل في قائمة'
                        : 'ذكر واحد في الصفحة',
                    icon: Icon(
                      single
                          ? Icons.view_agenda_outlined
                          : Icons.crop_portrait_rounded,
                    ),
                    onPressed: _switchView,
                  ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: _items.isEmpty
                      ? _empty(c)
                      : single
                      ? _singleView(c)
                      : _listView(c),
                ),
                AthkarPlayerBar(items: _items),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _empty(AthkarColors c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        widget.emptyHint ?? '',
        textAlign: TextAlign.center,
        style: TextStyle(color: c.muted, fontSize: 15, height: 1.8),
      ),
    ),
  );

  BoxDecoration _cardDecoration(AthkarColors c, AthkarItem item) =>
      BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: _audio.current?.id == item.id
            ? Border.all(color: c.fill, width: 2)
            : Border.all(color: c.hair),
      );

  // ---- the list ----

  Widget _listView(AthkarColors c) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _readingWidth),
          child: Column(
            children: [for (var i = 0; i < _items.length; i++) _listCard(c, i)],
          ),
        ),
      ),
    );
  }

  Widget _listCard(AthkarColors c, int i) {
    final item = _items[i];
    final count = _store.countOf(item);
    final done = count >= item.count;
    return Container(
      key: _keys[i],
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      decoration: _cardDecoration(c, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AthkarCardHeader(
            item: item,
            index: i,
            total: _items.length,
            onPlay: () => _play(i),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedOpacity(
              opacity: done ? 0.55 : 1,
              duration: const Duration(milliseconds: 220),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text.rich(
                    athkarTextSpan(
                      item.text,
                      TextStyle(color: c.text, fontSize: 21, height: 1.9),
                      c.accent,
                    ),
                  ),
                  AthkarSourceLine(item: item, sectionName: _sectionName(item)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: AthkarCounterBar(
                    count: count,
                    total: item.count,
                    onTap: () => _count(i),
                  ),
                ),
                // said several times: the reader may move on without
                // finishing the count (said it without tapping, or skips
                // it); it is not marked done
                if (!done && item.count > 1 && i + 1 < _items.length) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.icon,
                        side: BorderSide(color: c.hair),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _skip(i),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('التالي'),
                          Icon(Icons.chevron_right_rounded, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (done)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: c.accent,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _store.reset(item),
                child: const Text('إعادة'),
              ),
            ),
        ],
      ),
    );
  }

  // ---- one dhikr a page ----

  Widget _singleView(AthkarColors c) {
    final i = _index.clamp(0, _items.length - 1);
    final item = _items[i];
    final count = _store.countOf(item);
    final done = _store.doneIn(_items);
    final progress = ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: done / _items.length,
        minHeight: 4,
        backgroundColor: c.tile,
        color: c.accent,
      ),
    );
    final pages = PageView.builder(
      controller: _pages,
      itemCount: _items.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, page) => _singleCard(c, page),
    );
    Widget arrow({required bool next}) => IconButton(
      tooltip: next ? 'التالي' : 'السابق',
      icon: Icon(
        next ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
        color: c.icon,
      ),
      iconSize: 30,
      onPressed: next
          ? (i < _items.length - 1 ? () => _goTo(i + 1, byReader: true) : null)
          : (i > 0 ? () => _goTo(i - 1, byReader: true) : null),
    );
    final note = SizedBox(
      height: 26,
      child: count >= item.count
          ? TextButton(
              style: TextButton.styleFrom(
                foregroundColor: c.accent,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              onPressed: () => _store.reset(item),
              child: const Text('إعادة'),
            )
          : Text(
              'اضغط في أي مكان للعدّ',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
    );
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, box) {
          // a phone held sideways: under the card the dhikr kept half a
          // line (emulator, 2026-11-21), so the counter and the arrows go
          // beside it and the text has the whole height
          if (box.maxHeight < 420 && box.maxWidth > box.maxHeight * 1.4) {
            return Row(
              children: [
                Expanded(child: pages),
                SizedBox(
                  width: 210,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      0,
                      12,
                      12,
                      10,
                    ),
                    child: Column(
                      children: [
                        progress,
                        const SizedBox(height: 10),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, side) => AthkarCounterBar(
                              count: count,
                              total: item.count,
                              height: side.maxHeight,
                              onTap: () => _count(i),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            arrow(next: false),
                            Expanded(child: Center(child: note)),
                            arrow(next: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return Center(
            child: ConstrainedBox(
              // a tablet: lines no longer than a reader's eye takes in
              constraints: const BoxConstraints(maxWidth: _readingWidth),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: progress,
                  ),
                  Expanded(child: pages),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                    child: Row(
                      children: [
                        arrow(next: false),
                        Expanded(
                          child: AthkarCounterBar(
                            count: count,
                            total: item.count,
                            height: 56,
                            onTap: () => _count(i),
                          ),
                        ),
                        arrow(next: true),
                      ],
                    ),
                  ),
                  note,
                  const SizedBox(height: 6),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The widest the athkar's text runs (tablets).
  static const double _readingWidth = 760;

  Widget _singleCard(AthkarColors c, int i) {
    final item = _items[i];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _count(i),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          decoration: _cardDecoration(c, item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AthkarCardHeader(
                item: item,
                index: i,
                total: _items.length,
                onPlay: () => _play(i),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: ConstrainedBox(
                      // short athkar sit in the middle of the card
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text.rich(
                            athkarTextSpan(
                              item.text,
                              TextStyle(
                                color: c.text,
                                fontSize: 25,
                                height: 1.95,
                              ),
                              c.accent,
                            ),
                          ),
                          AthkarSourceLine(
                            item: item,
                            sectionName: _sectionName(item),
                            expanded: true,
                          ),
                          if (item.count > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                athkarTimes(item.count),
                                style: TextStyle(
                                  color: c.accent,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

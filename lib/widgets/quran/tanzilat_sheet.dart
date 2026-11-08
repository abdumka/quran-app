import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../models/quran_page_data.dart';
import '../../services/quran_json_service.dart';
import '../../services/tanzilat_notes_store.dart';
import '../../services/tanzilat_service.dart';
import '../../surah_data.dart';
import '../../utils/quran_display_text.dart';
import 'tanzilat_overlay.dart';

/// Where a place of a tanzilah is printed: its ayah's text and page.
class _AyahInfo {
  final List<String> words;
  final int page;

  const _AyahInfo(this.words, this.page);
}

Future<Map<(int, int), _AyahInfo>>? _ayahIndex;

Future<Map<(int, int), _AyahInfo>> _loadAyahIndex() =>
    _ayahIndex ??= QuranJsonService.loadQuranPages().then((pages) {
      return {
        for (final QuranPageData p in pages)
          for (final a in p.ayahs)
            (a.surah, a.ayah): _AyahInfo(a.text.split(' '), p.page),
      };
    });

String _surahName(int surah) =>
    surahList.firstWhere(
          (s) => s['number'] == surah,
          orElse: () => const {},
        )['name']
        as String? ??
    '';

/// The places a card lists: every row's, its «متكررة» rows too, one entry
/// per ayah (البينة 5 has two of 911's words: one place, both coloured).
List<TanzilahPlace> _placesOf(TanzilahHit hit) {
  final byAyah = <(int, int), Set<int>>{};
  for (final r in hit.group.rows) {
    for (final p in r.places) {
      byAyah.putIfAbsent((p.surah, p.ayah), () => {}).addAll(p.words);
    }
  }
  return [
    for (final e in byAyah.entries)
      TanzilahPlace(e.key.$1, e.key.$2, e.value.toList()..sort()),
  ];
}

/// The card's title: the one the reviewers gave the tanzilah, else its
/// first words («أذيً، مسميً، ضحيً …»). Its count is in the coloured badge.
String _headingOf(TanzilahHit hit, List<String>? Function(int, int) wordsAt) {
  final title = hit.group.title;
  if (title != null && title.isNotEmpty) return title;
  final names = <String>[];
  for (final r in hit.group.rows) {
    if (r.rule) {
      if (r.places.isNotEmpty && r.word != null) {
        names.add(quranDisplayText(r.word!));
      }
      continue;
    }
    for (final p in r.places) {
      final w = wordsAt(p.surah, p.ayah);
      if (w == null) continue;
      names.add(
        [
          for (final i in p.words)
            if (i < w.length) quranDisplayText(w[i]),
        ].join(' '),
      );
    }
  }
  final unique = names.where((n) => n.isNotEmpty).toSet().toList();
  if (unique.isEmpty) return hit.group.isGharibah ? 'غريبة' : 'تنزيلة';
  return unique.take(3).join('، ') + (unique.length > 3 ? ' …' : '');
}

/// The badge's content, for the copied text (it has no coloured circle).
String _countOf(TanzilahHit hit) =>
    hit.group.isGharibah ? 'غريبة' : '${hit.group.count}';

/// The words shown for a place: a few around the coloured ones.
(int, int) _snippetRange(TanzilahPlace p, List<String> words) {
  if (p.words.isEmpty || words.isEmpty) return (0, words.length);
  final first = p.words.reduce((a, b) => a < b ? a : b);
  final last = p.words.reduce((a, b) => a > b ? a : b);
  return (
    (first - 4).clamp(0, words.length),
    (last + 5).clamp(0, words.length),
  );
}

/// Everything the sheet says about one ayah as plain text (every place, also
/// the folded ones), for «نسخ الكل». The coloured words are put in «».
String tanzilatCopyText(
  int surah,
  int ayah,
  List<TanzilahHit> hits,
  Map<(int, int), List<String>> words, {
  String note = '',
}) {
  final out = StringBuffer(
    'تنزيلات ومتشابهات — سورة ${_surahName(surah)} $ayah\n',
  );
  if (note.trim().isNotEmpty) out.write('\nملاحظاتي:\n${note.trim()}\n');
  for (final hit in hits) {
    _writeTanzilah(out, surah, ayah, hit, words);
  }
  return out.toString().trimRight();
}

/// One tanzilah of the sheet as plain text, for the small copy icon on its
/// card: the same lines «نسخ الكل» writes for it, under the ayah's line.
String tanzilahCopyText(
  int surah,
  int ayah,
  TanzilahHit hit,
  Map<(int, int), List<String>> words,
) {
  final out = StringBuffer(
    'تنزيلات ومتشابهات — سورة ${_surahName(surah)} $ayah\n',
  );
  _writeTanzilah(out, surah, ayah, hit, words);
  return out.toString().trimRight();
}

void _writeTanzilah(
  StringBuffer out,
  int surah,
  int ayah,
  TanzilahHit hit,
  Map<(int, int), List<String>> words,
) {
  final heading = _headingOf(hit, (s, a) => words[(s, a)]);
  out.write('\n$heading (${_countOf(hit)})\n');
  final places = _placesOf(hit);
  for (final p in places) {
    final w = words[(p.surah, p.ayah)] ?? const <String>[];
    final (from, to) = _snippetRange(p, w);
    final marked = p.words.toSet();
    // neighbouring coloured words share one «»: «لعلكم تشكرون»
    final text = [
      for (var i = from; i < to; i++)
        [
          if (marked.contains(i) && !marked.contains(i - 1)) '«',
          quranDisplayText(w[i]),
          if (marked.contains(i) && !marked.contains(i + 1)) '»',
        ].join(),
    ].join(' ');
    final here = p.surah == surah && p.ayah == ayah ? ' (هذه الآية)' : '';
    final head = from > 0 ? '… ' : '';
    final tail = to < w.length ? ' …' : '';
    out.write('- ${_surahName(p.surah)} ${p.ayah}$here: $head$text$tail\n');
  }
  for (final d in hit.danfasi) {
    out.write('قال الدنفاسي («${d.title}»):\n');
    for (final line in d.lines) {
      out.write('$line\n');
    }
  }
}

/// The «تنزيلات ومتشابهات» sheet of one ayah: every tanzilah touching it, its
/// count from «مذكرة التنزيل», all its places (tap one to open its page) and
/// الدنفاسي's verse when there is one. [onOpenPlace] gets the 1-based page of
/// the tapped place.
Future<void> showTanzilatSheet(
  BuildContext context, {
  required int surah,
  required int ayah,
  required void Function(int page, int surah, int ayah) onOpenPlace,
}) async {
  await TanzilatService.instance.load();
  await TanzilatNotesStore.instance.load();
  if (!context.mounted) return;
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDarkMode
        ? const Color(0xFF19130A)
        : const Color(0xFFF8F1DE),
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(
        color: isDarkMode
            ? const Color(0xFFD6B35D).withValues(alpha: 0.55)
            : const Color(0xFFE2D2A5),
        width: 2,
      ),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, controller) => TanzilatSheetContent(
        surah: surah,
        ayah: ayah,
        dark: isDarkMode,
        controller: controller,
        onOpenPlace: (page, s, a) {
          Navigator.of(sheetContext).pop();
          onOpenPlace(page, s, a);
        },
      ),
    ),
  );
}

class TanzilatSheetContent extends StatelessWidget {
  const TanzilatSheetContent({
    super.key,
    required this.surah,
    required this.ayah,
    required this.dark,
    required this.onOpenPlace,
    this.controller,
  });

  final int surah;
  final int ayah;
  final bool dark;
  final ScrollController? controller;
  final void Function(int page, int surah, int ayah) onOpenPlace;

  Color get _title => dark ? const Color(0xFFFFF4D6) : const Color(0xFF35250E);
  Color get _accent => dark ? const Color(0xFFD6B35D) : const Color(0xFF8D6E3F);
  Color get _border => dark
      ? const Color(0xFFD6B35D).withValues(alpha: 0.4)
      : const Color(0xFFE2D2A5);
  Color get _card => dark ? const Color(0xFF241B0E) : Colors.white;

  @override
  Widget build(BuildContext context) {
    // Rarest first: a غريبة is the one most worth knowing.
    final hits = [...TanzilatService.instance.forAyah(surah, ayah)]
      ..sort((a, b) => a.count.compareTo(b.count));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<Map<(int, int), _AyahInfo>>(
        future: _loadAyahIndex(),
        builder: (context, snap) {
          final index = snap.data;
          // Every text in the sheet can be marked and copied (long press);
          // «نسخ الكل» copies the whole sheet at once.
          return SelectionArea(
            child: ListView(
              controller: controller,
              padding: EdgeInsets.fromLTRB(
                14,
                10,
                14,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'تنزيلات ومتشابهات — سورة ${_surahName(surah)} $ayah',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _title,
                        ),
                      ),
                    ),
                    // Also on an ayah with no tanzilah: it may have a note.
                    if (index != null)
                      _CopyAllButton(
                        colour: _accent,
                        text: () => tanzilatCopyText(
                          surah,
                          ayah,
                          hits,
                          {
                            for (final e in index.entries)
                              e.key: e.value.words,
                          },
                          note: TanzilatNotesStore.instance.noteOf(
                            surah,
                            ayah,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'اضغط على أي موضع لتنتقل إلى صفحته.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: _accent),
                ),
                const SizedBox(height: 10),
                _NotesCard(
                  surah: surah,
                  ayah: ayah,
                  dark: dark,
                  title: _title,
                  accent: _accent,
                  border: _border,
                  card: _card,
                ),
                const SizedBox(height: 10),
                if (hits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'لا توجد تنزيلة في هذه الآية.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _title),
                    ),
                  )
                else if (index == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  for (final hit in hits) ...[
                    _TanzilahCard(
                      hit: hit,
                      surah: surah,
                      ayah: ayah,
                      index: index,
                      dark: dark,
                      title: _title,
                      accent: _accent,
                      border: _border,
                      card: _card,
                      onOpenPlace: onOpenPlace,
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// «ملاحظاتي»: the reader's note on this ayah, at the top of the sheet. One
/// line while empty (the hint names it), growing with the text up to 6 lines
/// and then scrolling; the label moves above once there is text. Saved as it
/// is typed; the keyboard opens only on a touch.
class _NotesCard extends StatefulWidget {
  const _NotesCard({
    required this.surah,
    required this.ayah,
    required this.dark,
    required this.title,
    required this.accent,
    required this.border,
    required this.card,
  });

  final int surah;
  final int ayah;
  final bool dark;
  final Color title;
  final Color accent;
  final Color border;
  final Color card;

  @override
  State<_NotesCard> createState() => _NotesCardState();
}

class _NotesCardState extends State<_NotesCard> {
  static const Color _gold = Color(0xFFD6B35D);

  late final TextEditingController _controller = TextEditingController(
    text: TanzilatNotesStore.instance.noteOf(widget.surah, widget.ayah),
  );
  final FocusNode _focus = FocusNode();
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  void _changed(String text) {
    setState(() {});
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 400),
      () => TanzilatNotesStore.instance.setNote(widget.surah, widget.ayah, text),
    );
  }

  @override
  void dispose() {
    // Closing the sheet mid-word still keeps the last letters.
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      TanzilatNotesStore.instance.setNote(
        widget.surah,
        widget.ayah,
        _controller.text,
      );
    }
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.isNotEmpty;
    final focused = _focus.hasFocus;
    final hint = widget.accent.withValues(alpha: widget.dark ? 0.55 : 0.6);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.fromLTRB(12, hasText ? 6 : 8, 12, 8),
      decoration: BoxDecoration(
        color: widget.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: focused ? _gold : widget.border, width: 1.5),
        boxShadow: [
          if (focused)
            BoxShadow(color: _gold.withValues(alpha: 0.18), spreadRadius: 3),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasText)
            Text(
              'ملاحظاتي',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: widget.accent,
              ),
            ),
          TextField(
            controller: _controller,
            focusNode: _focus,
            onChanged: _changed,
            onTapOutside: (_) => _focus.unfocus(),
            minLines: 1,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 15, height: 1.6, color: widget.title),
            decoration: InputDecoration.collapsed(
              hintText: 'ملاحظاتي: اكتب هنا ملاحظاتك عن متشابهات هذه الآية…',
              hintStyle: TextStyle(fontSize: 14.5, color: hint),
            ).copyWith(hintMaxLines: 1),
          ),
        ],
      ),
    );
  }
}

/// «نسخ الكل»: copies the whole sheet; says so for a moment (a snack bar
/// would sit behind the sheet). [iconOnly] is the small icon on one
/// tanzilah's card, which copies that tanzilah only.
class _CopyAllButton extends StatefulWidget {
  const _CopyAllButton({
    required this.colour,
    required this.text,
    this.iconOnly = false,
  });

  final Color colour;
  final String Function() text;
  final bool iconOnly;

  @override
  State<_CopyAllButton> createState() => _CopyAllButtonState();
}

class _CopyAllButtonState extends State<_CopyAllButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text()));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.iconOnly) {
      return IconButton(
        onPressed: _copy,
        tooltip: _copied ? 'تم النسخ' : 'نسخ هذه التنزيلة',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
        icon: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
          size: 18,
          color: widget.colour,
        ),
      );
    }
    return TextButton.icon(
      onPressed: _copy,
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_rounded,
        size: 18,
        color: widget.colour,
      ),
      label: Text(
        _copied ? 'تم النسخ' : 'نسخ الكل',
        style: TextStyle(color: widget.colour, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TanzilahCard extends StatefulWidget {
  const _TanzilahCard({
    required this.hit,
    required this.surah,
    required this.ayah,
    required this.index,
    required this.dark,
    required this.title,
    required this.accent,
    required this.border,
    required this.card,
    required this.onOpenPlace,
  });

  final TanzilahHit hit;
  final int surah;
  final int ayah;
  final Map<(int, int), _AyahInfo> index;
  final bool dark;
  final Color title;
  final Color accent;
  final Color border;
  final Color card;
  final void Function(int page, int surah, int ayah) onOpenPlace;

  @override
  State<_TanzilahCard> createState() => _TanzilahCardState();
}

class _TanzilahCardState extends State<_TanzilahCard> {
  static const int _collapsedCount = 8;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hit = widget.hit;
    final colour = TanzilatColors.of(
      hit.count,
      dark: widget.dark,
      byCount: TanzilatSetting.colorByCount.value,
    );
    final places = _placesOf(hit);
    final ownIndex = places.indexWhere(
      (p) => p.surah == widget.surah && p.ayah == widget.ayah,
    );
    var shown = places;
    if (!_expanded && places.length > _collapsedCount + 2) {
      shown = places.take(_collapsedCount).toList();
      if (ownIndex >= _collapsedCount) shown = [...shown, places[ownIndex]];
    }
    final heading = _headingOf(hit, (s, a) => widget.index[(s, a)]?.words);
    return Container(
      decoration: BoxDecoration(
        color: widget.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.border),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hit.group.isGharibah ? 'غريبة' : hit.group.label,
                  style: TextStyle(
                    color: widget.dark ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  heading,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: widget.title,
                  ),
                ),
              ),
              // at the far left of the title (the row is right to left)
              _CopyAllButton(
                colour: widget.accent,
                iconOnly: true,
                text: () => tanzilahCopyText(widget.surah, widget.ayah, hit, {
                  for (final e in widget.index.entries) e.key: e.value.words,
                }),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final p in shown) _placeTile(p, colour),
          if (shown.length < places.length)
            TextButton(
              onPressed: () => setState(() => _expanded = true),
              child: Text(
                'عرض كل المواضع (${places.length})',
                style: TextStyle(
                  color: widget.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          for (final d in hit.danfasi) _danfasi(d),
        ],
      ),
    );
  }

  Widget _placeTile(TanzilahPlace p, Color colour) {
    final info = widget.index[(p.surah, p.ayah)];
    final isHere = p.surah == widget.surah && p.ayah == widget.ayah;
    final words = info?.words ?? const <String>[];
    final marked = p.words.toSet();
    // A few words around the coloured ones, enough to recognise the place.
    final (from, to) = _snippetRange(p, words);
    final spans = <TextSpan>[
      if (from > 0) const TextSpan(text: '… '),
      for (var i = from; i < to; i++)
        TextSpan(
          text: '${quranDisplayText(words[i])}${i + 1 < to ? ' ' : ''}',
          style: marked.contains(i)
              ? TextStyle(color: colour, fontWeight: FontWeight.w800)
              : null,
        ),
      if (to < words.length) const TextSpan(text: ' …'),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: info == null
          ? null
          : () => widget.onOpenPlace(info.page, p.surah, p.ayah),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isHere ? colour.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    '${_surahName(p.surah)} ${p.ayah}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: widget.accent,
                    ),
                  ),
                ),
                if (isHere)
                  Flexible(
                    child: Text(
                      '  (هذه الآية)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: widget.accent),
                    ),
                  ),
                const Spacer(),
                if (info != null)
                  Text(
                    'صفحة ${info.page}',
                    style: TextStyle(fontSize: 12, color: widget.accent),
                  ),
                if (info != null && !isHere)
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: widget.accent,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(children: spans),
              style: TextStyle(fontSize: 17, height: 1.7, color: widget.title),
            ),
          ],
        ),
      ),
    );
  }

  Widget _danfasi(DanfasiVerse d) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: widget.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(right: BorderSide(color: widget.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'قال الدنفاسي («${d.title}»):',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: widget.accent,
            ),
          ),
          const SizedBox(height: 4),
          for (final line in d.lines)
            Text(
              line,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.8, color: widget.title),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../models/quran_page_data.dart';
import '../../services/quran_json_service.dart';
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

/// «في N مواضع» with the Arabic number agreement (always after «في», so the
/// dual is genitive: «في موضعين»).
String tanzilahCountText(int n) {
  if (n <= 1) return 'موضع واحد';
  if (n == 2) return 'موضعين';
  if (n <= 10) return '$n مواضع';
  return '$n موضعًا';
}

/// The places a card lists: a spelling rule its own, a tanzilah every row's.
List<TanzilahPlace> _placesOf(TanzilahHit hit) => hit.row.rule
    ? hit.row.places
    : [for (final r in hit.group.rows) ...r.places];

String _headingOf(TanzilahHit hit) {
  if (hit.row.rule) {
    final word = quranDisplayText(hit.row.word ?? '');
    return hit.row.places.isEmpty
        ? '«$word» لا تُلوَّن'
        : '«$word» تُكتب هكذا حيث وردت';
  }
  if (hit.group.isGharibah) return 'غريبة: لا نظير لها';
  return 'تتكرر في ${tanzilahCountText(hit.group.count)}';
}

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
  Map<(int, int), List<String>> words,
) {
  final out = StringBuffer(
    'تنزيلات ومتشابهات — سورة ${_surahName(surah)} $ayah\n',
  );
  for (final hit in hits) {
    out.write('\n${_headingOf(hit)}');
    final places = _placesOf(hit);
    if (hit.row.rule && places.isNotEmpty) {
      out.write(' (في ${tanzilahCountText(places.length)})');
    }
    out.write('\n');
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
  return out.toString().trimRight();
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
    // Rarest first: a غريبة is the one most worth knowing; the spelling
    // rules (hundreds of places) go last.
    final hits = [...TanzilatService.instance.forAyah(surah, ayah)]
      ..sort((a, b) {
        if (a.row.rule != b.row.rule) return a.row.rule ? 1 : -1;
        return a.count.compareTo(b.count);
      });
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
                    if (index != null && hits.isNotEmpty)
                      _CopyAllButton(
                        colour: _accent,
                        text: () => tanzilatCopyText(surah, ayah, hits, {
                          for (final e in index.entries) e.key: e.value.words,
                        }),
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

/// «نسخ الكل»: copies the whole sheet; says so for a moment (a snack bar
/// would sit behind the sheet).
class _CopyAllButton extends StatefulWidget {
  const _CopyAllButton({required this.colour, required this.text});

  final Color colour;
  final String Function() text;

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
    final heading = _headingOf(hit);
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
                  hit.row.rule
                      ? '${hit.row.places.length}'
                      : (hit.group.isGharibah ? 'غريبة' : hit.group.label),
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
            ],
          ),
          if (hit.row.rule && places.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'في ${tanzilahCountText(places.length)}',
                style: TextStyle(fontSize: 12.5, color: widget.accent),
              ),
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

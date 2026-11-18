import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../services/quran_json_service.dart';
import '../../surah_data.dart';
import '../../theme/app_surfaces.dart';
import '../../utils/quran_display_text.dart';

/// «خلافات القراء» (owner, 2026-11-17): how the ten readers' narrators read
/// the words of one ayah. The cards are the source's own, word for word and in
/// its order (assets/data/khilaf.json, built by tools/build_khilaf_data.py);
/// the only change is that the row covering Qalun comes first. Nothing here
/// rewords, classifies or adds to them.
class KhilafCard {
  const KhilafCard(this.word, this.rows);

  /// The word(s) as the source writes them.
  final String word;

  /// (reader label or null, description), Qalun's row first.
  final List<(String?, String)> rows;
}

class KhilafData {
  KhilafData._(this._labels, this._descs, this._shapes, this._ayat);

  final List<String> _labels;
  final List<String> _descs;
  final List<List<List<int>>> _shapes;
  final Map<String, List<dynamic>> _ayat;

  static Future<KhilafData>? _loading;

  static Future<KhilafData> load() => _loading ??= rootBundle
      .loadString('assets/data/khilaf.json')
      .then((s) => compute(_decode, s))
      .then(KhilafData._fromJson);

  static Map<String, dynamic> _decode(String s) =>
      jsonDecode(s) as Map<String, dynamic>;

  static KhilafData _fromJson(Map<String, dynamic> j) => KhilafData._(
    (j['w'] as List).cast<String>(),
    (j['d'] as List).cast<String>(),
    [
      for (final p in j['p'] as List)
        [for (final r in p as List) (r as List).cast<int>()],
    ],
    (j['a'] as Map).cast<String, List<dynamic>>(),
  );

  List<KhilafCard> forAyah(int surah, int ayah) => [
    for (final c in _ayat['$surah:$ayah'] ?? const [])
      KhilafCard(c[0] as String, [
        for (final r in _shapes[c[1] as int])
          (r[0] < 0 ? null : _labels[r[0]], _descs[r[1]]),
      ]),
  ];
}

String _surahName(int surah) =>
    surahList.firstWhere(
          (s) => s['number'] == surah,
          orElse: () => const {},
        )['name']
        as String? ??
    '';

Future<String?> _ayahText(int surah, int ayah) async {
  for (final p in await QuranJsonService.loadQuranPages()) {
    for (final a in p.ayahs) {
      if (a.surah == surah && a.ayah == ayah) return a.text;
    }
  }
  return null;
}

Future<void> showKhilafSheet(
  BuildContext context, {
  required int surah,
  required int ayah,
}) async {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  final s = AppSurfaces.maybeOf(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDarkMode
        ? const Color(0xFF19130A)
        : s?.sheet ?? const Color(0xFFF8F1DE),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(s == null ? 22 : AppSurfaces.radius),
      ),
      side: BorderSide(
        color: isDarkMode
            ? const Color(0xFFD6B35D).withValues(alpha: 0.55)
            : s?.border ?? const Color(0xFFE2D2A5),
        width: s == null ? 2 : 1,
      ),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, controller) => KhilafSheetContent(
        surah: surah,
        ayah: ayah,
        dark: isDarkMode,
        controller: controller,
      ),
    ),
  );
}

class KhilafSheetContent extends StatelessWidget {
  const KhilafSheetContent({
    super.key,
    required this.surah,
    required this.ayah,
    required this.dark,
    this.controller,
  });

  final int surah;
  final int ayah;
  final bool dark;
  final ScrollController? controller;

  Color get _title => dark ? const Color(0xFFFFF4D6) : const Color(0xFF35250E);
  Color get _accent => dark ? const Color(0xFFD6B35D) : const Color(0xFF8D6E3F);
  Color get _muted => dark ? const Color(0xFFBFAE8C) : const Color(0xFF7B7266);
  Color get _border => dark
      ? const Color(0xFFD6B35D).withValues(alpha: 0.4)
      : const Color(0xFFE2D2A5);
  Color get _card => dark ? const Color(0xFF241B0E) : Colors.white;

  @override
  Widget build(BuildContext context) {
    final s = dark ? null : AppSurfaces.maybeOf(context);
    final border = s?.border ?? _border;
    final hair = s?.hair ?? _border;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<(KhilafData, String?)>(
        future: Future.wait([KhilafData.load(), _ayahText(surah, ayah)])
            .then((r) => (r[0] as KhilafData, r[1] as String?)),
        builder: (context, snap) {
          final data = snap.data;
          final cards = data?.$1.forAyah(surah, ayah) ?? const [];
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
                      color: s?.handle ?? _border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'خلافات القراء',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: s == null ? FontWeight.bold : FontWeight.w600,
                    color: _title,
                  ),
                ),
                Text(
                  'سورة ${_surahName(surah)}، الآية $ayah',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: _accent),
                ),
                if (data?.$2 != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    quranDisplayText(data!.$2!),
                    style: TextStyle(fontSize: 20, height: 1.9, color: _title),
                  ),
                ],
                const SizedBox(height: 6),
                if (data == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'لا خلاف بين القراء في هذه الآية.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _title),
                    ),
                  )
                else
                  for (final c in cards)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      decoration: BoxDecoration(
                        color: s?.card ?? _card,
                        borderRadius: BorderRadius.circular(
                          AppSurfaces.cardRadius,
                        ),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            c.word,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              color: _accent,
                            ),
                          ),
                          for (final (who, how) in c.rows)
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                border: Border(top: BorderSide(color: hair)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (who != null)
                                    Text(
                                      who,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _muted,
                                      ),
                                    ),
                                  Text(
                                    how,
                                    style: TextStyle(
                                      fontSize: 15,
                                      height: 1.6,
                                      color: _title,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

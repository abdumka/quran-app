import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/athkar.dart';
import '../../services/athkar_audio.dart';
import '../../services/athkar_service.dart';
import '../../services/reciter_service.dart';
import '../../theme/app_surfaces.dart';
import '../../utils/copy_helper.dart';

/// The colours of «الأذكار»: the menus' colours in the new look, charcoal in
/// night mode, cream in the previous look.
@immutable
class AthkarColors {
  const AthkarColors({
    required this.page,
    required this.card,
    required this.text,
    required this.muted,
    required this.icon,
    required this.tile,
    required this.hair,
    required this.accent,
    required this.fill,
    required this.quiet,
    required this.button,
    required this.onButton,
  });

  final Color page;
  final Color card;
  final Color text;
  final Color muted;
  final Color icon;
  final Color tile;
  final Color hair;

  /// Verses, the star, links.
  final Color accent;

  /// The part of the counter bar that is already counted.
  final Color fill;

  /// The counter bar before anything is counted.
  final Color quiet;

  /// A completed counter bar and its label.
  final Color button;
  final Color onButton;

  static const AthkarColors _night = AthkarColors(
    page: Color(0xFF111111),
    card: Color(0xFF1C1C1E),
    text: Color(0xFFEDEDED),
    muted: Color(0xFF9A9AA0),
    icon: Color(0xFFD2B97E),
    tile: Color(0xFF2A2A2D),
    hair: Color(0x1FFFFFFF),
    accent: Color(0xFFD2B97E),
    fill: Color(0xFF6E5B2E),
    quiet: Color(0xFF2A2A2D),
    button: Color(0xFFD2B97E),
    onButton: Color(0xFF1C1C1E),
  );

  static AthkarColors _from(AppSurfaces s) => AthkarColors(
    page: s.page,
    card: s.card,
    text: s.text,
    muted: s.muted,
    icon: s.icon,
    tile: s.tile,
    hair: s.hair,
    accent: s.accent,
    fill: s.selected,
    quiet: s.buttonQuiet,
    button: s.button,
    onButton: s.onButton,
  );

  static AthkarColors of(BuildContext context) {
    final s = AppSurfaces.maybeOf(context);
    if (s != null) return _from(s);
    if (Theme.of(context).brightness == Brightness.dark) return _night;
    return _from(AppSurfaces.cream);
  }
}

/// The top bar of every «الأذكار» page: the reader's bars (so the section
/// reads as its own window), back on the right.
PreferredSizeWidget athkarAppBar(
  BuildContext context,
  String title, {
  List<Widget> actions = const [],
}) {
  final chrome = AppChrome.of(context);
  return AppBar(
    backgroundColor: chrome.bar,
    foregroundColor: chrome.barText,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    systemOverlayStyle: chrome.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    iconTheme: IconThemeData(color: chrome.barIcon),
    automaticallyImplyLeading: false,
    leading: IconButton(
      icon: const Icon(Icons.arrow_forward_rounded),
      tooltip: 'رجوع',
      onPressed: () => Navigator.of(context).maybePop(),
    ),
    title: Text(
      title,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: chrome.barText,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    actions: [...actions, const SizedBox(width: 4)],
    shape: chrome.dark
        ? null
        : Border(bottom: BorderSide(color: chrome.barHair)),
  );
}

final RegExp _verse = RegExp('﴿[^﴾]*﴾');

/// The dhikr with its verses in the accent colour.
TextSpan athkarTextSpan(String text, TextStyle style, Color verseColor) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in _verse.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    spans.add(
      TextSpan(
        text: m[0],
        style: TextStyle(color: verseColor),
      ),
    );
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: spans);
}

/// The counter: a bar that fills as the dhikr is said, one tap each time.
/// When the count is reached it turns into «تمّ».
class AthkarCounterBar extends StatelessWidget {
  const AthkarCounterBar({
    super.key,
    required this.count,
    required this.total,
    required this.onTap,
    this.height = 48,
  });

  final int count;
  final int total;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    final done = count >= total;
    final String label = done
        ? 'تمّ'
        : total == 1
        ? 'إتمام'
        : count == 0
        ? 'اضغط للعدّ: ${athkarTimes(total)}'
        : '$count من $total';
    final Color onColor = done ? c.onButton : c.text;
    return Semantics(
      button: true,
      label: done ? 'تمّ' : 'عدّاد، $count من $total',
      child: Material(
        color: done ? c.button : c.quiet,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: done ? null : onTap,
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                if (!done)
                  Positioned.fill(
                    child: AnimatedFractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: (count / total).clamp(0.0, 1.0),
                      heightFactor: 1,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: ColoredBox(color: c.fill),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    // a long label shrinks rather than overflowing a narrow bar
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (done) ...[
                            Icon(Icons.check_rounded, color: onColor, size: 20),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            label,
                            style: TextStyle(
                              color: onColor,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The buttons on top of a dhikr: listen, more, favourite, its number.
class AthkarCardHeader extends StatelessWidget {
  const AthkarCardHeader({
    super.key,
    required this.item,
    required this.index,
    required this.total,
    required this.onPlay,
  });

  final AthkarItem item;
  final int index;
  final int total;

  /// Plays from this dhikr on.
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    final store = AthkarStore.instance;
    final audio = AthkarAudio.instance;
    final favourite = store.isFavourite(item);
    final playingThis = audio.current?.id == item.id;
    return Row(
      children: [
        if (audio.canPlay(item))
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: playingThis && !audio.isPaused ? 'إيقاف مؤقت' : 'استماع',
            icon: Icon(
              playingThis && !audio.isPaused
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: c.icon,
            ),
            onPressed: playingThis ? audio.togglePause : onPlay,
          ),
        Builder(
          builder: (buttonContext) => IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'خيارات',
            icon: Icon(Icons.more_horiz_rounded, color: c.icon),
            onPressed: () =>
                showAthkarItemSheet(buttonContext, item, onPlay: onPlay),
          ),
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: favourite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
          icon: Icon(
            favourite ? Icons.star_rounded : Icons.star_outline_rounded,
            color: favourite ? c.accent : c.icon,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            store.toggleFavourite(item);
          },
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: c.tile,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${index + 1} / $total',
            textDirection: TextDirection.ltr,
            style: TextStyle(color: c.icon, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

/// Who narrated it (and, in the favourites, which section it is from). Long
/// sources are two lines until tapped.
class AthkarSourceLine extends StatefulWidget {
  const AthkarSourceLine({
    super.key,
    required this.item,
    this.sectionName,
    this.expanded = false,
  });

  final AthkarItem item;
  final String? sectionName;

  /// Always in full (the one-dhikr page).
  final bool expanded;

  @override
  State<AthkarSourceLine> createState() => _AthkarSourceLineState();
}

class _AthkarSourceLineState extends State<AthkarSourceLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    final parts = [
      if (widget.sectionName != null) widget.sectionName!,
      if (widget.item.source.isNotEmpty) widget.item.source,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    final open = widget.expanded || _open;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.expanded ? null : () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.topCenter,
          child: Text(
            parts.join(' · '),
            maxLines: open ? null : 2,
            overflow: open ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.6),
          ),
        ),
      ),
    );
  }
}

Future<void> _shareAthkarItem(
  BuildContext anchorContext,
  AthkarItem item,
) async {
  final text = athkarShareText(item);
  final box = anchorContext.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  try {
    final result = await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
    if (result.status != ShareResultStatus.unavailable) return;
  } catch (_) {
    // fall through to the clipboard
  }
  if (!anchorContext.mounted) return;
  await CopyHelper.copy(anchorContext, text);
}

/// The ⋯ menu of a dhikr: favourite, copy, share, listen, start counting
/// again.
Future<void> showAthkarItemSheet(
  BuildContext context,
  AthkarItem item, {
  required VoidCallback onPlay,
}) {
  final c = AthkarColors.of(context);
  final store = AthkarStore.instance;
  final audio = AthkarAudio.instance;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.card,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) {
      Widget row(IconData icon, String label, VoidCallback onTap) => ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.tile,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: c.icon, size: 20),
        ),
        title: Text(label, style: TextStyle(color: c.text, fontSize: 15.5)),
        onTap: onTap,
      );
      final favourite = store.isFavourite(item);
      return Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(
                favourite ? Icons.star_rounded : Icons.star_outline_rounded,
                favourite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
                () {
                  store.toggleFavourite(item);
                  Navigator.of(sheetContext).pop();
                },
              ),
              row(Icons.copy_rounded, 'نسخ', () {
                Navigator.of(sheetContext).pop();
                CopyHelper.copy(context, athkarShareText(item));
              }),
              Builder(
                builder: (rowContext) => row(
                  Icons.share_outlined,
                  'مشاركة',
                  () async {
                    await _shareAthkarItem(rowContext, item);
                    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                ),
              ),
              if (audio.canPlay(item)) ...[
                row(Icons.play_arrow_rounded, 'استماع', () {
                  Navigator.of(sheetContext).pop();
                  onPlay();
                }),
                row(Icons.tune_rounded, 'القارئ وطريقة الاستماع', () {
                  Navigator.of(sheetContext).pop();
                  showAthkarReciterSheet(context);
                }),
              ],
              if (store.countOf(item) > 0)
                row(Icons.restart_alt_rounded, 'تصفير العدّاد', () {
                  store.reset(item);
                  Navigator.of(sheetContext).pop();
                }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// The slim player under the athkar while one is being listened to: pause,
/// what is playing, the voice (tap to change it), close.
class AthkarPlayerBar extends StatelessWidget {
  const AthkarPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = AthkarAudio.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([audio, AthkarStore.instance]),
      builder: (context, _) {
        final item = audio.current;
        if (item == null) return const SizedBox.shrink();
        final chrome = AppChrome.of(context);
        final (at, of) = audio.position;
        final repeat = audio.repeat;
        // one of the two (both on one line mix up their digits in Arabic)
        final status = repeat != null
            ? 'المرة ${repeat.$1} من ${repeat.$2}'
            : AthkarStore.instance.continuous && of > 1
            ? 'الذكر $at من $of'
            : '';
        final voiceName = audio.voiceNameFor(item);
        return Material(
          color: chrome.bar,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: chrome.barIcon,
                      foregroundColor: chrome.bar,
                    ),
                    tooltip: audio.isPaused ? 'متابعة' : 'إيقاف مؤقت',
                    icon: Icon(
                      audio.isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                    onPressed: audio.togglePause,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.text.replaceAll('\n', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: chrome.barText,
                            fontSize: 13.5,
                          ),
                        ),
                        if (status.isNotEmpty)
                          Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: chrome.barSubtext,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (voiceName != null)
                    Tooltip(
                      message: 'تغيير القارئ',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => showAthkarReciterSheet(context),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: chrome.barText.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  voiceName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: chrome.barText,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.expand_more_rounded,
                                size: 16,
                                color: chrome.barSubtext,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (audio.hasNext)
                    IconButton(
                      tooltip: 'التالي',
                      // "next" points left in Arabic, like the page arrows
                      icon: Transform.flip(
                        flipX: true,
                        child: Icon(
                          Icons.skip_next_rounded,
                          color: chrome.barIcon,
                        ),
                      ),
                      onPressed: audio.skip,
                    ),
                  IconButton(
                    tooltip: 'إيقاف',
                    icon: Icon(Icons.close_rounded, color: chrome.barSubtext),
                    onPressed: audio.stop,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// How the athkar are listened to: on to the next one by itself or not, and
/// the voices: one for the athkar, one for the verses (the mushaf's
/// reciters, so one the server adds is offered here too).
Future<void> showAthkarReciterSheet(BuildContext context) {
  final c = AthkarColors.of(context);
  final audio = AthkarAudio.instance;
  final voices = AthkarService.instance.data.reciters;
  final quranReciters = ReciterService.instance.reciters;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.card,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      Widget heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(
          text,
          style: TextStyle(
            color: c.muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      Widget row(String name, bool chosen, VoidCallback onTap) => ListTile(
        dense: true,
        title: Text(name, style: TextStyle(color: c.text, fontSize: 15.5)),
        trailing: chosen ? Icon(Icons.check_rounded, color: c.accent) : null,
        onTap: () {
          Navigator.of(sheetContext).pop();
          onTap();
        },
      );
      final quranId = audio.quranReciter.id;
      return Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListenableBuilder(
                  listenable: AthkarStore.instance,
                  builder: (context, _) {
                    final store = AthkarStore.instance;
                    return SwitchListTile(
                      value: store.continuous,
                      onChanged: (v) => store.continuous = v,
                      title: Text(
                        'تشغيل متواصل',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        store.continuous
                            ? 'بعد انتهاء الذكر يبدأ الذي يليه'
                            : 'يتوقف بعد الذكر الذي تستمع إليه',
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                    );
                  },
                ),
                Divider(height: 8, color: c.muted.withValues(alpha: 0.2)),
                if (voices.isNotEmpty) ...[
                  heading('قارئ الأذكار'),
                  for (final r in voices)
                    row(
                      r.name,
                      r.id == audio.reciter?.id,
                      () => audio.chooseReciter(r),
                    ),
                ],
                heading('قارئ الآيات'),
                for (final r in quranReciters)
                  row(
                    r.name,
                    r.id == quranId,
                    () => audio.chooseQuranReciter(r),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
}

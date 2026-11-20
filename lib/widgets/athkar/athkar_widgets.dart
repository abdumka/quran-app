import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vibration/vibration.dart';

import '../../models/athkar.dart';
import '../../services/athkar_audio.dart';
import '../../services/athkar_service.dart';
import '../../services/reciter_service.dart';
import '../../theme/app_surfaces.dart';
import '../../utils/copy_helper.dart';
import '../menu_scroll_cue.dart';

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

/// A counted tap is felt, as a short real vibration on both phones. The
/// system's light haptic taps were not enough: Android drops them whenever
/// the phone's touch vibration is off, and the owner felt nothing on either
/// phone (2026-11-18). No hasVibrator() check first: the plugin answers
/// false for any emulator, and its native side checks for a vibrator itself.
void athkarBuzz({bool strong = false}) {
  unawaited(() async {
    try {
      await Vibration.vibrate(
        duration: strong ? 90 : 30,
        amplitude: strong ? 255 : 150,
      );
    } catch (_) {
      // no vibration plugin (tests, some tablets): the haptic, at least
      strong ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
    }
  }());
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
    final canPlay = audio.canPlay(item);
    // the chosen voice did not record this one: say whose voice it plays in
    final voice = item.isQuran ? null : audio.voiceFor(item);
    final chosen = audio.reciter;
    final otherVoice = voice != null && chosen != null && voice.id != chosen.id
        ? voice.name
        : null;
    return Row(
      children: [
        if (!canPlay && audio.hasReciters)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'لا يوجد تسجيل صوتي',
            icon: Icon(
              Icons.volume_off_outlined,
              color: c.muted.withValues(alpha: 0.6),
            ),
            onPressed: () =>
                CopyHelper.showToast(context, 'لا يوجد تسجيل صوتي لهذا الذكر'),
          ),
        if (canPlay)
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
        if (otherVoice != null)
          Flexible(
            flex: 3,
            child: Text(
              'بصوت $otherVoice',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.muted, fontSize: 12),
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
  final text = athkarShareText(
    item,
    shareLine: AthkarService.instance.data.shareLine,
  );
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
                CopyHelper.copy(
                  context,
                  athkarShareText(
                    item,
                    shareLine: AthkarService.instance.data.shareLine,
                  ),
                );
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
                row(Icons.settings_outlined, 'إعدادات الأذكار', () {
                  Navigator.of(sheetContext).pop();
                  showAthkarSettingsSheet(context);
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
/// what is playing and in whose voice (tap to change it), «التالي», close.
class AthkarPlayerBar extends StatelessWidget {
  const AthkarPlayerBar({super.key, this.items});

  /// The athkar on the page, for the voices' counts in the settings sheet.
  final List<AthkarItem>? items;

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
        final sub = TextStyle(color: chrome.barSubtext, fontSize: 12);
        // the phone's largest text left the status line and the voice as
        // «ال…» beside «التالي» (emulator, 2026-11-18): the bar grows only so far
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: Material(
            color: chrome.bar,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
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
                          Row(
                            children: [
                              if (status.isNotEmpty) ...[
                                Flexible(
                                  child: Text(
                                    status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sub,
                                  ),
                                ),
                                Text('  ·  ', style: sub),
                              ],
                              if (voiceName != null)
                                Flexible(
                                  child: Tooltip(
                                    message: 'تغيير القارئ',
                                    child: InkWell(
                                      onTap: () =>
                                          showAthkarSettingsSheet(context),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              voiceName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: sub.copyWith(
                                                color: chrome.barText,
                                                decoration:
                                                    TextDecoration.underline,
                                                decorationColor: chrome.barText
                                                    .withValues(alpha: 0.4),
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
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (audio.hasNext)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: chrome.barIcon,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        // chevron_right is drawn pointing left in Arabic
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                        iconAlignment: IconAlignment.end,
                        label: const Text('التالي'),
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
          ),
        );
      },
    );
  }
}

/// «إعدادات الأذكار»: on to the next dhikr by itself or not, list or one a
/// page, and the two voices side by side so both choices are in sight at
/// once (owner, 2026-11-19): the athkar voice on the right, the verses'
/// reciter on the left (the mushaf's reciters, so one the server adds is
/// offered here too). Picking a voice keeps the sheet open, so both can be
/// changed in one go. [switchView] is the open reader's own view switch,
/// which keeps the reader on the dhikr it is at.
Future<void> showAthkarSettingsSheet(
  BuildContext context, {
  VoidCallback? switchView,
}) {
  final c = AthkarColors.of(context);
  final audio = AthkarAudio.instance;
  final store = AthkarStore.instance;
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
        onTap: onTap,
      );

      return Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
            ),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      'إعدادات الأذكار',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SwitchListTile(
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
                  ),
                  heading('طريقة العرض'),
                  for (final (view, label) in const [
                    (AthkarView.list, 'كل الأذكار في قائمة'),
                    (AthkarView.single, 'ذكر واحد في الصفحة'),
                  ])
                    row(label, store.view == view, () {
                      if (store.view == view) return;
                      if (switchView != null) {
                        switchView();
                      } else {
                        store.view = view;
                      }
                    }),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (voices.isNotEmpty) ...[
                          Expanded(
                            child: AthkarVoiceColumn(
                              title: 'قارئ الأذكار',
                              names: [for (final r in voices) r.name],
                              chosen: voices.indexWhere(
                                (r) => r.id == audio.reciter?.id,
                              ),
                              onPick: (i) => audio.chooseReciter(voices[i]),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: AthkarVoiceColumn(
                            title: 'قارئ الآيات',
                            names: [for (final r in quranReciters) r.name],
                            chosen: quranReciters.indexWhere(
                              (r) => r.id == audio.quranReciter.id,
                            ),
                            onPick: (i) =>
                                audio.chooseQuranReciter(quranReciters[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (voices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Text(
                        'ما لم يسجّله قارئ الأذكار يُقرأ بصوت قارئ آخر، '
                        'ويظهر اسمه فوق الذكر.',
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// One of the two voice lists of «إعدادات الأذكار»: a title over a framed
/// list about five rows high that scrolls inside itself, with the reciter
/// menus' gold bar and edge fade (menu_scroll_cue.dart) so a longer list
/// shows it goes on. It opens scrolled to the chosen voice.
class AthkarVoiceColumn extends StatefulWidget {
  const AthkarVoiceColumn({
    super.key,
    required this.title,
    required this.names,
    required this.chosen,
    required this.onPick,
  });

  final String title;
  final List<String> names;

  /// Index in [names] of the voice in use; -1 for none.
  final int chosen;
  final ValueChanged<int> onPick;

  /// One row: room for a name on two lines in half a phone's width.
  static const double rowHeight = 52;

  /// Five and a half rows: the half row says there is more below.
  static const double listHeight = rowHeight * 5.5;

  @override
  State<AthkarVoiceColumn> createState() => _AthkarVoiceColumnState();
}

class _AthkarVoiceColumnState extends State<AthkarVoiceColumn> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.chosen > 0
        ? (widget.chosen - 1) * AthkarVoiceColumn.rowHeight
        : 0,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    final height = math.min(
      AthkarVoiceColumn.listHeight,
      widget.names.length * AthkarVoiceColumn.rowHeight,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(
            widget.title,
            style: TextStyle(
              color: c.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: c.page,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.hair),
          ),
          clipBehavior: Clip.antiAlias,
          child: ScrollbarTheme(
            data: menuScrollbarTheme(context),
            child: Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.zero,
                itemExtent: AthkarVoiceColumn.rowHeight,
                itemCount: widget.names.length,
                itemBuilder: (context, i) {
                  final chosen = i == widget.chosen;
                  return Material(
                    color: chosen
                        ? c.accent.withValues(alpha: 0.14)
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onPick(i),
                      child: MenuRowEdgeFade(
                        child: Padding(
                          // the end side (left) leaves room for the scroll bar
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            12,
                            0,
                            16,
                            0,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.names[i],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.text,
                                    fontSize: 14.5,
                                    height: 1.25,
                                    fontWeight: chosen
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (chosen)
                                Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: c.accent,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

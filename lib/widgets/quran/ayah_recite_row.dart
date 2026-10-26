import 'package:flutter/material.dart';

import '../../models/reciter.dart';
import '../../services/ayah_play_setting.dart';
import '../../services/reciter_service.dart';

/// The «تلاوة» line at the foot of an ayah's options: play from this ayah,
/// the reciter it will use, and whether to go on past it («متابعة») or stop
/// after it («آية فقط»), all on one line.
///
/// The reciter is the app's own selection, so a change here is a change
/// everywhere, as in خيارات التلاوة, and the line always opens on the reciter
/// used last.
class AyahReciteRow extends StatelessWidget {
  const AyahReciteRow({
    super.key,
    required this.onPlay,
    required this.isDarkMode,
  });

  final VoidCallback onPlay;
  final bool isDarkMode;

  static const double _height = 40;
  static const double _menuItemHeight = 48;

  static const String _label = 'تلاوة';
  static const TextStyle _labelStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
  );
  static const List<String> _segments = ['متابعة', 'آية فقط'];
  static const TextStyle _segmentStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  /// What the reciter's button keeps before the play button gives up its
  /// word: enough for a short name.
  static const double _minPickerWidth = 96;

  _ReciteRowColors get _colors =>
      isDarkMode ? _ReciteRowColors.dark : _ReciteRowColors.light;

  @override
  Widget build(BuildContext context) {
    final c = _colors;
    // One line is the point of this row: large system text would push the
    // toggle onto a second one.
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.15);
    final baseStyle = DefaultTextStyle.of(context).style;
    double widthOf(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: baseStyle.merge(style)),
        textDirection: TextDirection.rtl,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The play button drops its word, keeping the icon, when the
            // reciter's name would otherwise be squeezed (small phones,
            // large text). Measured, not guessed: fonts differ by device.
            var toggleWidth = 6.0;
            for (final s in _segments) {
              toggleWidth += widthOf(s, _segmentStyle) + 16;
            }
            const iconButtonWidth = 6 + 26 + 7;
            final labelWidth = 2 + widthOf(_label, _labelStyle) + 5;
            final spare =
                constraints.maxWidth -
                toggleWidth -
                iconButtonWidth -
                16 -
                _minPickerWidth;
            final showLabel = spare >= labelWidth;
            return Row(
              textDirection: TextDirection.rtl,
              children: [
                _playButton(c, showLabel: showLabel),
                const SizedBox(width: 8),
                Expanded(child: _reciterPicker(c)),
                const SizedBox(width: 8),
                _modeToggle(c),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _playButton(_ReciteRowColors c, {required bool showLabel}) {
    return Material(
      color: c.accent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPlay,
        child: Tooltip(
          message: 'تلاوة من هذه الآية',
          child: SizedBox(
            height: _height,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: 6,
                end: showLabel ? 12 : 7,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.rtl,
                children: [
                  Icon(Icons.play_arrow_rounded, color: c.onAccent, size: 26),
                  if (showLabel) ...[
                    const SizedBox(width: 2),
                    Text(
                      _label,
                      style: _labelStyle.copyWith(color: c.onAccent),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reciterPicker(_ReciteRowColors c) {
    final service = ReciterService.instance;
    return ValueListenableBuilder<Reciter>(
      valueListenable: service.selected,
      builder: (context, selected, _) {
        final reciters = service.reciters;
        return PopupMenuButton<String>(
          tooltip: 'اختيار القارئ',
          // Opens scrolled to the reciter in use, however long the list.
          initialValue: selected.id,
          color: c.menu,
          constraints: BoxConstraints(
            minWidth: 220,
            maxWidth: 260,
            maxHeight: ReciterService.pickerMenuMaxHeight(_menuItemHeight),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: c.border),
          ),
          onSelected: (id) {
            if (id == selected.id) return;
            for (final r in reciters) {
              if (r.id == id) {
                service.select(r);
                return;
              }
            }
          },
          itemBuilder: (context) => [
            for (final r in reciters)
              PopupMenuItem<String>(
                value: r.id,
                height: _menuItemHeight,
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(
                      r.id == selected.id
                          ? Icons.check_circle_rounded
                          : Icons.person_outline_rounded,
                      size: 20,
                      color: r.id == selected.id ? c.accent : c.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.shortName,
                        textDirection: TextDirection.rtl,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Container(
            height: _height,
            padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: Text(
                    selected.shortName,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.expand_more_rounded, color: c.accent, size: 22),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _modeToggle(_ReciteRowColors c) {
    return ValueListenableBuilder<bool>(
      valueListenable: AyahPlaySetting.onlyThisAyah,
      builder: (context, onlyThis, _) {
        Widget segment(
          String label, {
          required bool selected,
          required bool value,
        }) {
          return Semantics(
            selected: selected,
            child: Material(
              color: selected ? c.accent : Colors.transparent,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => AyahPlaySetting.setOnlyThisAyah(value),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: _segmentStyle.copyWith(
                      color: selected ? c.onAccent : c.toggleText,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: c.toggleTrack,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.rtl,
            children: [
              segment(_segments[0], selected: !onlyThis, value: false),
              const SizedBox(width: 2),
              segment(_segments[1], selected: onlyThis, value: true),
            ],
          ),
        );
      },
    );
  }
}

class _ReciteRowColors {
  const _ReciteRowColors({
    required this.accent,
    required this.onAccent,
    required this.text,
    required this.muted,
    required this.border,
    required this.chip,
    required this.menu,
    required this.toggleTrack,
    required this.toggleText,
  });

  final Color accent;
  final Color onAccent;
  final Color text;
  final Color muted;
  final Color border;
  final Color chip;
  final Color menu;
  final Color toggleTrack;
  final Color toggleText;

  static const light = _ReciteRowColors(
    accent: Color(0xFF8D6E3F),
    onAccent: Colors.white,
    text: Color(0xFF35250E),
    muted: Color(0xFFA8977A),
    border: Color(0xFFD9C79A),
    chip: Color(0xFFFFFBF1),
    menu: Color(0xFFF8F1DE),
    toggleTrack: Color(0xFFEADDBB),
    toggleText: Color(0xFF5E4A2E),
  );

  static const dark = _ReciteRowColors(
    accent: Color(0xFFD6B35D),
    onAccent: Color(0xFF19130A),
    text: Color(0xFFFFF4D6),
    muted: Color(0xFF9C8A62),
    border: Color(0xFF6B5527),
    chip: Color(0xFF241B0D),
    menu: Color(0xFF1E1A12),
    toggleTrack: Color(0xFF2E2414),
    toggleText: Color(0xFFE8D7A8),
  );
}

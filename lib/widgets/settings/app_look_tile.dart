import 'package:flutter/material.dart';

import '../../services/app_look_service.dart';
import '../../theme/app_surfaces.dart';
import 'settings_components.dart';

/// «شكل التطبيق»: the new look or the previous one, switched at once. The
/// first row of «إعدادات العرض» in both looks, so a reader who tried the
/// previous look always finds the way back in the same place.
class AppLookTile extends StatelessWidget {
  const AppLookTile({super.key});

  static const Key currentKey = ValueKey('appLookCurrent');
  static const Key previousKey = ValueKey('appLookPrevious');

  @override
  Widget build(BuildContext context) {
    final previous = AppLookScope.isPrevious(context);
    return _ChoiceRow<AppLook>(
      icon: Icons.palette_outlined,
      title: 'شكل التطبيق',
      subtitle: 'الجديد، أو كما كان من قبل',
      value: previous ? AppLook.previous : AppLook.current,
      options: const [
        _Option(AppLook.current, 'الجديد', currentKey),
        _Option(AppLook.previous, 'السابق', previousKey),
      ],
      onChanged: AppLookService.instance.set,
      inline: true,
    );
  }
}

/// The new look's own choices, under «شكل التطبيق» (owner, 2026-11-12:
/// "add multiple options to the settings so the users choose"). Hidden in
/// the previous look, which stays exactly as it was.
class AppLookChoicesTile extends StatelessWidget {
  const AppLookChoicesTile({super.key});

  static const Key paletteKey = ValueKey('appLookPalette');
  static const Key darkChromeKey = ValueKey('appLookDarkChrome');
  static const Key barOpacityKey = ValueKey('appLookBarOpacity');
  static const Key tasmeeBarKey = ValueKey('appLookTasmeeBar');

  @override
  Widget build(BuildContext context) {
    if (AppLookScope.isPrevious(context)) return const SizedBox.shrink();
    final look = AppLookService.instance;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PaletteRow(key: paletteKey),
        Padding(
          key: darkChromeKey,
          padding: SettingsSwitchRow.padding,
          child: SettingsSwitchRow(
            title: 'إبقاء الأشرطة والقائمة داكنة',
            icon: Icons.dark_mode_outlined,
            value: look.chromeIsDark,
            onChanged: look.setDarkChrome,
          ),
        ),
        _ChoiceRow<BarOpacity>(
          key: barOpacityKey,
          icon: Icons.opacity_rounded,
          title: 'شفافية الأشرطة',
          subtitle: 'الشريط العلوي والسفلي',
          value: look.barOpacity.value,
          options: const [
            _Option(BarOpacity.p65, '65%'),
            _Option(BarOpacity.p80, '80%'),
            _Option(BarOpacity.p94, '94%'),
            _Option(BarOpacity.solid, 'كاملة'),
          ],
          onChanged: look.setBarOpacity,
        ),
        _ChoiceRow<TasmeeBarStyle>(
          key: tasmeeBarKey,
          icon: Icons.mic_none_rounded,
          title: 'شريط التسميع',
          value: look.tasmeeBar.value,
          options: const [
            _Option(TasmeeBarStyle.recoloured, 'كما هو'),
            _Option(TasmeeBarStyle.hairline, 'بإطار رفيع'),
            _Option(TasmeeBarStyle.slim, 'أنحف'),
          ],
          onChanged: look.setTasmeeBar,
        ),
      ],
    );
  }
}

/// «لون التطبيق»: seven round swatches, each the bar colour on one half and
/// the menu colour on the other (owner, 2026-11-13: all seven ship).
class _PaletteRow extends StatelessWidget {
  const _PaletteRow({super.key});

  static const Map<MenuPalette, String> names = {
    MenuPalette.paper: 'ورقي',
    MenuPalette.cream: 'كريمي وذهبي',
    MenuPalette.olive: 'زيتوني',
    MenuPalette.navy: 'كحلي',
    MenuPalette.maroon: 'عنّابي',
    MenuPalette.brown: 'بنّي',
    MenuPalette.graphite: 'رمادي هادئ',
  };

  static Key swatchKey(MenuPalette p) => ValueKey('appLookPalette_${p.name}');

  @override
  Widget build(BuildContext context) {
    final s = AppSurfaces.maybeOf(context);
    final look = AppLookService.instance;
    return Padding(
      padding: SettingsSwitchRow.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              SizedBox(
                width: 22,
                child: Icon(
                  Icons.format_paint_outlined,
                  color: s?.icon ?? const Color(0xFF8B7355),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'لون التطبيق',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: s?.text ?? const Color(0xFF2C2C2C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Wrap(
              spacing: 4,
              runSpacing: 10,
              children: [
                for (final p in MenuPalette.values)
                  _Swatch(
                    key: swatchKey(p),
                    palette: p,
                    label: names[p]!,
                    selected: look.palette.value == p,
                    ring: s?.accent ?? const Color(0xFF8A6420),
                    labelColor: s?.text ?? const Color(0xFF2C2C2C),
                    mutedColor: s?.muted ?? const Color(0xFF7B7266),
                    onTap: () => look.setPalette(p),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.palette,
    required this.label,
    required this.selected,
    required this.ring,
    required this.labelColor,
    required this.mutedColor,
    required this.onTap,
  });

  final MenuPalette palette;
  final String label;
  final bool selected;
  final Color ring;
  final Color labelColor;
  final Color mutedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = AppChrome.swatchInk(palette);
    final sheet = AppSurfaces.of(palette).sheet;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? ring : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x1F000000)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [ink, ink, sheet, sheet],
                        stops: const [0, 0.5, 0.5, 1],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? labelColor : mutedColor,
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

class _Option<T> {
  const _Option(this.value, this.label, [this.key]);
  final T value;
  final String label;
  final Key? key;
}

/// A settings row with a few choices as segments: beside the title when
/// [inline], otherwise on their own line under it (room for 5).
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.inline = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<_Option<T>> options;
  final ValueChanged<T> onChanged;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final s = AppSurfaces.maybeOf(context);
    final heading = Row(
      textDirection: TextDirection.rtl,
      children: [
        SizedBox(
          width: 22,
          child: Icon(
            icon,
            color: s?.icon ?? const Color(0xFF8B7355),
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: s?.text ?? const Color(0xFF2C2C2C),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 12,
                    color: s?.muted ?? const Color(0xFF7B7266),
                  ),
                ),
            ],
          ),
        ),
        if (inline) ...[const SizedBox(width: 8), _segments(s)],
      ],
    );
    return Padding(
      padding: SettingsSwitchRow.padding,
      child: inline
          ? heading
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                heading,
                const SizedBox(height: 8),
                Padding(
                  // under the title, not under the icon
                  padding: const EdgeInsetsDirectional.only(start: 0),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _segments(s),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _segments(AppSurfaces? s) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: s?.page ?? const Color(0xFFF4EFE4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: s?.border ?? const Color(0x245C4522)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                _Segment(
                  key: o.key,
                  label: o.label,
                  selected: o.value == value,
                  onTap: () => onChanged(o.value),
                  surfaces: s,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.surfaces,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppSurfaces? surfaces;

  @override
  Widget build(BuildContext context) {
    final s = surfaces;
    // the old look's gold-brown, which also reads with white text
    const fallback = Color(0xFF8A6420);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 36, minWidth: 52),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? (s?.button ?? fallback) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected
                  ? (s?.onButton ?? Colors.white)
                  : (s?.icon ?? const Color(0xFF6B5332)),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Every switch in the app. On: a solid green track. Off: a pale grey track
/// with a darker outline. Readers could not tell the old beige-on-beige states
/// apart (owner, 2026-10-25); the colours fixed that. The same in the light
/// and dark themes.
///
/// The ✓ / ✕ in the thumb (also 2026-10-25) stay only in the previous look
/// («شكل التطبيق: السابق»): the 2026-11-12 polish dropped them, since a cross
/// in every off switch made a settings page read like a list of errors.
SwitchThemeData appSwitchThemeFor({required bool previousLook}) =>
    previousLook ? _withIcons : appSwitchTheme;

final SwitchThemeData appSwitchTheme = SwitchThemeData(
  thumbColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? const Color(0xFFF2EFEA)
        : Colors.white,
  ),
  trackColor: WidgetStateProperty.resolveWith(
    (states) =>
        _faded(states, states.contains(WidgetState.selected) ? _on : _offTrack),
  ),
  trackOutlineColor: WidgetStateProperty.resolveWith(
    (states) => _faded(
      states,
      states.contains(WidgetState.selected) ? _on : _offOutline,
    ),
  ),
  trackOutlineWidth: const WidgetStatePropertyAll(1.5),
);

final SwitchThemeData _withIcons = appSwitchTheme.copyWith(
  thumbIcon: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? Icon(Icons.check_rounded, size: 16, color: _faded(states, _on))
        : Icon(Icons.close_rounded, size: 16, color: _faded(states, _offIcon)),
  ),
);

const Color _on = Color(0xFF3F7D3A);
const Color _offTrack = Color(0xFFDCD6CC);
const Color _offOutline = Color(0xFFA0968A);
const Color _offIcon = Color(0xFF7D7468);

Color _faded(Set<WidgetState> states, Color color) =>
    states.contains(WidgetState.disabled)
    ? color.withValues(alpha: 0.45)
    : color;

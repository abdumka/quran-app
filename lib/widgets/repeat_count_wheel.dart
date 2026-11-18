import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A repeat count set in place (owner, 2026-11-11), standing among the
/// تكرار مقطع chips in the place of the largest one, with a small arrow above
/// and below it, like one cylinder of a suitcase lock.
///
/// Swiping up makes the number bigger and swiping down smaller (a flick runs
/// on a few numbers), the arrows add or take one, and a tap on the wheel when
/// it is already the chosen count turns it into a box to type the number in.
/// Nothing opens a window. Two-digit numbers are set smaller so the chip
/// stays as wide as its neighbours.
class RepeatCountWheel extends StatefulWidget {
  const RepeatCountWheel({
    super.key,
    required this.value,
    required this.selected,
    required this.onChanged,
    required this.accentColor,
    required this.borderColor,
    required this.textColor,
    this.min = 2,
    this.max = 99,
    this.chipHeight = 38,
    this.semanticsLabel = 'عدد مرات التكرار',
  });

  final int value;

  /// This wheel, not one of the chips beside it, is the chosen count.
  final bool selected;

  /// Called with the wheel's number whenever it changes or is chosen.
  final ValueChanged<int> onChanged;

  final Color accentColor;
  final Color borderColor;
  final Color textColor;
  final int min;
  final int max;
  final double chipHeight;
  final String semanticsLabel;

  /// The number itself (the part that is swiped and tapped), for tests.
  static const Key chipKey = ValueKey('repeatCountWheelChip');

  @override
  State<RepeatCountWheel> createState() => _RepeatCountWheelState();
}

class _RepeatCountWheelState extends State<RepeatCountWheel> {
  /// Finger travel per number.
  static const double _notch = 14;

  late int _value = widget.value;
  int _direction = 1;
  // Where the finger came down, and how many numbers that swipe has moved:
  // counted from the touch itself, so the few pixels the gesture needs
  // before it is recognised as a swipe count too.
  double? _startY;
  int _taken = 0;
  Timer? _flick;
  bool _editing = false;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void didUpdateWidget(RepeatCountWheel old) {
    super.didUpdateWidget(old);
    if (widget.value != _value && _flick == null) _value = widget.value;
  }

  @override
  void dispose() {
    _flick?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _step(int by) {
    if (_editing) return;
    final next = (_value + by).clamp(widget.min, widget.max);
    if (next != _value) {
      HapticFeedback.selectionClick();
      setState(() {
        _direction = by >= 0 ? 1 : -1;
        _value = next;
      });
    }
    widget.onChanged(_value);
  }

  void _onDragStart(DragStartDetails d) {
    _flick?.cancel();
    _flick = null;
    _startY = d.globalPosition.dy;
    _taken = 0;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final start = _startY;
    if (start == null) return;
    // Finger up = positive = bigger.
    final want = ((start - d.globalPosition.dy) / _notch).truncate();
    while (_taken < want) {
      _taken++;
      _step(1);
    }
    while (_taken > want) {
      _taken--;
      _step(-1);
    }
  }

  void _onDragEnd(DragEndDetails d) {
    _startY = null;
    final v = -(d.primaryVelocity ?? 0); // up = positive
    final extra = (v.abs() / 450).floor().clamp(0, 15);
    if (extra < 2) return;
    final dir = v > 0 ? 1 : -1;
    var left = extra;
    _flick?.cancel();
    _flick = Timer.periodic(const Duration(milliseconds: 45), (t) {
      if (!mounted || left-- <= 0) {
        t.cancel();
        _flick = null;
        return;
      }
      _step(dir);
    });
  }

  void _onTap() {
    if (!widget.selected) {
      widget.onChanged(_value);
      return;
    }
    setState(() {
      _editing = true;
      _controller.text = '$_value';
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
    _focus.requestFocus();
  }

  void _commit() {
    final typed = int.tryParse(_controller.text);
    setState(() {
      _editing = false;
      if (typed != null) _value = typed.clamp(widget.min, widget.max);
    });
    widget.onChanged(_value);
  }

  Widget _arrow(IconData icon, String label, int by) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _step(by),
      child: SizedBox(
        height: 16,
        width: double.infinity,
        child: Icon(
          icon,
          size: 18,
          color: widget.selected
              ? widget.accentColor
              : widget.textColor.withValues(alpha: 0.7),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final style = TextStyle(
      color: selected ? widget.accentColor : widget.textColor,
      // Two digits are set smaller so the chip keeps its width.
      fontSize: _value >= 10 ? 12 : 14,
      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final number = AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      // Like a drum: going up, the new number rolls in from below and the
      // old one leaves at the top; going down, the other way round.
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(_value);
        return ClipRect(
          child: SlideTransition(
            position: Tween(
              begin: Offset(0, (incoming ? 0.6 : -0.6) * _direction),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: Text('$_value×', key: ValueKey(_value), style: style),
    );

    return Semantics(
      label: widget.semanticsLabel,
      value: '$_value',
      increasedValue: '${(_value + 1).clamp(widget.min, widget.max)}',
      decreasedValue: '${(_value - 1).clamp(widget.min, widget.max)}',
      onIncrease: () => _step(1),
      onDecrease: () => _step(-1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(Icons.keyboard_arrow_up_rounded, 'زيادة العدد', 1),
          GestureDetector(
            key: RepeatCountWheel.chipKey,
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: _editing ? null : _onDragStart,
            onVerticalDragUpdate: _editing ? null : _onDragUpdate,
            onVerticalDragEnd: _editing ? null : _onDragEnd,
            child: Container(
              height: widget.chipHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? widget.accentColor.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? widget.accentColor : widget.borderColor,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: _editing
                  ? TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [_WesternDigits()],
                      style: style.copyWith(fontSize: 15),
                      cursorColor: widget.accentColor,
                      decoration: const InputDecoration.collapsed(
                        hintText: '',
                      ),
                      onSubmitted: (_) => _focus.unfocus(),
                      onTapOutside: (_) => _focus.unfocus(),
                    )
                  : number,
            ),
          ),
          _arrow(Icons.keyboard_arrow_down_rounded, 'إنقاص العدد', -1),
        ],
      ),
    );
  }
}

/// Keeps at most two digits, turning Arabic-Indic ones (an Arabic keyboard
/// types those) into 0-9.
class _WesternDigits extends TextInputFormatter {
  const _WesternDigits();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final out = StringBuffer();
    for (final c in newValue.text.runes) {
      if (c >= 0x30 && c <= 0x39) {
        out.writeCharCode(c);
      } else if (c >= 0x0660 && c <= 0x0669) {
        out.writeCharCode(0x30 + c - 0x0660);
      } else if (c >= 0x06F0 && c <= 0x06F9) {
        out.writeCharCode(0x30 + c - 0x06F0);
      }
      if (out.length == 2) break;
    }
    final text = out.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

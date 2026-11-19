import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The "there is more below" cue for capped pick lists (the reciter menus).
///
/// Those menus show six and a half rows, and Material's own scrollbar there
/// is a hairline that fades in grey: people did not notice the list went on
/// (owner's report, 2026-11-18). The cue is the one the owner picked from the
/// mockups («شريط واضح»): a wide gold bar on a visible track that never fades
/// away, plus a soft fade over the row the list's bottom edge cuts in half,
/// for as long as there is more to scroll to.
///
/// Three pieces, because the app's reciter pickers come in two kinds:
/// * [MenuScrollCue] restyles the scrollbar Material already draws inside a
///   `DropdownButton` menu. The menu opens in its own route, but it carries
///   over the themes around the button, so wrapping the button is enough.
/// * [MenuRowEdgeFade] goes around each row's content. Neither menu kind lets
///   anything be drawn over the list itself, so each row fades its own part
///   that crosses the edge.
/// * [ScrollingMenuEntry] is for `PopupMenuButton`, whose menu has no
///   scrollbar at all on Android: the whole list goes into one entry that
///   scrolls by itself, with the same bar and fade.

/// The bar's look. Gold on a visible track in both themes.
ScrollbarThemeData menuScrollbarTheme(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return ScrollbarThemeData(
    thumbVisibility: const WidgetStatePropertyAll(true),
    trackVisibility: const WidgetStatePropertyAll(true),
    thickness: const WidgetStatePropertyAll(7),
    radius: const Radius.circular(4),
    thumbColor: const WidgetStatePropertyAll(Color(0xFFD2B97E)),
    trackColor: WidgetStatePropertyAll(
      dark ? const Color(0x2EFFFFFF) : const Color(0x298A6420),
    ),
    trackBorderColor: const WidgetStatePropertyAll(Color(0x00000000)),
    crossAxisMargin: 4,
    mainAxisMargin: 8,
    minThumbLength: 28,
    // A bar this wide is worth grabbing on a phone.
    interactive: true,
  );
}

/// Restyles the scrollbar of the `DropdownButton` menu below it.
class MenuScrollCue extends StatelessWidget {
  const MenuScrollCue({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ScrollbarTheme(data: menuScrollbarTheme(context), child: child);
}

/// Fades the part of a menu row that the bottom of its scrolling list cuts
/// off, while the list can still scroll further down. The half row that
/// peeks out then reads as "more below" rather than as a clipped row. Off a
/// scrolling list (the same row shown in the closed button) it does nothing.
class MenuRowEdgeFade extends StatefulWidget {
  const MenuRowEdgeFade({super.key, required this.child});

  final Widget child;

  /// How far above the edge the fade begins.
  static const double fadeLength = 28;

  @override
  State<MenuRowEdgeFade> createState() => MenuRowEdgeFadeState();
}

class MenuRowEdgeFadeState extends State<MenuRowEdgeFade> {
  ScrollableState? _scrollable;
  ScrollPosition? _position;
  bool _scheduled = false;

  /// Where the fade starts and where it ends (the list's edge), in this
  /// row's own coordinates. Null while the edge does not cross the row.
  (double, double)? _fade;

  @visibleForTesting
  (double, double)? get fade => _fade;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    final position = scrollable?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_schedule);
      position?.addListener(_schedule);
    }
    _scrollable = scrollable;
    _position = position;
    _schedule();
  }

  @override
  void dispose() {
    _position?.removeListener(_schedule);
    super.dispose();
  }

  /// Measured after the frame is laid out: a scroll moves the rows only at
  /// the next layout, so reading positions straight away gives the old ones.
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _measure();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _measure() {
    if (!mounted) return;
    final position = _position;
    final row = context.findRenderObject();
    final view = _scrollable?.context.findRenderObject();
    (double, double)? fade;
    if (position != null &&
        position.hasContentDimensions &&
        position.hasPixels &&
        position.axis == Axis.vertical &&
        position.pixels < position.maxScrollExtent - 0.5 &&
        row is RenderBox &&
        view is RenderBox &&
        row.attached &&
        view.attached &&
        row.hasSize &&
        view.hasSize) {
      final top = row.localToGlobal(Offset.zero, ancestor: view).dy;
      final edge = view.size.height;
      if (top < edge &&
          top + row.size.height > edge - MenuRowEdgeFade.fadeLength) {
        final end = ((edge - top) * 2).roundToDouble() / 2;
        fade = (end - MenuRowEdgeFade.fadeLength, end);
      }
    }
    if (fade != _fade) setState(() => _fade = fade);
  }

  @override
  Widget build(BuildContext context) {
    final fade = _fade;
    // Always a ShaderMask, so the row's subtree keeps its place in the tree
    // as the fade comes and goes.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => fade == null
          ? const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
            ).createShader(bounds)
          : ui.Gradient.linear(Offset(0, fade.$1), Offset(0, fade.$2), const [
              Color(0xFFFFFFFF),
              Color(0x1AFFFFFF),
            ]),
      child: widget.child,
    );
  }
}

/// A whole pick list as ONE `PopupMenuButton` entry that scrolls by itself,
/// with the [menuScrollbarTheme] bar and the [MenuRowEdgeFade] cue.
///
/// Give the button `constraints.maxHeight` of
/// `visibleRows * itemHeight + 16` (the menu's own padding), as
/// `ReciterService.pickerMenuMaxHeight` does, so the menu's own scroll view
/// never has anything to scroll. The list opens with [selected] in the
/// middle, and that row is marked selected for screen readers and for the
/// TV remote, which starts there.
///
/// [width] is fixed because a popup menu sizes itself from its entries'
/// intrinsic widths, which a scrolling list cannot report (it would have to
/// build every row). The button's own `constraints` still clamp it.
class ScrollingMenuEntry<T> extends PopupMenuEntry<T> {
  const ScrollingMenuEntry({
    super.key,
    required this.values,
    required this.selected,
    required this.itemHeight,
    required this.rowBuilder,
    this.width = 240,
    this.visibleRows = 6.5,
  });

  final List<T> values;
  final double width;
  final T? selected;
  final double itemHeight;
  final double visibleRows;
  final Widget Function(BuildContext context, T value) rowBuilder;

  @override
  double get height =>
      math.min(values.length.toDouble(), visibleRows) * itemHeight;

  /// The list is one entry, so the menu is placed at the button rather than
  /// lined up on a row; the list itself scrolls to the current value.
  @override
  bool represents(T? value) => false;

  @override
  State<ScrollingMenuEntry<T>> createState() => _ScrollingMenuEntryState<T>();
}

class _ScrollingMenuEntryState<T> extends State<ScrollingMenuEntry<T>> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final selected = widget.selected;
    final index = selected == null ? -1 : widget.values.indexOf(selected);
    final visible = widget.height;
    final total = widget.values.length * widget.itemHeight;
    final offset = index < 0
        ? 0.0
        : (index * widget.itemHeight - (visible - widget.itemHeight) / 2)
              .clamp(0.0, math.max(0.0, total - visible))
              .toDouble();
    _controller = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // What a PopupMenuItem would have given the row's text.
    final textStyle =
        PopupMenuTheme.of(context).labelTextStyle?.resolve(<WidgetState>{}) ??
        (theme.useMaterial3
            ? theme.textTheme.labelLarge
            : theme.textTheme.titleMedium);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ScrollbarTheme(
        data: menuScrollbarTheme(context),
        child: ScrollConfiguration(
          // Ours is the only bar: no second one from the platform's
          // behaviour on desktop.
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Scrollbar(
            controller: _controller,
            child: ListView.builder(
              controller: _controller,
              padding: EdgeInsets.zero,
              itemExtent: widget.itemHeight,
              itemCount: widget.values.length,
              itemBuilder: (context, i) {
                final value = widget.values[i];
                return Semantics(
                  selected: value == widget.selected,
                  button: true,
                  child: InkWell(
                    onTap: () => Navigator.pop<T>(context, value),
                    child: Padding(
                      // A Material scrollbar sits on the END side; leave the
                      // rows room beside it.
                      padding: const EdgeInsetsDirectional.only(
                        start: 12,
                        end: 22,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DefaultTextStyle.merge(
                          style: textStyle,
                          child: MenuRowEdgeFade(
                            child: widget.rowBuilder(context, value),
                          ),
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
    );
  }
}

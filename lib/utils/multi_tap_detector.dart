/// Counts rapid repeated taps on one widget, for a control that does its
/// ordinary job on a single tap but opens something else when tapped several
/// times in a row — the ℹ️ on «إعدادات متقدمة» opening the developer tools.
///
/// A gap longer than [maxGap] starts the count over, so taps spread out over a
/// session never add up to a trigger.
class MultiTapDetector {
  MultiTapDetector({
    required this.taps,
    this.maxGap = const Duration(seconds: 1),
  }) : assert(taps > 1);

  /// Taps needed to trigger, counting the first one.
  final int taps;

  /// Longest pause allowed between two taps of the same run.
  final Duration maxGap;

  int _count = 0;
  DateTime? _last;

  /// Taps registered in the current run. 1 right after the tap that started it,
  /// so a caller can react to the first tap only and leave the screen still
  /// while the rest of the run is tapped out.
  int get count => _count;

  /// Registers a tap and returns whether this one completed a run. The count
  /// resets on a trigger, so holding the finger down afterwards cannot fire it
  /// again immediately.
  ///
  /// [now] exists so tests need no real waiting.
  bool register([DateTime? now]) {
    final at = now ?? DateTime.now();
    final last = _last;
    final continuing = last != null && at.difference(last) <= maxGap;
    _count = continuing ? _count + 1 : 1;
    _last = at;
    if (_count < taps) return false;
    reset();
    return true;
  }

  void reset() {
    _count = 0;
    _last = null;
  }
}

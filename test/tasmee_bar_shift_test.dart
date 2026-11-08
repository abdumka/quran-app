import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/memorization_test_overlay.dart';

// A 1500 px page of 15 lines of 100 px; the bar is 80 px high and sits at
// the bottom (top 1411).
const double h = 1500;
const double barH = 80;
const double home = h - h * 0.006 - barH;
Rect line(int n) => Rect.fromLTWH(0, n * 100.0, 900, 100);

double? step(int n, double shift) => tasmeeBarShift(
      line: line(n),
      homeTop: home,
      barHeight: barH,
      pageHeight: h,
      shift: shift,
    );

void main() {
  test('stays home while the reading line is well above it', () {
    for (var n = 0; n <= 12; n++) {
      expect(step(n, 0), isNull, reason: 'line $n');
    }
  });

  test('steps once to 2 lines above the line when the reading reaches it', () {
    final s = step(13, 0); // line 13 ends at 1400, within a line of 1411
    expect(s, isNotNull);
    final top = home + s! * h;
    expect(top + barH, closeTo(line(13).top - 200, 0.01));
    // Reading on down the page: no more moves.
    expect(step(13, s), isNull);
    expect(step(14, s), isNull);
  });

  test('goes home when the reading jumps back up the page', () {
    final s = step(13, 0)!;
    expect(step(0, s), 0);
    // A small step back up (still under the moved bar) does not.
    expect(step(12, s), isNull);
  });

  test('a bar dragged to the top steps below the line at the page top', () {
    final s = tasmeeBarShift(
      line: line(0),
      homeTop: 10,
      barHeight: barH,
      pageHeight: h,
      shift: 0,
    );
    expect(10 + s! * h, closeTo(line(0).bottom + 200, 0.01));
  });
}

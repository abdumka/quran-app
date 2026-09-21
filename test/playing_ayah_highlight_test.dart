import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/playing_ayah_highlight.dart';

void main() {
  test('boxes map page ratios onto the page box, trimmed top and bottom', () {
    const painter = PlayingAyahHighlightPainter(
      [Rect.fromLTWH(0.25, 0.5, 0.5, 0.1)],
      null,
      false,
    );
    final box = painter.boxes(const Size(720, 1640)).single;
    expect(box.left, closeTo(180, 0.01));
    expect(box.right, closeTo(540, 0.01));
    // 164 px tall line: 8% trimmed above, 4% below.
    expect(box.top, closeTo(820 + 164 * 0.08, 0.01));
    expect(box.bottom, closeTo(984 - 164 * 0.04, 0.01));
  });

  test('in the margin view the page sits inside the shown image', () {
    const painter = PlayingAyahHighlightPainter(
      [Rect.fromLTWH(0, 0, 1, 1)],
      Rect.fromLTWH(0.1, 0.2, 0.5, 0.5),
      true,
    );
    final box = painter.boxes(const Size(1000, 1000)).single;
    expect(box.left, closeTo(100, 0.01));
    expect(box.right, closeTo(600, 0.01));
    expect(box.top, closeTo(200 + 500 * 0.08, 0.01));
    expect(box.bottom, closeTo(700 - 500 * 0.04, 0.01));
  });
}

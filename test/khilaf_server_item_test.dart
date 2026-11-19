import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/content_update_service.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/khilaf_sheet.dart';

/// «خلافات القراء» can be corrected from the server (the `khilaf` item)
/// like the athkar and the tanzilat, without a store release.
void main() {
  final text = File('assets/data/khilaf.json').readAsStringSync();

  test('the bundled version matches bundledVersions', () {
    final j = json.decode(text) as Map<String, dynamic>;
    expect(j['ver'], ContentUpdateService.bundledVersions['khilaf']);
    expect(ContentUpdateService.items, contains('khilaf'));
  });

  test('the bundled file is valid; a broken download is refused', () {
    final data = KhilafData.parse(text);
    expect(data.forAyah(1, 4), isNotEmpty); // مالك / ملك
    expect(
      () => ContentUpdateService.validate('khilaf', text),
      returnsNormally,
    );
    expect(
      () => ContentUpdateService.validate('khilaf', '{"v":1,"a":{}}'),
      throwsFormatException,
    );
    expect(
      () => ContentUpdateService.validate('khilaf', '[1,2]'),
      throwsFormatException,
    );
  });
}

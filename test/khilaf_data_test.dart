import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/widgets/quran/khilaf_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('khilaf.json: cards per Qaloon ayah, Qalun row first', () async {
    final data = await KhilafData.load();
    // الأنبياء 78 in our numbering (79 in the source's)
    final cards = data.forAyah(21, 78);
    expect(cards.first.word, 'وكلا آتينا');
    expect(cards.first.rows.first.$1, 'باقي الرواة'); // Qalun is among them
    // البقرة 9: صلة ميم الجمع, Qalun's row first
    final b = data.forAyah(2, 9);
    expect(b.first.rows.first.$1, 'قالون عن نافع');
    expect(data.forAyah(1, 1), isEmpty);
  });
}

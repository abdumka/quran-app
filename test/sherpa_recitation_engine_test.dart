import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/sherpa_recitation_engine.dart';

void main() {
  group('SherpaRecitationEngine.trimInterimResult', () {
    test('drops the (least trustworthy) trailing word', () {
      expect(
        SherpaRecitationEngine.trimInterimResult('الحمد لله رب العالمين'),
        'الحمد لله رب',
      );
    });

    test('collapses stray whitespace while trimming', () {
      expect(
        SherpaRecitationEngine.trimInterimResult('  الحمد   لله  '),
        'الحمد',
      );
    });

    test('rejects single-word interims outright', () {
      expect(SherpaRecitationEngine.trimInterimResult('الحمد'), '');
      expect(SherpaRecitationEngine.trimInterimResult('   '), '');
      expect(SherpaRecitationEngine.trimInterimResult(''), '');
    });
  });
}

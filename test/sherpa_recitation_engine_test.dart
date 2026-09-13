import 'dart:typed_data';

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

  group('interim tail window', () {
    test('short utterances pass through uncut', () {
      final samples = Float32List.fromList([1, 2, 3]);
      final (tail, cut) = SherpaRecitationEngine.interimTail(samples, 5);
      expect(identical(tail, samples), isTrue);
      expect(cut, isFalse);
    });

    test('long utterances keep only the trailing window', () {
      final samples = Float32List.fromList([1, 2, 3, 4, 5, 6]);
      final (tail, cut) = SherpaRecitationEngine.interimTail(samples, 4);
      expect(tail, [3, 4, 5, 6]);
      expect(cut, isTrue);
    });

    test('a tail-cut result also drops its (possibly half) first word', () {
      expect(
        SherpaRecitationEngine.trimTailCutResult('لله رب العالمين'),
        'رب العالمين',
      );
      expect(SherpaRecitationEngine.trimTailCutResult('رب العالمين'), '');
    });
  });
}

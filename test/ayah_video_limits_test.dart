import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/share/ayah_video_service.dart';

/// [s] inside left-to-right isolate marks.
String iso(String s) => String.fromCharCodes([0x2066, ...s.codeUnits, 0x2069]);

void main() {
  test('limits are worded the Arabic way (3 to 10 plural, 11+ singular)', () {
    String f(int s) => AyahVideoService.formatLimit(s);
    expect(f(60), 'دقيقة');
    expect(f(120), 'دقيقتين');
    expect(f(240), '4 دقائق');
    expect(f(600), '10 دقائق');
    expect(f(1800), '30 دقيقة');
    expect(f(3600), 'ساعة');
    expect(f(7200), 'ساعتين');
    expect(f(10800), '3 ساعات');
    expect(f(90), '90 ثانية');
  });

  test('size estimate: the whole asked rate plus the sound', () {
    // 10 minutes at 5 Mbps: (5 Mbps + 128 kbps) / 8 * 600 s
    final b = AyahVideoService.estimateBytes(
      const Duration(minutes: 10),
      5000000,
    );
    expect(b, 384600000);
    expect(AyahVideoService.formatBytes(b), iso('390 MB'));
    expect(AyahVideoService.formatBytes(1940000000), iso('1.9 GB'));
  });
}

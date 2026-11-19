import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/models/audio_clip.dart';
import 'package:islamic_dawah_mushaf/services/share/ayah_video_service.dart';
import 'package:islamic_dawah_mushaf/services/share/mp3_length.dart';

/// MPEG-1 Layer III, 128 kbps, 44.1 kHz, stereo: 417-byte frames.
const _header = [0xFF, 0xFB, 0x90, 0x00];
const _frame = 417;

Uint8List _frames({int offset = 0, int count = 3}) {
  final b = Uint8List(offset + _frame * count + 64);
  for (var f = 0; f < count; f++) {
    b.setRange(offset + f * _frame, offset + f * _frame + 4, _header);
  }
  return b;
}

void main() {
  test('a constant-bitrate MP3: size over bitrate', () {
    // 10 s at 128 kbps = 160000 bytes
    final d = Mp3Length.estimate(_frames(), 160000);
    expect(d!.inMilliseconds, closeTo(10000, 5));
  });

  test('a Xing header gives the exact frame count', () {
    final b = _frames();
    const at = 4 + 32; // after the side info of a stereo MPEG-1 frame
    b.setRange(at, at + 4, 'Xing'.codeUnits);
    b.setRange(at + 4, at + 8, [0, 0, 0, 1]); // frames field present
    b.setRange(at + 8, at + 12, [0, 0, 0, 100]); // 100 frames
    final d = Mp3Length.estimate(b, 999999);
    expect(d!.inMilliseconds, closeTo(100 * 1152 * 1000 / 44100, 2));
  });

  test('an ID3 tag before the audio is skipped', () {
    final b = _frames(offset: 110);
    b.setRange(0, 10, [0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 100]);
    final d = Mp3Length.estimate(b, 110 + 160000);
    expect(d!.inMilliseconds, closeTo(10000, 5));
  });

  test('not an MP3: no estimate', () {
    expect(Mp3Length.estimate(Uint8List(2000), 2000), isNull);
  });

  test('breaths: every ayah in one, joined ones together', () {
    const clip = AudioClip.whole('x.mp3');
    final b = AyahBreaths([
      const AyahBreath(1, 1, [clip]),
      const AyahBreath(2, 4, [clip]), // a reciter joining 2-4
      const AyahBreath(5, 5, [clip]),
    ]);
    expect(b.at(3).from, 2);
    expect(b.at(3).to, 4);
    expect(b.at(3).isJoined, isTrue);
    expect(b.at(5).isJoined, isFalse);
    expect(b.within(3, 5).map((x) => x.from), [2, 5]);
    expect(b.indexOf(4), 1);
  });

  test('the limit is worded in Arabic minutes', () {
    expect(AyahVideoService.formatLimit(240), '4 دقائق');
    expect(AyahVideoService.formatLimit(120), 'دقيقتين');
    expect(AyahVideoService.formatLimit(90), '90 ثانية');
  });
}

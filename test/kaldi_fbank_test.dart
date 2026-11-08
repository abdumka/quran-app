import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/kaldi_fbank.dart';

/// The fixture is 2.4 s of a phone session (16 kHz PCM16) and the frames
/// kaldi_native_fbank computed for it with sherpa-onnx's options
/// (`own_verify/own_ctc.py`, 2026-11-07).
void main() {
  test('matches kaldi_native_fbank frame for frame', () {
    final pcm16 = File('test/fixtures/posterior/clip_16k.pcm16').readAsBytesSync();
    final samples = Int16List.view(pcm16.buffer, pcm16.offsetInBytes, pcm16.length ~/ 2);
    final pcm = Float32List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      pcm[i] = samples[i] / 32768;
    }
    final ref = jsonDecode(File('test/fixtures/posterior/fbank_knf.json').readAsStringSync())
        as Map<String, dynamic>;
    final frames = ref['frames'] as int;
    final data = (ref['data'] as List).cast<num>();
    expect(KaldiFbank.frameCount(pcm.length), frames);

    final got = KaldiFbank().compute(pcm);
    expect(got.length, frames * 80);
    var worst = 0.0;
    var worstAt = -1;
    for (var i = 0; i < got.length; i++) {
      final d = (got[i] - data[i]).abs();
      if (d > worst) {
        worst = d;
        worstAt = i;
      }
    }
    // Float32 in kaldi, float64 here; the fixture is rounded to 1e-5.
    expect(worst, lessThan(2e-3), reason: 'frame ${worstAt ~/ 80} bin ${worstAt % 80}: ${got[worstAt]} vs ${data[worstAt]}');
  });
}

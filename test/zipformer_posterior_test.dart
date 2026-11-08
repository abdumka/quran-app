import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:islamic_dawah_mushaf/services/zipformer_posterior.dart';

/// Parity of the Dart ONNX Runtime path with the Python reference
/// (`own_verify/own_ctc.py`, fixtures of 2026-11-07). Needs the chunk-16
/// model, the token table and an ONNX Runtime DLL on this machine; skipped
/// elsewhere. Tolerances: float32 fbank in kaldi vs float64 here moves
/// unlikely tokens' log-probs by up to about 0.1 and alignment costs by a
/// few tenths; best tokens and greedy output are identical.
void main() {
  const model =
      r'D:\quran app\tasmee_work\research_2026-10-05\models\zipformer_p_arabic_v3.1_c16.int8.onnx';
  const tokensPath = r'D:\quran app\tasmee_work\zipformer\tokens.txt';
  final dll = [
    r'C:\Users\keilani\AppData\Roaming\Python\Python314\site-packages\onnxruntime\capi\onnxruntime.dll',
    r'C:\Python314\Lib\site-packages\onnxruntime\capi\onnxruntime.dll',
  ].where((p) => File(p).existsSync()).firstOrNull;
  final available = Platform.isWindows &&
      dll != null &&
      File(model).existsSync() &&
      File(tokensPath).existsSync();

  Float32List clip() {
    final pcm16 = File('test/fixtures/posterior/clip_16k.pcm16').readAsBytesSync();
    final s = Int16List.view(pcm16.buffer, pcm16.offsetInBytes, pcm16.length ~/ 2);
    final pcm = Float32List(s.length);
    for (var i = 0; i < s.length; i++) {
      pcm[i] = s[i] / 32768;
    }
    return pcm;
  }

  Map<String, dynamic> json(String name) =>
      jsonDecode(File('test/fixtures/posterior/$name').readAsStringSync()) as Map<String, dynamic>;

  test('log posteriors and greedy tokens match the Python ORT loop', () {
    final ref = json('logprobs_c16.json');
    final zp = ZipformerPosterior.load(model, tokensPath, libraryPath: dll);
    expect(zp, isNotNull);
    try {
      expect(zp!.chunkFrames, ref['T']);
      expect(zp.chunkShift, ref['shift']);
      final lp = zp.logProbs(clip());
      expect(lp.frames, ref['frames']);
      expect(lp.vocab, 251);
      final argmax = (ref['argmax'] as List).cast<int>();
      var differ = 0;
      for (var t = 0; t < lp.frames; t++) {
        if (lp.argmax(t) != argmax[t]) differ++;
      }
      expect(differ, lessThanOrEqualTo(1), reason: 'frames whose best token differs');
      expect(lp.greedy(zp.tokens), (ref['tokens'] as List).cast<String>());
      final rowmax = (ref['rowmax'] as List).cast<num>();
      for (var t = 0; t < lp.frames; t++) {
        expect(lp.at(t, lp.argmax(t)), closeTo(rowmax[t].toDouble(), 0.3));
      }
      final frame5 = (ref['lp_frame5'] as List).cast<num>();
      for (var k = 0; k < 251; k++) {
        expect(lp.at(5, k), closeTo(frame5[k].toDouble(), 0.3));
      }
    } finally {
      zp?.dispose();
    }
  }, skip: available ? false : 'model, tokens or ONNX Runtime DLL not on this machine');

  test('the aligner reproduces the Python scores on the same posteriors', () {
    final ref = json('align_ref.json');
    final zp = ZipformerPosterior.load(model, tokensPath, libraryPath: dll)!;
    try {
      final lp = zp.logProbs(clip());
      final aligns = ref['align'] as Map<String, dynamic>;
      for (final e in aligns.entries) {
        final r = Aligner.align(lp, zp.tokens, e.key, 0);
        final want = e.value as Map<String, dynamic>;
        expect(r, isNotNull, reason: e.key);
        expect(r!.score, closeTo((want['score'] as num).toDouble(), 0.4), reason: e.key);
        expect(r.weakest, closeTo((want['weakest'] as num).toDouble(), 0.4), reason: e.key);
        expect(r.start, want['start'], reason: e.key);
        expect(r.end, want['end'], reason: e.key);
      }
      final cands = Aligner.candidates(zp.tokens, ['فَذكُرُ'], 'بِسمِ', 'ءَللَاهَ');
      expect([for (final c in cands) c.text], [for (final c in ref['cands'] as List) c[1]]);
      expect([for (final c in cands) c.nextAnchored], [for (final c in ref['cands'] as List) c[0] == 'next']);
      final g = Aligner.guardedScore(lp, zp.tokens, cands, 'بِسمِ', 0)!;
      final want = ref['guarded'] as Map<String, dynamic>;
      expect(g.score, closeTo((want['score'] as num).toDouble(), 0.4));
      expect(g.text, want['s']);
      // The verdict on the word the clip holds, asked the way the service asks.
      final v = zp.verify(
        clip(),
        const PosteriorQuery(forms: ['فَذكُرُ'], prevPhon: 'كُم', nextPhon: 'ءَللَاهَ', minEndFrame: 30),
      );
      expect(v.tokens.join(), 'فَذكُرُءَ');
      expect(v.score, isNotNull);
    } finally {
      zp.dispose();
    }
  }, skip: available ? false : 'model, tokens or ONNX Runtime DLL not on this machine');

  test('tokensOf cuts a phoneme string like the Python longest match', () {
    final ref = json('align_ref.json');
    final table = TokenTable.fromFile(tokensPath);
    final want = (ref['tokens_of'] as Map<String, dynamic>);
    for (final e in want.entries) {
      expect(table.tokensOf(e.key), (e.value as List).cast<String>());
    }
  }, skip: File(tokensPath).existsSync() ? false : 'token table not on this machine');
}

import 'dart:typed_data';

import 'posterior_common.dart';

export 'posterior_common.dart';

/// Web stand-in for the ONNX Runtime engine in zipformer_posterior.dart:
/// browsers have no dart:ffi, so the posterior verify is never available
/// there ([load] gives null, as on a phone without the runtime).
class ZipformerPosterior {
  ZipformerPosterior._();

  static ZipformerPosterior? load(String modelPath, String tokensPath,
          {int threads = 1, String? libraryPath}) =>
      null;

  TokenTable get tokens => throw UnsupportedError('posterior verify is not on the web');
  int get chunkFrames => 0;
  int get chunkShift => 0;
  String get runtimeVersion => '';

  LogProbs logProbs(Float32List pcm, {int padMs = 500}) =>
      throw UnsupportedError('posterior verify is not on the web');

  PosteriorVerdict verify(Float32List clip, PosteriorQuery query) =>
      throw UnsupportedError('posterior verify is not on the web');

  void dispose() {}
}

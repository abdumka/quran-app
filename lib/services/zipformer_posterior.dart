import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'kaldi_fbank.dart';
import 'posterior_common.dart';
import 'ort_ffi.dart';

export 'posterior_common.dart';

/// Our streaming zipformer run through ONNX Runtime directly, so a verify
/// window yields the 251-way log posteriors that the sherpa-onnx streaming
/// API does not expose. A CTC forced alignment of the expected word (with a
/// neighbour as anchor) over those posteriors says how confidently the model
/// heard it; a stop whose word aligns at near-zero cost is withdrawn even
/// when the greedy decode wrote something else. Mirrors
/// `tasmee_work/research_2026-10-05/own_verify/{own_ctc,score_lib}.py`
/// (study of 2026-11-06: 52 more of 741 phone stops cleared at the a=3, c=3
/// rule, sheikh false stops cleared 39 % -> 65 %, planted look-alike words
/// pass 0.7 %).
class ZipformerPosterior {
  ZipformerPosterior._(this._api, this._env, this._options, this._session,
      this._memory, this.tokens, this._inputs, this._outputNames, this.chunkFrames,
      this.chunkShift, this._inNames, this._outNames, this._x);

  /// Loads [modelPath] (the same chunk-16 int8 export sherpa runs) and the
  /// token table. Null when the runtime is not reachable on this platform.
  static ZipformerPosterior? load(String modelPath, String tokensPath,
      {int threads = 1, String? libraryPath}) {
    final api = OrtApi.load(libraryPath: libraryPath);
    if (api == null) return null;
    final env = api.createEnv();
    final options = api.createSessionOptions(threads: threads);
    final session = api.createSession(env, modelPath, options);
    final allocator = api.defaultAllocator();
    final memory = api.cpuMemoryInfo();
    final t = int.parse(api.metadata(session, allocator, 'T') ?? '45');
    final shift = int.parse(api.metadata(session, allocator, 'decode_chunk_len') ?? '32');
    final n = api.inputCount(session);
    final inputs = <_StateInput>[];
    final names = <String>[];
    Pointer<Void>? x;
    for (var i = 0; i < n; i++) {
      final name = api.inputName(session, i, allocator);
      final (type, dims) = api.inputTypeAndShape(session, i);
      names.add(name);
      final shape = [for (final d in dims) d < 0 ? 1 : d];
      if (name == 'x') {
        shape[1] = t;
        shape[2] = 80;
        x = calloc<Float>(t * 80).cast();
        inputs.add(_StateInput(name, type, shape, x, t * 80 * 4));
      } else {
        final count = shape.fold<int>(1, (a, b) => a * b);
        final bytes = count * (type == OrtApi.typeInt64 ? 8 : 4);
        inputs.add(_StateInput(name, type, shape, calloc<Uint8>(bytes).cast(), bytes));
      }
    }
    final outCount = api.outputCount(session);
    final outputNames = [for (var i = 0; i < outCount; i++) api.outputName(session, i, allocator)];
    final tokenTable = TokenTable.fromFile(tokensPath);
    return ZipformerPosterior._(api, env, options, session, memory, tokenTable, inputs,
        outputNames, t, shift, OrtApi.names(names), OrtApi.names(outputNames), x!);
  }

  final OrtApi _api;
  final Pointer<Void> _env;
  final Pointer<Void> _options;
  final Pointer<Void> _session;
  final Pointer<Void> _memory;
  final List<_StateInput> _inputs;
  final List<String> _outputNames;
  final Pointer<Pointer<Utf8>> _inNames;
  final Pointer<Pointer<Utf8>> _outNames;
  final Pointer<Void> _x;
  final TokenTable tokens;

  /// Feature frames per model step and the step's advance (chunk 16: 45 / 32).
  final int chunkFrames;
  final int chunkShift;

  final KaldiFbank _fbank = KaldiFbank();
  bool _disposed = false;

  String get runtimeVersion => _api.version;

  /// Frames x 251 log posteriors of [pcm] (16 kHz, -1..1) on a fresh stream,
  /// [padMs] of silence appended so the last word's frames come out.
  LogProbs logProbs(Float32List pcm, {int padMs = 500}) {
    if (_disposed) throw StateError('disposed');
    final padded = Float32List(pcm.length + padMs * 16)..setAll(0, pcm);
    final feats = _fbank.compute(padded);
    final frames = feats.length ~/ 80;
    for (final s in _inputs) {
      if (s.name != 'x') s.data.cast<Uint8>().asTypedList(s.bytes).fillRange(0, s.bytes, 0);
    }
    final xView = _x.asFloat32(chunkFrames * 80);
    final chunks = <Float32List>[];
    var total = 0;
    var vocab = 0;
    for (var p = 0; p + chunkFrames <= frames; p += chunkShift) {
      xView.setRange(0, chunkFrames * 80, feats, p * 80);
      final values = <Pointer<Void>>[];
      for (final s in _inputs) {
        values.add(_api.tensorOver(_memory, s.data, s.bytes, s.shape, s.type));
      }
      List<Pointer<Void>> outs;
      try {
        outs = _api.run(_session, _inNames, values, _outNames, _outputNames.length);
      } finally {
        for (final v in values) {
          _api.releaseValue(v);
        }
      }
      try {
        for (var k = 0; k < outs.length; k++) {
          final name = _outputNames[k];
          final data = _api.tensorData(outs[k]);
          if (name == 'log_probs') {
            final dims = _api.valueDims(outs[k]);
            final t = dims[1];
            vocab = dims[2];
            final copy = Float32List(t * vocab)..setAll(0, data.asFloat32(t * vocab));
            chunks.add(copy);
            total += t;
          } else if (name.startsWith('new_')) {
            final s = _byName[name.substring(4)];
            if (s != null) {
              s.data.cast<Uint8>().asTypedList(s.bytes).setAll(0, data.cast<Uint8>().asTypedList(s.bytes));
            }
          }
        }
      } finally {
        for (final o in outs) {
          _api.releaseValue(o);
        }
      }
    }
    final all = Float32List(total * vocab);
    var at = 0;
    for (final c in chunks) {
      all.setAll(at, c);
      at += c.length;
    }
    return LogProbs(total, vocab, all, tokens.blank);
  }

  late final Map<String, _StateInput> _byName = {for (final s in _inputs) s.name: s};

  /// Fresh decode plus the posterior judgement of one disputed word.
  PosteriorVerdict verify(Float32List clip, PosteriorQuery query) {
    final lp = logProbs(clip);
    final decoded = lp.greedy(tokens);
    final cands = Aligner.candidates(tokens, query.forms, query.prevPhon, query.nextPhon);
    final best = Aligner.guardedScore(lp, tokens, cands, query.prevPhon, query.minEndFrame);
    final cleared = best != null &&
        best.score >= -PosteriorQuery.scoreFloor &&
        best.weakest >= -PosteriorQuery.weakestFloor;
    return PosteriorVerdict(decoded, best?.score, best?.weakest, cleared, best?.text);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final s in _inputs) {
      calloc.free(s.data);
    }
    OrtApi.freeNames(_inNames, _inputs.length);
    OrtApi.freeNames(_outNames, _outputNames.length);
    _api.releaseMemoryInfo(_memory);
    _api.releaseSession(_session);
    _api.releaseSessionOptions(_options);
    _api.releaseEnv(_env);
  }
}

class _StateInput {
  _StateInput(this.name, this.type, this.shape, this.data, this.bytes);
  final String name;
  final int type;
  final List<int> shape;
  final Pointer<Void> data;
  final int bytes;
}

import 'dart:math' as math;
import 'dart:typed_data';

/// Kaldi-style log mel filterbank, matching kaldi-native-fbank with the
/// options sherpa-onnx uses for our zipformer: 16 kHz, 25 ms frames every
/// 10 ms, no dither, pre-emphasis 0.97, DC offset removed, Povey window,
/// 512-point FFT, 80 mel bins between 20 Hz and 7600 Hz, snip_edges off (the
/// first frame is centred 5 ms into the signal and the edges are mirrored).
///
/// This is the front end of `ZipformerPosterior`: the ONNX model takes these
/// frames, and running them through ONNX Runtime ourselves gives the
/// posteriors that the sherpa streaming API keeps to itself. Parity with the
/// Python reference (`own_verify/own_ctc.py`, kaldi_native_fbank) is checked
/// by `test/kaldi_fbank_test.dart`.
class KaldiFbank {
  KaldiFbank({this.numBins = 80})
      : _window = _poveyWindow(_frameLength),
        _mel = _MelBanks(numBins, _paddedLength, _sampleRate, 20, 7600);

  static const int _sampleRate = 16000;
  static const int _frameLength = 400; // 25 ms
  static const int _frameShift = 160; // 10 ms
  static const int _paddedLength = 512;
  static const double _preemphasis = 0.97;
  static const double _floor = 1.1920929e-7; // FLT_EPSILON

  final int numBins;
  final Float64List _window;
  final _MelBanks _mel;

  /// Number of frames kaldi produces for [samples] samples (snip_edges off).
  static int frameCount(int samples) =>
      (samples + _frameShift ~/ 2) ~/ _frameShift;

  /// Frames x [numBins] log mel energies of [pcm] (-1..1 floats), row-major.
  Float32List compute(Float32List pcm) {
    final n = frameCount(pcm.length);
    final out = Float32List(n * numBins);
    final frame = Float64List(_paddedLength);
    final im = Float64List(_paddedLength);
    final power = Float64List(_paddedLength ~/ 2 + 1);
    for (var f = 0; f < n; f++) {
      _extract(pcm, f, frame);
      _process(frame);
      for (var i = _frameLength; i < _paddedLength; i++) {
        frame[i] = 0;
      }
      im.fillRange(0, _paddedLength, 0);
      _fft(frame, im);
      for (var k = 0; k <= _paddedLength ~/ 2; k++) {
        power[k] = frame[k] * frame[k] + im[k] * im[k];
      }
      _mel.apply(power, out, f * numBins, _floor);
    }
    return out;
  }

  /// Frame [f] of [pcm] into [frame] (first [_frameLength] entries), with
  /// kaldi's mirrored edges.
  static void _extract(Float32List pcm, int f, Float64List frame) {
    final start = f * _frameShift + _frameShift ~/ 2 - _frameLength ~/ 2;
    final n = pcm.length;
    for (var j = 0; j < _frameLength; j++) {
      var s = start + j;
      while (s < 0 || s >= n) {
        s = s < 0 ? -s - 1 : 2 * n - 1 - s;
      }
      frame[j] = pcm[s];
    }
  }

  /// DC offset, pre-emphasis and window, in kaldi's order.
  void _process(Float64List frame) {
    var sum = 0.0;
    for (var j = 0; j < _frameLength; j++) {
      sum += frame[j];
    }
    final mean = sum / _frameLength;
    for (var j = 0; j < _frameLength; j++) {
      frame[j] -= mean;
    }
    for (var j = _frameLength - 1; j > 0; j--) {
      frame[j] -= _preemphasis * frame[j - 1];
    }
    frame[0] -= _preemphasis * frame[0];
    for (var j = 0; j < _frameLength; j++) {
      frame[j] *= _window[j];
    }
  }

  static Float64List _poveyWindow(int n) {
    final w = Float64List(n);
    final a = 2 * math.pi / (n - 1);
    for (var i = 0; i < n; i++) {
      w[i] = math.pow(0.5 - 0.5 * math.cos(a * i), 0.85).toDouble();
    }
    return w;
  }

  /// In-place iterative radix-2 complex FFT (length a power of two).
  static void _fft(Float64List re, Float64List im) {
    final n = re.length;
    // Bit reversal.
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j |= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wr = math.cos(ang);
      final wi = math.sin(ang);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0;
        var ci = 0.0;
        final half = len >> 1;
        for (var k = 0; k < half; k++) {
          final ur = re[i + k];
          final ui = im[i + k];
          final vr = re[i + k + half] * cr - im[i + k + half] * ci;
          final vi = re[i + k + half] * ci + im[i + k + half] * cr;
          re[i + k] = ur + vr;
          im[i + k] = ui + vi;
          re[i + k + half] = ur - vr;
          im[i + k + half] = ui - vi;
          final ncr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = ncr;
        }
      }
    }
  }
}

/// Kaldi's triangular mel filters on the half spectrum (bins 0..N/2-1).
class _MelBanks {
  _MelBanks(int numBins, int paddedLength, int sampleRate, double lowFreq,
      double highFreq) {
    final numFftBins = paddedLength ~/ 2;
    final binWidth = sampleRate / paddedLength;
    final lowMel = _mel(lowFreq);
    final highMel = _mel(highFreq);
    final delta = (highMel - lowMel) / (numBins + 1);
    for (var b = 0; b < numBins; b++) {
      final left = lowMel + b * delta;
      final center = left + delta;
      final right = center + delta;
      var first = -1;
      final w = <double>[];
      for (var i = 0; i < numFftBins; i++) {
        final mel = _mel(binWidth * i);
        if (mel > left && mel < right) {
          if (first < 0) first = i;
          w.add(mel <= center
              ? (mel - left) / (center - left)
              : (right - mel) / (right - center));
        } else if (first >= 0) {
          break;
        }
      }
      _offset.add(first < 0 ? 0 : first);
      _weights.add(Float64List.fromList(w));
    }
  }

  final List<int> _offset = [];
  final List<Float64List> _weights = [];

  static double _mel(double f) => 1127.0 * math.log(1 + f / 700.0);

  void apply(Float64List power, Float32List out, int at, double floor) {
    for (var b = 0; b < _weights.length; b++) {
      final w = _weights[b];
      final o = _offset[b];
      var e = 0.0;
      for (var i = 0; i < w.length; i++) {
        e += w[i] * power[o + i];
      }
      out[at + b] = math.log(e < floor ? floor : e);
    }
  }
}

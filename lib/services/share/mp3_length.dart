import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// How long an MP3 plays, from its first few kilobytes: the frame count of
/// a Xing/Info or VBRI header when the file has one (exact), otherwise its
/// size over its bitrate (exact for the constant-bitrate mirrors, close for
/// the rest). Used for the length shown before an ayah video is made, so a
/// per-ayah reciter's files need not be downloaded first.
class Mp3Length {
  Mp3Length._();

  static final Map<String, Duration?> _cache = {};
  static const int _headBytes = 64 * 1024;

  /// [local] when the app already has the file, else the first bytes of
  /// [url] (an HTTP range request). Null when neither can be read.
  static Future<Duration?> of(Uri url, {File? local}) async {
    final key = local?.path ?? url.toString();
    if (_cache.containsKey(key)) return _cache[key];
    Duration? d;
    try {
      if (local != null && await local.exists()) {
        final total = await local.length();
        if (total > 0) {
          final raf = await local.open();
          try {
            d = estimate(await raf.read(_headBytes), total);
          } finally {
            await raf.close();
          }
        }
      }
      if (d == null) {
        final res = await http
            .get(url, headers: {'Range': 'bytes=0-${_headBytes - 1}'})
            .timeout(const Duration(seconds: 15));
        int? total;
        if (res.statusCode == 206) {
          total = int.tryParse(
            res.headers['content-range']?.split('/').last ?? '',
          );
        } else if (res.statusCode == 200) {
          total = res.bodyBytes.length; // the server sent the whole file
        }
        if (total != null) d = estimate(res.bodyBytes, total);
      }
    } catch (e) {
      debugPrint('Mp3Length: $url: $e');
    }
    // A failed lookup is not remembered, so it is tried again later.
    if (d != null) _cache[key] = d;
    return d;
  }

  static const _rates1 = [
    0,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    160,
    192,
    224,
    256,
    320,
  ];
  static const _rates2 = [
    0,
    8,
    16,
    24,
    32,
    40,
    48,
    56,
    64,
    80,
    96,
    112,
    128,
    144,
    160,
  ];

  /// The play time of an MP3 of [total] bytes whose first bytes are [b].
  @visibleForTesting
  static Duration? estimate(Uint8List b, int total) {
    var i = 0;
    // An ID3v2 tag first: 10 bytes, then a syncsafe size (+10 for a footer).
    if (b.length >= 10 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
      final size =
          (b[6] & 0x7f) << 21 |
          (b[7] & 0x7f) << 14 |
          (b[8] & 0x7f) << 7 |
          (b[9] & 0x7f);
      i = 10 + size + ((b[5] & 0x10) != 0 ? 10 : 0);
    }
    for (; i + 4 <= b.length; i++) {
      final h = _Frame.parse(b, i);
      if (h == null) continue;
      // A real frame is followed by another one where its length says.
      final next = i + h.length;
      if (next + 4 <= b.length && _Frame.parse(b, next) == null) continue;

      final xing = i + 4 + h.sideInfo;
      if (xing + 12 <= b.length) {
        final tag = String.fromCharCodes(b.sublist(xing, xing + 4));
        if (tag == 'Xing' || tag == 'Info') {
          final flags = _u32(b, xing + 4);
          if (flags & 1 != 0) {
            return _frames(_u32(b, xing + 8), h);
          }
        }
      }
      final vbri = i + 4 + 32;
      if (vbri + 18 <= b.length &&
          String.fromCharCodes(b.sublist(vbri, vbri + 4)) == 'VBRI') {
        return _frames(_u32(b, vbri + 14), h);
      }
      final bytes = total - i;
      if (bytes <= 0) return null;
      return Duration(milliseconds: (bytes * 8 * 1000 / h.bitrate).round());
    }
    return null;
  }

  static Duration _frames(int frames, _Frame h) => Duration(
    milliseconds: (frames * h.samples * 1000 / h.sampleRate).round(),
  );

  static int _u32(Uint8List b, int o) =>
      b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];
}

class _Frame {
  const _Frame(
    this.bitrate,
    this.sampleRate,
    this.samples,
    this.length,
    this.sideInfo,
  );

  /// bits per second
  final int bitrate;
  final int sampleRate;
  final int samples;
  final int length;

  /// Bytes between the header and a Xing/Info tag.
  final int sideInfo;

  static const _srates = {
    3: [44100, 48000, 32000], // MPEG 1
    2: [22050, 24000, 16000], // MPEG 2
    0: [11025, 12000, 8000], // MPEG 2.5
  };

  static _Frame? parse(Uint8List b, int i) {
    if (i + 4 > b.length) return null;
    if (b[i] != 0xFF || (b[i + 1] & 0xE0) != 0xE0) return null;
    final version = (b[i + 1] >> 3) & 3;
    final layer = (b[i + 1] >> 1) & 3;
    if (version == 1 || layer != 1) return null; // Layer III only
    final rateIdx = b[i + 2] >> 4;
    final srIdx = (b[i + 2] >> 2) & 3;
    if (rateIdx == 0 || rateIdx == 15 || srIdx == 3) return null;
    final mpeg1 = version == 3;
    final kbps = (mpeg1 ? Mp3Length._rates1 : Mp3Length._rates2)[rateIdx];
    final sr = _srates[version]![srIdx];
    final padding = (b[i + 2] >> 1) & 1;
    final mono = (b[i + 3] >> 6) == 3;
    final samples = mpeg1 ? 1152 : 576;
    final length = (samples ~/ 8) * kbps * 1000 ~/ sr + padding;
    if (length < 24) return null;
    final side = mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17);
    return _Frame(kbps * 1000, sr, samples, length, side);
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import 'content_update_service.dart';

/// The pack of `assets/data/tanzilat_paint.bin` (or a newer one from our
/// server), built by build_tanzilat_paint.py: one small transparent PNG per
/// page holding exactly what the reviewers' brush painted, so the app's colours
/// match the editor's. The word boxes cannot: a box takes all the ink inside it.
///
///     "TZP1", header length (uint32 LE), header JSON, the PNGs
///     header: {"ver": N, "tz": tanzilat version, "pages": {"2": [offset, length]}}
///
/// Each PNG covers the 720x1640 page area and is indexed: entry 0 is
/// transparent, entries 1..5 are the colour buckets, so a palette for the dark
/// page or the one-colour setting costs only rewriting its PLTE chunk.
class TanzilatPaintPack {
  TanzilatPaintPack._(this.ver, this.tanzilatVer, this._bytes, this._pages);

  final int ver;

  /// The `tanzilat` version these pictures were painted for. A pack that does
  /// not match the data in use is not shown (see [TanzilatPaintService]).
  final int tanzilatVer;
  final Uint8List _bytes;
  final Map<int, (int, int)> _pages;

  Iterable<int> get pages => _pages.keys;

  /// Reads a pack, or throws [FormatException].
  static TanzilatPaintPack parse(Uint8List bytes) {
    if (bytes.length < 8 ||
        bytes[0] != 0x54 ||
        bytes[1] != 0x5A ||
        bytes[2] != 0x50 ||
        bytes[3] != 0x31) {
      throw const FormatException('tanzilat_paint: bad magic');
    }
    final view = ByteData.sublistView(bytes);
    final headerLength = view.getUint32(4, Endian.little);
    final start = 8 + headerLength;
    if (start > bytes.length) {
      throw const FormatException('tanzilat_paint: short header');
    }
    final header =
        json.decode(utf8.decode(bytes.sublist(8, start)))
            as Map<String, dynamic>;
    final ver = header['ver'];
    final tz = header['tz'];
    final raw = header['pages'];
    if (ver is! int || tz is! int || raw is! Map<String, dynamic>) {
      throw const FormatException('tanzilat_paint: bad header');
    }
    final pages = <int, (int, int)>{};
    raw.forEach((k, v) {
      final at = (v as List<dynamic>)[0] as int;
      final length = v[1] as int;
      if (start + at + length > bytes.length) {
        throw const FormatException('tanzilat_paint: page out of range');
      }
      pages[int.parse(k)] = (start + at, length);
    });
    return TanzilatPaintPack._(ver, tz, bytes, pages);
  }

  /// The PNG of [page], or null. Its palette is left as stored.
  Uint8List? pngOf(int page) {
    final at = _pages[page];
    if (at == null) return null;
    return Uint8List.sublistView(_bytes, at.$1, at.$1 + at.$2);
  }
}

/// A copy of [png] with its PLTE chunk replaced: entry 0 stays, entries 1.. take
/// [colours]. Returns null when the file is not the indexed PNG we build.
Uint8List? recolourPng(Uint8List png, List<ui.Color> colours) {
  final view = ByteData.sublistView(png);
  var at = 8;
  while (at + 12 <= png.length) {
    final length = view.getUint32(at);
    final isPlte =
        png[at + 4] == 0x50 &&
        png[at + 5] == 0x4C &&
        png[at + 6] == 0x54 &&
        png[at + 7] == 0x45;
    if (isPlte) {
      if (length != (colours.length + 1) * 3) return null;
      final out = Uint8List.fromList(png);
      var p = at + 8 + 3;
      for (final c in colours) {
        out[p++] = (c.r * 255).round();
        out[p++] = (c.g * 255).round();
        out[p++] = (c.b * 255).round();
      }
      ByteData.sublistView(out).setUint32(
        at + 8 + length,
        _crc32(Uint8List.sublistView(out, at + 4, at + 8 + length)),
      );
      return out;
    }
    at += 12 + length;
  }
  return null;
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

int _crc32(Uint8List bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Loads the pack on first use and decodes a page's picture for the overlay.
/// A page without a picture, or a pack that does not match the tanzilat data in
/// use, gives null: the overlay then colours from the word boxes as before.
class TanzilatPaintService {
  TanzilatPaintService._() {
    ContentUpdateService.instance.registerItem(
      'tanzilat_paint',
      apply: reload,
      isLoaded: () => _pack != null,
    );
  }
  static final TanzilatPaintService instance = TanzilatPaintService._();

  static const String assetPath = 'assets/data/tanzilat_paint.bin';

  /// Decoded pages kept: about 5 MB each, and a two-page spread with its
  /// neighbours in light and dark is the most that is ever wanted at once.
  static const int _maxImages = 8;

  Future<TanzilatPaintPack?>? _pack;
  final Map<String, Future<ui.Image?>> _images = {};

  /// Bumped when a new pack was swapped in.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<void> reload() async {
    _pack = null;
    _images.clear();
    revision.value++;
  }

  Future<TanzilatPaintPack?> _loadPack() async {
    try {
      final file = await ContentUpdateService.instance.bytesFor(
        'tanzilat_paint',
      );
      if (file != null) return TanzilatPaintPack.parse(file);
      final data = await rootBundle.load(assetPath);
      return TanzilatPaintPack.parse(Uint8List.sublistView(data));
    } catch (e) {
      debugPrint('TanzilatPaintService: no pack: $e');
      return null;
    }
  }

  /// The picture of [page] in [colours] (one per bucket), or null.
  Future<ui.Image?> imageFor(int page, List<ui.Color> colours) {
    final key = '$page|${colours.map((c) => c.toARGB32()).join(',')}';
    final cached = _images.remove(key);
    final future = cached ?? _decode(page, colours);
    // Most recently used last; evicted images are freed with their last user.
    _images[key] = future;
    if (_images.length > _maxImages) _images.remove(_images.keys.first);
    return future;
  }

  Future<ui.Image?> _decode(int page, List<ui.Color> colours) async {
    try {
      final pack = await (_pack ??= _loadPack());
      if (pack == null) return null;
      await ContentUpdateService.instance.init();
      if (pack.tanzilatVer !=
          ContentUpdateService.instance.versionOf('tanzilat')) {
        return null;
      }
      final png = pack.pngOf(page);
      if (png == null) return null;
      final bytes = recolourPng(png, colours);
      if (bytes == null) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (e) {
      debugPrint('TanzilatPaintService: page $page: $e');
      return null;
    }
  }
}

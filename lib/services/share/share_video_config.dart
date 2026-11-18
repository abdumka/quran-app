import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import '../content_update_service.dart';

/// Everything about «مشاركة الآية» that can change without a release: the
/// share text, the link, the backgrounds and their pictures, the sound
/// effects and their strength, the watermark, the closing card and the
/// layout numbers.
///
/// The bundled copy is `assets/data/share_video.json`; a newer one arrives
/// as the `share_video` content item ([ContentUpdateService]) and is used the
/// next time a share sheet opens. A file that fails [parse] is never
/// installed (the content service validates with this same parser), so a
/// phone always has a working config.
class ShareVideoConfig {
  ShareVideoConfig._({
    required this.ver,
    required this.enabled,
    required this.videoEnabled,
    required this.baseUrl,
    required this.link,
    required this.textTemplate,
    required this.video,
    required this.shapes,
    required this.effects,
    required this.categories,
    required this.defaultBackground,
    required this.backgrounds,
  });

  static const String assetPath = 'assets/data/share_video.json';
  static const String item = 'share_video';

  final int ver;

  /// The share icon in the ayah menu.
  final bool enabled;

  /// The «فيديو الآية» choice (text sharing stays when this is off).
  final bool videoEnabled;

  /// Where background clips and pictures live; `path`s are relative to it.
  final String baseUrl;

  /// The app's link in the shared text and on the video.
  final String link;

  /// `{text}`, `{surah}`, `{ayah}` and `{link}` are filled in.
  final String textTemplate;
  final ShareVideoLook video;
  final List<ShareVideoShape> shapes;
  final List<ShareVideoEffect> effects;
  final List<ShareVideoCategory> categories;
  final String defaultBackground;
  final List<ShareVideoBackground> backgrounds;

  String urlOf(String path) => '$baseUrl$path';

  ShareVideoBackground? background(String? id) {
    for (final b in backgrounds) {
      if (b.id == id) return b;
    }
    return null;
  }

  static ShareVideoConfig? _current;
  static Future<ShareVideoConfig>? _loading;

  /// For the ayah menu, which is built synchronously: whether to show the
  /// share icon. Until the config is read (a few ms after the first call)
  /// the icon shows; the server can still hide it with `enabled: false`.
  static bool get shareEnabled {
    if (_current == null) load();
    return _current?.enabled ?? true;
  }

  /// The config in use: the downloaded one when it is newer and valid, else
  /// the bundled one. Cached; [reload] drops the cache.
  static Future<ShareVideoConfig> load() {
    final c = _current;
    if (c != null) return Future.value(c);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<void> reload() async {
    _current = null;
    await load();
  }

  static Future<ShareVideoConfig> _load() async {
    ContentUpdateService.instance.registerItem(item, apply: reload);
    final remote = await ContentUpdateService.instance.readFor(item);
    if (remote != null) {
      try {
        return _current = parse(remote);
      } catch (e) {
        debugPrint('ShareVideoConfig: downloaded file refused: $e');
      }
    }
    return _current = parse(await rootBundle.loadString(assetPath));
  }

  @visibleForTesting
  static void debugSet(ShareVideoConfig? c) => _current = c;

  /// Throws [FormatException] for anything the app could not use safely.
  static ShareVideoConfig parse(String text) {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) {
      throw const FormatException('share_video: not an object');
    }
    final ver = j['ver'];
    if (ver is! int || ver < 1) {
      throw const FormatException('share_video: bad ver');
    }
    final baseUrl = _str(j['baseUrl'], 'baseUrl');
    final link = _str(j['link'], 'link');
    for (final u in [baseUrl, link]) {
      final uri = Uri.tryParse(u);
      if (uri == null ||
          uri.scheme != 'https' ||
          !(uri.host == 'mushaf-qaloon.com' ||
              uri.host.endsWith('.mushaf-qaloon.com'))) {
        throw FormatException('share_video: $u is not one of our hosts');
      }
    }
    if (!baseUrl.endsWith('/')) {
      throw const FormatException('share_video: baseUrl must end with /');
    }
    final text0 = j['text'];
    final template = text0 is Map
        ? _str(text0['template'], 'text.template')
        : '';
    if (!template.contains('{text}')) {
      throw const FormatException('share_video: template has no {text}');
    }

    final shapes = <ShareVideoShape>[
      for (final s in _list(j['shapes'], 'shapes')) ShareVideoShape._parse(s),
    ];
    if (shapes.isEmpty) throw const FormatException('share_video: no shapes');
    final effects = <ShareVideoEffect>[
      for (final e in _list(j['effects'], 'effects'))
        ShareVideoEffect._parse(e),
    ];
    if (effects.isEmpty) {
      throw const FormatException('share_video: no effects');
    }
    final categories = <ShareVideoCategory>[
      for (final c in _list(j['categories'], 'categories'))
        ShareVideoCategory(
          id: _str((c as Map)['id'], 'category id'),
          title: _str(c['title'], 'category title'),
        ),
    ];
    final ids = <String>{};
    final backgrounds = <ShareVideoBackground>[];
    for (final b in _list(j['backgrounds'], 'backgrounds')) {
      final bg = ShareVideoBackground._parse(b, shapes);
      if (!ids.add(bg.id)) {
        throw FormatException('share_video: duplicate background ${bg.id}');
      }
      if (!categories.any((c) => c.id == bg.category)) {
        throw FormatException('share_video: ${bg.id} has no category');
      }
      backgrounds.add(bg);
    }
    if (backgrounds.isEmpty) {
      throw const FormatException('share_video: no backgrounds');
    }
    final def = j['defaultBackground'];
    return ShareVideoConfig._(
      ver: ver,
      enabled: j['enabled'] != false,
      videoEnabled: j['videoEnabled'] != false,
      baseUrl: baseUrl,
      link: link,
      textTemplate: template,
      video: ShareVideoLook._parse(j['video']),
      shapes: List.unmodifiable(shapes),
      effects: List.unmodifiable(effects),
      categories: List.unmodifiable(
        categories.where((c) => backgrounds.any((b) => b.category == c.id)),
      ),
      defaultBackground: def is String && ids.contains(def)
          ? def
          : backgrounds.first.id,
      backgrounds: List.unmodifiable(backgrounds),
    );
  }

  static String _str(Object? v, String what) {
    if (v is String && v.trim().isNotEmpty) return v;
    throw FormatException('share_video: missing $what');
  }

  static List<dynamic> _list(Object? v, String what) {
    if (v is List) return v;
    throw FormatException('share_video: $what is not a list');
  }
}

/// The numbers of the video's look, each kept within a safe range.
class ShareVideoLook {
  const ShareVideoLook({
    required this.maxAyat,
    required this.maxSeconds,
    required this.fps,
    required this.bitrate,
    required this.dim,
    required this.textWidth,
    required this.textHeight,
    required this.textMaxScale,
    this.textHalo = 0.9,
    this.textBackdrop = 0.0,
    required this.showTitle,
    required this.titleTemplate,
    this.titleImages,
    this.titleImageHeight = 0.085,
    this.titleImageMaxWidth = 0.72,
    required this.showWatermark,
    required this.watermarkName,
    required this.watermarkLink,
    required this.watermarkOpacity,
    required this.showClosing,
    required this.closingSeconds,
    required this.closingTitle,
    required this.closingSubtitle,
    required this.closingStores,
    required this.closingLink,
  });

  final int maxAyat;
  final int maxSeconds;
  final int fps;
  final int bitrate;
  final double dim;
  final double textWidth;
  final Map<String, double> textHeight;
  final double textMaxScale;

  /// Darkness of the halo hugging the white letters (0 = the old light drop
  /// shadow only), so the ayat read on bright or busy backgrounds.
  final double textHalo;

  /// A soft dark veil behind the whole text block (0 = none).
  final double textBackdrop;
  final bool showTitle;
  final String titleTemplate;

  /// The surah name as cut from the mushaf's own pages: a path under
  /// [ShareVideoConfig.baseUrl] with `{surah}` for the 3-digit surah number
  /// (white ink on transparent, tinted in the video). Null, or a picture that
  /// cannot be fetched, falls back to [titleTemplate] as text.
  final String? titleImages;

  /// Ink height of that picture, as a share of the frame's short side.
  final double titleImageHeight;

  /// Its widest, as a share of the frame's width.
  final double titleImageMaxWidth;
  final bool showWatermark;
  final String watermarkName;
  final String watermarkLink;
  final double watermarkOpacity;
  final bool showClosing;
  final double closingSeconds;
  final String closingTitle;
  final String closingSubtitle;
  final List<String> closingStores;
  final String closingLink;

  double textHeightFor(String shape) => textHeight[shape] ?? 0.62;

  /// A safe relative path holding `{surah}`, or null (then the text title).
  static String? _titleImages(Object? v) {
    if (v is! String || !v.contains('{surah}')) return null;
    final bare = v.replaceAll('{surah}', '000');
    if (!ShareVideoBackground._safePath.hasMatch(bare) ||
        bare.contains('..') ||
        bare.startsWith('/')) {
      return null;
    }
    return v;
  }

  /// The picture path of [surah], if pictures are set.
  String? titleImageFor(int surah) =>
      titleImages?.replaceAll('{surah}', surah.toString().padLeft(3, '0'));

  static ShareVideoLook _parse(Object? v) {
    final m = v is Map ? v : const {};
    double d(Object? x, double def, double lo, double hi) =>
        x is num && x.isFinite ? x.toDouble().clamp(lo, hi) : def;
    int i(Object? x, int def, int lo, int hi) =>
        x is num ? x.toInt().clamp(lo, hi) : def;
    String s(Object? x, String def) => x is String ? x : def;
    Map sub(Object? x) => x is Map ? x : const {};
    final title = sub(m['title']);
    final mark = sub(m['watermark']);
    final close = sub(m['closing']);
    final heights = <String, double>{};
    final th = m['textHeight'];
    if (th is Map) {
      th.forEach((k, val) {
        if (k is String) heights[k] = d(val, 0.62, 0.2, 0.9);
      });
    }
    return ShareVideoLook(
      maxAyat: i(m['maxAyat'], 30, 1, 300),
      maxSeconds: i(m['maxSeconds'], 600, 10, 3600),
      fps: i(m['fps'], 30, 15, 60),
      bitrate: i(m['bitrate'], 5000000, 1000000, 20000000),
      dim: d(m['dim'], 0.38, 0, 0.9),
      textWidth: d(m['textWidth'], 0.9, 0.4, 1),
      textHeight: heights,
      textMaxScale: d(m['textMaxScale'], 1.6, 0.5, 4),
      textHalo: d(m['textHalo'], 0.9, 0, 1),
      textBackdrop: d(m['textBackdrop'], 0, 0, 0.8),
      showTitle: title['show'] != false,
      titleTemplate: s(title['template'], 'سورة {surah}'),
      titleImages: _titleImages(title['images']),
      titleImageHeight: d(title['imageHeight'], 0.085, 0.03, 0.2),
      titleImageMaxWidth: d(title['imageMaxWidth'], 0.72, 0.3, 0.95),
      showWatermark: mark['show'] != false,
      watermarkName: s(mark['name'], 'المصحف الجامع'),
      watermarkLink: s(mark['link'], 'mushaf-qaloon.com'),
      watermarkOpacity: d(mark['opacity'], 0.9, 0.2, 1),
      showClosing: close['show'] != false,
      closingSeconds: d(close['seconds'], 2, 0.5, 10),
      closingTitle: s(close['title'], 'المصحف الجامع'),
      closingSubtitle: s(close['subtitle'], ''),
      closingStores: [
        if (close['stores'] is List)
          for (final x in close['stores'] as List)
            if (x is String) x,
      ],
      closingLink: s(close['link'], 'mushaf-qaloon.com'),
    );
  }
}

class ShareVideoShape {
  const ShareVideoShape({
    required this.id,
    required this.title,
    required this.width,
    required this.height,
  });

  final String id;
  final String title;
  final int width;
  final int height;

  static ShareVideoShape _parse(Object? v) {
    if (v is! Map) throw const FormatException('share_video: bad shape');
    final w = v['width'];
    final h = v['height'];
    if (w is! int || h is! int || w < 240 || h < 240 || w > 2160 || h > 2160) {
      throw const FormatException('share_video: bad shape size');
    }
    if (w.isOdd || h.isOdd) {
      throw const FormatException('share_video: odd shape size');
    }
    return ShareVideoShape(
      id: ShareVideoConfig._str(v['id'], 'shape id'),
      title: ShareVideoConfig._str(v['title'], 'shape title'),
      width: w,
      height: h,
    );
  }
}

/// A sound effect: [params] go to the phone's audio processor as they are
/// (`type` none / echo / reverb plus its numbers; the processor clamps them).
class ShareVideoEffect {
  const ShareVideoEffect({
    required this.id,
    required this.title,
    required this.params,
  });

  final String id;
  final String title;
  final Map<String, Object?> params;

  bool get isNone => params['type'] == 'none';

  static ShareVideoEffect _parse(Object? v) {
    if (v is! Map) throw const FormatException('share_video: bad effect');
    final type = v['type'];
    if (type != 'none' && type != 'echo' && type != 'reverb') {
      throw FormatException('share_video: unknown effect $type');
    }
    return ShareVideoEffect(
      id: ShareVideoConfig._str(v['id'], 'effect id'),
      title: ShareVideoConfig._str(v['title'], 'effect title'),
      params: Map<String, Object?>.unmodifiable({
        for (final e in v.entries)
          if (e.key is String && e.key != 'id' && e.key != 'title')
            e.key as String: e.value,
      }),
    );
  }
}

class ShareVideoCategory {
  const ShareVideoCategory({required this.id, required this.title});
  final String id;
  final String title;
}

class ShareVideoFile {
  const ShareVideoFile({required this.path, required this.bytes});
  final String path;
  final int bytes;
}

class ShareVideoBackground {
  const ShareVideoBackground({
    required this.id,
    required this.title,
    required this.category,
    required this.thumb,
    required this.files,
  });

  final String id;
  final String title;
  final String category;
  final String thumb;

  /// One clip per shape id, downloaded only when picked.
  final Map<String, ShareVideoFile> files;

  static final RegExp _safePath = RegExp(r'^[A-Za-z0-9_\-/.]+$');

  static ShareVideoBackground _parse(Object? v, List<ShareVideoShape> shapes) {
    if (v is! Map) throw const FormatException('share_video: bad background');
    final id = ShareVideoConfig._str(v['id'], 'background id');
    String path(Object? p) {
      final s = ShareVideoConfig._str(p, '$id path');
      if (!_safePath.hasMatch(s) || s.contains('..') || s.startsWith('/')) {
        throw FormatException('share_video: bad path $s');
      }
      return s;
    }

    final filesJ = v['files'];
    if (filesJ is! Map) throw FormatException('share_video: $id has no files');
    final files = <String, ShareVideoFile>{};
    for (final s in shapes) {
      final f = filesJ[s.id];
      if (f is! Map) {
        throw FormatException('share_video: $id has no ${s.id} file');
      }
      final bytes = f['bytes'];
      files[s.id] = ShareVideoFile(
        path: path(f['path']),
        bytes: bytes is int && bytes > 0 ? bytes : 0,
      );
    }
    return ShareVideoBackground(
      id: id,
      title: ShareVideoConfig._str(v['title'], '$id title'),
      category: ShareVideoConfig._str(v['category'], '$id category'),
      thumb: path(v['thumb']),
      files: Map.unmodifiable(files),
    );
  }
}

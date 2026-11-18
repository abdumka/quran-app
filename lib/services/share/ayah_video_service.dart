import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/audio_clip.dart';
import '../../models/reciter.dart';
import '../audio_ayah_map_service.dart';
import '../audio_service.dart';
import '../quran_json_service.dart';
import '../surah_timings_service.dart';
import 'ayah_share_text.dart';
import 'ayah_video_art.dart';
import 'share_video_config.dart';

/// One recited stretch of the video: the ayat shown together and the audio
/// that recites them. Ayat a reciter joins in one breath share a group.
class AyahVideoGroup {
  AyahVideoGroup(this.ayat, this.clips);
  final List<int> ayat;
  final List<AudioClip> clips;
}

class AyahVideoPlan {
  const AyahVideoPlan(this.surah, this.from, this.to, this.groups);
  final int surah;
  final int from;
  final int to;
  final List<AyahVideoGroup> groups;
}

/// What the sheet shows while a video is made.
class AyahVideoProgress {
  final ValueNotifier<String> stage = ValueNotifier('');
  final ValueNotifier<double?> fraction = ValueNotifier(null);
  bool _cancelled = false;
  bool get cancelled => _cancelled;

  void _set(String s, double f) {
    stage.value = s;
    fraction.value = f;
  }

  void dispose() {
    stage.dispose();
    fraction.dispose();
  }
}

class AyahVideoCancelled implements Exception {
  const AyahVideoCancelled();
}

class AyahVideoError implements Exception {
  const AyahVideoError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// «فيديو الآية»: everything happens on the phone. The background clip and
/// its picture come from our server only when the reader picks them, and
/// stay cached; the recitation is the app's own audio (a file already
/// downloaded for playback is reused).
class AyahVideoService {
  AyahVideoService._();
  static final AyahVideoService instance = AyahVideoService._();

  static const MethodChannel _channel = MethodChannel(
    'com.mahfodqr.qalon_mushaf/ayah_video',
  );

  bool? _supported;
  Directory? _bgDir;

  /// Android only for now: the encoder is native code.
  Future<bool> isSupported() async {
    if (_supported != null) return _supported!;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return _supported = false;
    }
    try {
      return _supported =
          await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return _supported = false;
    }
  }

  // ───────────────────── backgrounds (on demand, cached) ─────────────────────

  Future<Directory> _backgrounds() async {
    if (_bgDir != null) return _bgDir!;
    final support = await getApplicationSupportDirectory();
    final d = Directory(p.join(support.path, 'video_bg'));
    await d.create(recursive: true);
    return _bgDir = d;
  }

  Future<File> _local(String path) async =>
      File(p.join((await _backgrounds()).path, p.joinAll(path.split('/'))));

  final Map<String, Future<File?>> _thumbs = {};

  /// The background's small picture, downloaded the first time it is shown.
  Future<File?> thumb(ShareVideoConfig config, ShareVideoBackground bg) =>
      _thumbs[bg.thumb] ??= () async {
        final f = await _local(bg.thumb);
        if (await f.exists() && await f.length() > 0) return f;
        try {
          await _download(Uri.parse(config.urlOf(bg.thumb)), f);
          return f;
        } catch (e) {
          debugPrint('AyahVideo: thumb ${bg.id}: $e');
          _thumbs.remove(bg.thumb);
          return null;
        }
      }();

  /// The surah's name cut from the mushaf (option «خط المصحف»), downloaded
  /// once and kept; null when the config has none or it cannot be fetched,
  /// and the video then writes the name as text.
  Future<File?> surahTitle(ShareVideoConfig config, int surah) async {
    final path = config.video.titleImageFor(surah);
    if (path == null) return null;
    final f = await _local(path);
    if (await f.exists() && await f.length() > 0) return f;
    try {
      await _download(Uri.parse(config.urlOf(path)), f);
      return f;
    } catch (e) {
      debugPrint('AyahVideo: surah title $surah: $e');
      return null;
    }
  }

  Future<bool> isClipCached(ShareVideoBackground bg, String shape) async {
    final file = bg.files[shape];
    if (file == null) return false;
    final f = await _local(file.path);
    return f.exists();
  }

  /// The clip of [bg] in [shape]: from the phone when it was used before,
  /// else downloaded now (only this one file).
  Future<File> clip(
    ShareVideoConfig config,
    ShareVideoBackground bg,
    String shape, {
    void Function(double)? onProgress,
  }) async {
    final file = bg.files[shape];
    if (file == null) {
      throw const AyahVideoError('لا تتوفر هذه الخلفية بهذا الشكل');
    }
    final f = await _local(file.path);
    if (await f.exists() &&
        (file.bytes == 0 || await f.length() == file.bytes)) {
      return f;
    }
    await _download(
      Uri.parse(config.urlOf(file.path)),
      f,
      expectBytes: file.bytes,
      onProgress: onProgress,
    );
    return f;
  }

  Future<void> _download(
    Uri url,
    File target, {
    int expectBytes = 0,
    void Function(double)? onProgress,
  }) async {
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET', url))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw AyahVideoError('HTTP ${res.statusCode}');
      }
      final total = res.contentLength ?? expectBytes;
      final sink = part.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.stream.timeout(
          const Duration(seconds: 30),
        )) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress?.call((got / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }
      if (expectBytes > 0 && got != expectBytes) {
        throw AyahVideoError('size $got != $expectBytes');
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } finally {
      client.close();
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }

  // ───────────────────── the recitation ─────────────────────

  /// The ayat [from]..[to] of [surah] as [reciter] recites them. The range
  /// grows to whole breaths: an ayah recited inside its neighbour's audio
  /// brings that neighbour in (as «تلاوة» from the ayah menu does).
  Future<AyahVideoPlan> plan(
    Reciter reciter,
    int surah,
    int from,
    int to,
  ) async {
    if (reciter.scheme == AudioScheme.timedSurah) {
      await SurahTimingsService.instance.load(reciter, surah);
    } else {
      await AudioAyahMapService.instance.load();
    }
    final count = await ayahCount(surah);
    List<AudioClip> clipsOf(int a) =>
        AudioService.instance.clipsForAyahOf(reciter, surah, a);
    bool joined(int a) {
      if (a <= 1 || reciter.isMissing(surah, a)) return false;
      final c = clipsOf(a);
      return c.isEmpty || listEquals(c, clipsOf(a - 1));
    }

    while (from > 1 && joined(from)) {
      from--;
    }
    while (to < count && joined(to + 1)) {
      to++;
    }
    final groups = <AyahVideoGroup>[];
    for (var a = from; a <= to; a++) {
      if (reciter.isMissing(surah, a)) continue;
      if (groups.isNotEmpty && joined(a)) {
        groups.last.ayat.add(a);
        continue;
      }
      final c = clipsOf(a);
      if (c.isEmpty) continue;
      groups.add(AyahVideoGroup([a], c));
    }
    return AyahVideoPlan(surah, from, to, groups);
  }

  final Map<int, int> _counts = {};

  Future<int> ayahCount(int surah) async {
    if (_counts.isEmpty) {
      for (final page in await QuranJsonService.loadQuranPages()) {
        for (final a in page.ayahs) {
          if (a.ayah > (_counts[a.surah] ?? 0)) _counts[a.surah] = a.ayah;
        }
      }
    }
    return _counts[surah] ?? 0;
  }

  /// The clip as the encoder reads it: the file on the phone when the app
  /// already has it, else the mirror. On Android a whole-surah file is read
  /// straight from the server, only the part needed. iPhone's reader cannot
  /// stream, so there it is downloaded whole, like a per-ayah file, into the
  /// player's own cache (where it also serves offline listening later).
  Future<Map<String, Object?>> _clipArg(
    Reciter reciter,
    AudioClip c, {
    void Function(double)? onProgress,
  }) async {
    final dir = Directory(
      p.join(
        (await getApplicationSupportDirectory()).path,
        reciter.cacheFolder,
      ),
    );
    final local = File(p.join(dir.path, c.file));
    String uri;
    if (await local.exists() && await local.length() > 0) {
      uri = Uri.file(local.path).toString();
    } else if (c.isClipped && !Platform.isIOS) {
      uri = '${reciter.audioBaseUrl}${c.file}';
    } else {
      await _download(
        Uri.parse('${reciter.audioBaseUrl}${c.file}'),
        local,
        onProgress: onProgress,
      );
      uri = Uri.file(local.path).toString();
    }
    return {
      'uri': uri,
      if (c.start != null) 'startMs': c.start!.inMilliseconds,
      if (c.end != null) 'endMs': c.end!.inMilliseconds,
    };
  }

  // ───────────────────── making the video ─────────────────────

  Future<File> render({
    required ShareVideoConfig config,
    required Reciter reciter,
    required AyahVideoPlan plan,
    required ShareVideoShape shape,
    required ShareVideoBackground background,
    required ShareVideoEffect effect,
    required AyahVideoProgress progress,
  }) async {
    void check() {
      if (progress.cancelled) throw const AyahVideoCancelled();
    }

    final look = config.video;
    if (plan.groups.isEmpty) {
      throw const AyahVideoError('لا تتوفر تلاوة هذه الآيات بصوت هذا القارئ');
    }
    final timedMs = plan.groups
        .expand((g) => g.clips)
        .map((c) => c.duration?.inMilliseconds ?? 0)
        .fold<int>(0, (a, b) => a + b);
    if (timedMs > look.maxSeconds * 1000) {
      throw AyahVideoError(
        'المقطع أطول من ${look.maxSeconds ~/ 60} دقائق، اختر آيات أقل',
      );
    }

    final work = Directory(
      p.join((await getTemporaryDirectory()).path, 'ayah_video'),
    );
    if (await work.exists()) {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
    await work.create(recursive: true);

    // 1. the recitation
    progress._set('تجهيز التلاوة', 0.02);
    final segments = <Map<String, Object?>>[];
    final allClips = plan.groups.fold<int>(0, (n, g) => n + g.clips.length);
    var done = 0;
    final clipArgs = <List<Map<String, Object?>>>[];
    for (final g in plan.groups) {
      final args = <Map<String, Object?>>[];
      for (final c in g.clips) {
        check();
        try {
          args.add(
            await _clipArg(
              reciter,
              c,
              onProgress: (f) => progress._set(
                'تنزيل التلاوة',
                0.02 + 0.1 * (done + f) / allClips,
              ),
            ),
          );
        } catch (e) {
          throw const AyahVideoError('تعذّر تنزيل التلاوة، تحقّق من الاتصال');
        }
        done++;
        progress._set('تجهيز التلاوة', 0.02 + 0.1 * done / allClips);
      }
      clipArgs.add(args);
    }

    // 2. the background
    check();
    progress._set('تنزيل الخلفية', 0.12);
    final File bg;
    try {
      bg = await clip(
        config,
        background,
        shape.id,
        onProgress: (f) => progress._set('تنزيل الخلفية', 0.12 + 0.15 * f),
      );
    } catch (e) {
      throw const AyahVideoError('تعذّر تنزيل الخلفية، تحقّق من الاتصال');
    }

    // 3. the pictures
    check();
    progress._set('تجهيز النص', 0.28);
    final title = look.titleTemplate.replaceAll(
      '{surah}',
      AyahShareText.surahName(plan.surah),
    );
    final titleFile = look.showTitle
        ? await surahTitle(config, plan.surah)
        : null;
    final titleImage = titleFile == null
        ? null
        : await AyahVideoArt.decodeFile(titleFile);
    for (var i = 0; i < plan.groups.length; i++) {
      check();
      final image = await AyahVideoArt.ayatImage(
        plan.surah,
        plan.groups[i].ayat,
      );
      final png = await AyahVideoArt.framePng(
        width: shape.width,
        height: shape.height,
        shapeId: shape.id,
        look: look,
        ayat: image,
        title: title,
        titleImage: titleImage,
      );
      image?.dispose();
      final f = File(p.join(work.path, 'frame_$i.png'));
      await f.writeAsBytes(png);
      segments.add({'clips': clipArgs[i], 'overlay': f.path});
      progress._set('تجهيز النص', 0.28 + 0.07 * (i + 1) / plan.groups.length);
    }
    titleImage?.dispose();
    Map<String, Object?>? closing;
    if (look.showClosing) {
      final card = File(p.join(work.path, 'closing.png'));
      await card.writeAsBytes(
        await AyahVideoArt.closingPng(
          width: shape.width,
          height: shape.height,
          look: look,
        ),
      );
      final silence = File(p.join(work.path, 'silence.wav'));
      await silence.writeAsBytes(AyahVideoArt.silenceWav(look.closingSeconds));
      closing = {
        'overlay': card.path,
        'silence': Uri.file(silence.path).toString(),
        'ms': (look.closingSeconds * 1000).round(),
      };
    }

    // 4. the encoder
    check();
    progress._set('إنشاء الفيديو', 0.35);
    final name = plan.from == plan.to
        ? 'ayah_${plan.surah}_${plan.from}.mp4'
        : 'ayah_${plan.surah}_${plan.from}-${plan.to}.mp4';
    final out = File(p.join(work.path, name));
    final poll = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      try {
        final f = await _channel.invokeMethod<double>('progress');
        if (f != null && !progress.cancelled) {
          progress._set('إنشاء الفيديو', 0.35 + 0.65 * f);
        }
      } catch (_) {}
    });
    try {
      await _channel.invokeMethod('render', {
        'output': out.path,
        'fps': look.fps,
        'bitrate': look.bitrate,
        'width': shape.width,
        'height': shape.height,
        'background': {'uri': Uri.file(bg.path).toString()},
        'segments': segments,
        'closing': ?closing,
        if (!effect.isNone) 'effect': effect.params,
      });
    } on PlatformException catch (e) {
      if (progress.cancelled || e.code == 'cancelled') {
        throw const AyahVideoCancelled();
      }
      debugPrint('AyahVideo: render failed: ${e.code} ${e.message}');
      throw const AyahVideoError('تعذّر إنشاء الفيديو');
    } finally {
      poll.cancel();
    }
    check();
    progress._set('تم', 1);
    return out;
  }

  Future<void> cancel(AyahVideoProgress progress) async {
    progress._cancelled = true;
    try {
      await _channel.invokeMethod('cancel');
    } catch (_) {}
  }

  // ───────────────────── the gallery ─────────────────────

  /// The album the videos go into on Android (a folder the gallery shows).
  static const galleryAlbum = 'المصحف الجامع';

  /// Puts a finished video in the phone's gallery. Every video made is saved
  /// this way. Android: the «المصحف الجامع» album, with no permission asked
  /// on Android 11+. iOS: the Photos library with add-only access (no album,
  /// so iOS asks only to add, never to read the user's photos).
  Future<GallerySave> saveToGallery(File video) async {
    try {
      await Gal.putVideo(
        video.path,
        album: Platform.isAndroid ? galleryAlbum : null,
      );
      return GallerySave.saved;
    } on GalException catch (e) {
      debugPrint('AyahVideo: gallery save failed: ${e.type}');
      return switch (e.type) {
        GalExceptionType.permissionDenied => GallerySave.denied,
        GalExceptionType.notEnoughSpace => GallerySave.noSpace,
        _ => GallerySave.failed,
      };
    } catch (e) {
      debugPrint('AyahVideo: gallery save failed: $e');
      return GallerySave.failed;
    }
  }
}

enum GallerySave { saved, denied, noSpace, failed }

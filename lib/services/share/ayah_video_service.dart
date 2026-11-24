import 'dart:async';
import 'dart:io';
import 'dart:math' show max;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/audio_clip.dart';
import '../../models/reciter.dart';
import '../audio_ayah_map_service.dart';
import '../audio_service.dart';
import '../keep_screen_awake_service.dart';
import '../quran_json_service.dart';
import '../surah_timings_service.dart';
import '../tv_service.dart';
import 'ayah_share_text.dart';
import 'ayah_video_art.dart';
import 'mp3_length.dart';
import 'share_video_config.dart';

/// Wording the server can change (`strings` in share_video.json).
String _t(
  String key,
  String fallback, [
  Map<String, Object?> args = const {},
]) => ShareVideoConfig.tr(key, fallback, args);

/// One recited stretch of the video: the ayat shown together and the audio
/// that recites them. Ayat a reciter joins in one breath share a group.
class AyahVideoGroup {
  AyahVideoGroup(this.ayat, this.clips);
  final List<int> ayat;
  final List<AudioClip> clips;
}

/// One breath: ayat [from]..[to] that a reciter recites without stopping
/// between them. One ayah for most reciters; several where a reciter joins
/// ayat (the Habti waqf). A video always starts on a breath's first ayah and
/// ends on a breath's last one, never where the reciter does not stop.
class AyahBreath {
  const AyahBreath(this.from, this.to, this.clips);
  final int from;
  final int to;

  /// The audio of the whole breath (empty for an ayah a mirror lacks).
  final List<AudioClip> clips;

  bool get isJoined => to > from;
}

/// Every ayah of a surah in exactly one [AyahBreath], in order.
class AyahBreaths {
  AyahBreaths(this.list);
  final List<AyahBreath> list;

  int indexOf(int ayah) {
    for (var i = 0; i < list.length; i++) {
      if (list[i].from <= ayah && ayah <= list[i].to) return i;
    }
    return ayah <= 1 ? 0 : list.length - 1;
  }

  AyahBreath at(int ayah) => list[indexOf(ayah)];

  Iterable<AyahBreath> within(int from, int to) =>
      list.where((b) => b.to >= from && b.from <= to);
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
  Future<File?> surahTitle(ShareVideoConfig config, int surah) =>
      _picture(config, config.video.titleImageFor(surah));

  /// A picture under the config's baseUrl, downloaded once and kept (phones
  /// cache by path, so a changed picture needs a new path); null when unset
  /// or it cannot be fetched.
  Future<File?> _picture(ShareVideoConfig config, String? path) async {
    if (path == null) return null;
    final f = await _local(path);
    if (await f.exists() && await f.length() > 0) return f;
    try {
      await _download(Uri.parse(config.urlOf(path)), f);
      return f;
    } catch (e) {
      debugPrint('AyahVideo: picture $path: $e');
      return null;
    }
  }

  // ───────────────────── fonts of the reciter line ─────────────────────

  final Map<String, Future<File?>> _previews = {};
  final Map<String, Future<String?>> _fonts = {};

  /// The picture of [font] the picker shows, downloaded once and kept.
  Future<File?> fontPreview(ShareVideoConfig config, ShareVideoFont font) {
    final path = font.preview;
    if (path == null) return Future.value(null);
    return _previews[path] ??= _picture(config, path).then((f) {
      if (f == null) _previews.remove(path);
      return f;
    });
  }

  /// [font] registered with the engine, downloaded the first time it is
  /// used: its family name; null for the phone's own font, and when the file
  /// cannot be had (the video is then written in the phone's font rather
  /// than not made). The family carries the file's path, so a font replaced
  /// on the server under a new path is registered afresh.
  Future<String?> fontFamily(ShareVideoConfig config, ShareVideoFont font) {
    final path = font.file;
    if (path == null) return Future.value(null);
    return _fonts[path] ??= () async {
      try {
        final f = await _local(path);
        if (!(await f.exists() &&
            (font.bytes == 0 || await f.length() == font.bytes))) {
          await _download(
            Uri.parse(config.urlOf(path)),
            f,
            expectBytes: font.bytes,
          );
        }
        final family =
            'share_video_${path.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';
        await ui.loadFontFromList(await f.readAsBytes(), fontFamily: family);
        return family;
      } catch (e) {
        debugPrint('AyahVideo: font ${font.id}: $e');
        _fonts.remove(path);
        return null;
      }
    }();
  }

  /// The reciter line of a video by [reciter] (`video.credit`).
  static String creditLine(ShareVideoLook look, Reciter reciter) => look
      .creditTemplate
      .replaceAll('{reciter}', reciter.name.trim())
      .replaceAll('{riwaya}', reciter.riwaya.trim());

  /// The background clips kept on the phone (every `.mp4` under `video_bg`,
  /// plus any half-finished `.part`). Pictures, fonts and surah names are
  /// small and stay.
  Future<List<File>> _cachedClips() async {
    final d = await _backgrounds();
    final out = <File>[];
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File && (e.path.endsWith('.mp4') || e.path.endsWith('.part'))) {
        out.add(e);
      }
    }
    return out;
  }

  /// Total size of the cached background clips, for «إدارة الملفات المحمّلة».
  Future<int> cachedClipsBytes() async {
    var total = 0;
    for (final f in await _cachedClips()) {
      try {
        total += await f.length();
      } catch (_) {}
    }
    return total;
  }

  /// Deletes the cached background clips; each is downloaded again the next
  /// time a video uses it.
  Future<void> deleteCachedClips() async {
    for (final f in await _cachedClips()) {
      try {
        await f.delete();
      } catch (e) {
        debugPrint('AyahVideo: delete ${f.path}: $e');
      }
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
      throw AyahVideoError(
        _t('noBackgroundShape', 'لا تتوفر هذه الخلفية بهذا الشكل'),
      );
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

  /// [reciter]'s breaths in [surah], by the same rule as [plan].
  Future<AyahBreaths> breaths(Reciter reciter, int surah) async {
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

    final list = <AyahBreath>[];
    for (var a = 1; a <= count; a++) {
      if (list.isNotEmpty && joined(a)) {
        final last = list.removeLast();
        list.add(AyahBreath(last.from, a, last.clips));
      } else {
        list.add(
          AyahBreath(a, a, reciter.isMissing(surah, a) ? const [] : clipsOf(a)),
        );
      }
    }
    return AyahBreaths(list);
  }

  /// How long [clips] play: exact for a timed-surah reciter (the spans), from
  /// the MP3 headers for per-ayah files (the app's own copy when it has one,
  /// else the first bytes from the mirror). Null when it cannot be known.
  Future<Duration?> clipsLength(Reciter reciter, List<AudioClip> clips) async {
    var total = Duration.zero;
    for (final c in clips) {
      final d = c.duration;
      if (d != null) {
        total += d;
        continue;
      }
      final local = File(
        p.join(
          (await getApplicationSupportDirectory()).path,
          reciter.cacheFolder,
          c.file,
        ),
      );
      final whole = await Mp3Length.of(
        Uri.parse('${reciter.audioBaseUrl}${c.file}'),
        local: local,
      );
      if (whole == null) return null;
      final start = c.start ?? Duration.zero;
      total += whole > start ? whole - start : Duration.zero;
    }
    return total;
  }

  /// How long ayat [from]..[to] play (whole breaths), or null if unknown.
  Future<Duration?> rangeLength(
    Reciter reciter,
    AyahBreaths breaths,
    int from,
    int to,
  ) async {
    // Eight at a time: a whole surah of per-ayah files reads hundreds of
    // MP3 headers from the mirror the first time.
    final list = breaths.within(from, to).toList();
    var total = Duration.zero;
    for (var i = 0; i < list.length; i += 8) {
      final lengths = await Future.wait([
        for (final b in list.skip(i).take(8)) clipsLength(reciter, b.clips),
      ]);
      for (final d in lengths) {
        if (d == null) return null;
        total += d;
      }
    }
    return total;
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
  /// [stream] false downloads a whole-surah file even on Android: a long
  /// video reads it for many minutes, and one network drop would end it.
  Future<Map<String, Object?>> _clipArg(
    Reciter reciter,
    AudioClip c, {
    void Function(double)? onProgress,
    bool stream = true,
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
    } else if (stream && c.isClipped && !Platform.isIOS) {
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

  /// «4 دقائق», «30 دقيقة», «ساعتين», «90 ثانية»: the limit as the sheet
  /// words it (3 to 10 take the plural, 11 and up the singular).
  static String formatLimit(int seconds) {
    if (seconds % 3600 == 0) {
      final h = seconds ~/ 3600;
      return switch (h) {
        1 => _t('hour', 'ساعة'),
        2 => _t('twoHours', 'ساعتين'),
        <= 10 => _t('hours', '{n} ساعات', {'n': h}),
        _ => _t('hoursMany', '{n} ساعة', {'n': h}),
      };
    }
    if (seconds % 60 == 0) {
      final m = seconds ~/ 60;
      return switch (m) {
        1 => _t('minute', 'دقيقة'),
        2 => _t('twoMinutes', 'دقيقتين'),
        <= 10 => _t('minutes', '{n} دقائق', {'n': m}),
        _ => _t('minutesMany', '{n} دقيقة', {'n': m}),
      };
    }
    return _t('seconds', '{n} ثانية', {'n': seconds});
  }

  /// A video longer than this (seconds of recitation) gets the long-video
  /// care: a note with its size, the surah file downloaded first, a check
  /// of the free space, and a question before it is stopped.
  static const int longVideoSeconds = 600;

  /// The most [length] of video can come to at [bitrate], plus the 128 kbps
  /// sound. Encoders differ: a Galaxy S10e stayed at 2.1 of 5 Mbps on calm
  /// backgrounds, the emulator's encoder used all 5 (2026-11-22), so the
  /// free-space check and the note count the whole rate.
  static int estimateBytes(Duration length, int bitrate) =>
      (length.inMilliseconds / 1000 * (bitrate + 128000) / 8).round();

  /// «450 MB», «1.9 GB», kept left to right inside Arabic text (without
  /// the isolate marks it shows as «GB 1.9»).
  static String formatBytes(int bytes) {
    final mb = bytes / 1000000;
    final s = mb < 1000
        ? '${(mb / 10).ceil() * 10} MB'
        : '${(mb / 1000).toStringAsFixed(1)} GB';
    return String.fromCharCodes([0x2066, ...s.codeUnits, 0x2069]);
  }

  /// Free space where the video is made, or null if the phone cannot say.
  Future<int?> freeBytes() async {
    try {
      return await _channel.invokeMethod<int>('freeBytes');
    } catch (_) {
      return null;
    }
  }

  /// Keeps the screen on while a video is made: a phone that locks pauses
  /// the app, and an iPhone then stops the encoder. Afterwards the screen
  /// goes back to the reader's own «إبقاء الشاشة مضاءة» choice.
  static Future<void> _keepAwake(bool on) async {
    try {
      await WakelockPlus.toggle(
        enable:
            on ||
            KeepScreenAwakeService.instance.enabled.value ||
            TvService.instance.isTv,
      );
    } catch (_) {}
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
    ShareVideoFont? font,
    double creditSize = 1,
    bool wholeSurah = false,
  }) async {
    await _keepAwake(true);
    try {
      return await _render(
        config: config,
        reciter: reciter,
        plan: plan,
        shape: shape,
        background: background,
        effect: effect,
        progress: progress,
        font: font,
        creditSize: creditSize,
        wholeSurah: wholeSurah,
      );
    } finally {
      await _keepAwake(false);
    }
  }

  Future<File> _render({
    required ShareVideoConfig config,
    required Reciter reciter,
    required AyahVideoPlan plan,
    required ShareVideoShape shape,
    required ShareVideoBackground background,
    required ShareVideoEffect effect,
    required AyahVideoProgress progress,
    required ShareVideoFont? font,
    required double creditSize,
    required bool wholeSurah,
  }) async {
    void check() {
      if (progress.cancelled) throw const AyahVideoCancelled();
    }

    final look = config.video;
    if (plan.groups.isEmpty) {
      throw AyahVideoError(
        _t('noRecitation', 'لا تتوفر تلاوة هذه الآيات بصوت هذا القارئ'),
      );
    }
    // The limit (owner, 2026-11-18: 4 minutes; a whole surah has its own,
    // [ShareVideoLook.wholeSurahMaxSeconds]) never refuses a single breath:
    // the longest ayah alone is always allowed.
    final limit = wholeSurah ? look.wholeSurahMaxSeconds : look.maxSeconds;
    final bitrate = wholeSurah ? look.wholeSurahBitrate : look.bitrate;
    Duration? total;
    if (plan.groups.length > 1) {
      total = Duration.zero;
      for (final g in plan.groups) {
        final d = await clipsLength(reciter, g.clips);
        if (d == null) {
          total = null;
          break;
        }
        total = total! + d;
      }
      if (total != null && total.inMilliseconds > limit * 1000 * 1.05) {
        throw AyahVideoError(
          _t('tooLongPick', 'المقطع أطول من {limit}، اختر آيات أقل', {
            'limit': formatLimit(limit),
          }),
        );
      }
    }
    // The last video goes first (it is in the gallery by now), so its
    // space counts as free below.
    final work = Directory(
      p.join((await getTemporaryDirectory()).path, 'ayah_video'),
    );
    if (await work.exists()) {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
    await work.create(recursive: true);

    final long = total != null && total.inSeconds > longVideoSeconds;
    if (long) {
      // Room for the video and a little over; the gallery copy is checked
      // by the gallery itself (GallerySave.noSpace).
      final need = estimateBytes(total, bitrate) + 200000000;
      final free = await freeBytes();
      if (free != null && free < need) {
        throw AyahVideoError(
          _t(
            'noSpace',
            'لا توجد مساحة كافية في الهاتف: يحتاج هذا الفيديو نحو {size}',
            {'size': formatBytes(need)},
          ),
        );
      }
    }

    // 1. the recitation
    progress._set(_t('stepRecitation', 'تجهيز التلاوة'), 0.02);
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
              stream: !long,
              // A whole-surah file is every clip's file at once: its
              // download fills the step by itself.
              onProgress: (f) => progress._set(
                _t('stepDownloadRecitation', 'تنزيل التلاوة'),
                0.02 + 0.1 * (c.isClipped ? f : (done + f) / allClips),
              ),
            ),
          );
        } catch (e) {
          throw AyahVideoError(
            _t(
              'recitationDownloadFailed',
              'تعذّر تنزيل التلاوة، تحقّق من الاتصال',
            ),
          );
        }
        done++;
        // Never back: after a whole-surah file the bar is already full here.
        progress._set(
          _t('stepRecitation', 'تجهيز التلاوة'),
          max(progress.fraction.value ?? 0, 0.02 + 0.1 * done / allClips),
        );
      }
      clipArgs.add(args);
    }

    // 2. the background
    check();
    progress._set(_t('stepDownloadBackground', 'تنزيل الخلفية'), 0.12);
    final File bg;
    try {
      bg = await clip(
        config,
        background,
        shape.id,
        onProgress: (f) => progress._set(
          _t('stepDownloadBackground', 'تنزيل الخلفية'),
          0.12 + 0.15 * f,
        ),
      );
    } catch (e) {
      throw AyahVideoError(
        _t('backgroundDownloadFailed', 'تعذّر تنزيل الخلفية، تحقّق من الاتصال'),
      );
    }

    // 3. the pictures
    check();
    progress._set(_t('stepText', 'تجهيز النص'), 0.28);
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
    // The app icon of the watermark and closing card: the server's, if set.
    final iconFile = look.showWatermark || look.showClosing
        ? await _picture(config, look.icon)
        : null;
    final iconImage = iconFile == null
        ? null
        : await AyahVideoArt.decodeFile(iconFile);
    // The reciter line, in the picked font (no font = «بدون سطر القارئ»).
    String? credit;
    String? creditFont;
    var creditScale = 1.0;
    if (look.showCredit && font != null) {
      credit = creditLine(look, reciter);
      creditFont = await fontFamily(config, font);
      if (creditFont != null) creditScale = font.scale;
      creditScale *= creditSize;
    }
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
        iconImage: iconImage,
        credit: credit,
        creditFont: creditFont,
        creditScale: creditScale,
      );
      image?.dispose();
      final f = File(p.join(work.path, 'frame_$i.png'));
      await f.writeAsBytes(png);
      segments.add({'clips': clipArgs[i], 'overlay': f.path});
      progress._set(
        _t('stepText', 'تجهيز النص'),
        0.28 + 0.07 * (i + 1) / plan.groups.length,
      );
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
          iconImage: iconImage,
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

    iconImage?.dispose();

    // 4. the encoder
    check();
    progress._set(_t('stepRender', 'إنشاء الفيديو'), 0.35);
    final name = plan.from == plan.to
        ? 'ayah_${plan.surah}_${plan.from}.mp4'
        : 'ayah_${plan.surah}_${plan.from}-${plan.to}.mp4';
    final out = File(p.join(work.path, name));
    final poll = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      try {
        final f = await _channel.invokeMethod<double>('progress');
        if (f != null && !progress.cancelled) {
          progress._set(_t('stepRender', 'إنشاء الفيديو'), 0.35 + 0.65 * f);
        }
      } catch (_) {}
    });
    try {
      await _channel.invokeMethod('render', {
        'output': out.path,
        'fps': look.fps,
        'bitrate': bitrate,
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
      // A long video can fill the phone part way through.
      final free = await freeBytes();
      if (free != null && free < 100000000) {
        try {
          await out.delete();
        } catch (_) {}
        throw AyahVideoError(
          _t('noSpaceLeft', 'امتلأت ذاكرة الهاتف قبل أن يكتمل الفيديو'),
        );
      }
      throw AyahVideoError(_t('renderFailed', 'تعذّر إنشاء الفيديو'));
    } finally {
      poll.cancel();
    }
    check();
    progress._set(_t('stepDone', 'تم'), 1);
    return out;
  }

  Future<void> cancel(AyahVideoProgress progress) async {
    progress._cancelled = true;
    try {
      await _channel.invokeMethod('cancel');
    } catch (_) {}
  }

  // ───────────────────── the gallery ─────────────────────

  /// Puts a finished video in the phone's gallery. Every video made is saved
  /// this way. Android: the «المصحف الجامع» album, with no permission asked
  /// on Android 11+. iOS: the Photos library with add-only access (no album,
  /// so iOS asks only to add, never to read the user's photos).
  /// The album name comes from the config (`album`).
  Future<GallerySave> saveToGallery(File video) async {
    try {
      final album = (await ShareVideoConfig.load()).album;
      await Gal.putVideo(video.path, album: Platform.isAndroid ? album : null);
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

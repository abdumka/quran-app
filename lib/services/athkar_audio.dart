import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/athkar.dart';
import '../models/audio_clip.dart';
import '../models/reciter.dart';
import 'athkar_service.dart';
import 'audio_ayah_map_service.dart';
import 'audio_service.dart';
import 'reciter_service.dart';
import 'surah_timings_service.dart';

/// One piece of audio: a whole file, or a slice of one (an ayah inside a
/// timed reciter's surah file).
@immutable
class AthkarSource {
  const AthkarSource(this.uri, {this.start, this.end});
  final Uri uri;
  final Duration? start;
  final Duration? end;

  @override
  bool operator ==(Object other) =>
      other is AthkarSource &&
      other.uri == uri &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(uri, start, end);
}

/// Plays a dhikr's audio (one or more pieces, back to back) to its end. The
/// app's player is [JustAudioAthkarPlayer]; tests bring their own.
abstract class AthkarPlayer {
  /// Completes true when [sources] played to their end, false when [stop]
  /// cut them short. Throws when they cannot be played.
  Future<bool> play(List<AthkarSource> sources);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}

class JustAudioAthkarPlayer implements AthkarPlayer {
  AudioPlayer? _player;
  Completer<bool>? _done;
  List<AthkarSource>? _loaded;

  AudioPlayer _ensure() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _finish(true);
    });
    player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace _) {
        final done = _done;
        _done = null;
        _loaded = null;
        if (done != null && !done.isCompleted) done.completeError(error);
      },
    );
    return _player = player;
  }

  void _finish(bool value) {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete(value);
  }

  @override
  Future<bool> play(List<AthkarSource> sources) async {
    final player = _ensure();
    _finish(false);
    if (listEquals(_loaded, sources)) {
      // the same dhikr again (it is said several times): no second load
      await player.seek(Duration.zero, index: 0);
    } else {
      _loaded = null;
      await player.setAudioSources([
        for (final s in sources)
          s.start == null && s.end == null
              ? AudioSource.uri(s.uri)
              : ClippingAudioSource(
                  child: AudioSource.uri(s.uri),
                  start: s.start,
                  end: s.end,
                ),
      ]);
      _loaded = sources;
    }
    final done = _done = Completer<bool>();
    unawaited(player.play());
    return done.future;
  }

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> resume() async {
    final player = _player;
    if (player != null && _done != null) unawaited(player.play());
  }

  @override
  Future<void> stop() async {
    _finish(false);
    await _player?.pause();
  }
}

/// Listening to the athkar: plays a dhikr as many times as it is said
/// (counting each one on its counter), then goes on to the next one.
///
/// Two kinds of voice:
/// * the recited Qur'an (آية الكرسي, the Quls, السجدة…) plays from the app's
///   own reciters, النهي unless the reader picks another; the list is the
///   mushaf's, so a reciter the server adds shows up here too;
/// * every other dhikr plays in an athkar voice ([AthkarReciter]), from the
///   data, so voices are added from the server without a release. A voice
///   that did not record a dhikr is skipped for it in favour of one that did.
class AthkarAudio extends ChangeNotifier {
  AthkarAudio._();
  static final AthkarAudio instance = AthkarAudio._();

  AthkarPlayer player = JustAudioAthkarPlayer();

  /// Keep heard voice clips on the phone ([voiceClipUri]); tests turn it off.
  bool cacheClips = !kIsWeb;

  /// Silences the Qur'an recitation first; tests replace it.
  VoidCallback stopOtherAudio = () => AudioService.instance.stop();

  /// Where the verses' audio comes from; tests replace it.
  Future<List<AthkarSource>?> Function(Reciter reciter, AthkarItem item)
  quranSources = _quranSourcesOf;

  List<AthkarItem> _queue = const [];
  int _index = -1;
  bool _paused = false;
  int _session = 0;
  bool _skip = false;

  /// Bumped when a recording could not be played (no network, missing file).
  final ValueNotifier<int> failures = ValueNotifier<int>(0);

  AthkarData get _data => AthkarService.instance.data;

  /// The athkar voice the reader chose (or the first).
  AthkarReciter? get reciter => AthkarStore.instance.reciterOf(_data);

  /// The voice [item] will actually play in.
  AthkarReciter? voiceFor(AthkarItem item) =>
      AthkarStore.instance.voiceFor(_data, item);

  /// The app reciter the verses play in.
  Reciter get quranReciter {
    final id = AthkarStore.instance.quranReciterIdOf(_data);
    for (final r in ReciterService.instance.reciters) {
      if (r.id == id) return r;
    }
    for (final r in ReciterService.instance.reciters) {
      if (r.id == _data.quranReciterId) return r;
    }
    return Reciter.byId(id);
  }

  bool get hasReciters => _data.reciters.isNotEmpty;

  bool canPlay(AthkarItem item) => item.isQuran || voiceFor(item) != null;

  /// Who [item] plays in, for the player bar.
  String? voiceNameFor(AthkarItem item) =>
      item.isQuran ? quranReciter.name : voiceFor(item)?.name;

  /// The dhikr being played (or paused), if any.
  AthkarItem? get current =>
      _index >= 0 && _index < _queue.length ? _queue[_index] : null;

  bool get isActive => current != null;
  bool get isPaused => _paused;

  /// Where [current] is in what is being played: (position from 1, total).
  (int, int) get position => (_index + 1, _queue.length);

  /// Whether more athkar follow the one playing.
  bool get hasNext =>
      AthkarStore.instance.continuous && _index + 1 < _queue.length;

  /// The time [current] is being heard, from 1, and how many times it is
  /// played this round; null when it is said once.
  (int, int)? get repeat =>
      current == null || _repeatOf <= 1 ? null : (_repeatAt + 1, _repeatOf);
  int _repeatAt = 0;
  int _repeatOf = 0;

  Future<List<AthkarSource>?> _sourcesFor(AthkarItem item) async {
    if (item.isQuran) return quranSources(quranReciter, item);
    final voice = voiceFor(item);
    final url = voice?.urlFor(item);
    if (voice == null || url == null) return null;
    final span = voice.spanFor(item);
    return [
      AthkarSource(
        cacheClips ? await voiceClipUri(url) : Uri.parse(url),
        start: span?.$1,
        end: span?.$2,
      ),
    ];
  }

  /// A voice clip from the phone once it has been heard (the morning and
  /// evening athkar are played every day): the first time it streams and
  /// is saved in the background, every later time it plays offline.
  static Future<Uri> voiceClipUri(String url) async {
    if (kIsWeb) return Uri.parse(url);
    try {
      final remote = Uri.parse(url);
      final dir = await getApplicationSupportDirectory();
      final file = File(
        p.joinAll([dir.path, 'athkar_audio', ...remote.pathSegments]),
      );
      if (file.existsSync() && file.lengthSync() > 0) {
        return Uri.file(file.path);
      }
      unawaited(_save(remote, file));
      return remote;
    } catch (_) {
      return Uri.parse(url);
    }
  }

  static final Set<String> _saving = {};

  static Future<void> _save(Uri remote, File file) async {
    if (!_saving.add(file.path)) return;
    try {
      final response = await http
          .get(remote)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return;
      await file.parent.create(recursive: true);
      final part = File('${file.path}.part');
      await part.writeAsBytes(response.bodyBytes, flush: true);
      await part.rename(file.path);
    } catch (e) {
      debugPrint('AthkarAudio: not saved ${remote.path}: $e');
    } finally {
      _saving.remove(file.path);
    }
  }

  /// Plays [items] from [index] on.
  Future<void> start(List<AthkarItem> items, int index) async {
    final session = ++_session;
    await player.stop();
    if (session != _session) return;
    stopOtherAudio();
    _queue = List.of(items);
    _paused = false;
    final store = AthkarStore.instance;
    List<AthkarSource>? previous;
    for (var i = index; i < _queue.length; i++) {
      // «تشغيل متواصل» off: only the dhikr that was played (read each time,
      // so turning it off while listening stops after the current one)
      if (i != index && !store.continuous) break;
      final item = _queue[i];
      List<AthkarSource>? sources;
      try {
        sources = await _sourcesFor(item);
      } catch (error) {
        debugPrint('AthkarAudio: no audio for ${item.id}: $error');
        sources = null;
      }
      if (session != _session) return;
      if (_skip) {
        // «التالي» was pressed while this one was being fetched
        _skip = false;
        continue;
      }
      if (sources == null || sources.isEmpty) continue;
      // one recording that covers two athkar in a row is not played twice
      if (i != index && listEquals(sources, previous)) continue;
      previous = sources;
      // as many times as it is said: the ones still to say today, counted
      // as they are heard; a completed one is heard all its times again
      final left = item.count - store.countOf(item);
      final counted = left > 0;
      final times = counted ? left : item.count;
      _index = i;
      for (var k = 0; k < times; k++) {
        // shown as «المرة 2 من 3» (out of the dhikr's own number)
        _repeatOf = item.count;
        _repeatAt = item.count - times + k;
        notifyListeners();
        bool finished;
        try {
          finished = await player.play(sources);
        } catch (error) {
          debugPrint('AthkarAudio: cannot play ${item.id}: $error');
          if (session != _session) return;
          failures.value++;
          _clear();
          return;
        }
        if (session != _session) return;
        if (!finished) {
          if (_skip) {
            // «التالي»: on to the next dhikr. Only the times heard in full
            // were counted, so this one is not marked done.
            _skip = false;
            break;
          }
          _clear();
          return;
        }
        if (counted) store.increment(item);
      }
    }
    if (session == _session) _clear();
  }

  void _clear() {
    _queue = const [];
    _index = -1;
    _paused = false;
    _repeatAt = 0;
    _repeatOf = 0;
    notifyListeners();
  }

  /// Leaves the dhikr being played (and its repeats) for the next one.
  /// What it was counted so far stays; it is done only if it was heard as
  /// many times as it is said.
  Future<void> skip() async {
    if (!isActive) return;
    _skip = true;
    if (_paused) {
      _paused = false;
      stopOtherAudio();
    }
    await player.stop();
  }

  Future<void> togglePause() async {
    if (!isActive) return;
    _paused = !_paused;
    notifyListeners();
    if (_paused) {
      await player.pause();
    } else {
      stopOtherAudio();
      await player.resume();
    }
  }

  Future<void> stop() async {
    _session++;
    _clear();
    await player.stop();
  }

  /// Another athkar voice: what was playing stops.
  Future<void> chooseReciter(AthkarReciter reciter) async {
    await stop();
    AthkarStore.instance.chooseReciter(reciter);
    notifyListeners();
  }

  /// Another reciter for the verses: what was playing stops.
  Future<void> chooseQuranReciter(Reciter reciter) async {
    await stop();
    AthkarStore.instance.chooseQuranReciter(reciter.id);
    notifyListeners();
  }
}

/// The verses of [item] in [reciter]'s recitation: the same files the
/// mushaf plays (a downloaded one from the phone, else from the mirror),
/// with consecutive ayat inside one surah file joined into one slice.
Future<List<AthkarSource>?> _quranSourcesOf(
  Reciter reciter,
  AthkarItem item,
) async {
  if (reciter.scheme == AudioScheme.timedSurah) {
    for (final v in item.verses) {
      await SurahTimingsService.instance.load(reciter, v.surah);
    }
  } else {
    await AudioAyahMapService.instance.load();
  }
  final clips = <AudioClip>[];
  for (final v in item.verses) {
    for (var a = v.from; a <= v.to; a++) {
      clips.addAll(AudioService.instance.clipsForAyahOf(reciter, v.surah, a));
    }
  }
  if (clips.isEmpty) return null;

  final joined = <AudioClip>[];
  for (final c in clips) {
    final last = joined.isEmpty ? null : joined.last;
    if (last != null &&
        last.file == c.file &&
        last.end != null &&
        c.start != null &&
        (c.start! - last.end!).inMilliseconds.abs() < 400) {
      joined[joined.length - 1] = AudioClip(
        c.file,
        start: last.start,
        end: c.end,
      );
    } else {
      joined.add(c);
    }
  }

  Directory? dir;
  if (!kIsWeb) {
    try {
      dir = Directory(
        p.join(
          (await getApplicationSupportDirectory()).path,
          reciter.cacheFolder,
        ),
      );
    } catch (_) {
      dir = null;
    }
  }
  return [
    for (final c in joined)
      AthkarSource(
        dir != null && File(p.join(dir.path, c.file)).existsSync()
            ? Uri.file(p.join(dir.path, c.file))
            : Uri.parse('${reciter.audioBaseUrl}${c.file}'),
        start: c.start,
        end: c.end,
      ),
  ];
}

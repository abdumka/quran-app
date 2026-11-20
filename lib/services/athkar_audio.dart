import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'quran_media_handler.dart';
import 'reciter_service.dart';
import 'surah_timings_service.dart';

/// One piece of audio: a whole file, or a slice of one (an ayah inside a
/// timed reciter's surah file).
@immutable
class AthkarSource {
  const AthkarSource(this.uri, {this.start, this.end, this.origin});
  final Uri uri;
  final Duration? start;
  final Duration? end;

  /// The address [uri] was fetched from when it is a copy on the phone.
  final Uri? origin;

  /// The recording itself, wherever it is played from: the same one heard
  /// streamed and later from the phone is still the same one.
  Uri get address => origin ?? uri;

  @override
  bool operator ==(Object other) =>
      other is AthkarSource &&
      other.address == address &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(address, start, end);
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

  /// 1 is normal; the hidden «أدوات الاختبار» page sets more.
  Future<void> setSpeed(double speed);
}

/// Plays one piece at a time from its WHOLE file: seeks to the piece's start
/// and watches the position to stop at its end, the way the mushaf plays a
/// timed reciter's ayah. No playlist and no ClippingAudioSource: on the
/// iPhone a playlist of clipped pieces (the three Quls from النائحي's surah
/// files) played the first piece and then hung, still showing pause,
/// 2026-11-18.
class JustAudioAthkarPlayer implements AthkarPlayer {
  AudioPlayer? _player;
  Completer<bool>? _done;
  Uri? _loaded;
  Duration? _end;
  int _session = 0;
  double _speed = 1;

  /// Told when Android or iOS pauses the player itself (a call, headphones
  /// pulled out, Bluetooth gone: just_audio pauses for those) and when it
  /// resumes it, so the bar and the lock screen show the truth.
  void Function(bool paused)? onSystemPause;
  bool _ourPause = false;
  bool _systemPaused = false;

  /// Told when a piece has been loading or buffering for a while (true) and
  /// when it is heard again (false), so the bar says it is on its way
  /// instead of sitting silent on a slow network.
  void Function(bool loading)? onLoading;
  static const Duration loadingShownAfter = Duration(milliseconds: 1500);
  Timer? _loadingTimer;
  bool _loadingShown = false;

  /// A piece is being loaded or played (not between pieces).
  bool _busy = false;

  /// A piece that says it is playing while its position does not move for
  /// this long has hung; it is reported as a failure, never left spinning.
  static const Duration stallLimit = Duration(seconds: 12);

  /// The same for a piece waiting on the network mid-way (buffering), and
  /// for loading one: reported as a failure, which is tried again
  /// ([AthkarAudio.retryFor]).
  static const Duration bufferLimit = Duration(seconds: 30);
  Timer? _stallTimer;
  Duration _lastPosition = Duration.zero;
  DateTime _lastMove = DateTime.now();

  AudioPlayer _ensure() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    player.processingStateStream.listen((state) {
      // the file ended before the piece's end (or the piece is the whole file)
      if (state == ProcessingState.completed) _finish(true);
      _updateLoading();
    });
    player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace _) => _fail(error),
    );
    // one stream for the player's life (see AudioService for why)
    player
        .createPositionStream(
          steps: 800,
          minPeriod: const Duration(milliseconds: 16),
          maxPeriod: const Duration(milliseconds: 40),
        )
        .listen(_onPosition);
    player.playingStream.listen((playing) {
      if (_done == null) return; // between pieces: our own doing
      if (!playing && !_ourPause && !_systemPaused) {
        _systemPaused = true;
        onSystemPause?.call(true);
      } else if (playing && _systemPaused) {
        _systemPaused = false;
        onSystemPause?.call(false);
      }
    });
    unawaited(player.setSpeed(_speed));
    return _player = player;
  }

  void _onPosition(Duration position) {
    if (_done == null) return;
    if (position != _lastPosition) {
      _lastPosition = position;
      _lastMove = DateTime.now();
    }
    final end = _end;
    // a frame early at speed, so nothing of what follows is heard
    final early = Duration(milliseconds: (12 * _speed).round());
    if (end != null && position >= end - early) {
      _ourPause = true;
      unawaited(_player?.pause());
      _finish(true);
    }
  }

  void _checkStall() {
    final player = _player;
    if (_done == null || player == null) return;
    if (!player.playing) {
      _lastMove = DateTime.now();
      return;
    }
    final limit = player.processingState == ProcessingState.ready
        ? stallLimit
        : bufferLimit;
    if (DateTime.now().difference(_lastMove) > limit) {
      _fail(StateError('playback stalled at $_lastPosition'));
    }
  }

  /// Says «loading» once a piece has waited on the network for a moment
  /// (a quick load between two athkar shows nothing).
  void _updateLoading() {
    final state = _player?.processingState;
    final waiting =
        _busy &&
        state != ProcessingState.ready &&
        state != ProcessingState.completed;
    if (waiting) {
      if (_loadingShown || _loadingTimer != null) return;
      _loadingTimer = Timer(loadingShownAfter, () {
        _loadingTimer = null;
        _loadingShown = true;
        onLoading?.call(true);
      });
    } else {
      _loadingTimer?.cancel();
      _loadingTimer = null;
      if (_loadingShown) {
        _loadingShown = false;
        onLoading?.call(false);
      }
    }
  }

  void _finish(bool value) {
    final done = _done;
    _done = null;
    _end = null;
    _busy = false;
    _updateLoading();
    if (done != null && !done.isCompleted) done.complete(value);
  }

  void _fail(Object error) {
    final done = _done;
    _done = null;
    _end = null;
    _loaded = null;
    _ourPause = true;
    _busy = false;
    _updateLoading();
    unawaited(_player?.pause());
    if (done != null && !done.isCompleted) done.completeError(error);
  }

  @override
  Future<bool> play(List<AthkarSource> sources) async {
    final session = ++_session;
    _finish(false);
    _stallTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkStall(),
    );
    for (final source in sources) {
      final finished = await _playOne(source, session);
      if (!finished || session != _session) return false;
    }
    return true;
  }

  Future<bool> _playOne(AthkarSource source, int session) async {
    final player = _ensure();
    final start = source.start ?? Duration.zero;
    _busy = true;
    _updateLoading();
    if (_loaded != source.uri) {
      _loaded = null;
      Future<void> load() => player
          .setAudioSource(AudioSource.uri(source.uri), initialPosition: start)
          .timeout(bufferLimit);
      try {
        await load();
      } on PlayerInterruptedException {
        // A voice's dhikr ends before its file does, so on a slow link the
        // rest of that file is still coming in when the next one is handed
        // over, and the transfer cut short is reported against the NEW load
        // ("Connection aborted"). Nothing is wrong with it: load it again
        // (the mushaf met the same, AudioService._playClip). This is what
        // stopped the morning athkar after their first dhikr, 2026-11-20.
        if (session != _session) return false;
        await load();
      }
      _loaded = source.uri;
    } else {
      // the same file again (a dhikr said several times, or the next ayah
      // range in it): no second load
      await player.seek(start);
    }
    if (session != _session) return false;
    final done = _done = Completer<bool>();
    _end = source.end;
    _lastPosition = start;
    _lastMove = DateTime.now();
    _ourPause = false;
    _systemPaused = false;
    _busy = true;
    _updateLoading();
    unawaited(player.play());
    return done.future;
  }

  @override
  Future<void> pause() async {
    _ourPause = true;
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    final player = _player;
    if (player != null && _done != null) {
      _lastMove = DateTime.now();
      _ourPause = false;
      _systemPaused = false;
      unawaited(player.play());
    }
  }

  @override
  Future<void> stop() async {
    _session++;
    _ourPause = true;
    _busy = false;
    _finish(false);
    await _player?.pause();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _player?.setSpeed(speed);
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
  AthkarAudio._() {
    final p = player;
    if (p is JustAudioAthkarPlayer) {
      p.onSystemPause = _onSystemPause;
      p.onLoading = _onLoading;
    }
  }
  static final AthkarAudio instance = AthkarAudio._();

  AthkarPlayer player = JustAudioAthkarPlayer();

  /// A call, unplugged headphones or a lost Bluetooth link paused the
  /// player (or the end of a call resumed it): the bar follows.
  void _onSystemPause(bool paused) {
    if (!isActive || _paused == paused) return;
    _paused = paused;
    notifyListeners();
  }

  void _onLoading(bool loading) {
    if (_loading == loading) return;
    _loading = loading;
    if (isActive) notifyListeners();
  }

  bool _loading = false;
  bool _waiting = false;

  /// The recording is still on its way (a slow or busy network).
  bool get isLoading => _loading && !_waiting;

  /// The recording could not be fetched; it is tried again shortly.
  bool get isWaiting => _waiting;

  /// What the bar and the notification say while the network holds the
  /// recording up, or null.
  String? get statusNote => _paused
      ? null
      : _waiting
      ? 'ينتظر الاتصال…'
      : _loading
      ? 'جارٍ التحميل…'
      : null;

  /// How long a dhikr that could not be played keeps being tried before the
  /// listening gives up and says so. Meanwhile it waits on that same dhikr,
  /// never going on without it: a phone whose data was just turned on, its
  /// link busy with the morning's e-mails, stopped the athkar after their
  /// first dhikr (owner, 2026-11-20).
  Duration retryFor = const Duration(seconds: 60);

  /// The pauses between those tries (the last one repeats).
  List<Duration> retryWaits = const [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
  ];

  /// Ends a pause between tries early: «متابعة», «التالي» or stop.
  Completer<void>? _wake;

  Future<void> _rest(Duration length) {
    final wake = _wake = Completer<void>();
    final timer = Timer(length, () {
      if (!wake.isCompleted) wake.complete();
    });
    return wake.future.whenComplete(timer.cancel);
  }

  void _wakeUp() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  void _setWaiting(bool waiting) {
    if (_waiting == waiting) return;
    _waiting = waiting;
    notifyListeners();
  }

  /// Keep heard voice clips on the phone ([voiceClipUri]); tests turn it off.
  bool cacheClips = !kIsWeb;

  /// Silences the Qur'an recitation first; tests replace it.
  VoidCallback stopOtherAudio = () => AudioService.instance.stop();

  /// Shows the listening on the media session (notification, lock screen,
  /// headset buttons) and so keeps the app in the foreground while it
  /// plays: on a plain player a locked phone cut the network within seconds
  /// (2026-11-18). Tests replace it.
  void Function(AthkarAudio audio) session = _toMediaSession;

  @override
  void notifyListeners() {
    super.notifyListeners();
    session(this);
  }

  static void _toMediaSession(AthkarAudio a) {
    final handler = QuranMediaHandler.instance;
    if (handler == null) return;
    final item = a.current;
    if (item == null) {
      handler.endGuest();
      return;
    }
    final text = item.text.replaceAll(RegExp(r'\s+'), ' ');
    final repeat = a.repeat;
    handler.showGuest(
      GuestPlayback(
        id: '${item.id}:${repeat?.$1 ?? 0}',
        title: text.length > 90 ? '${text.substring(0, 90)}…' : text,
        artist: [
          ?a.voiceNameFor(item),
          if (a.statusNote != null)
            a.statusNote!
          else if (repeat != null)
            'المرة ${repeat.$1} من ${repeat.$2}',
        ].join(' · '),
        album: 'الأذكار',
        artUri: item.isQuran
            ? QuranMediaHandler.reciterArt(a.quranReciterFor(item).id)
            : null,
        playing: !a.isPaused,
        onPlay: () {
          if (a.isPaused) a.togglePause();
        },
        onPause: () {
          if (!a.isPaused) a.togglePause();
        },
        onStop: a.stop,
        onNext: a.hasNext ? a.skip : null,
      ),
    );
  }

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

  /// Bumped when the dhikr the reader pressed ▶ on has no recording to play
  /// (so the press is answered, never met with silence).
  final ValueNotifier<int> unavailable = ValueNotifier<int>(0);

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
      item.isQuran ? quranReciterFor(item).name : voiceFor(item)?.name;

  /// The reciter a verse is actually heard in: the chosen one, or the one
  /// standing in for him where he has no recording of it of its own.
  Reciter quranReciterFor(AthkarItem item) {
    final chosen = quranReciter;
    final stand = _standIns[item.id];
    return stand != null && stand.$1 == chosen.id ? stand.$2 : chosen;
  }

  /// Per verse dhikr: (the chosen reciter's id, who stood in for him).
  final Map<int, (String, Reciter)> _standIns = {};

  /// The verses of [item] in the chosen reciter, or where he reads them
  /// only inside the ayah before (قنيوه and الدوكالي join «فاذكروني
  /// أذكركم» 2:151 to 2:150, so neither has a file of it alone), in the
  /// first reciter that has them, the default one first: the rule the
  /// athkar voices follow (2026-11-20).
  Future<List<AthkarSource>?> _versesFor(AthkarItem item) async {
    final chosen = quranReciter;
    final own = await quranSources(chosen, item);
    if (own != null && own.isNotEmpty) {
      _standIns.remove(item.id);
      return own;
    }
    final others = [
      for (final r in ReciterService.instance.reciters)
        if (r.id == _data.quranReciterId) r,
      for (final r in ReciterService.instance.reciters)
        if (r.id != _data.quranReciterId) r,
    ];
    for (final r in others) {
      if (r.id == chosen.id) continue;
      List<AthkarSource>? found;
      try {
        found = await quranSources(r, item);
      } catch (_) {
        found = null;
      }
      if (found != null && found.isNotEmpty) {
        _standIns[item.id] = (chosen.id, r);
        return found;
      }
    }
    return null;
  }

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

  Future<List<AthkarSource>?> _sourcesFor(
    AthkarItem item, {
    bool ahead = false,
  }) async {
    if (item.isQuran) return _versesFor(item);
    final voice = voiceFor(item);
    final url = voice?.urlFor(item);
    if (voice == null || url == null) return null;
    final span = voice.spanFor(item);
    return [
      AthkarSource(
        cacheClips ? await voiceClipUri(url, wait: !ahead) : Uri.parse(url),
        start: span?.$1,
        end: span?.$2,
        origin: Uri.parse(url),
      ),
    ];
  }

  /// Fetches the next athkar's recordings onto the phone while this one
  /// plays, so going on to them does not wait on the network: on a busy
  /// link the next one could not get through in time (owner, 2026-11-20).
  void _fetchAhead(int index, int session) {
    if (!cacheClips) return;
    // after this one has had a head start on the link
    Timer(const Duration(seconds: 2), () async {
      for (var j = index + 1; j <= index + 2 && j < _queue.length; j++) {
        if (session != _session || !AthkarStore.instance.continuous) return;
        try {
          await _sourcesFor(_queue[j], ahead: true);
        } catch (_) {}
      }
    });
  }

  /// A recording from the phone once it has been heard or fetched ahead
  /// (the morning and evening athkar are played every day): the first time
  /// it streams and is saved in the background, every later time it plays
  /// offline. The athkar's verses are kept the same way, one ayah file each
  /// (a timed reciter's whole surah is not).
  ///
  /// One already on its way (fetched ahead while the dhikr before it
  /// played) is waited for a little rather than fetched a second time over
  /// the same slow link, unless [wait] is off.
  static Future<Uri> voiceClipUri(String url, {bool wait = true}) async {
    if (kIsWeb) return Uri.parse(url);
    try {
      final remote = Uri.parse(url);
      final file = await clipFile(url);
      if (file.existsSync() && file.lengthSync() > 0) {
        return Uri.file(file.path);
      }
      final coming = _saving[file.path];
      if (coming != null) {
        if (!wait) return remote;
        final saved = await coming.timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        );
        return saved ? Uri.file(file.path) : remote;
      }
      unawaited(_save(remote, file));
      return remote;
    } catch (_) {
      return Uri.parse(url);
    }
  }

  /// Where [url] is kept on the phone (the folder «أصوات الأذكار» in the
  /// downloads page fills and empties).
  static Future<File> clipFile(String url) async {
    final remote = Uri.parse(url);
    final dir = await getApplicationSupportDirectory();
    return File(p.joinAll([dir.path, clipFolder, ...remote.pathSegments]));
  }

  static const String clipFolder = 'athkar_audio';

  /// Puts [url] on the phone (the downloads page): true when it is there.
  static Future<bool> keepOnPhone(String url) async {
    final file = await clipFile(url);
    if (file.existsSync() && file.lengthSync() > 0) return true;
    return _save(Uri.parse(url), file);
  }

  /// The saves under way, by file: true once the file is on the phone.
  static final Map<String, Future<bool>> _saving = {};

  static Future<bool> _save(Uri remote, File file) => _saving[file.path] ??=
      // a block, not `=> _saving.remove(..)`: that returns this very future,
      // which whenComplete would then wait on forever (2026-11-20: every
      // download hung)
      _download(remote, file).whenComplete(() {
        _saving.remove(file.path);
      });

  static Future<bool> _download(Uri remote, File file) async {
    try {
      final response = await http
          .get(remote)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return false;
      }
      await file.parent.create(recursive: true);
      final part = File('${file.path}.part');
      await part.writeAsBytes(response.bodyBytes, flush: true);
      await part.rename(file.path);
      return true;
    } catch (e) {
      debugPrint('AthkarAudio: not saved ${remote.path}: $e');
      return false;
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
    await player.setSpeed(store.speed);
    if (session != _session) return;
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
      if (sources == null || sources.isEmpty) {
        if (i == index) unavailable.value++;
        continue;
      }
      // one recording that covers two athkar in a row is not played twice
      if (i != index && listEquals(sources, previous)) continue;
      previous = sources;
      // as many times as it is said: the ones still to say today, counted
      // as they are heard; a completed one is heard all its times again
      final left = item.count - store.countOf(item);
      final counted = left > 0;
      final times = counted ? left : item.count;
      _index = i;
      _fetchAhead(i, session);
      for (var k = 0; k < times; k++) {
        // shown as «المرة 2 من 3» (out of the dhikr's own number)
        _repeatOf = item.count;
        _repeatAt = item.count - times + k;
        notifyListeners();
        final finished = await _playTrying(item, sources, session);
        if (finished == null) return;
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

  /// Plays [sources] to their end, trying again while the network lets it
  /// down: true when heard in full, false when cut short (stop, «التالي»),
  /// null when this listening is over (stopped meanwhile, or given up on
  /// and reported).
  Future<bool?> _playTrying(
    AthkarItem item,
    List<AthkarSource> sources,
    int session,
  ) async {
    DateTime? firstFailure;
    var tries = 0;
    while (true) {
      try {
        final finished = await player.play(sources);
        if (session != _session) return null;
        return finished;
      } catch (error) {
        debugPrint('AthkarAudio: cannot play ${item.id}: $error');
        if (session != _session) return null;
        final now = DateTime.now();
        firstFailure ??= now;
        if (retryWaits.isEmpty || now.difference(firstFailure) >= retryFor) {
          failures.value++;
          _clear();
          unawaited(player.stop());
          return null;
        }
        _setWaiting(true);
        await _rest(retryWaits[math.min(tries++, retryWaits.length - 1)]);
        // paused meanwhile: tried again once «متابعة» is pressed
        while (_paused && !_skip && session == _session) {
          await _rest(const Duration(hours: 1));
        }
        if (session != _session) return null;
        if (_skip) {
          _setWaiting(false);
          return false;
        }
        // saved on the phone meanwhile (or about to be)? then from there
        try {
          sources = await _sourcesFor(item) ?? sources;
        } catch (_) {}
        if (session != _session) return null;
        _setWaiting(false);
      }
    }
  }

  void _clear() {
    _wakeUp();
    _queue = const [];
    _index = -1;
    _paused = false;
    _waiting = false;
    _loading = false;
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
    _wakeUp();
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
      // waiting to try the recording again: «متابعة» tries it now
      _wakeUp();
      await player.resume();
    }
  }

  Future<void> stop() async {
    _session++;
    _clear();
    await player.stop();
  }

  /// ↺ in the player bar: the recording being heard starts again from its
  /// beginning, once, and the listening goes on from there as usual (owner,
  /// 2026-11-20). The times already heard in full stay counted; paused, it
  /// plays.
  Future<void> replay() async {
    if (!isActive) return;
    unawaited(start(_queue, _index));
  }

  /// Another athkar voice. A dhikr being heard in the old voice starts again
  /// from its beginning in the new one and the listening goes on from there
  /// (owner, 2026-11-20: it used to stop). One the change does not touch (a
  /// verse, or a dhikr the new voice did not record) plays on; the athkar
  /// after it are in the new voice.
  Future<void> chooseReciter(AthkarReciter reciter) async {
    final item = current;
    final before = item == null || item.isQuran ? null : voiceFor(item)?.id;
    AthkarStore.instance.chooseReciter(reciter);
    _restartIf(before != null && voiceFor(item!)?.id != before);
  }

  /// Another reciter for the verses: the same, for a verse being heard.
  Future<void> chooseQuranReciter(Reciter reciter) async {
    final item = current;
    final changed =
        item != null && item.isQuran && quranReciter.id != reciter.id;
    AthkarStore.instance.chooseQuranReciter(reciter.id);
    _restartIf(changed);
  }

  void _restartIf(bool changed) {
    if (changed && isActive) {
      // the times already heard in full stay counted; the one cut short is
      // heard again, whole
      unawaited(start(_queue, _index));
    } else {
      notifyListeners();
    }
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
  final keep = AthkarAudio.instance.cacheClips;
  return [
    for (final c in joined)
      AthkarSource(
        dir != null && File(p.join(dir.path, c.file)).existsSync()
            ? Uri.file(p.join(dir.path, c.file))
            // one ayah's file is kept like a voice clip (even one that stops
            // early, see recitationEndCaps); a slice of a timed reciter's
            // whole surah streams
            : keep && c.start == null
            ? await AthkarAudio.voiceClipUri('${reciter.audioBaseUrl}${c.file}')
            : Uri.parse('${reciter.audioBaseUrl}${c.file}'),
        start: c.start,
        end: c.end,
        origin: Uri.parse('${reciter.audioBaseUrl}${c.file}'),
      ),
  ];
}

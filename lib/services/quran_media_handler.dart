import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart' hide AudioService;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quran_page_data.dart';
import '../models/reciter.dart';
import '../surah_data.dart';
import '../thumn_data.dart';
import '../utils/quran_display_text.dart';
import 'audio_service.dart';
import 'quran_json_service.dart';
import 'reciter_service.dart';

/// The media session: the notification, the lock screen, headset and
/// Bluetooth buttons, and Android Auto.
///
/// Replaces just_audio_background, which mirrored the player to the session
/// but could not offer the car anything to browse. The player and the whole
/// recitation engine stay in [AudioService]; this class only reports their
/// state and turns the session's commands into the engine's own calls, so a
/// tap in the car does exactly what the same tap does in the app.
///
/// Car layout (owner's choice, option B + player 2, 2026-11-16): four tabs
/// (الرئيسية, السور, الأجزاء, القرّاء); the player shows the ayah now
/// playing and has ±10 s, أعد الآية and القارئ التالي beside ⏮ ⏯ ⏭.
class QuranMediaHandler extends BaseAudioHandler {
  QuranMediaHandler() {
    instance = this;
    final audio = AudioService.instance;
    audio.player.playbackEventStream.listen(
      (_) => _broadcastState(),
      // The engine handles player errors itself (see AudioService); the
      // session keeps showing the last good state.
      onError: (Object _, StackTrace _) {},
    );
    audio.player.playingStream.listen((_) => _broadcastState());
    audio.player.durationStream.listen((_) => _publishItem());
    audio.currentAyah.addListener(_onAyahChanged);
    // The repeat button's icon follows the mode, whichever side changed it.
    audio.repeatMode.addListener(_broadcastState);
    audio.repeatCount.addListener(_broadcastState);
    audio.rangeRepeatMode.addListener(_broadcastState);
    audio.repeatRange.addListener(_broadcastState);
    audio.playbackSpeed.addListener(_broadcastState);
    audio.player.playingStream.listen(_onPlayingChanged);
    ReciterService.instance.selected.addListener(_publishItem);
  }

  /// The live handler: null until audio_service has started it (and in
  /// tests, and on platforms without a media session).
  static QuranMediaHandler? instance;

  // ─────────────────────────────────────
  //  GUEST PLAYBACK (the athkar)
  // ─────────────────────────────────────

  /// Something other than the recitation is being heard: the athkar. It
  /// borrows the session, so the notification, the lock screen and headset
  /// buttons drive it, and Android keeps the app in the foreground while
  /// it plays. Without this the athkar played on a plain player outside the
  /// session's foreground service, and a locked phone cut the app's network
  /// within seconds (emulator, 2026-11-18).
  ///
  /// [playing] is the listening as a whole, not the player between clips:
  /// a «pause» between two pieces would drop the foreground service, and
  /// Android does not let it start again from a locked screen.
  GuestPlayback? _guest;

  bool get hasGuest => _guest != null;

  void showGuest(GuestPlayback guest) {
    final was = _guest;
    // the same dhikr in another voice, or «ينتظر الاتصال…» coming and going,
    // is new text for the notification too (it kept the old voice's name)
    final changedItem =
        was == null ||
        was.id != guest.id ||
        was.title != guest.title ||
        was.artist != guest.artist ||
        was.album != guest.album ||
        was.artUri != guest.artUri;
    _guest = guest;
    if (changedItem) {
      mediaItem.add(
        MediaItem(
          id: 'guest:${guest.id}',
          title: guest.title,
          artist: guest.artist,
          album: guest.album,
          artUri: guest.artUri,
        ),
      );
    }
    _broadcastState();
  }

  /// The guest is done: the session goes back to the recitation (idle).
  void endGuest() {
    if (_guest == null) return;
    _guest = null;
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    // the last dhikr's title is not left on the session; the recitation's
    // ayah comes back if one is loaded
    mediaItem.add(null);
    _publishItem();
    _broadcastState();
  }

  void _broadcastGuest(GuestPlayback g) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          g.playing ? MediaControl.pause : MediaControl.play,
          if (g.onNext != null) MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {},
        androidCompactActionIndices: g.onNext != null
            ? const [0, 1]
            : const [0],
        queueIndex: null,
        processingState: AudioProcessingState.ready,
        playing: g.playing,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1,
      ),
    );
  }

  // ─────────────────────────────────────
  //  IDS
  // ─────────────────────────────────────

  static const String _rootId = 'root'; // AudioService.browsableRootId
  static const String _recentRootId = 'recent'; // AudioService.recentRootId
  static const String _homeId = 'tab:home';
  static const String _surahsId = 'tab:surahs';
  static const String _juzId = 'tab:juz';
  static const String _recitersId = 'tab:reciters';
  static const String _resumeId = 'resume';

  // Android Auto content-style keys (androidx.media.utils.MediaConstants).
  static const String _browsableHint =
      'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
  static const String _playableHint =
      'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';
  static const String _groupTitle =
      'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT';
  static const int _styleList = 1;
  static const int _styleGrid = 2;

  /// What [AudioServiceConfig.androidBrowsableRootExtras] should carry.
  static const Map<String, dynamic> rootExtras = {
    'android.media.browse.SEARCH_SUPPORTED': true,
    _browsableHint: _styleList,
    _playableHint: _styleList,
  };

  // ─────────────────────────────────────
  //  CONTROLS
  // ─────────────────────────────────────

  static final MediaControl _rewind10 = MediaControl.custom(
    androidIcon: 'drawable/ic_media_replay_10',
    label: 'رجوع 10 ثوانٍ',
    name: 'rewind10',
  );
  static final MediaControl _forward10 = MediaControl.custom(
    androidIcon: 'drawable/ic_media_forward_10',
    label: 'تقديم 10 ثوانٍ',
    name: 'forward10',
  );

  /// تكرار: the bar's ayah cycle (off → 2× → 3× → ∞; the first tap also
  /// restarts the ayah), then the whole surah, then off. Its icon shows the
  /// state, since the car shows no text on these buttons.
  static MediaControl _repeatControl() {
    final audio = AudioService.instance;
    if (audio.isSurahRepeat) {
      return MediaControl.custom(
        androidIcon: 'drawable/ic_media_repeat_surah',
        label: 'تكرار السورة',
        name: 'repeatAyah',
      );
    }
    final (icon, label) = switch (audio.repeatMode.value) {
      AyahRepeatMode.off => ('ic_media_repeat_off', 'تكرار الآية'),
      AyahRepeatMode.infinite => ('ic_media_repeat_inf', 'تكرار بلا توقف'),
      AyahRepeatMode.count =>
        audio.repeatCount.value <= 2
            ? ('ic_media_repeat_2', 'تكرار مرتين')
            : ('ic_media_repeat_3', 'تكرار 3 مرات'),
    };
    return MediaControl.custom(
      androidIcon: 'drawable/$icon',
      label: label,
      name: 'repeatAyah',
    );
  }

  static final MediaControl _nextReciter = MediaControl.custom(
    androidIcon: 'drawable/ic_media_next_reciter',
    label: 'القارئ التالي',
    name: 'nextReciter',
  );

  /// السرعة: 1× → 1.25× → 0.75× → 1×. A speed set in the app (0.5×–2×)
  /// shows as it is; the next tap brings it back to 1×.
  static MediaControl _speedControl() {
    final speed = AudioService.instance.playbackSpeed.value;
    final code = (speed * 100).round().toString().padLeft(3, '0');
    return MediaControl.custom(
      androidIcon: 'drawable/ic_media_speed_$code',
      label: 'السرعة ${AudioService.speedLabel(speed)}',
      name: 'speed',
    );
  }

  static const List<double> _speedCycle = [1.0, 1.25, 0.75];

  MediaControl _sleepControl() {
    final (icon, label) = switch (_sleep) {
      _Sleep.off => ('ic_media_sleep_off', 'مؤقت الإيقاف'),
      _Sleep.surahEnd => ('ic_media_sleep_surah', 'إيقاف بعد السورة'),
      _Sleep.min15 => ('ic_media_sleep_15', 'إيقاف بعد 15 دقيقة'),
      _Sleep.min30 => ('ic_media_sleep_30', 'إيقاف بعد 30 دقيقة'),
      _Sleep.min60 => ('ic_media_sleep_60', 'إيقاف بعد 60 دقيقة'),
    };
    return MediaControl.custom(
      androidIcon: 'drawable/$icon',
      label: label,
      name: 'sleep',
    );
  }

  /// Mirrors the player to the session.
  ///
  /// Custom controls become session actions only (audio_service never puts
  /// them in the notification's own button row), so phones before Android 13
  /// keep the plain ⏮ ⏯ ⏭ ⏹ notification; Android 13+ shows the first two
  /// (±10 s) beside ⏮ ⏯ ⏭, and the car shows all four.
  void _broadcastState() {
    final guest = _guest;
    if (guest != null) return _broadcastGuest(guest);
    final audio = AudioService.instance;
    final p = audio.player;
    final active = audio.currentAyah.value != null;
    final state = switch (p.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
    final playing =
        p.playing &&
        state != AudioProcessingState.idle &&
        state != AudioProcessingState.completed;
    final controls = [
      if (active) MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      if (active) MediaControl.skipToNext,
      // The car shows as many as fit and puts the rest behind a «…» button,
      // so the most used come first.
      if (active) ...[
        _rewind10,
        _forward10,
        _repeatControl(),
        _nextReciter,
        _sleepControl(),
        _speedControl(),
      ],
      MediaControl.stop,
    ];
    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.playFromMediaId,
          MediaAction.playFromSearch,
        },
        androidCompactActionIndices: active ? const [0, 1, 2] : const [0],
        // Highlights the surah now playing in the car's surah list (the
        // queue, see [_publishQueue]).
        queueIndex: active ? audio.currentAyah.value!.surah - 1 : null,
        processingState: state,
        playing: playing,
        updatePosition: p.position,
        bufferedPosition: p.bufferedPosition,
        speed: p.speed,
      ),
    );
  }

  // ─────────────────────────────────────
  //  NOW PLAYING
  // ─────────────────────────────────────

  (int, int)? _lastSaved;

  void _onAyahChanged() {
    _publishItem();
    _broadcastState(); // ⏮ ⏭ and the extras appear / go with the recitation
    final ayah = AudioService.instance.currentAyah.value;
    if (ayah == null) return;
    _checkSurahEnd(ayah.surah, ayah.ayah);
    // The surah queue is built on first need (the car asking, or the first
    // recitation), never at launch: startup stays as lean as it was.
    unawaited(_ensureData());
    final key = (ayah.surah, ayah.ayah);
    if (key == _lastSaved) return;
    final surahChanged = _lastSaved?.$1 != ayah.surah;
    _lastSaved = key;
    unawaited(_saveResume(ayah.surah, ayah.ayah, surahChanged));
  }

  /// «سورة يوسف · الآية 53» over «أحمد صالح رجب · الصفحة 242 · الجزء 13».
  ///
  /// Built from the ayah being recited rather than the player's source tag:
  /// a whole-surah file is loaded once and seeked within, so its tag can only
  /// name the surah, while this follows every ayah. The duration stays the
  /// source's, so the bar is the same one the seek controls move.
  void _publishItem() {
    if (_guest != null) return;
    final audio = AudioService.instance;
    final ayah = audio.currentAyah.value;
    if (ayah == null) return;
    final reciter = ReciterService.instance.selected.value;
    final pageIndex = audio.pageIndexForAyah(ayah.surah, ayah.ayah);
    final juz = _juzOf(ayah.surah, ayah.ayah);
    mediaItem.add(
      MediaItem(
        id: 'ayah:${ayah.surah}:${ayah.ayah}',
        title: 'سورة ${ayah.surahName} · الآية ${ayah.ayah}',
        artist: [
          reciter.shortName,
          if (pageIndex >= 0) 'الصفحة ${pageIndex + 1}',
          'الجزء $juz',
        ].join(' · '),
        album: reciter.riwaya,
        duration: audio.player.duration,
        // The reciter's tile fills the player's picture, so who is reciting
        // shows at a glance and changes visibly with القارئ التالي.
        artUri: reciterArt(reciter.id),
      ),
    );
  }

  /// The reciter's name tile, served by ReciterArtProvider (Android only:
  /// the car and the notification read it from another process, which only
  /// a content:// URI allows). A reciter without its own tile gets the
  /// generic one from the provider.
  static Uri? reciterArt(String reciterId) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final name = _tileName(reciterId);
    // A tile fetched this run gets a new address: the car caches pictures by
    // address and would otherwise keep showing the generic one.
    final fresh = _fetchedTiles.contains(name) ? '?t=1' : '';
    return Uri.parse(
      'content://com.mahfodqr.qalon_mushaf.reciterart/reciter/$name.png$fresh',
    );
  }

  static String _tileName(String reciterId) =>
      reciterId.toLowerCase().replaceAll(RegExp('[^a-z0-9_]'), '_');

  /// Tiles bundled in android/app/src/main/assets/reciter_art (keep in step
  /// with tools/make_reciter_tiles.py BUNDLED).
  static const Set<String> _bundledTiles = {
    'husary_qaloun',
    'naihi_qaloun',
    'qaniwah_qaloun',
    'abusenainah_qaloun',
    'hudaifi_qaloun',
    'doukali_qaloun',
    'alqryw_qaloun',
    'rajab_qaloun',
    'almislati_qaloun',
    'trabulsi_qaloun',
    'zarrouq_qaloun',
    'younsi_qaloun',
    'ahmed_qleab_qaloun',
  };

  static final Set<String> _fetchedTiles = {};
  static final Set<String> _triedTiles = {};

  /// A reciter added from the server after this build has no bundled tile
  /// (its own or its family's, see ReciterArtProvider): fetch
  /// `reciter_art/<id>.png` from the public bucket once, into files/reciter_art,
  /// where the provider looks first. Missing on the server = the generic tile.
  Future<void> _fetchMissingTiles() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    var changed = false;
    for (final r in ReciterService.instance.reciters) {
      final name = _tileName(r.id);
      final family = '${name.split('_').first}_qaloun';
      if (_bundledTiles.contains(name) || _bundledTiles.contains(family)) {
        continue;
      }
      if (!_triedTiles.add(name)) continue;
      try {
        final dir = Directory(
          p.join((await getApplicationSupportDirectory()).path, 'reciter_art'),
        );
        final file = File(p.join(dir.path, '$name.png'));
        if (await file.exists() && await file.length() > 0) continue;
        final res = await http
            .get(Uri.parse('$_tileBaseUrl/$name.png'))
            .timeout(const Duration(seconds: 15));
        final b = res.bodyBytes;
        final isPng = b.length > 8 && b[0] == 0x89 && b[1] == 0x50;
        if (res.statusCode != 200 || !isPng) continue;
        await dir.create(recursive: true);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsBytes(b, flush: true);
        await tmp.rename(file.path);
        _fetchedTiles.add(name);
        changed = true;
      } catch (e) {
        debugPrint('reciter tile $name: $e');
      }
    }
    // The player picture updates now; the القرّاء tab on its next opening.
    if (changed) _publishItem();
  }

  static const String _tileBaseUrl =
      'https://quran-content.mushaf-qaloon.com/reciter_art';

  /// The 114 surahs as the session's queue: Android Auto shows it as a list
  /// button on the player screen, so the surah can be changed without going
  /// back to the tabs. Tapping one arrives in [skipToQueueItem].
  void _publishQueue() {
    queueTitle.add('السور');
    queue.add([for (var s = 1; s <= 114; s++) _shown(_surahItem(s))]);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _ensureData();
    if (index >= 0 && index < 114) await _playFrom(index + 1, 1);
  }

  // ─────────────────────────────────────
  //  TRANSPORT
  // ─────────────────────────────────────

  @override
  Future<void> play() async {
    final guest = _guest;
    if (guest != null) return guest.onPlay();
    final audio = AudioService.instance;
    if (audio.currentAyah.value == null) {
      await _playResume();
    } else {
      audio.resume();
    }
  }

  @override
  Future<void> pause() async {
    final guest = _guest;
    if (guest != null) return guest.onPause();
    AudioService.instance.pause();
  }

  @override
  Future<void> stop() async {
    final guest = _guest;
    if (guest != null) {
      guest.onStop();
      endGuest();
      return;
    }
    _setSleep(_Sleep.off);
    AudioService.instance.stop();
    await super.stop();
  }

  /// The app swiped away from the recent apps (Android): the athkar stop
  /// with it. They belong to the page they were started on, which is gone,
  /// and an ayah of آية الكرسي went on playing after the app was closed
  /// (owner, 2026-11-20). The recitation keeps its background playing.
  @override
  Future<void> onTaskRemoved() async {
    final guest = _guest;
    if (guest != null) {
      guest.onStop();
      endGuest();
    }
    await super.onTaskRemoved();
  }

  @override
  Future<void> skipToNext() async {
    final guest = _guest;
    if (guest != null) return guest.onNext?.call();
    AudioService.instance.nextAyah();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_guest != null) return; // the athkar have no ⏮
    AudioService.instance.previousAyah();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_guest != null) return;
    await AudioService.instance.player.seek(position);
  } // the engine re-syncs the ayah itself (AudioService._onExternalSeek)

  @override
  Future<void> fastForward() async {
    if (_guest != null) return;
    await AudioService.instance.seekBy(const Duration(seconds: 10));
  }

  @override
  Future<void> rewind() async {
    if (_guest != null) return;
    await AudioService.instance.seekBy(const Duration(seconds: -10));
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (_guest != null) return null; // the recitation's own buttons
    switch (name) {
      case 'rewind10':
        await rewind();
      case 'forward10':
        await fastForward();
      case 'repeatAyah':
        await _cycleRepeat();
      case 'nextReciter':
        await _selectNextReciter();
      case 'sleep':
        _setSleep(_Sleep.values[(_sleep.index + 1) % _Sleep.values.length]);
      case 'speed':
        final audio = AudioService.instance;
        final i = _speedCycle.indexOf(audio.playbackSpeed.value);
        audio.setPlaybackSpeed(
          i < 0 ? 1.0 : _speedCycle[(i + 1) % _speedCycle.length],
        );
    }
  }

  /// Ayah 2× → 3× → ∞ (the bar's own cycle), then the whole surah, then
  /// off. Any other section repeat set in the app is left alone until the
  /// cycle reaches it.
  Future<void> _cycleRepeat() async {
    final audio = AudioService.instance;
    final ayah = audio.currentAyah.value;
    if (audio.isSurahRepeat) {
      audio.cancelRangeRepeat();
    } else if (audio.repeatMode.value == AyahRepeatMode.infinite &&
        ayah != null) {
      await audio.armSurahRepeat(ayah.surah);
    } else {
      audio.cycleAyahRepeatMode();
    }
    _broadcastState();
  }

  // ─────────────────────────────────────
  //  SLEEP TIMER
  // ─────────────────────────────────────

  _Sleep _sleep = _Sleep.off;
  Timer? _sleepTimer;

  /// The surah «إيقاف بعد السورة» waits for, and whether its last ayah is
  /// already playing (the engine then parks after it).
  int? _sleepSurah;
  bool _sleepArmed = false;

  void _setSleep(_Sleep next) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleep = next;
    _sleepSurah = null;
    _sleepArmed = false;
    final minutes = switch (next) {
      _Sleep.min15 => 15,
      _Sleep.min30 => 30,
      _Sleep.min60 => 60,
      _ => 0,
    };
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        AudioService.instance.pause();
        _setSleep(_Sleep.off);
      });
    } else if (next == _Sleep.surahEnd) {
      final ayah = AudioService.instance.currentAyah.value;
      if (ayah != null) _checkSurahEnd(ayah.surah, ayah.ayah);
    }
    _broadcastState();
  }

  /// «إيقاف بعد السورة»: when the surah's last ayah begins, tell the engine
  /// to park after it (no sound from the next surah). A surah picked by hand
  /// moves the stop to that surah; if the last ayah was never reported (it
  /// was recited joined to the one before), the next surah's opening pauses.
  void _checkSurahEnd(int surah, int ayah) {
    if (_sleep != _Sleep.surahEnd) return;
    final watched = _sleepSurah;
    if (watched != null && surah == watched + 1 && ayah <= 1 && !_sleepArmed) {
      AudioService.instance.pause();
      _setSleep(_Sleep.off);
      return;
    }
    if (watched != surah) {
      _sleepSurah = surah;
      _sleepArmed = false;
    }
    final last = _ayahCounts[surah] ?? 0;
    if (last > 0 && ayah >= last) {
      AudioService.instance.stopAfterAyah(surah, ayah);
      _sleepArmed = true;
    }
  }

  /// The park after the last ayah ends the surah timer.
  void _onPlayingChanged(bool playing) {
    if (!playing && _sleep == _Sleep.surahEnd && _sleepArmed) {
      _setSleep(_Sleep.off);
    }
  }

  /// Moves to the next reciter in the picker's order. A recitation going on
  /// carries on from the same ayah with the new voice (the engine restarts
  /// it on a reciter change).
  Future<void> _selectNextReciter() async {
    final all = ReciterService.instance.reciters;
    if (all.length < 2) return;
    final i = all.indexWhere(
      (r) => r.id == ReciterService.instance.selected.value.id,
    );
    await ReciterService.instance.select(all[(i + 1) % all.length]);
  }

  // ─────────────────────────────────────
  //  PLAY FROM THE CAR
  // ─────────────────────────────────────

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    await _ensureData();
    final parts = mediaId.split(':');
    int? n(int i) => parts.length > i ? int.tryParse(parts[i]) : null;
    switch (parts.first) {
      case _resumeId:
        await _playResume();
      case 'surah':
        final s = n(1);
        if (s != null) await _playFrom(s, 1);
      case 'ayah':
        final s = n(1), a = n(2);
        if (s != null && a != null) await _playFrom(s, a);
      case 'juz':
        final j = n(1);
        if (j != null) await _playHizb(j * 2 - 1);
      case 'hizb':
        final h = n(1);
        if (h != null) await _playHizb(h);
      case 'page':
        final pg = n(1);
        if (pg != null) await _playPage(pg);
      case 'reciter':
        await _playWithReciter(parts.skip(1).join(':'));
    }
  }

  Future<void> _playFrom(int surah, int ayah) {
    // A surah picked in the car is the one «إيقاف بعد السورة» now waits for.
    if (_sleep == _Sleep.surahEnd) {
      _sleepSurah = surah;
      _sleepArmed = false;
    }
    return AudioService.instance.playFromAyah(surah, ayah, onlyThisAyah: false);
  }

  Future<void> _playHizb(int hizb) async {
    final start = thumnEntries.where((t) => t.hizb == hizb).firstOrNull;
    if (start != null) await _playFrom(start.startSurah, start.startAyah);
  }

  /// [page] is the printed page number (1-based).
  Future<void> _playPage(int page) async {
    final audio = AudioService.instance;
    await audio.init();
    audio.onPageChangeRequired?.call(page - 1);
    await audio.playPage(page - 1);
  }

  /// Where the recitation last was; failing that, the page the reader was
  /// last on; failing that, the first page.
  Future<void> _playResume() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getInt(_resumeSurahKey);
    final a = prefs.getInt(_resumeAyahKey);
    if (s != null && a != null) {
      await _playFrom(s, a);
    } else {
      await _playPage((prefs.getInt('lastPage') ?? 0) + 1);
    }
  }

  /// A reciter tapped in the القرّاء tab: switch to them and play. A
  /// recitation going on carries on with the new voice; with nothing
  /// playing, the last place starts.
  Future<void> _playWithReciter(String id) async {
    final reciter = ReciterService.instance.reciters
        .where((r) => r.id == id)
        .firstOrNull;
    if (reciter == null) return;
    final wasActive = AudioService.instance.currentAyah.value != null;
    await ReciterService.instance.select(reciter);
    if (!wasActive) await _playResume();
    _publishItem();
  }

  // ─────────────────────────────────────
  //  VOICE / SEARCH
  // ─────────────────────────────────────

  /// «شغّل سورة الكهف»: Google Assistant hands over the words after the
  /// verb. An empty query («شغّل المصحف الجامع») resumes.
  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    await _ensureData();
    final hits = _searchIds(query);
    if (hits.isEmpty) {
      await _playResume();
    } else {
      await playFromMediaId(hits.first);
    }
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    await _ensureData();
    return [
      for (final id in _searchIds(query).take(20))
        if (_itemFor(id) case final item?) _shown(item),
    ];
  }

  /// Media ids matching [query], best first: a juz or hizb number, surah
  /// names, then reciters.
  List<String> _searchIds(String query) {
    final q = _normalize(query);
    if (q.isEmpty) return const [];
    final out = <String>[];
    final number = int.tryParse(
      RegExp(r'\d+').firstMatch(_westernDigits(query))?.group(0) ?? '',
    );
    if (number != null) {
      bool has(String pattern) => RegExp(pattern).hasMatch(q);
      if (has(r'جزء|\bjuz|\bjuzz|\bpara\b') && number >= 1 && number <= 30) {
        out.add('juz:$number');
      } else if (has(r'حزب|\bhizb') && number >= 1 && number <= 60) {
        out.add('hizb:$number');
      } else if (has(r'صفحه|\bpage') && number >= 1 && number <= _pageCount) {
        out.add('page:$number');
      } else if (number >= 1 &&
          number <= 114 &&
          has(r'سوره|\bsur|\bsoor|\bchapter')) {
        out.add('surah:$number');
      }
    }
    // Assistant in English hands over a transliteration: "al kahf",
    // "surah yaseen", "baqara".
    final latin = _latinKey(q);
    if (latin.length >= 2 && out.isEmpty) {
      final plain = _latinPlain(q);
      final exact = <(int, String)>[], partial = <String>[];
      for (final s in surahList) {
        final name = s['english'] as String;
        final key = _latinKey(name);
        if (key == latin) {
          // Same spelling first, then the closest length.
          final p = _latinPlain(name);
          final rank = p == plain ? -1 : (p.length - plain.length).abs();
          exact.add((rank, 'surah:${s['number']}'));
        } else if (latin.length >= 3 &&
            (key.contains(latin) || latin.contains(key))) {
          partial.add('surah:${s['number']}');
        }
      }
      exact.sort((a, b) => a.$1.compareTo(b.$1));
      out
        ..addAll(exact.map((e) => e.$2))
        ..addAll(partial);
    }
    final words = q
        .replaceAll('سوره', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final text = words.join(' ');
    if (text.isNotEmpty) {
      for (var s = 1; s <= 114; s++) {
        final name = _normalize(_surahNames[s] ?? '');
        if (name.isEmpty) continue;
        if (name == text ||
            _stripAl(name) == _stripAl(text) ||
            (text.length >= 3 && name.contains(text))) {
          out.add('surah:$s');
        }
      }
      for (final r in ReciterService.instance.reciters) {
        final name = _normalize(r.name);
        if (words.any((w) => w.length >= 3 && name.contains(w))) {
          out.add('reciter:${r.id}');
        }
      }
    }
    return out.toSet().toList();
  }

  static String _westernDigits(String s) =>
      s.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
        final c = m.group(0)!.codeUnitAt(0);
        return String.fromCharCode(
          0x30 + (c >= 0x06F0 ? c - 0x06F0 : c - 0x0660),
        );
      });

  /// Drops harakat and tatweel, folds أ إ آ ٱ → ا, ة → ه, ى → ي, so a
  /// spoken «سورة الكهف» meets the data's «الكهف».
  static String _normalize(String s) {
    var t = _westernDigits(s).replaceAll(RegExp('[ً-ٰٟـۖ-ۭ]'), '');
    t = t
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[^ء-ي0-9a-zA-Z ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    return t;
  }

  static String _stripAl(String s) => s.startsWith('ال') ? s.substring(2) : s;

  /// A spelling-proof key for a Latin surah name: the filler words and the
  /// article go, then the vowels, doubled letters and a final h, with q read
  /// as k. "Al-Baqarah", "baqara" and "Bakara" all become "bkr"; "Ya-Sin"
  /// and "yaseen" become "ysn".
  static String _latinKey(String s) {
    final t = _latinPlain(s);
    if (t.isEmpty) return '';
    final first = t[0];
    var rest = t.substring(1).replaceAll(RegExp('[aeiouwy]'), '');
    rest = rest.replaceAll('q', 'k');
    var key = (first == 'q' ? 'k' : first) + rest;
    key = key.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
    if (key.length > 2 && key.endsWith('h')) {
      key = key.substring(0, key.length - 1);
    }
    // A leading vowel says little ("imran" / "Aal-E-Imran").
    if (key.length > 3 && 'aeiou'.contains(key[0])) key = key.substring(1);
    return key;
  }

  /// The name's letters without the filler words and the article:
  /// "Al-Fatiha" → "fatiha". Breaks ties between names sharing a
  /// [_latinKey] (Al-Fatiha / Al-Fath, An-Nisa / An-Nas, Hud / Al-Hadid).
  static String _latinPlain(String s) => s
      .toLowerCase()
      .replaceAll(RegExp("['`’]"), '')
      .replaceAll(RegExp('[^a-z ]'), ' ')
      .replaceAll(
        RegExp(
          r'\b(play|recite|listen|to|the|surah|surat|sura|soorah|'
          r'chapter|quran|holy|of|on|by|al|el|an|ar|as|at|ad|adh|az|ash|ath|'
          r'aal|e)\b',
        ),
        ' ',
      )
      .replaceAll(' ', '');

  // ─────────────────────────────────────
  //  BROWSING
  // ─────────────────────────────────────

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async => [for (final item in await _children(parentMediaId)) _shown(item)];

  /// Android shows an item's [MediaItem.displaySubtitle] only when it also
  /// has a [MediaItem.displayTitle] (MediaMetadataCompat.getDescription;
  /// without one it falls back to title, artist, album), so every item with
  /// a subtitle gets its title copied there.
  static MediaItem _shown(MediaItem item) =>
      item.displaySubtitle == null || item.displayTitle != null
      ? item
      : item.copyWith(displayTitle: item.title);

  Future<List<MediaItem>> _children(String parentMediaId) async {
    await _ensureData();
    switch (parentMediaId) {
      case _rootId:
        return [
          _tab(_homeId, 'الرئيسية'),
          _tab(_surahsId, 'السور'),
          _tab(_juzId, 'الأجزاء'),
          _tab(_recitersId, 'القرّاء', playableStyle: _styleGrid),
        ];
      case _recentRootId:
        // Android's media resumption («continue listening») asks for this.
        return [await _resumeItem()];
      case _homeId:
        return _homeItems();
      case _surahsId:
        return [for (var s = 1; s <= 114; s++) _surahBrowseItem(s)];
      case _juzId:
        return [for (var j = 1; j <= 30; j++) _juzItem(j)];
      case _recitersId:
        unawaited(_fetchMissingTiles());
        final selected = ReciterService.instance.selected.value.id;
        return [
          for (final r in ReciterService.instance.reciters)
            _reciterItem(r, selected: r.id == selected),
        ];
    }
    // A surah opens to «من أول السورة» and its ayat; a long surah to groups
    // of [_ayahGroup] (the car limits how far a list scrolls while driving).
    if (parentMediaId.startsWith('surahbrowse:')) {
      final s = int.tryParse(parentMediaId.substring(12));
      final count = s == null ? 0 : (_ayahCounts[s] ?? 0);
      if (count == 0) return const [];
      return [
        MediaItem(
          id: 'surah:$s',
          title: 'من أول السورة',
          displaySubtitle: 'سورة ${_surahNames[s] ?? ''}',
        ),
        if (count <= _ayahGroup)
          for (var a = 1; a <= count; a++) _ayahItem(s!, a)
        else
          for (var a = 1; a <= count; a += _ayahGroup)
            MediaItem(
              id: 'ayahs:$s:$a',
              // Words, not «1–20»: the car lays the list header out
              // left to right and showed it as «20–1».
              title: 'الآيات من $a إلى ${(a + _ayahGroup - 1).clamp(1, count)}',
              displaySubtitle: _snippets[(s!, a)],
              playable: false,
            ),
      ];
    }
    if (parentMediaId.startsWith('ayahs:')) {
      final parts = parentMediaId.split(':');
      final s = parts.length > 2 ? int.tryParse(parts[1]) : null;
      final from = parts.length > 2 ? int.tryParse(parts[2]) : null;
      final count = s == null ? 0 : (_ayahCounts[s] ?? 0);
      if (s == null || from == null || count == 0) return const [];
      final to = (from + _ayahGroup - 1).clamp(1, count);
      return [for (var a = from; a <= to; a++) _ayahItem(s, a)];
    }
    if (parentMediaId.startsWith('juzbrowse:')) {
      final j = int.tryParse(parentMediaId.substring(10));
      if (j == null) return const [];
      return [
        MediaItem(
          id: 'juz:$j',
          title: 'الجزء $j كاملًا',
          displaySubtitle: _startLabel(j * 2 - 1),
        ),
        for (final h in [j * 2 - 1, j * 2])
          MediaItem(
            id: 'hizb:$h',
            title: 'الحزب $h',
            displaySubtitle: _startLabel(h),
          ),
      ];
    }
    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    await _ensureData();
    final item = _itemFor(mediaId);
    return item == null ? null : _shown(item);
  }

  MediaItem? _itemFor(String id) {
    final parts = id.split(':');
    final n = parts.length > 1 ? int.tryParse(parts[1]) : null;
    switch (parts.first) {
      case 'surah':
        return n == null ? null : _surahItem(n);
      case 'ayah':
        final a = parts.length > 2 ? int.tryParse(parts[2]) : null;
        return n == null || a == null ? null : _ayahItem(n, a);
      case 'juz':
        return n == null
            ? null
            : MediaItem(
                id: id,
                title: 'الجزء $n',
                displaySubtitle: _startLabel(n * 2 - 1),
              );
      case 'hizb':
        return n == null
            ? null
            : MediaItem(
                id: id,
                title: 'الحزب $n',
                displaySubtitle: _startLabel(n),
              );
      case 'page':
        return n == null ? null : MediaItem(id: id, title: 'الصفحة $n');
      case 'reciter':
        final r = ReciterService.instance.reciters
            .where((r) => r.id == parts.skip(1).join(':'))
            .firstOrNull;
        return r == null
            ? null
            : _reciterItem(
                r,
                selected: r.id == ReciterService.instance.selected.value.id,
              );
    }
    return null;
  }

  MediaItem _tab(String id, String title, {int? playableStyle}) => MediaItem(
    id: id,
    title: title,
    playable: false,
    extras: {_playableHint: ?playableStyle},
  );

  Future<List<MediaItem>> _homeItems() async {
    final prefs = await SharedPreferences.getInstance();
    const recentGroup = 'استمعت إليها مؤخرًا';
    const bookmarkGroup = 'العلامات';
    final recent = prefs.getStringList(_recentKey) ?? const [];
    final items = <MediaItem>[await _resumeItem()];
    for (final raw in recent) {
      final s = int.tryParse(raw);
      if (s == null) continue;
      items.add(_surahItem(s, extras: const {_groupTitle: recentGroup}));
    }
    for (final page in _bookmarkPages(prefs)) {
      final ayahs = AudioService.instance.getAyahsForPage(page - 1);
      items.add(
        MediaItem(
          id: 'page:$page',
          title: 'الصفحة $page',
          displaySubtitle: ayahs.isEmpty
              ? null
              : 'سورة ${ayahs.first.surahName}، الآية ${ayahs.first.ayah}',
          extras: const {_groupTitle: bookmarkGroup},
        ),
      );
    }
    return items;
  }

  /// The reader's bookmarks (`readerBookmarks`, kept by the reader), as
  /// 1-based page numbers in slot order.
  List<int> _bookmarkPages(SharedPreferences prefs) {
    final raw = prefs.getString('readerBookmarks');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list =
          (jsonDecode(raw) as List<dynamic>)
              .whereType<Map<dynamic, dynamic>>()
              .toList()
            ..sort(
              (a, b) => ((a['slot'] as num?) ?? 0).compareTo(
                (b['slot'] as num?) ?? 0,
              ),
            );
      return <int>{
        for (final b in list)
          if (b['page'] is num) (b['page'] as num).toInt() + 1,
      }.toList();
    } catch (_) {
      return const [];
    }
  }

  Future<MediaItem> _resumeItem() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getInt(_resumeSurahKey);
    final a = prefs.getInt(_resumeAyahKey);
    final reciter = ReciterService.instance.selected.value.shortName;
    return MediaItem(
      id: _resumeId,
      title: 'متابعة التلاوة',
      displaySubtitle: s == null || a == null
          ? reciter
          : 'سورة ${_surahNames[s] ?? ''}، الآية $a · $reciter',
    );
  }

  MediaItem _surahItem(int s, {Map<String, dynamic>? extras}) {
    final count = _ayahCounts[s] ?? 0;
    return MediaItem(
      id: 'surah:$s',
      title: '$s. ${_surahNames[s] ?? ''}',
      displaySubtitle: count == 0 ? null : _ayatLabel(count),
      extras: extras,
    );
  }

  /// السور tab: the surah opens to its ayat (the queue and «استمعت إليها
  /// مؤخرًا» keep the one-tap [_surahItem]).
  MediaItem _surahBrowseItem(int s) {
    final count = _ayahCounts[s] ?? 0;
    return MediaItem(
      id: 'surahbrowse:$s',
      title: '$s. ${_surahNames[s] ?? ''}',
      displaySubtitle: count == 0 ? null : _ayatLabel(count),
      playable: false,
    );
  }

  /// «الآية 5» over its opening words.
  MediaItem _ayahItem(int s, int a) => MediaItem(
    id: 'ayah:$s:$a',
    title: 'الآية $a',
    displaySubtitle: _snippets[(s, a)],
  );

  static const int _ayahGroup = 20;

  MediaItem _juzItem(int j) => MediaItem(
    id: 'juzbrowse:$j',
    title: 'الجزء $j',
    displaySubtitle:
        'الحزبان ${j * 2 - 1} و${j * 2} · ${_startLabel(j * 2 - 1)}',
    playable: false,
  );

  MediaItem _reciterItem(Reciter r, {required bool selected}) => MediaItem(
    id: 'reciter:${r.id}',
    title: selected ? '✓ ${r.name}' : r.name,
    displaySubtitle: r.riwaya,
    artUri: reciterArt(r.id),
  );

  /// «يبدأ من الكهف 75».
  String _startLabel(int hizb) {
    final t = thumnEntries.where((t) => t.hizb == hizb).firstOrNull;
    if (t == null) return '';
    return 'يبدأ من ${_surahNames[t.startSurah] ?? ''} ${t.startAyah}';
  }

  static String _ayatLabel(int n) => n >= 3 && n <= 10 ? '$n آيات' : '$n آية';

  static int _juzOf(int surah, int ayah) {
    var hizb = 1;
    for (final t in thumnEntries) {
      if (t.startSurah > surah ||
          (t.startSurah == surah && t.startAyah > ayah)) {
        break;
      }
      hizb = t.hizb;
    }
    return (hizb + 1) ~/ 2;
  }

  // ─────────────────────────────────────
  //  DATA + MEMORY
  // ─────────────────────────────────────

  static const String _resumeSurahKey = 'mediaResumeSurah';
  static const String _resumeAyahKey = 'mediaResumeAyah';
  static const String _recentKey = 'mediaRecentSurahs';

  final Map<int, String> _surahNames = {};
  final Map<int, int> _ayahCounts = {};

  /// The first words of every ayah, for the car's ayah lists.
  final Map<(int, int), String> _snippets = {};
  int _pageCount = 0;

  /// The ayah's first five words, readable in the car's font (see
  /// quranDisplayText); any ayah-number sign in the text is left out.
  static String _snippet(String text) {
    final words = quranDisplayText(text)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !RegExp('[0-9٠-٩۰-۹۝]').hasMatch(w))
        .toList();
    if (words.length <= 5) return words.join(' ');
    return '${words.take(5).join(' ')}…';
  }

  Future<void>? _dataFuture;

  /// The car can connect with the app closed (audio_service then runs main()
  /// without a screen), so nothing here may assume the reader set anything up.
  Future<void> _ensureData() => _dataFuture ??= _loadData();

  Future<void> _loadData() async {
    try {
      await ReciterService.instance.load();
      final pages = await QuranJsonService.loadQuranPages();
      _indexPages(pages);
      _publishQueue();
      // Playback needs the engine; starting it here also means the first tap
      // in the car does not wait for it.
      unawaited(AudioService.instance.init());
    } catch (e, st) {
      _dataFuture = null; // try again on the next request
      debugPrint('QuranMediaHandler data load failed: $e\n$st');
    }
  }

  void _indexPages(List<QuranPageData> pages) {
    _pageCount = pages.length;
    for (final page in pages) {
      for (final a in page.ayahs) {
        _surahNames.putIfAbsent(a.surah, () => a.surahName);
        final c = _ayahCounts[a.surah] ?? 0;
        if (a.ayah > c) _ayahCounts[a.surah] = a.ayah;
        _snippets.putIfAbsent((a.surah, a.ayah), () => _snippet(a.text));
      }
    }
  }

  Future<void> _saveResume(int surah, int ayah, bool surahChanged) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_resumeSurahKey, surah);
      await prefs.setInt(_resumeAyahKey, ayah);
      if (surahChanged) {
        final recent = prefs.getStringList(_recentKey) ?? <String>[];
        recent
          ..remove('$surah')
          ..insert(0, '$surah');
        await prefs.setStringList(_recentKey, recent.take(5).toList());
      }
    } catch (_) {}
  }
}

/// مؤقت الإيقاف, in the order the car's button cycles through.
enum _Sleep { off, surahEnd, min15, min30, min60 }

/// What a guest (see [QuranMediaHandler.showGuest]) shows and answers.
class GuestPlayback {
  const GuestPlayback({
    required this.id,
    required this.title,
    required this.artist,
    required this.playing,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    this.album,
    this.artUri,
    this.onNext,
  });

  final String id;
  final String title;
  final String artist;
  final String? album;
  final Uri? artUri;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;

  /// Null hides ⏭ (the last dhikr, or «تشغيل متواصل» off).
  final VoidCallback? onNext;
}

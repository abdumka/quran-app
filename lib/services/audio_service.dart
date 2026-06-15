import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/quran_page_data.dart';
import 'quran_json_service.dart';

/// Repeat mode for ayah playback.
enum AyahRepeatMode {
  /// No repeat – move to next ayah when done.
  off,

  /// Repeat current ayah infinitely.
  infinite,

  /// Repeat current ayah a fixed number of times.
  count,
}

class AudioService {
  static final AudioService instance = AudioService._internal();
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();

  // Base URL for individual MP3 files on GitHub
  static const String _baseUrl =
      'https://raw.githubusercontent.com/quran-by-verses/alhosary-qaloon-32/main/verses/';

  List<QuranPageData>? _quranPages;
  int _currentGlobalAyahIndex = 0;
  int _currentFileIndexWithinAyah = 0;
  int _currentPageIndex = -1;
  List<QuranAyahData> _playlistAyahs = [];
  List<String> _currentAyahFiles = [];
  bool _isChangingPage = false;
  DateTime _lastAyahChangeTime = DateTime(2000);

  /// The page index currently playing.
  int get currentAudioPageIndex => _currentPageIndex;

  /// Whether audio is currently playing.
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);

  /// Whether audio files are being downloaded.
  final ValueNotifier<bool> isLoadingAudio = ValueNotifier(false);

  /// The currently active ayah.
  final ValueNotifier<QuranAyahData?> currentAyah = ValueNotifier(null);

  /// Expose the current playlist for the UI.
  List<QuranAyahData> get currentPlaylist => List.unmodifiable(_playlistAyahs);

  /// Returns the list of ayahs for a given 0-indexed page index.
  List<QuranAyahData> getAyahsForPage(int pageIndex) {
    if (_quranPages == null || pageIndex < 0 || pageIndex >= _quranPages!.length) {
      return [];
    }
    return _quranPages![pageIndex].ayahs;
  }

  /// Whether the recitation bar should be visible.
  final ValueNotifier<bool> isRecitationBarVisible = ValueNotifier(false);

  /// Current repeat mode.
  final ValueNotifier<AyahRepeatMode> repeatMode = ValueNotifier(
    AyahRepeatMode.off,
  );

  /// Repeat count (used when repeatMode == AyahRepeatMode.count).
  final ValueNotifier<int> repeatCount = ValueNotifier(3);

  /// Tracks how many times current ayah has been repeated so far.
  int _currentRepeatIteration = 0;

  /// ── Page Repeat ──
  /// Page repeat mode: off, infinite, or counted.
  final ValueNotifier<AyahRepeatMode> pageRepeatMode = ValueNotifier(
    AyahRepeatMode.off,
  );

  /// Page repeat count (used when pageRepeatMode == AyahRepeatMode.count).
  final ValueNotifier<int> pageRepeatCount = ValueNotifier(3);

  /// Tracks how many times current page has been repeated so far.
  int _pageRepeatIteration = 0;

  /// Playback progress within the current ayah (0.0 = start, 1.0 = end).
  final ValueNotifier<double> playbackProgress = ValueNotifier(0.0);

  // Callback to notify the UI to flip the page
  Function(int newPage)? onPageChangeRequired;

  Directory? _cacheDir;

  /// Subscription for split monitoring (intra-ayah UI updates).
  StreamSubscription? _splitMonitorSubscription;

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    _quranPages ??= await QuranJsonService.loadQuranPages();
    _cacheDir ??= await _getAudioCacheDir();

    _player.playerStateStream.listen((state) {
      isPlaying.value = state.playing;
      if (state.processingState == ProcessingState.completed) {
        _handleAyahCompleted();
      }
    });
  }

  Future<Directory> _getAudioCacheDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'audio_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ─────────────────────────────────────────────
  //  AUDIO FILE MAPPING (Qalon → Hafs filenames)
  // ─────────────────────────────────────────────

  List<String> _getAudioFilesForAyah(QuranAyahData ayah, {int? pageNumber}) {
    final s = ayah.surah;
    final a = ayah.ayah;
    final surahStr = s.toString().padLeft(3, '0');

    // ── معالجة الآيات المدمجة في آخر السورة ──
    // (لأن التسجيل الصوتي دمج آخر آيات قالون في ملف واحد نظراً لكون عدد آيات قالون أكثر)
    if (s == 5 && a >= 120) return ['005120.mp3'];
    if (s == 6 && a >= 165) return ['006165.mp3'];
    if (s == 8 && a >= 75) return ['008075.mp3'];
    if (s == 9 && a >= 129) return ['009129.mp3'];
    if (s == 13 && a >= 43) return ['013043.mp3'];
    if (s == 14 && a >= 52) return ['014052.mp3'];
    if (s == 23 && a >= 118) return ['023118.mp3'];
    if (s == 27 && a >= 93) return ['027093.mp3'];
    if (s == 47 && a >= 38) return ['047038.mp3'];
    if (s == 56 && a >= 96) return ['056096.mp3'];
    if (s == 71 && a >= 28) return ['071028.mp3'];
    if (s == 89 && a >= 30) return ['089030.mp3'];
    if (s == 91 && a >= 15) return ['091015.mp3'];
    if (s == 96 && a >= 19) return ['096019.mp3'];
    if (s == 106 && a >= 4) return ['106004.mp3'];

    // ── الربط المباشر لرواية قالون ──
    // لا حاجة لمقارنة مع حفص أو عمل إزاحات (Offsets).
    // الملفات الزائدة (الصامتة 1 ثانية) في نهاية بعض السور سيتم تجاهلها تلقائياً لأن التطبيق لن يطلبها.
    final ayahStr = a.toString().padLeft(3, '0');
    return ['$surahStr$ayahStr.mp3'];
  }

  // ─────────────────────────────────────
  //  SPANNING AYAH INJECTION (Logic 36)
  // ─────────────────────────────────────

  /// Dynamically inject a spanning ayah into the first page if it's missing.
  void _injectSpannedAyah(int fromPage, int toPage, int surah, int ayah) {
    if (_quranPages == null) return;
    final fromIndex = _quranPages!.indexWhere((p) => p.page == fromPage);
    if (fromIndex != -1) {
      final fromP = _quranPages![fromIndex];
      if (!fromP.ayahs.any((a) => a.surah == surah && a.ayah == ayah)) {
        // Find the ayah data from the target page
        final toIndex = _quranPages!.indexWhere((p) => p.page == toPage);
        if (toIndex != -1) {
          final toP = _quranPages![toIndex];
          final ayahData = toP.ayahs.firstWhere(
            (a) => a.surah == surah && a.ayah == ayah,
            orElse: () => QuranAyahData(
              surah: surah,
              surahName: '',
              ayah: ayah,
              text: '',
            ),
          );
          fromP.ayahs.add(ayahData);
        }
      }
    }
  }

  // ─────────────────────────────────────
  //  PLAYBACK
  // ─────────────────────────────────────

  /// Opens the recitation bar and starts playing from the given page.
  Future<void> playPage(int pageIndex, {bool startFromLastAyah = false, int? startFromAyahIndex, bool autoPlay = true}) async {
    if (_isChangingPage) return;
    _isChangingPage = true;
    try {
      if (_quranPages == null) await init();

    // Inject spanning ayahs (Logic 36) - dynamic, Hot Reload safe
    _injectSpannedAyah(354, 355, 24, 36); // Surah 24 Ayah 36
    _injectSpannedAyah(355, 356, 24, 42); // Surah 24 Ayah 42

    final int pageNumber = pageIndex + 1;
    _currentPageIndex = pageIndex;
    final pageData = _quranPages!.firstWhere(
      (p) => p.page == pageNumber,
      orElse: () => QuranPageData(page: pageNumber, ayahs: []),
    );

    if (pageData.ayahs.isEmpty) return;

    _playlistAyahs = pageData.ayahs;
    if (startFromAyahIndex != null) {
      _currentGlobalAyahIndex = startFromAyahIndex;
    } else {
      _currentGlobalAyahIndex = startFromLastAyah ? _playlistAyahs.length - 1 : 0;
    }
    _currentFileIndexWithinAyah = 0;
    _currentRepeatIteration = 0;

    // Show the recitation bar
    isRecitationBarVisible.value = true;

    // Download only the first ayah to play immediately
    final firstAyah = _playlistAyahs[_currentGlobalAyahIndex];
    isLoadingAudio.value = true;
    await _downloadPageAyahs([firstAyah]);
    isLoadingAudio.value = false;

    await _playCurrentAyah(autoPlay: autoPlay);

      // Download remaining ayahs + next page in background
      _downloadPageAyahs(pageData.ayahs); // Fire and forget
      _preloadNextPage(pageIndex);
    } finally {
      _isChangingPage = false;
    }
  }

  Future<void> _preloadNextPage(int currentPageIndex) async {
    final nextPageIndex = currentPageIndex + 1;
    if (nextPageIndex >= 604 || _quranPages == null) return;
    final nextPageNumber = nextPageIndex + 1;
    final nextPage = _quranPages!.firstWhere(
      (p) => p.page == nextPageNumber,
      orElse: () => QuranPageData(page: nextPageNumber, ayahs: []),
    );
    if (nextPage.ayahs.isNotEmpty) {
      _downloadPageAyahs(nextPage.ayahs); // Fire and forget
    }
  }

  /// Play a specific ayah by its index in the current playlist.
  void playAyahAtIndex(int index) {
    if (index < 0 || index >= _playlistAyahs.length) return;
    _currentGlobalAyahIndex = index;
    _currentFileIndexWithinAyah = 0;
    _currentRepeatIteration = 0;
    _playCurrentAyah();
  }

  /// Jumps to a specific surah and ayah across the entire Quran.
  Future<void> jumpToAyah(int surah, int ayah) async {
    if (_quranPages == null) await init();
    for (int i = 0; i < _quranPages!.length; i++) {
      final page = _quranPages![i];
      final index = page.ayahs.indexWhere((a) => a.surah == surah && a.ayah == ayah);
      if (index != -1) {
        onPageChangeRequired?.call(i);
        // If we are already on this page, just jump to the ayah.
        // Otherwise, initialize the page playlist and then jump.
        if (_currentPageIndex == i && _playlistAyahs.isNotEmpty) {
          playAyahAtIndex(index);
        } else {
          await playPage(i, startFromAyahIndex: index);
        }
        return;
      }
    }
  }

  Future<void> _downloadPageAyahs(List<QuranAyahData> ayahs) async {
    final dir = _cacheDir ?? await _getAudioCacheDir();

    for (final ayah in ayahs) {
      final fileNames = _getAudioFilesForAyah(ayah);
      for (final fileName in fileNames) {
        final localFile = File(p.join(dir.path, fileName));

        if (localFile.existsSync()) continue;

        try {
          final url = '$_baseUrl$fileName';
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            await localFile.writeAsBytes(response.bodyBytes, flush: true);
          }
        } catch (e) {
          debugPrint('Error downloading $fileName: $e');
        }
      }
    }
  }

  Future<void> _playCurrentAyah({bool isManualSelection = false, bool autoPlay = true}) async {
    if (_currentGlobalAyahIndex >= _playlistAyahs.length) {
      _goToNextPage();
      return;
    }

    final ayah = _playlistAyahs[_currentGlobalAyahIndex];
    currentAyah.value = ayah;
    _currentAyahFiles = _getAudioFilesForAyah(
      ayah,
      pageNumber: _currentPageIndex + 1,
    );

    // Check if it's a "silent" ayah in Qalon but needs audio from previous file
    if (_currentAyahFiles.isEmpty) {
      if (isManualSelection) {
        if (ayah.surah == 23 && ayah.ayah == 46) {
          // Manual selection of 46: Play file 45 and seek to the split point.
          _currentAyahFiles = ['023045.mp3'];
          await _playFile(
            _currentAyahFiles[0],
            seekTo: const Duration(milliseconds: 8000),
            autoPlay: autoPlay,
          );
          return;
        }
      }
      _handleAyahCompleted();
      return;
    }

    if (_currentFileIndexWithinAyah >= _currentAyahFiles.length) {
      _handleAyahCompleted();
      return;
    }

    final fileName = _currentAyahFiles[_currentFileIndexWithinAyah];
    await _playFile(fileName, autoPlay: autoPlay);

    // Set up split monitoring for UI updates
    _setupSplitMonitoring(ayah);
  }

  Future<void> _playFile(String fileName, {Duration? seekTo, bool autoPlay = true}) async {
    try {
      final dir = _cacheDir ?? await _getAudioCacheDir();
      final localFile = File(p.join(dir.path, fileName));

      if (localFile.existsSync()) {
        await _player.setFilePath(localFile.path);
      } else {
        // Fallback: stream directly
        final url = '$_baseUrl$fileName';
        await _player.setUrl(url);
      }

      if (seekTo != null) {
        await _player.seek(seekTo);
      }
      if (autoPlay) {
        _player.play();
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      // Don't call stop() here — it could cascade into more errors
    }
  }

  // ─────────────────────────────────────
  //  SPLIT MONITORING (intra-ayah UI)
  // ─────────────────────────────────────

  void _setupSplitMonitoring(QuranAyahData ayah) {
    _splitMonitorSubscription?.cancel();

    // Surah Al-Mu'minun: Split between Ayah 45 and 46
    if (ayah.surah == 23 && ayah.ayah == 45) {
      const splitTime = Duration(milliseconds: 8000);

      _splitMonitorSubscription = _player.positionStream.listen((pos) {
        if (pos >= splitTime && currentAyah.value?.ayah == 45) {
          // Update the UI to show Ayah 46
          final ayah46 = _playlistAyahs.firstWhere(
            (a) => a.surah == 23 && a.ayah == 46,
            orElse: () => QuranAyahData(
              surah: 23,
              surahName: 'المؤمنون',
              ayah: 46,
              text: '',
            ),
          );
          currentAyah.value = ayah46;
          // Update index to 46's position
          final idx = _playlistAyahs.indexOf(ayah46);
          if (idx != -1) _currentGlobalAyahIndex = idx;
        }
      });
    }
  }

  // ─────────────────────────────────────
  //  COMPLETION & NAVIGATION
  // ─────────────────────────────────────

  /// Called when a single audio file finishes.
  void _handleAyahCompleted() {
    _currentFileIndexWithinAyah++;
    if (_currentAyahFiles.isNotEmpty &&
        _currentFileIndexWithinAyah < _currentAyahFiles.length) {
      // Play next file of the SAME ayah
      _playCurrentAyah();
      return;
    }

    // Finished all files for this ayah, apply repeat logic
    final mode = repeatMode.value;

    if (mode == AyahRepeatMode.infinite) {
      // Repeat the same ayah forever
      _currentFileIndexWithinAyah = 0;
      _playCurrentAyah();
      return;
    }

    if (mode == AyahRepeatMode.count) {
      _currentRepeatIteration++;
      if (_currentRepeatIteration < repeatCount.value) {
        _currentFileIndexWithinAyah = 0;
        _playCurrentAyah();
        return;
      }
      // Done repeating, move to next
      _currentRepeatIteration = 0;
    }

    // Move to next ayah
    _currentGlobalAyahIndex++;
    _currentFileIndexWithinAyah = 0;

    // Check if we've finished all ayahs on this page → apply page repeat
    if (_currentGlobalAyahIndex >= _playlistAyahs.length) {
      final pgMode = pageRepeatMode.value;
      if (pgMode == AyahRepeatMode.infinite) {
        // Replay page forever
        _currentGlobalAyahIndex = 0;
        _playCurrentAyah();
        return;
      }
      if (pgMode == AyahRepeatMode.count) {
        _pageRepeatIteration++;
        if (_pageRepeatIteration < pageRepeatCount.value) {
          _currentGlobalAyahIndex = 0;
          _playCurrentAyah();
          return;
        }
        // Done repeating page
        _pageRepeatIteration = 0;
      }
    }

    _playCurrentAyah();
  }

  /// Go to the next ayah manually.
  void nextAyah() {
    // Debounce: ignore if less than 300ms since last change
    final now = DateTime.now();
    if (now.difference(_lastAyahChangeTime).inMilliseconds < 300) return;
    _lastAyahChangeTime = now;

    _currentRepeatIteration = 0;
    _currentFileIndexWithinAyah = 0;
    if (_currentGlobalAyahIndex < _playlistAyahs.length - 1) {
      _currentGlobalAyahIndex++;
      _playCurrentAyah();
    } else {
      _goToNextPage();
    }
  }

  /// Go to the previous ayah manually.
  void previousAyah() {
    // Debounce: ignore if less than 300ms since last change
    final now = DateTime.now();
    if (now.difference(_lastAyahChangeTime).inMilliseconds < 300) return;
    _lastAyahChangeTime = now;

    _currentRepeatIteration = 0;
    _currentFileIndexWithinAyah = 0;

    // Handle split verse navigation: if we're on a "virtual" ayah (like 23:46),
    // go back to the real ayah (23:45)
    if (_playlistAyahs.isNotEmpty &&
        _currentGlobalAyahIndex < _playlistAyahs.length) {
      final actualAyah = _playlistAyahs[_currentGlobalAyahIndex];
      if (currentAyah.value != null &&
          currentAyah.value!.ayah != actualAyah.ayah) {
        // We're on a split portion - go back to the actual ayah
        currentAyah.value = actualAyah;
        _playCurrentAyah();
        return;
      }
    }

    if (_currentGlobalAyahIndex > 0) {
      _currentGlobalAyahIndex--;
      _playCurrentAyah();
    } else {
      // Go to previous page
      if (_currentPageIndex > 0) {
        final prevPageIndex = _currentPageIndex - 1;
        onPageChangeRequired?.call(prevPageIndex);
        playPage(prevPageIndex, startFromLastAyah: true);
      } else {
        _player.seek(Duration.zero);
      }
    }
  }

  /// Cycle through repeat modes: off → 1× → 2× → 3× → infinite (∞) → off
  void cycleAyahRepeatMode() {
    _currentRepeatIteration = 0;
    final mode = repeatMode.value;
    if (mode == AyahRepeatMode.off) {
      // First tap: repeat once.
      repeatCount.value = 1;
      repeatMode.value = AyahRepeatMode.count;
    } else if (mode == AyahRepeatMode.count) {
      final current = repeatCount.value;
      if (current < 3) {
        // 1× → 2× → 3×
        repeatCount.value = current + 1;
      } else {
        // After 3× comes infinite.
        repeatMode.value = AyahRepeatMode.infinite;
      }
    } else {
      // infinite → off (cancel).
      repeatMode.value = AyahRepeatMode.off;
    }
  }

  /// Get a human-readable label for current repeat mode.
  String get repeatLabel {
    switch (repeatMode.value) {
      case AyahRepeatMode.off:
        return '';
      case AyahRepeatMode.infinite:
        return '∞';
      case AyahRepeatMode.count:
        return '${repeatCount.value}×';
    }
  }

  /// Cycle through page repeat modes: off → 1× → 2× → 3× → infinite (∞) → off
  void cyclePageRepeatMode() {
    _pageRepeatIteration = 0;
    final mode = pageRepeatMode.value;
    if (mode == AyahRepeatMode.off) {
      // First tap: repeat once.
      pageRepeatCount.value = 1;
      pageRepeatMode.value = AyahRepeatMode.count;
    } else if (mode == AyahRepeatMode.count) {
      final current = pageRepeatCount.value;
      if (current < 3) {
        // 1× → 2× → 3×
        pageRepeatCount.value = current + 1;
      } else {
        // After 3× comes infinite.
        pageRepeatMode.value = AyahRepeatMode.infinite;
      }
    } else {
      // infinite → off (cancel).
      pageRepeatMode.value = AyahRepeatMode.off;
    }
  }

  /// Get a human-readable label for current page repeat mode.
  String get pageRepeatLabel {
    switch (pageRepeatMode.value) {
      case AyahRepeatMode.off:
        return '';
      case AyahRepeatMode.infinite:
        return '∞';
      case AyahRepeatMode.count:
        return '${pageRepeatCount.value}×';
    }
  }

  /// Checks if the currently active ayah is located on the given page index.
  bool isAudioOnPage(int pageIndex) {
    if (currentAyah.value == null || _quranPages == null) return false;
    final pageNumber = pageIndex + 1;
    final pageData = _quranPages!.firstWhere(
      (p) => p.page == pageNumber,
      orElse: () => QuranPageData(page: pageNumber, ayahs: []),
    );
    return pageData.ayahs.any(
      (a) =>
          a.surah == currentAyah.value!.surah &&
          a.ayah == currentAyah.value!.ayah,
    );
  }

  Future<void> _goToNextPage() async {
    if (_playlistAyahs.isEmpty) return;

    final lastAyah = _playlistAyahs.last;

    int nextPageIndex = -1;
    for (int i = 0; i < _quranPages!.length; i++) {
      final p = _quranPages![i];
      if (p.ayahs.isNotEmpty &&
          p.ayahs.first.surah == lastAyah.surah &&
          p.ayahs.first.ayah == lastAyah.ayah + 1) {
        nextPageIndex = p.page - 1;
        break;
      }
    }

    if (nextPageIndex == -1) {
      for (int i = 0; i < _quranPages!.length; i++) {
        final p = _quranPages![i];
        if (p.ayahs.isNotEmpty &&
            p.ayahs.first.surah == lastAyah.surah + 1 &&
            p.ayahs.first.ayah == 1) {
          nextPageIndex = p.page - 1;
          break;
        }
      }
    }

    if (nextPageIndex == -1) {
      final currentPageNum = _quranPages!
          .firstWhere(
            (p) => p.ayahs.contains(lastAyah),
            orElse: () => QuranPageData(page: _currentPageIndex + 1, ayahs: []),
          )
          .page;
      nextPageIndex = currentPageNum;
    }

    if (nextPageIndex >= 0 && nextPageIndex < _quranPages!.length) {
      onPageChangeRequired?.call(nextPageIndex);
      await playPage(nextPageIndex);
    } else {
      // Don't stop unless we really reached the end of the Quran
      if (nextPageIndex >= _quranPages!.length) {
        stop();
      }
    }
  }

  void pause() {
    _player.pause();
  }

  void resume() {
    _player.play();
  }

  /// Stop playback and close the recitation bar.
  void stop() {
    _splitMonitorSubscription?.cancel();
    _player.stop();
    _player.seek(Duration.zero);
    isPlaying.value = false;
    currentAyah.value = null;
    isRecitationBarVisible.value = false;
    repeatMode.value = AyahRepeatMode.off;
    _currentRepeatIteration = 0;
    _currentFileIndexWithinAyah = 0;
    pageRepeatMode.value = AyahRepeatMode.off;
    _pageRepeatIteration = 0;
  }

  /// Close the recitation bar (stops playback).
  void closeRecitationBar() {
    stop();
  }

  void dispose() {
    _splitMonitorSubscription?.cancel();
    _player.dispose();
  }
}

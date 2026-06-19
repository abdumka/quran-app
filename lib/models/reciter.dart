/// A selectable Qur'an reciter (تلاوة).
///
/// Every reciter we ship uses the **same per-ayah Qaloun file scheme** as the
/// original Al-Husary recitation: files are named `SSSAAA.mp3` (zero-padded
/// surah + ayah) and a handful of end-of-surah ayahs are merged into one file
/// (see `AudioService._getAudioFilesForAyah`). This means adding a new reciter
/// is just a matter of pointing [audioBaseUrl] at a mirror that contains the
/// *identical* file set produced with that reciter's voice.
///
/// To stay independent of any third-party website (which may be taken down),
/// each reciter's audio must live on stable hosting **we control** — e.g. a
/// GitHub raw mirror like the existing `quran-by-verses` repos. Nothing here
/// points at a streaming/player website directly.
class Reciter {
  /// Stable identifier, persisted in SharedPreferences and used as the cache
  /// folder discriminator. Never change an existing id or users lose their
  /// downloaded audio for that reciter.
  final String id;

  /// Display name shown in the UI (Arabic).
  final String name;

  /// Short subtitle, e.g. the riwaya / extra note (Arabic).
  final String riwaya;

  /// Base URL the per-ayah MP3 files are streamed/downloaded from. Must end
  /// with a trailing slash; `audioBaseUrl + 'SSSAAA.mp3'` is the full URL.
  final String audioBaseUrl;

  /// Folder name (under the app support dir) where this reciter's MP3s are
  /// cached on disk. Kept distinct per reciter because every reciter uses the
  /// same file names (`001001.mp3` …) but different audio.
  final String cacheFolder;

  /// Audio file scheme.
  ///
  /// * `false` (Al-Husary): legacy Hafs-style filenames where a few end-of-surah
  ///   Qaloun ayahs were merged into one file (see `AudioService` merge map).
  /// * `true` (al-Naihi mirror): one file per ayah in **native Madani/Qaloun
  ///   numbering**, matching the app's page data 1:1, plus a separate basmala
  ///   file `SSS000.mp3` for every surah except At-Tawba (9). No merging.
  final bool nativeQalounScheme;

  const Reciter({
    required this.id,
    required this.name,
    required this.riwaya,
    required this.audioBaseUrl,
    required this.cacheFolder,
    this.nativeQalounScheme = false,
  });

  // ───────────────────────────────────────────────
  //  AVAILABLE RECITERS
  // ───────────────────────────────────────────────

  /// Mahmoud Khalil Al-Husary — Qaloun (the original bundled recitation).
  /// Keeps the legacy `audio_cache` folder so existing downloads survive.
  static const Reciter husaryQaloun = Reciter(
    id: 'husary_qaloun',
    name: 'محمود خليل الحصري',
    riwaya: 'رواية قالون',
    audioBaseUrl:
        'https://raw.githubusercontent.com/quran-by-verses/alhosary-qaloon-32/main/verses/',
    cacheFolder: 'audio_cache',
  );

  /// Walid Ali Al-Naihi — Qaloun.
  ///
  /// Audio is mirrored from nquran.com to our own GitHub repo (so we never
  /// depend on that site at runtime). Files sit at the repo root in native
  /// Madani numbering: `SSS000.mp3` (basmala) + `SSS001..SSSmax.mp3` per surah —
  /// see tools/download_naihi.py and [nativeQalounScheme].
  static const Reciter naihiQaloun = Reciter(
    id: 'naihi_qaloun',
    name: 'وليد علي النائحي',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://raw.githubusercontent.com/abdumka/alnaihiaudio/main/',
    cacheFolder: 'audio_cache_naihi',
    nativeQalounScheme: true,
  );

  /// Native Madani/Qaloun ayah count per surah for the al-Naihi mirror, taken
  /// from nquran.com's authoritative per-surah counts (see tools/download_naihi.py).
  /// Matches the app's page-data ayah numbering 1:1, EXCEPT a few surahs the app
  /// data numbers in Kufi style — e.g. surah 4 (app 176 vs Madani 175): the app's
  /// extra trailing ayah has no distinct al-Naihi file (its audio is part of the
  /// previous, combined ayah), so the mapping treats it as a silent "phantom".
  static const List<int> naihiMadaniAyahCounts = [
    7,   285, 200, 175, 122, 167, 206, 76,  130, 109, // 1-10
    122, 111, 44,  54,  99,  128, 110, 105, 98,  134, // 11-20
    111, 76,  119, 62,  77,  227, 95,  88,  69,  60,  // 21-30
    33,  30,  73,  54,  45,  82,  181, 86,  72,  84,  // 31-40
    53,  50,  89,  56,  36,  34,  39,  29,  18,  45,  // 41-50
    60,  47,  61,  55,  77,  99,  28,  22,  24,  13,  // 51-60
    14,  11,  11,  18,  12,  12,  30,  52,  52,  44,  // 61-70
    30,  28,  20,  56,  39,  31,  50,  40,  45,  41,  // 71-80
    28,  19,  36,  25,  22,  16,  19,  26,  32,  20,  // 81-90
    16,  21,  11,  8,   8,   20,  5,   8,   8,   11,  // 91-100
    10,  8,   3,   9,   5,   5,   6,   3,   6,   3,   // 101-110
    5,   4,   5,   6,                                   // 111-114
  ];

  /// All reciters offered in the picker, in display order.
  static const List<Reciter> all = [husaryQaloun, naihiQaloun];

  /// The reciter used before the user has chosen one.
  static const Reciter fallback = husaryQaloun;

  static Reciter byId(String? id) {
    return all.firstWhere(
      (r) => r.id == id,
      orElse: () => fallback,
    );
  }
}

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

  /// Whether this reciter uses الوقف الهبطي — he recites several ayat together in
  /// one breath, so the source serves byte-identical audio for those ayat. When
  /// true, the app skips the "continuation" ayat (see assets/data/
  /// qaniwah_continuations.json) so each breath plays once and then jumps to the
  /// next distinct ayah.
  final bool breathCombining;

  const Reciter({
    required this.id,
    required this.name,
    required this.riwaya,
    required this.audioBaseUrl,
    required this.cacheFolder,
    this.nativeQalounScheme = false,
    this.breathCombining = false,
  });

  // ───────────────────────────────────────────────
  //  AVAILABLE RECITERS
  // ───────────────────────────────────────────────

  /// Mahmoud Khalil Al-Husary — Qaloun (the original bundled recitation).
  /// Keeps the legacy `audio_cache` folder so existing downloads survive.
  ///
  /// Served from our Cloudflare R2 bucket (same bucket as al-Naihi/قنيوه) under
  /// `alhosary/`, mirrored 1:1 from the original GitHub raw repo (6236 files) via
  /// tools/mirror_alhusary_to_r2.py. Legacy Hafs-style filenames with a few
  /// end-of-surah ayat merged into one file (see AudioService `_mergedThresholds`).
  static const Reciter husaryQaloun = Reciter(
    id: 'husary_qaloun',
    name: 'محمود خليل الحصري',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://pub-f4e99834c32943d2a947531d938b19f6.r2.dev/alhosary/',
    cacheFolder: 'audio_cache',
  );

  /// Walid Ali Al-Naihi — Qaloun.
  ///
  /// Audio is mirrored from nquran.com to our own Cloudflare R2 bucket (so we
  /// never depend on that site at runtime), in the same bucket as قنيوه under an
  /// `Alnaihi/` folder. Native Madani numbering: `SSS000.mp3` (basmala) +
  /// `SSS001..SSSmax.mp3` per surah — see tools/download_naihi.py and
  /// [nativeQalounScheme]. (Previously served from a GitHub raw mirror.)
  ///
  /// Known source gap: nquran lacks al-Naihi's Yusuf 012111.mp3 (verified 404 on
  /// nquran and both mirrors, though nquran's inventory claims 111 ayat), so
  /// Yusuf's last ayah has no al-Naihi audio — a source limitation, not the CDN.
  static const Reciter naihiQaloun = Reciter(
    id: 'naihi_qaloun',
    name: 'وليد علي النائحي',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://pub-f4e99834c32943d2a947531d938b19f6.r2.dev/Alnaihi/',
    cacheFolder: 'audio_cache_naihi',
    nativeQalounScheme: true,
  );

  /// Native Madani/Qaloun ayah count per surah for the al-Naihi mirror, taken
  /// from nquran.com's authoritative per-surah counts (see tools/download_naihi.py).
  /// Now matches the app's page-data ayah numbering 1:1 for every surah. (Surah 4
  /// used to differ — the page data numbered it Kufi-style as 176 vs Madani 175 —
  /// but the page data now uses the Madani 175 count, so no silent "phantom"
  /// trailing ayah remains.)
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

  /// Al-Amin Muhammad Qaniwah — Qaloun, recited with الوقف الهبطي (combines ayat
  /// in one breath). Audio mirrored from nquran.com to a Cloudflare R2 bucket.
  /// Reuses the same Qaloun ayah counts + audio map as al-Naihi (same source),
  /// plus [breathCombining] to skip the repeated-breath ayat.
  static const Reciter qaniwahQaloun = Reciter(
    id: 'qaniwah_qaloun',
    name: 'الأمين محمد قنيوه',
    riwaya: 'رواية قالون ',
    audioBaseUrl: 'https://pub-f4e99834c32943d2a947531d938b19f6.r2.dev/qaniwah/',
    cacheFolder: 'audio_cache_qaniwah',
    nativeQalounScheme: true,
    breathCombining: true,
  );

  /// All reciters offered in the picker, in display order.
  static const List<Reciter> all = [husaryQaloun, naihiQaloun, qaniwahQaloun];

  /// The reciter used before the user has chosen one.
  static const Reciter fallback = husaryQaloun;

  static Reciter byId(String? id) {
    return all.firstWhere(
      (r) => r.id == id,
      orElse: () => fallback,
    );
  }
}

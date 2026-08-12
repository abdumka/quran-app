/// How a reciter's mirror maps a *displayed* (output.json) ayah to file name(s).
///
/// Mirrors the `scheme` field the web player uses for the same mirrors (see
/// tools/build_web_player_data.py), so both surfaces describe an audio set the
/// same way.
enum AudioScheme {
  /// Al-Husary: legacy Hafs-style filenames where the trailing Qaloun ayat of a
  /// few surahs were merged into one file (see `AudioService`'s merge table).
  mergedTail,

  /// al-Naihi / قنيوه: one file per ayah in native Madani/Qaloun numbering, plus
  /// a separate basmala file `SSS000.mp3` for every surah except At-Tawba (9),
  /// with the displayed→recited ayah differences resolved via the audio map.
  nativeQaloun,

  /// al-Hudaifi: file `SSSAAA.mp3` *is* the displayed ayah — no basmala file, no
  /// merged tails, no remapping. The only exception is [Reciter.coveredAyat]:
  /// ayat whose own file holds a silent placeholder rather than a recitation,
  /// which must be skipped.
  covered,
}

/// A selectable Qur'an reciter (تلاوة).
///
/// Every reciter we ship names its files `SSSAAA.mp3` (zero-padded surah +
/// ayah); what differs between mirrors is only *which* file a displayed ayah
/// resolves to, which [scheme] captures. Adding a new reciter is therefore a
/// matter of pointing [audioBaseUrl] at a mirror of that file set and picking
/// the scheme it follows.
///
/// To stay independent of any third-party website (which may be taken down),
/// each reciter's audio must live on stable hosting **we control** — today the
/// `quran-audio` Cloudflare R2 bucket behind audio.mushaf-qaloon.com. Nothing
/// here points at a streaming/player website directly.
class Reciter {
  /// Stable identifier, persisted in SharedPreferences and used as the cache
  /// folder discriminator. Never change an existing id or users lose their
  /// downloaded audio for that reciter.
  final String id;

  /// Full display name (Arabic), used wherever there is room for it.
  final String name;

  /// Compact form of [name] for narrow slots that would otherwise ellipsize —
  /// the two reciter dropdowns and the OS media notification. Defaults to
  /// [name] for reciters whose full name is already short.
  final String shortName;

  /// Short subtitle, e.g. the riwaya / extra note (Arabic).
  final String riwaya;

  /// Base URL the per-ayah MP3 files are streamed/downloaded from. Must end
  /// with a trailing slash; `audioBaseUrl + 'SSSAAA.mp3'` is the full URL.
  final String audioBaseUrl;

  /// Folder name (under the app support dir) where this reciter's MP3s are
  /// cached on disk. Kept distinct per reciter because every reciter uses the
  /// same file names (`001001.mp3` …) but different audio.
  final String cacheFolder;

  /// How this mirror's file names line up with the displayed ayah numbers.
  final AudioScheme scheme;

  /// [AudioScheme.covered] only: surah → the ayat this sheikh reads as part of a
  /// neighbouring ayah. Their own `SSSAAA.mp3` exists but holds silence, so
  /// playback skips them (see [breathCombining] for the same idea under the
  /// native scheme).
  final Map<int, Set<int>> coveredAyat;

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
    String? shortName,
    this.scheme = AudioScheme.mergedTail,
    this.coveredAyat = const {},
    this.breathCombining = false,
  }) : shortName = shortName ?? name;

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
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/alhosary/',
    cacheFolder: 'audio_cache',
  );

  /// Walid Ali Al-Naihi — Qaloun.
  ///
  /// Audio is mirrored from nquran.com to our own Cloudflare R2 bucket (so we
  /// never depend on that site at runtime), in the same bucket as قنيوه under an
  /// `Alnaihi/` folder. Native Madani numbering: `SSS000.mp3` (basmala) +
  /// `SSS001..SSSmax.mp3` per surah — see tools/download_naihi.py and
  /// [AudioScheme.nativeQaloun]. (Previously served from a GitHub raw mirror.)
  ///
  /// Known source gap: nquran lacks al-Naihi's Yusuf 012111.mp3 (verified 404 on
  /// nquran and both mirrors, though nquran's inventory claims 111 ayat), so
  /// Yusuf's last ayah has no al-Naihi audio — a source limitation, not the CDN.
  static const Reciter naihiQaloun = Reciter(
    id: 'naihi_qaloun',
    name: 'وليد علي النائحي',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/Alnaihi/',
    cacheFolder: 'audio_cache_naihi',
    scheme: AudioScheme.nativeQaloun,
  );

  /// Madani/Qaloun ayah count per surah, taken from nquran.com's authoritative
  /// per-surah counts (see tools/download_naihi.py). Matches the app's page-data
  /// ayah numbering 1:1 for every surah — 6214 ayat in total — so it doubles as
  /// the per-surah file count for every mirror except Al-Husary's merged-tail
  /// one. (Surah 4 used to differ — the page data numbered it Kufi-style as 176
  /// vs Madani 175 — but the page data now uses the Madani 175 count, so no
  /// silent "phantom" trailing ayah remains.)
  static const List<int> madaniAyahCounts = [
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
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/qaniwah/',
    cacheFolder: 'audio_cache_qaniwah',
    scheme: AudioScheme.nativeQaloun,
    breathCombining: true,
  );

  /// Ali ibn Abdurrahman Al-Hudaifi — Qaloun.
  ///
  /// The simplest mirror we host: file `SSSAAA.mp3` is exactly the displayed
  /// ayah, for all 6214 of them. There is no basmala file (`SSS000.mp3` 404s
  /// everywhere) and no merged tail — every surah has exactly
  /// [madaniAyahCounts] files, verified by a full HEAD sweep of the bucket.
  /// The 24 ayat in [hudaifiCoveredAyat] are the only special case.
  static const Reciter hudaifiQaloun = Reciter(
    id: 'hudaifi_qaloun',
    name: 'علي بن عبدالرحمن الحذيفي',
    shortName: 'علي الحذيفي',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/Hudaifi/',
    cacheFolder: 'audio_cache_hudaifi',
    scheme: AudioScheme.covered,
    coveredAyat: hudaifiCoveredAyat,
  );

  /// Ayat whose al-Hudaifi file carries no recitation: a 0.34 s placeholder,
  /// byte-identical (1579 bytes) across all of them, because the sheikh reads
  /// the verse as part of a neighbouring ayah's file. Skipping them keeps the
  /// highlight on the ayah being recited instead of blinking through silence.
  ///
  /// Found by sweeping every file in the bucket for tiny sizes, so this list has
  /// 24 entries where the web player's source page (mushaf3.html) declares only
  /// 20 — 14:23, 18:35, 18:87 and 91:15 are silent placeholders there too.
  static const Map<int, Set<int>> hudaifiCoveredAyat = {
    2: {218},
    11: {121},
    14: {23},
    18: {24, 35, 87},
    20: {87, 88},
    26: {211},
    30: {2, 55},
    40: {54},
    44: {42},
    56: {25, 29, 53},
    65: {10},
    71: {25},
    73: {2, 18},
    74: {41},
    91: {15},
    93: {2},
    103: {2},
  };

  /// All reciters offered in the picker, in display order.
  static const List<Reciter> all = [
    husaryQaloun,
    naihiQaloun,
    qaniwahQaloun,
    hudaifiQaloun,
  ];

  /// The reciter used before the user has chosen one.
  static const Reciter fallback = husaryQaloun;

  static Reciter byId(String? id) {
    return all.firstWhere(
      (r) => r.id == id,
      orElse: () => fallback,
    );
  }
}

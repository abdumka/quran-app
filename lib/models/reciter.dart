import 'doukali_covered_ayat.dart';

/// How a reciter's mirror maps a *displayed* (output.json) ayah to file name(s).
///
/// Mirrors the `scheme` field the web player uses for the same mirrors (see
/// tools/build_web_player_data.py), so both surfaces describe an audio set the
/// same way.
enum AudioScheme {
  /// Al-Husary: legacy Hafs-style filenames where the trailing Qaloun ayat of a
  /// few surahs were merged into one file (see `AudioService`'s merge table).
  mergedTail,

  /// al-Naihi / قنيوه / أبوسنينة: one file per ayah in native Madani/Qaloun
  /// numbering, plus a separate basmala file `SSS000.mp3` for every surah except
  /// At-Tawba (9), with the displayed→recited ayah differences resolved via the
  /// audio map.
  nativeQaloun,

  /// al-Hudaifi: file `SSSAAA.mp3` *is* the displayed ayah — no basmala file, no
  /// merged tails, no remapping. The only exception is [Reciter.coveredAyat]:
  /// ayat whose own file holds a silent placeholder rather than a recitation,
  /// which must be skipped.
  covered,

  /// عبدالحميد القريو: one MP3 per *surah* (`SSS.mp3`) plus a per-surah timing
  /// file (`timings/SSS.json`) giving each ayah's start/end inside it. Playback
  /// seeks to the span rather than loading a separate file, via
  /// `ClippingAudioSource` — which reports the span's end as
  /// `ProcessingState.completed`, so every repeat mode behaves identically to
  /// the per-ayah schemes without knowing the difference.
  ///
  /// The timing file carries everything the other schemes keep in Dart tables:
  /// the basmala is folded into ayah 1's own span (the standard for every
  /// surah except At-Tawba, which has none), not a separate span of its own —
  /// and an ayah with a `null` span has no audio of its own (never published,
  /// or recited inside a neighbour's breath). So a reciter on this scheme
  /// needs no [Reciter.coveredAyat], [Reciter.missingAyat] or
  /// [Reciter.continuationsAsset].
  ///
  /// Requires the audio to be **constant bitrate** — VBR without a seek table
  /// makes a deep seek land seconds off, which would break every boundary.
  timedSurah,
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

  /// Base URL the MP3 files are streamed/downloaded from. Must end with a
  /// trailing slash; `audioBaseUrl + 'SSSAAA.mp3'` is the full URL for a
  /// per-ayah mirror, `audioBaseUrl + 'SSS.mp3'` for [AudioScheme.timedSurah].
  final String audioBaseUrl;

  /// [AudioScheme.timedSurah] only: where the per-surah timing JSONs live.
  ///
  /// Deliberately NOT beside the audio. The MP3s are played through an
  /// `<audio>` element, which needs no CORS, but the timings are fetched with
  /// `http.get` — and on the Flutter web build that is a cross-origin request
  /// the browser blocks unless the host allows it. `audio.mushaf-qaloon.com`
  /// sends no `Access-Control-Allow-Origin`; `quran-content.mushaf-qaloon.com`
  /// already sends `*` (it serves the tafsir JSON the same way). Hosting the
  /// timings there makes web work with no Cloudflare change — and if this ever
  /// moves back to the audio host, that bucket must get CORS first or the web
  /// build will fetch nothing and play nothing.
  final String? timingsBaseUrlOverride;

  String get timingsBaseUrl =>
      timingsBaseUrlOverride ?? '${audioBaseUrl}timings/';

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
  /// true, the app skips the "continuation" ayat listed in
  /// [continuationsAsset] so each breath plays once and then jumps to the next
  /// distinct ayah.
  final bool breathCombining;

  /// [breathCombining] only: the bundled JSON holding this sheikh's breath
  /// groups (and the surahs whose ayah-1 file already contains the basmala).
  /// Every reciter has his own — the groups are a property of how *he* recites,
  /// not of the riwaya — so they must never be shared between reciters.
  final String? continuationsAsset;

  /// Ayat this mirror has no audio for at all, because the upstream source
  /// never published them (surah → ayat). Distinct from [coveredAyat], where a
  /// file exists but holds silence, and from a breath continuation, where the
  /// audio played as part of an earlier ayah: here there is simply nothing.
  ///
  /// Playback returns no file for these (so it advances to the next ayah
  /// instead of stalling on a 404), and the offline download leaves them out of
  /// its file list — otherwise "التحميل مكتمل" could never be reached.
  final Map<int, Set<int>> missingAyat;

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
    this.continuationsAsset,
    this.missingAyat = const {},
    this.timingsBaseUrlOverride,
  }) : shortName = shortName ?? name;

  /// Whether ([surah], [ayah]) is one of this mirror's upstream gaps.
  bool isMissing(int surah, int ayah) =>
      missingAyat[surah]?.contains(ayah) ?? false;

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
    missingAyat: {12: {111}},
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
    continuationsAsset: 'assets/data/qaniwah_continuations.json',
  );

  /// Muhammad Abu Senainah (محمد أبوسنينة) — Qaloun, recited with الوقف الهبطي.
  ///
  /// On [AudioScheme.timedSurah]: 114 whole-surah MP3s plus `timings/SSS.json`.
  /// Source is the same midad مرتّل khatma as before, but delivered whole rather
  /// than pre-cut, which is what lets the quality be what it is (below).
  ///
  /// **He is هبطي**, so several ayat share one breath. The timings express that
  /// the same way the per-ayah mirrors did: the covering ayah's span runs to the
  /// end of its whole breath and the ayat it swallows have no span at all, so
  /// `clipsFor` returns `[]` and playback advances. 1080 ayat across 724 breaths
  /// are grouped this way — the same set, cross-checked against قنيوه, that the
  /// per-ayah build used. Nothing a listener does behaves differently: sequential
  /// playback, single-ayah repeat, page/thumn/range repeat and offline download
  /// all work exactly as they do for every other reciter.
  ///
  /// Quality: 113 of the 114 source files were already CBR, so they are passed
  /// through **bit-for-bit** (`-c:a copy`) — no second lossy generation at all.
  /// Only surah 28 was VBR at source and had to be re-encoded (128 kbps CBR,
  /// above its ~102 kbps average). CBR matters here because every ayah boundary
  /// is a seek, and a deep seek into a VBR file without a seek table lands off.
  ///
  /// The older per-ayah build is still live at `abusenainah/` and is deliberately
  /// left in place; this entry points at `abusenainah_timed/` instead.
  static const Reciter abusenainahQaloun = Reciter(
    id: 'abusenainah_qaloun',
    name: 'محمد أبوسنينة',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/abusenainah_timed/',
    cacheFolder: 'audio_cache_abusenainah_timed',
    scheme: AudioScheme.timedSurah,
    // See [timingsBaseUrlOverride]: the audio host sends no CORS header, so the
    // web build could not fetch these from beside the MP3s.
    timingsBaseUrlOverride:
        'https://quran-content.mushaf-qaloon.com/timings/abusenainah_timed/',
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

  /// Al-Dokali Mohammed Al-Alem (الدوكالي محمد العالم) — Qaloun.
  ///
  /// A continuous khatma cut per-ayah with the same pipeline as the Hudaifi
  /// set: file `SSSAAA.mp3` is exactly the displayed ayah for all 6214, no
  /// basmala file (`SSS000.mp3` 404s) and no merged tail — verified by probing
  /// the surah boundaries on the bucket. The 1194 ayat he reads inside a
  /// neighbouring ayah's file are silent 1579-byte placeholders, listed in the
  /// generated [doukaliCoveredAyat] (see that file's header to regenerate).
  static const Reciter doukaliQaloun = Reciter(
    id: 'doukali_qaloun',
    name: 'الدوكالي محمد العالم',
    shortName: 'الدوكالي العالم',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/doukali/',
    cacheFolder: 'audio_cache_doukali',
    scheme: AudioScheme.covered,
    coveredAyat: doukaliCoveredAyat,
  );

  /// Abdul Hamid Al-Qryw (عبدالحميد القريو) — Qaloun.
  ///
  /// The first reciter on [AudioScheme.timedSurah]: 114 whole-surah MP3s plus
  /// `timings/SSS.json`, instead of 6214 per-ayah files. Nothing about the
  /// listening experience differs — see that scheme's note for why every repeat
  /// mode still works.
  ///
  /// Source: midad.com collection 464608 ("مصحف عبدالحميد القريو - قالون - مرتل",
  /// narration id 4 = قالون عن نافع), mirrored to our own R2 bucket like every
  /// other reciter. way2quran serves the identical master; islamweb blocks
  /// direct fetches.
  ///
  /// Two source facts worth keeping:
  ///   * midad's and way2quran's published `015.mp3` is **الحجر recorded
  ///     twice**, joined at a 0.6s silence at 942.99s — 32.4 min where ~15.5 is
  ///     right, and re-downloading from either site will not fix it. Our
  ///     mirror's surah 15 comes from a different, complete recording (an
  ///     islamweb.net.qa copy) instead: shape-correlates at 0.976 against a
  ///     verified reference reciter (matching the khatma-wide median, up from
  ///     0.66–0.68 for either half of the doubled file) and flags zero outlier
  ///     ayat, versus 21–34 for the doubled file's two halves.
  ///   * The published audio is VBR with no seek table, which would make a deep
  ///     seek land seconds off. Our mirror is re-encoded to 128 kbps **CBR**
  ///     before alignment, so the timings match what the app actually plays.
  static const Reciter alqrywQaloun = Reciter(
    id: 'alqryw_qaloun',
    name: 'عبدالحميد القريو',
    shortName: 'عبدالحميد القريو',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/alqryw/',
    cacheFolder: 'audio_cache_alqryw',
    scheme: AudioScheme.timedSurah,
    // See [timingsBaseUrlOverride]: the audio host sends no CORS header, so the
    // web build could not fetch these from beside the MP3s.
    timingsBaseUrlOverride:
        'https://quran-content.mushaf-qaloon.com/timings/alqryw/',
  );

  /// All reciters offered in the picker, in display order.
  ///
  static const List<Reciter> all = [
    husaryQaloun,
    naihiQaloun,
    qaniwahQaloun,
    hudaifiQaloun,
    doukaliQaloun,
    alqrywQaloun,
    abusenainahQaloun,
  ];

  /// Every reciter the code knows about, including any not currently offered in
  /// the picker. Use this for anything that must work for a reciter regardless
  /// of whether it is listed — loading [continuationsAsset]s, tests — and [all]
  /// only for what the user can actually choose.
  static const List<Reciter> allDefined = all;

  /// The reciter used before the user has chosen one.
  static const Reciter fallback = husaryQaloun;

  static Reciter byId(String? id) {
    return all.firstWhere(
      (r) => r.id == id,
      orElse: () => fallback,
    );
  }
}

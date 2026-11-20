import '../data/recitation_end_caps.dart';
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

  /// قنيوه (and al-Naihi before he moved to [timedSurah]): one file per ayah in native Madani/Qaloun
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
///
/// Every reciter in [all] also needs his own page-turn moments for the five
/// ayat printed across a page break — where in his audio he finishes the last
/// word on the earlier page (lib/page_turn_cues.dart). They are measured from
/// the recording by tools/measure_page_turn_cues.py, and
/// test/page_turn_cues_test.dart fails until a new reciter has them.
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

  /// [AudioScheme.timedSurah] only: bumped whenever the published timing files
  /// are corrected. A phone keeps a surah's timings on disk once fetched and
  /// never asks again, so without this a correction would only ever reach
  /// people who had not played that surah yet. Each revision is stored in its
  /// own folder (see `SurahTimingsService`), so a bump makes every surah
  /// re-fetch once; the audio cache is untouched.
  final int timingsRevision;

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
    this.timingsRevision = 1,
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
  /// On [AudioScheme.timedSurah] since 2026-10-01: 114 whole-surah MP3s plus
  /// `timings/SSS.json`, aligned against the app's own text, so the displayed
  /// numbering needs no audio map. Source: midad.com collection 35347 ("مصحف
  /// وليد النائحي - قالون عن نافع من طريق أبي نشيط - مرتل", complete), the
  /// same recording as the per-ayah set. Every file was already CBR (64 kbps),
  /// so the audio is passed through bit-for-bit. He does not use الوقف الهبطي.
  ///
  /// The id is unchanged so a saved choice survives; the cache folder is new
  /// because the file names differ (`SSS.mp3`, not `SSSAAA.mp3`). The older
  /// per-ayah nquran mirror is still live at `Alnaihi/` and is left in place.
  static const Reciter naihiQaloun = Reciter(
    id: 'naihi_qaloun',
    name: 'وليد علي النائحي',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/naihi_timed/',
    cacheFolder: 'audio_cache_naihi_timed',
    scheme: AudioScheme.timedSurah,
    // See [timingsBaseUrlOverride]: the audio host sends no CORS header, so the
    // web build could not fetch these from beside the MP3s.
    timingsBaseUrlOverride:
        'https://quran-content.mushaf-qaloon.com/timings/naihi_timed/',
    // 2 (2026-10-15): reviewer corrections -- 21 boundaries moved, 16:32 read
    // inside 16:31, and 56:30's start nudged off a byte where Chrome's seek
    // landed on a false MP3 frame header and stopped playback.
    timingsRevision: 2,
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
  /// Reuses the Qaloun ayah counts + audio map built for al-Naihi's nquran mirror,
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
  /// the surah boundaries on the bucket. The 1193 ayat he reads inside a
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

  /// Ahmad Saleh Rajab (أحمد صالح رجب) — Qaloun.
  ///
  /// On [AudioScheme.timedSurah]: 114 whole-surah MP3s plus `timings/SSS.json`.
  /// Source: midad.com collection 465947 («مصحف أحمد بن صالح رجب - قالون»,
  /// narration id 4 = قالون عن نافع). The owner's spelling of the name has no
  /// «بن» — keep it that way wherever it is shown.
  ///
  /// The published audio is VBR with no seek table (48 kHz mono, ~150 kbps);
  /// our mirror is re-encoded to 128 kbps mono **CBR** before alignment, so the
  /// timings match what the app actually plays.
  static const Reciter rajabQaloun = Reciter(
    id: 'rajab_qaloun',
    name: 'أحمد صالح رجب',
    shortName: 'أحمد صالح رجب',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/rajab/',
    cacheFolder: 'audio_cache_rajab',
    scheme: AudioScheme.timedSurah,
    // See [timingsBaseUrlOverride]: the audio host sends no CORS header, so the
    // web build could not fetch these from beside the MP3s.
    timingsBaseUrlOverride:
        'https://quran-content.mushaf-qaloon.com/timings/rajab/',
  );

  /// Nouraldin al-Mislati (نورالدين المسلاتي) — Qaloun.
  ///
  /// On [AudioScheme.timedSurah]: 114 whole-surah MP3s plus `timings/SSS.json`.
  /// Source: the sheikh's own Telegram channel (t.me/Nouraldinrecitation), a
  /// complete khatma at 320 kbps CBR; our mirror is 128 kbps mono **CBR**. The
  /// owner asked for الاستعاذة to be removed from every surah but al-Fatiha;
  /// measured, only al-Fatiha has one (kept in the file, outside every span).
  ///
  /// Timings revision 2 (2026-10-19): where he reads ayat without stopping, the
  /// group is one clip on its first ayah (452 ayat in 368 groups, e.g. 20:24-29)
  /// and the others have no span, as for the other joining reciters.
  ///
  /// Timings revision 3 (2026-11-07, owner's list): 56:70, 84:12 and 92:10
  /// joined; 3:33, 11:81, 15:92, 16:43 and 25:41 start at his second reading,
  /// the first one (read alone before the joined re-reading) is in no span.
  /// Builds that bundle revision 2 get 3 from the server `reciters` override.
  static const Reciter almislatiQaloun = Reciter(
    id: 'almislati_qaloun',
    name: 'نورالدين المسلاتي',
    shortName: 'نورالدين المسلاتي',
    riwaya: 'رواية قالون',
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/almislati/',
    cacheFolder: 'audio_cache_almislati',
    scheme: AudioScheme.timedSurah,
    // See [timingsBaseUrlOverride]: the audio host sends no CORS header, so the
    // web build could not fetch these from beside the MP3s.
    timingsBaseUrlOverride:
        'https://quran-content.mushaf-qaloon.com/timings/almislati/',
    timingsRevision: 3,
  );

  /// Ahmad Khadr Al-Trabulsi (أحمد خضر الطرابلسي) — Qaloun.
  ///
  /// On [AudioScheme.timedSurah]: 114 whole-surah MP3s plus `timings/SSS.json`.
  /// Source: midad.com collection 461010 («مصحف أحمد خضر الطرابلسي - قالون -
  /// مرتل», narration id 4 = قالون عن نافع).
  ///
  /// The published audio is VBR with no seek table (16 kHz mono, ~28 kbps);
  /// our mirror is re-encoded to 48 kbps mono **CBR** at the same 16 kHz
  /// before alignment, so the timings match what the app actually plays.
  static const Reciter trabulsiQaloun = Reciter(
    id: 'trabulsi_qaloun',
    name: 'أحمد خضر الطرابلسي',
    shortName: 'أحمد الطرابلسي',
    riwaya: 'رواية قالون بتقليل التوراة',
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/trabulsi/',
    cacheFolder: 'audio_cache_trabulsi',
    scheme: AudioScheme.timedSurah,
    // See [timingsBaseUrlOverride]: the audio host sends no CORS header, so the
    // web build could not fetch these from beside the MP3s.
    timingsBaseUrlOverride:
        'https://quran-content.mushaf-qaloon.com/timings/trabulsi/',
    // 2026-11-07: owner's joins (1:6+7, 55:33+34, 56:8+9/10+11/28+29/43+44,
    // 96:15+16, 106:4+5) and two moved boundaries (17:13, 18:91).
    timingsRevision: 2,
  );

  /// Mohammed Khalil Al-Zarrouq (محمد خليل الزروق) — Qaloun.
  ///
  /// On [AudioScheme.timedSurah]: 114 whole-surah MP3s plus `timings/SSS.json`.
  /// Source: midad.com collection 465737 («مصحف محمد خليلي الزروق - مرتل»,
  /// narration id 4 = قالون عن نافع). midad's collection title spells him
  /// «خليلي»; the owner's spelling is «محمد خليل الزروق».
  ///
  /// The published audio is VBR with no seek table (44.1 kHz stereo,
  /// ~160 kbps); our mirror is re-encoded to 128 kbps stereo **CBR** before
  /// alignment, so the timings match what the app actually plays. Each file
  /// ends with ~5 s of silence, left outside the last ayah's span. midad's
  /// 040.mp3 appears to be missing part of 40:83 («بالله وحده … مشركين»).
  static const Reciter zarrouqQaloun = Reciter(
    id: 'zarrouq_qaloun',
    name: 'محمد خليل الزروق',
    shortName: 'محمد خليل الزروق',
    riwaya: 'رواية قالون بتقليل التوراة',
    audioBaseUrl: 'https://audio.mushaf-qaloon.com/zarrouq/',
    cacheFolder: 'audio_cache_zarrouq',
    scheme: AudioScheme.timedSurah,
    // See [timingsBaseUrlOverride]: the audio host sends no CORS header, so the
    // web build could not fetch these from beside the MP3s.
    timingsBaseUrlOverride:
        'https://quran-content.mushaf-qaloon.com/timings/zarrouq/',
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
    rajabQaloun,
    almislatiQaloun,
    trabulsiQaloun,
    zarrouqQaloun,
  ];

  /// Every reciter the code knows about, including any not currently offered in
  /// the picker. Use this for anything that must work for a reciter regardless
  /// of whether it is listed — loading [continuationsAsset]s, tests — and [all]
  /// only for what the user can actually choose.
  static const List<Reciter> allDefined = all;

  /// The reciter used before the user has chosen one, and whenever a stored id
  /// no longer matches anything in [all].
  ///
  /// Only affects users who have not picked: a saved choice is resolved by
  /// [byId] and is never overridden. [all] keeps its own order regardless —
  /// this is the default, not the first entry.
  static const Reciter fallback = naihiQaloun;

  /// Reciters that reached this phone through a server update (see
  /// `ContentUpdateService` and `ReciterService.applyRemote`), and the
  /// bundled ones as that update adjusted them. Replaced wholesale, never
  /// edited in place.
  static List<Reciter> remote = const [];
  static Map<String, Reciter> _overridden = const {};
  static Set<String> _hidden = const {};
  static List<String> _order = const [];
  static Set<String> _recordingReplaced = const {};

  /// What the picker shows: [all] (with any server override: a newer timings
  /// revision, a new label, a replaced recording) followed by the
  /// server-added reciters, minus the ones the server hid, in the server's
  /// `order` when it sent one (ids it does not name keep their place after
  /// the named ones).
  static List<Reciter> get offered {
    final list = [
      for (final r in all)
        if (!_hidden.contains(r.id)) _overridden[r.id] ?? r,
      ...remote,
    ];
    if (_order.isEmpty) return list;
    final rank = {for (var i = 0; i < _order.length; i++) _order[i]: i};
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final ra = rank[a.$2.id] ?? _order.length + a.$1;
      final rb = rank[b.$2.id] ?? _order.length + b.$1;
      return ra.compareTo(rb);
    });
    return [for (final e in indexed) e.$2];
  }

  /// The offered reciter with [id]. Anything else (an unknown id, a reciter
  /// the server hid) resolves to [fallback], or to the first offered reciter
  /// when the fallback itself is hidden.
  static Reciter byId(String? id) {
    final list = offered;
    for (final r in list) {
      if (r.id == id) return r;
    }
    for (final r in list) {
      if (r.id == fallback.id) return r;
    }
    return list.isNotEmpty ? list.first : fallback;
  }

  /// The bundled reciter [id] as the server overrides left it, hidden or
  /// not; [fallback] for an id that is not bundled.
  static Reciter byIdIncludingHidden(String id) {
    for (final r in all) {
      if (r.id == id) return _overridden[id] ?? r;
    }
    return fallback;
  }

  /// Whether a server override gave the bundled reciter [id] a different
  /// recording ([overrideFromJson]'s `recording`). Its compiled page-turn
  /// cues then belong to audio it no longer plays.
  static bool recordingReplaced(String id) => _recordingReplaced.contains(id);

  /// The cache folders bundled reciters used before the server replaced their
  /// recording, and that no offered reciter uses any more: their files are
  /// audio the app will never play again.
  static Set<String> get retiredCacheFolders {
    final inUse = {
      for (final r in offered) r.cacheFolder,
      for (final r in all) _overridden[r.id]?.cacheFolder ?? r.cacheFolder,
    };
    return {
      for (final r in all)
        if (_recordingReplaced.contains(r.id) && !inUse.contains(r.cacheFolder))
          r.cacheFolder,
    };
  }

  /// Installs a parsed `reciters_v<N>.json` (see [fromJson]). Server-added
  /// reciters whose id a later build bundles are skipped: the bundled
  /// definition wins, so an app update never shows one twice.
  ///
  /// [overrides] (default: the file's own `overrides`) and [order] (default:
  /// its `order`) let the caller keep what it installed at launch while a
  /// newer file adds reciters mid-run (see `ReciterService.applyRemote`).
  static void installRemote(
    Map<String, dynamic> json, {
    Object? overrides = _fromFile,
    Object? order = _fromFile,
  }) {
    final bundledIds = {for (final r in all) r.id};
    final added = <Reciter>[];
    for (final item in (json['reciters'] as List<dynamic>? ?? const [])) {
      if (item is! Map<String, dynamic>) continue;
      final r = Reciter.fromJson(item);
      if (r == null || bundledIds.contains(r.id)) continue;
      if (added.any((x) => x.id == r.id)) continue;
      added.add(r);
    }
    final rawOverrides = identical(overrides, _fromFile)
        ? json['overrides']
        : overrides;
    final rawOrder = identical(order, _fromFile) ? json['order'] : order;
    final overridden = <String, Reciter>{};
    final hidden = <String>{};
    final replaced = <String>{};
    if (rawOverrides is Map<String, dynamic>) {
      // Folders no replaced recording may reuse: every bundled and
      // server-added reciter's own, and each other's.
      final taken = {for (final r in all) r.cacheFolder};
      for (final r in added) {
        taken.add(r.cacheFolder);
      }
      for (final r in all) {
        final o = rawOverrides[r.id];
        if (o is! Map<String, dynamic>) continue;
        final parsed = overrideFromJson(r, o, takenFolders: taken);
        if (parsed.hidden) hidden.add(r.id);
        if (parsed.reciter != null) {
          overridden[r.id] = parsed.reciter!;
          if (parsed.recordingReplaced) {
            replaced.add(r.id);
            taken.add(parsed.reciter!.cacheFolder);
          }
        }
      }
    }
    // Never hide every reciter: a picker with nothing in it would leave the
    // reader with no recitation at all.
    final shown = all.where((r) => !hidden.contains(r.id)).length + added.length;
    if (shown == 0) hidden.clear();
    final orderIds = <String>[];
    if (rawOrder is List) {
      for (final id in rawOrder) {
        if (id is String && !orderIds.contains(id)) orderIds.add(id);
      }
    }
    remote = List.unmodifiable(added);
    _overridden = Map.unmodifiable(overridden);
    _hidden = Set.unmodifiable(hidden);
    _order = List.unmodifiable(orderIds);
    _recordingReplaced = Set.unmodifiable(replaced);
    _remoteEndCaps = endCapsFromJson(json['endCaps']);
  }

  /// Where recordings must stop, sent with this file on top of the bundled
  /// [recitationEndCaps], so a «صدق الله العظيم» found after a release is
  /// cut without one (owner, 2026-11-20):
  /// `"endCaps": {"doukali_qaloun": {"114001.mp3": 29.65}}`.
  static Map<String, Map<String, double>> _remoteEndCaps = const {};

  static Map<String, Map<String, double>> endCapsFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final file = RegExp(r'^\d{3}(\d{3})?\.mp3$');
    final out = <String, Map<String, double>>{};
    raw.forEach((id, files) {
      if (id is! String || files is! Map) return;
      final caps = <String, double>{};
      files.forEach((f, sec) {
        if (f is String && file.hasMatch(f) && sec is num) {
          if (sec > 0.5 && sec < 36000) caps[f] = sec.toDouble();
        }
      });
      if (caps.isNotEmpty) out[id] = Map.unmodifiable(caps);
    });
    return Map.unmodifiable(out);
  }

  /// Seconds into [file] past which [reciterId]'s recording is never played
  /// («صدق الله العظيم»), or null. A recording the server replaced under the
  /// same id is other audio: the bundled caps no longer fit it.
  static double? endCapFor(String reciterId, String file) =>
      _remoteEndCaps[reciterId]?[file] ??
      (_recordingReplaced.contains(reciterId)
          ? null
          : recitationEndCaps[reciterId]?[file]);

  static const Object _fromFile = Object();

  /// Longest server-sent [name] / [shortName] / [riwaya] accepted. The short
  /// name sits in the two dropdowns and the media notification (the bundled
  /// ones are kept to 18 characters by a test).
  static const int maxNameLength = 60;
  static const int maxShortNameLength = 18;
  static const int maxRiwayaLength = 40;

  /// Reads one server override for the bundled reciter [base]. Each field is
  /// checked on its own and a bad one is ignored, never the whole entry:
  ///
  ///     {"name": "…", "shortName": "…", "riwaya": "…", "hidden": true,
  ///      "timingsRevision": 3,
  ///      "recording": {"audioBaseUrl": "https://audio.mushaf-qaloon.com/x/",
  ///                    "timingsBaseUrl": "https://quran-content.mushaf-qaloon.com/timings/x/",
  ///                    "cacheFolder": "audio_cache_x", "timingsRevision": 1}}
  ///
  /// `recording` swaps the reciter's audio for a whole-surah timed recording
  /// under the same id (so the reader's choice, bookmarks and settings stay).
  /// It needs our own hosts and a [cacheFolder] no other reciter uses (the
  /// old files are different audio under the same names); a recording that
  /// fails any check is ignored as a whole and the bundled one stays.
  /// A `timingsRevision` outside `recording` only raises the bundled
  /// recording's revision; inside it, it belongs to the new recording.
  static ReciterOverride overrideFromJson(
    Reciter base,
    Map<String, dynamic> o, {
    Set<String> takenFolders = const {},
  }) {
    String? text(Object? v, int max) {
      if (v is! String) return null;
      final t = v.trim();
      if (t.isEmpty || t.length > max) return null;
      return t;
    }

    final name = text(o['name'], maxNameLength);
    final shortName = text(o['shortName'], maxShortNameLength);
    final riwaya = text(o['riwaya'], maxRiwayaLength);
    final hidden = o['hidden'] == true;

    Reciter? swapped;
    final rec = o['recording'];
    if (rec is Map<String, dynamic>) {
      final audio = rec['audioBaseUrl'];
      final timings = rec['timingsBaseUrl'];
      final cache = rec['cacheFolder'];
      final rev = rec['timingsRevision'];
      if (_ourUrl(audio) &&
          _ourUrl(timings) &&
          audio != base.audioBaseUrl &&
          cache is String &&
          _idRe.hasMatch(cache) &&
          cache != base.cacheFolder &&
          !takenFolders.contains(cache)) {
        swapped = Reciter(
          id: base.id,
          name: base.name,
          shortName: base.shortName,
          riwaya: base.riwaya,
          audioBaseUrl: audio as String,
          cacheFolder: cache,
          scheme: AudioScheme.timedSurah,
          timingsBaseUrlOverride: timings as String,
          timingsRevision: rev is int && rev > 0 ? rev : 1,
        );
      }
    }

    var r = swapped ?? base;
    if (swapped == null) {
      final rev = o['timingsRevision'];
      if (rev is int && rev > base.timingsRevision) {
        r = r.copyWith(timingsRevision: rev);
      }
      // The per-ayah tables, each replaced whole: which ayat this sheikh
      // reads inside a neighbour ([coveredAyat], covered scheme only) and
      // which ones the mirror has no audio for ([missingAyat]; the timed
      // scheme has its gaps in the timing files instead).
      if (base.scheme == AudioScheme.covered) {
        final covered = _ayahTable(o['coveredAyat']);
        if (covered != null) r = r.copyWith(coveredAyat: covered);
      }
      if (base.scheme != AudioScheme.timedSurah) {
        final missing = _ayahTable(o['missingAyat']);
        if (missing != null) r = r.copyWith(missingAyat: missing);
      }
    }
    if (name != null || shortName != null || riwaya != null) {
      r = r.copyWith(
        name: name,
        // A new full name without a short one: the old short form may be a
        // shortening of the old name, so show the new name in full.
        shortName: shortName ?? name,
        riwaya: riwaya,
      );
    }
    return ReciterOverride(
      reciter: identical(r, base) ? null : r,
      hidden: hidden,
      recordingReplaced: swapped != null,
    );
  }

  /// Whether [other] plays exactly what this one plays (same files, same
  /// timings): a label change alone must not restart a recitation or cancel
  /// a download.
  bool samePlaybackAs(Reciter other) =>
      id == other.id &&
      audioBaseUrl == other.audioBaseUrl &&
      cacheFolder == other.cacheFolder &&
      scheme == other.scheme &&
      timingsBaseUrl == other.timingsBaseUrl &&
      timingsRevision == other.timingsRevision;

  /// `{"5": [34], "23": [46]}` -> surah -> ayat, or null when [v] is not
  /// such a table (an empty object is a valid table: nothing listed).
  static Map<int, Set<int>>? _ayahTable(Object? v) {
    if (v is! Map<String, dynamic>) return null;
    final out = <int, Set<int>>{};
    for (final e in v.entries) {
      final s = int.tryParse(e.key);
      final ayat = e.value;
      if (s == null || s < 1 || s > 114 || ayat is! List) return null;
      final set = <int>{};
      for (final a in ayat) {
        if (a is! int || a < 1 || a > madaniAyahCounts[s - 1]) return null;
        set.add(a);
      }
      if (set.isNotEmpty) out[s] = set;
    }
    return out;
  }

  Reciter copyWith({
    int? timingsRevision,
    String? name,
    String? shortName,
    String? riwaya,
    Map<int, Set<int>>? coveredAyat,
    Map<int, Set<int>>? missingAyat,
  }) => Reciter(
    id: id,
    name: name ?? this.name,
    shortName: shortName ?? this.shortName,
    riwaya: riwaya ?? this.riwaya,
    audioBaseUrl: audioBaseUrl,
    cacheFolder: cacheFolder,
    scheme: scheme,
    coveredAyat: coveredAyat ?? this.coveredAyat,
    breathCombining: breathCombining,
    continuationsAsset: continuationsAsset,
    missingAyat: missingAyat ?? this.missingAyat,
    timingsBaseUrlOverride: timingsBaseUrlOverride,
    timingsRevision: timingsRevision ?? this.timingsRevision,
  );

  static final RegExp _idRe = RegExp(r'^[a-z][a-z0-9_]{1,39}$');

  /// A server-added reciter. Only the [AudioScheme.timedSurah] scheme is
  /// accepted: its timing files carry everything the other schemes keep in
  /// Dart tables, so nothing else has to ship with the app. The audio and the
  /// timings must be on our own hosts. Returns null for anything else, so a
  /// bad entry is dropped rather than offered.
  ///
  ///     {"id": "x_qaloun", "name": "…", "shortName": "…",
  ///      "riwaya": "رواية قالون",
  ///      "audioBaseUrl": "https://audio.mushaf-qaloon.com/x/",
  ///      "timingsBaseUrl": "https://quran-content.mushaf-qaloon.com/timings/x/",
  ///      "cacheFolder": "audio_cache_x", "timingsRevision": 1}
  static Reciter? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final name = j['name'];
    final audio = j['audioBaseUrl'];
    final timings = j['timingsBaseUrl'];
    if (id is! String || !_idRe.hasMatch(id)) return null;
    if (name is! String || name.trim().isEmpty) return null;
    if (j['scheme'] != 'timedSurah') return null;
    if (!_ourUrl(audio) || !_ourUrl(timings)) return null;
    final cache = j['cacheFolder'];
    final cacheFolder = cache is String && _idRe.hasMatch(cache)
        ? cache
        : 'audio_cache_$id';
    final rev = j['timingsRevision'];
    final shortName = j['shortName'];
    final riwaya = j['riwaya'];
    return Reciter(
      id: id,
      name: name.trim(),
      shortName: shortName is String && shortName.trim().isNotEmpty
          ? shortName.trim()
          : null,
      riwaya: riwaya is String && riwaya.trim().isNotEmpty
          ? riwaya.trim()
          : 'رواية قالون',
      audioBaseUrl: audio as String,
      cacheFolder: cacheFolder,
      scheme: AudioScheme.timedSurah,
      timingsBaseUrlOverride: timings as String,
      timingsRevision: rev is int && rev > 0 ? rev : 1,
    );
  }

  static bool _ourUrl(Object? v) {
    if (v is! String || !v.endsWith('/')) return false;
    final u = Uri.tryParse(v);
    return u != null &&
        u.scheme == 'https' &&
        (u.host == 'mushaf-qaloon.com' || u.host.endsWith('.mushaf-qaloon.com'));
  }
}

/// One parsed server override (see [Reciter.overrideFromJson]).
class ReciterOverride {
  const ReciterOverride({
    required this.reciter,
    required this.hidden,
    required this.recordingReplaced,
  });

  /// The bundled reciter as the override changes it, or null when nothing
  /// usable was sent.
  final Reciter? reciter;

  /// The server took this reciter out of the pickers.
  final bool hidden;

  /// [reciter] plays a different recording than the bundled one.
  final bool recordingReplaced;
}

/// A selectable Qur'an tafsir edition (تفسير).
///
/// Two delivery modes:
///
/// * **Bundled** ([isBundled] == true): the whole tafsir ships inside the app as
///   an asset ([assetPath]) and works fully offline. Used for the two concise
///   editions (Sa'di, Muyassar).
///
/// * **Online** ([isBundled] == false): the tafsir is fetched **one Qur'an page
///   at a time** from stable hosting **we control** ([pageBaseUrl] — a Cloudflare
///   R2 bucket, same bucket family as the recitation audio; see [Reciter]) and
///   cached to disk under [cacheFolder]. Used for the large classical editions
///   (Ibn Kathir, Tabari, Qurtubi, Zad al-Masir) which are far too big to bundle.
///
/// Both modes read the app's Qalun (Madani) page/ayah data and translate to the
/// Hafs (Kufi) numbering the source tafaseer use via `narration_map.json` — for
/// bundled editions at runtime (see [TafsirService]), for online editions the
/// mapping is pre-baked into the per-page files at build time
/// (see tools/build_tafsir_pages.py) so no runtime mapping is needed.
class TafsirEdition {
  /// Stable identifier, persisted in SharedPreferences and used as the on-disk
  /// cache discriminator. Never change an existing id or users lose their
  /// selection / cached pages for that edition.
  final String id;

  /// Display name shown in the picker (Arabic).
  final String name;

  /// Short subtitle: author or source note (Arabic).
  final String subtitle;

  /// Whether the whole edition is bundled as an app asset (works offline).
  final bool isBundled;

  /// Asset path for a [isBundled] edition (whole tafsir in one JSON), else null.
  final String? assetPath;

  /// Base URL the per-page JSON files are fetched from for an online edition.
  /// Must end with a trailing slash; the full URL is
  /// `pageBaseUrl + pageFileName(pageNumber)`. Null for bundled editions.
  final String? pageBaseUrl;

  /// Folder name (under the app support dir) where this edition's fetched pages
  /// are cached. Empty for bundled editions (nothing is cached to disk).
  final String cacheFolder;

  /// Rough total download size in MB for an online edition (shown in the
  /// "download whole tafsir" confirmation). 0 for bundled editions.
  final int approxDownloadMb;

  const TafsirEdition({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.isBundled,
    required this.cacheFolder,
    this.assetPath,
    this.pageBaseUrl,
    this.approxDownloadMb = 0,
  });

  bool get isOnline => !isBundled;

  /// Number of per-page tafsir files an online edition has (page_001 … page_NNN),
  /// matching assets/data/output.json's page count. Used to download a whole
  /// edition. Kept in sync with tools/build_tafsir_pages.py output.
  static const int onlinePageCount = 602;

  /// Per-page cache/remote filename for a 1-based Qur'an [pageNumber].
  static String pageFileName(int pageNumber) =>
      'page_${pageNumber.toString().padLeft(3, '0')}.json';

  /// Full remote URL for a 1-based Qur'an [pageNumber] (online editions only).
  String pageUrl(int pageNumber) => '$pageBaseUrl${pageFileName(pageNumber)}';

  // ───────────────────────────────────────────────
  //  HOSTING
  // ───────────────────────────────────────────────

  /// Root of the tafsir mirror on our dedicated non-audio Cloudflare R2 bucket
  /// (`quran-content`, separate from the recitation-audio bucket). Each online
  /// edition lives under `<root><id>/`, holding `page_001.json` … `page_602.json`.
  /// The files are produced and uploaded by tools/build_tafsir_pages.py +
  /// tools/mirror_tafsir_to_r2.py.
  static const String _r2Root =
      'https://pub-5025f0d14b9046309795201770f30da1.r2.dev/tafsir/';

  // ───────────────────────────────────────────────
  //  AVAILABLE EDITIONS  (display order; Sa'di first)
  // ───────────────────────────────────────────────

  /// Tafsir as-Sa'di — the original bundled edition.
  static const TafsirEdition saddi = TafsirEdition(
    id: 'saddi',
    name: 'تفسير السعدي',
    subtitle: 'عبد الرحمن بن ناصر السعدي',
    isBundled: true,
    assetPath: 'assets/data/ar.saddi.json',
    cacheFolder: '',
  );

  /// Al-Tafsir al-Muyassar — concise, modern; bundled offline (small).
  static const TafsirEdition muyassar = TafsirEdition(
    id: 'muyassar',
    name: 'التفسير الميسّر',
    subtitle: 'مجمع الملك فهد',
    isBundled: true,
    assetPath: 'assets/data/ar.muyassar.json',
    cacheFolder: '',
  );

  /// Tafsir al-Jalalayn — concise classical; bundled offline (small).
  static const TafsirEdition jalalayn = TafsirEdition(
    id: 'jalalayn',
    name: 'تفسير الجلالين',
    subtitle: 'المحلي والسيوطي',
    isBundled: true,
    assetPath: 'assets/data/ar.jalalayn.json',
    cacheFolder: '',
  );

  /// Tafsir Ibn Kathir — online (fetched per page + cached).
  static const TafsirEdition ibnKathir = TafsirEdition(
    id: 'ibn_kathir',
    name: 'تفسير ابن كثير',
    subtitle: 'إسماعيل بن عمر بن كثير',
    isBundled: false,
    cacheFolder: 'tafsir_cache_ibn_kathir',
    pageBaseUrl: '${_r2Root}ibn_kathir/',
    approxDownloadMb: 88,
  );

  /// Tafsir at-Tabari (Jami' al-bayan) — online.
  static const TafsirEdition tabari = TafsirEdition(
    id: 'tabari',
    name: 'تفسير الطبري',
    subtitle: 'محمد بن جرير الطبري',
    isBundled: false,
    cacheFolder: 'tafsir_cache_tabari',
    pageBaseUrl: '${_r2Root}tabari/',
    approxDownloadMb: 61,
  );

  /// Tafsir al-Qurtubi (al-Jami' li-ahkam al-Qur'an) — online.
  static const TafsirEdition qurtubi = TafsirEdition(
    id: 'qurtubi',
    name: 'تفسير القرطبي',
    subtitle: 'محمد بن أحمد القرطبي',
    isBundled: false,
    cacheFolder: 'tafsir_cache_qurtubi',
    pageBaseUrl: '${_r2Root}qurtubi/',
    approxDownloadMb: 77,
  );

  /// Zad al-Masir fi 'ilm al-tafsir — Ibn al-Jawzi — online. Not available from
  /// quran.com/spa5k; built from the Shamela export (دار الكتاب العربي edition)
  /// by tools/build_zad_almasir.py and served from our R2 bucket.
  static const TafsirEdition zadAlmasir = TafsirEdition(
    id: 'zad_almasir',
    name: 'زاد المسير',
    subtitle: 'ابن الجوزي',
    isBundled: false,
    cacheFolder: 'tafsir_cache_zad_almasir',
    pageBaseUrl: '${_r2Root}zad_almasir/',
    approxDownloadMb: 39,
  );

  /// All editions offered in the picker, in display order (concise/bundled
  /// first, then the large online classical tafaseer).
  static const List<TafsirEdition> all = [
    saddi,
    muyassar,
    jalalayn,
    ibnKathir,
    tabari,
    qurtubi,
    zadAlmasir,
  ];

  /// Editions fetched from the network (used to size / clear the tafsir cache).
  static const List<TafsirEdition> onlineEditions = [
    ibnKathir,
    tabari,
    qurtubi,
    zadAlmasir,
  ];

  /// The edition used before the user has chosen one.
  static const TafsirEdition fallback = saddi;

  static TafsirEdition byId(String? id) {
    return all.firstWhere(
      (e) => e.id == id,
      orElse: () => fallback,
    );
  }
}

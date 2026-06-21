/// Build-time switch for how the high-fidelity Qur'an page images are delivered.
///
/// `true`  — SHIPPING DEFAULT. The high-fidelity images are **bundled** inside
///           the app under `assets/images/`. The "جودة عرض الصفحة" picker
///           defaults to level 3 (فائق الجودة), that level renders the bundled
///           asset directly, and **no download is required**. Store users get
///           the best quality out of the box.
///
/// `false` — LEGACY DOWNLOAD MODEL. `assets/images/` holds the lighter
///           "standard" set, the picker defaults to level 1 (قياسي), and level
///           3 is a one-time download from the GitHub release.
///
/// ── How to switch between the two models ──────────────────────────────────
/// The page image files themselves are swapped by helper scripts so the app
/// only ever bundles one set (keeping the build small):
///
///   • Bundle high-fidelity (current):  tools\use_high_fidelity.ps1  + flag = true
///   • Revert to standard + download:   tools\use_standard.ps1       + flag = false
///
/// The inactive set is kept in `image_sets\` (standard / high_fidelity), which
/// is part of the repo but NOT bundled into the app.
const bool kBundleHighFidelityImages = true;

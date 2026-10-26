# Server-updated data (no store release needed)

`lib/services/content_update_service.dart` fetches
`https://quran-content.mushaf-qaloon.com/data/manifest.json` once a day (and
when the reader taps «التحقق من وجود تحديث») and installs whatever is newer than
the app's bundle. Publish with `python tools/publish_content_updates.py`.

| item | source | bump |
|---|---|---|
| `tanzilat` | `assets/data/tanzilat.json` (built by `build_tanzilat_data.py`) | `VER` in the builder |
| `word_masks` | `tools/content_updates/word_masks_patch.json` | `"ver"` here |
| `reciters` | `tools/content_updates/reciters.json` | `"ver"` here |

A file with `"ver": 0` is left out of the manifest.

## word_masks_patch.json
Cumulative: every ayah whose boxes were corrected after the current bundle,
`{"page": 480, "surah": 41, "ayah": 43, "words": [[[x, y, w, h], …], …]}`
(the `words` array exactly as in `assets/data/word_masks.json`). Applied at
launch over the bundled boxes. When a release bundles the corrected
`word_masks.json`, raise `ContentUpdateService.bundledVersions['word_masks']`
to this file's `ver` and the phones stop using the patch.

## reciters.json
Reciters on the timed-surah scheme only (whole-surah MP3s + `timings/SSS.json`):

```json
{"id": "x_qaloun", "name": "…", "shortName": "…", "riwaya": "رواية قالون",
 "scheme": "timedSurah",
 "audioBaseUrl": "https://audio.mushaf-qaloon.com/x/",
 "timingsBaseUrl": "https://quran-content.mushaf-qaloon.com/timings/x/",
 "cacheFolder": "audio_cache_x", "timingsRevision": 1,
 "pageTurnCues": {"35": {"surah": 2, "ayah": 218, "file": "002.mp3", "ms": 5044020}, …}}
```
Both hosts must be ours; anything else is dropped by the app. A reciter whose
id a later build bundles in `Reciter.all` is skipped (the bundle wins).
`overrides` can raise a bundled reciter's `timingsRevision`
(`{"rajab_qaloun": {"timingsRevision": 2}}`) so phones re-fetch corrected
timings. Western digits only.

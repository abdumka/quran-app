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
| `tanzilat_paint` | `assets/data/tanzilat_paint.bin` (built by `build_tanzilat_paint.py`) | `VER` in the builder |
| `quran_text` | `tools/content_updates/quran_text_patch.json` (built by `tools/build_quran_text_patch.py`) | the builder bumps `"ver"` |

`tanzilat_paint` (build 133+): the colours as the reviewers' brush painted them,
one picture per page. A pack names the `tanzilat` version it was painted for and
is shown only with that version, so **rebuild it on every tanzilat bump**; the
publish script refuses a mismatch. Older builds keep colouring from the word
boxes, so a repaint publishes both this and `word_masks`.

A file with `"ver": 0` is left out of the manifest.

Only phones on build 126 (1.5.5) or newer read the manifest; older builds
never see these updates. After publishing, check the public file, not the
script's summary:
`curl -s https://quran-content.mushaf-qaloon.com/data/manifest.json`.
(On 2026-10-28 it returned 404: nothing had been published yet.)

## word_masks_patch.json
Cumulative: every ayah whose boxes were corrected after the current bundle,
`{"page": 480, "surah": 41, "ayah": 43, "words": [[[x, y, w, h], …], …]}`
(the `words` array exactly as in `assets/data/word_masks.json`). Applied at
launch over the bundled boxes. When a release bundles the corrected
`word_masks.json`, raise `ContentUpdateService.bundledVersions['word_masks']`
to this file's `ver` and the phones stop using the patch.

Since ver 6 (2026-11-10, Tasmee leak fix: every piece of ink is in some word's
boxes, coloured words included) the publish tool gives `word_masks` to builds
133+ only (`MIN_BUILD_OF`): those colour from the paint pictures, while 126-132
colour from the boxes and keep the v5 they have. Build the file with
`app_data/make_mask_patch.py <ver> --write` (tanzil review folder), after
`app_data/tasmee_fixes.sh` in a repaint round.

## reciters.json
Adds a new reciter without a store release (shows in the picker live, within
a day or on «التحقق من وجود تحديث»). The full new-reciter workflow, and when to
choose this over bundling, is in `C:\Down\new recitor time\NEW_RECITER_INSTRUCTIONS.md`
("Update 2026-10-28"). **Owner's rule since 2026-11-08: every new reciter comes
this way, and is published only when the owner says "push"** (until then the
entry waits in the reciter's run folder as `reciters_entry_pending.json`; never
leave an unapproved entry in this file, the next publish would ship it). Page-turn
cues for such an entry: `tools/measure_remote_page_turn_cues.py`. Reciters on the
timed-surah scheme only (whole-surah
MP3s + `timings/SSS.json`); per-ayah reciters cannot be added this way:

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

## quran_text_patch.json
Spelling fixes to the Qur'an text, read by builds that have the `quran_text`
item (the first release after 2026-11-10; older builds ignore it). Applied at
the NEXT launch only, so the text never changes under a recitation, a Tasmee
session or a search. Rules are in `lib/services/quran_text_patch.dart`.

Workflow:
1. Fix `assets/data/output.json` at exactly the places the owner listed (the
   usual derived files too: `page_phonemes.json` display word,
   `web-player/data/quran_text.json`).
2. Once per release that reads the patch: record its commit as a base,
   `python tools/build_quran_text_patch.py --base <release commit> --write`.
   Afterwards plain `--write` is enough (bases are kept in
   `quran_text_bases.json`, which is not published).
3. The builder lists every ayah that differs from a base, word by word. Check
   that each one is a place the owner listed. It refuses (and the app would
   refuse) a change to the number of words, to whether an ayah opens with the
   basmala, or any digit, ayah-end sign or other character the mushaf text
   does not use. It also refuses a base whose ayah numbering differs.
4. `python tools/publish_content_updates.py --dry-run`, then `--publish`. The
   publisher refuses a patch that is not up to date with `output.json`.

Each entry carries the corrected ayah (`text`) and the text(s) it replaces
(`from`). A phone replaces an ayah only when its bundled text is one of the
`from` texts; anything else stays as bundled. One bad entry makes the phone
refuse the whole file and keep what it had.

**Undo:** a bad fix cannot be recalled by deleting files. Revert the text in
`output.json`, run the builder (it bumps `"ver"`; an empty list restores the
bundled text everywhere) and publish.

**Not covered:** the Tasmee phonemes (a fix that changes how a word is READ
needs a release), the website player (manual deploy), the online tafsir pages,
and any change to pages, ayah numbering or word counts (release + the full
derived-artifact rebuild). When a release bundles the corrected
`output.json`, raise `ContentUpdateService.bundledVersions['quran_text']` to
the patch file's `ver` and add that release as a base.

## share_video.json (build 151+)
«مشاركة الآية» and «فيديو الآية». The source is the bundled
`assets/data/share_video.json` itself (like athkar): edit it, raise `ver`,
publish. Phones read it the next time a share sheet opens.
- `enabled` hides the share icon; `videoEnabled` hides only the video choice.
- `link` and `text.template` (`{text}`, `{surah}`, `{ayah}`, `{link}`): the
  shared text. Only https links on mushaf-qaloon.com are accepted.
- `video`: `maxAyat`, `maxSeconds`, `fps`, `bitrate`, `dim` (darkening of the
  background, 0 to 0.9), `textWidth` / `textHeight` (share of the frame per
  shape), `textMaxScale`, `title`, `watermark`, `closing` (all their wording,
  `show`, `seconds`).
- `video.textHalo` (0 to 1, darkness of the halo around the white letters; 0
  = the old light drop shadow) and `video.textBackdrop` (0 to 0.8, a soft
  dark veil behind the text block): how well the ayat read on bright or busy
  backgrounds such as the gold kiswa.
- `video.title.images` (e.g. `surah_titles/v1/{surah}.png`, `{surah}` = 001
  to 114): the surah name cut from the mushaf pages, white ink on
  transparent, tinted cream in the video; `imageHeight` (share of the short
  side) and `imageMaxWidth` (share of the width) size it. Each phone fetches
  only the surah it needs and keeps it. Missing key or a failed download =
  the `template` text. Recut names need a new folder (`v2/`): phones keep the
  old picture under the old path. Source and cutter:
  `C:\Down\AyahVideoBackgrounds\surah_titles`.
- `effects`: `type` none / echo (`taps` [[ms, gain]], `dry`) / reverb (`room`,
  `damping`, `wet`, `dry`, `width`, 0 to 1). New strengths need no release;
  a new effect TYPE does.
- `backgrounds` / `categories` / `defaultBackground`: the picker. Clips live
  under `video_bg/<id>/{9x16,1x1,16x9}.mp4` + `thumb.jpg` on the quran-content
  bucket (source and cutter: `C:\Down\AyahVideoBackgrounds`, `tools\cut2.py`).
  Upload clips BEFORE publishing (the publisher HEAD-checks every path). A
  changed clip needs a new path: phones cache by path and never re-download.
  `bytes` is checked after download.

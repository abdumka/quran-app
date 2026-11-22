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
| `tasmee_data` | `tools/content_updates/tasmee_data_patch.json` (built by `tools/build_tasmee_data_patch.py`) | the builder bumps `"ver"` |
| `app_config` | `tools/content_updates/app_config.json` (by hand) | `"ver"` here |
| `quran_data` | `tools/content_updates/quran_data.json` (by hand) | `"ver"` here |
| `notices` | `tools/content_updates/notices.json` (by hand) | `"ver"` here |

**Owner's rule (2026-11-17): a server update is the preferred way to ship any
change; a store release is the last resort.** Before planning a release, check
this file for a route. When a release is unavoidable, add to it whatever
server hook is still missing, so the next change of that kind skips the store.

The four items added 2026-11-17 (`tasmee_data`, `app_config`, `quran_data`,
`notices`) and the new `reciters` override keys are read only by the release
after 1.5.6+140. That release went out as 1.5.7+140 (the same build number),
so `NEW_ITEMS_MIN_BUILD` in the publisher is 140: 1.5.6+140 does not know these
items and ignores them, 1.5.7+140 and later read them. In the headings below,
"build 140+" means 1.5.7+140 and later. Each file is checked by the publisher with the app's own
rules and refused before upload if the app would refuse it; the app checks it
again at download and at load and keeps its bundle when anything is wrong.

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

### Overrides for the bundled reciters (build 140+)
Older builds read only `timingsRevision`; 1.5.7+140 and later also read, per id:

| key | effect |
|---|---|
| `name`, `shortName` (max 18), `riwaya` (max 40) | the labels in the pickers, the player and the notification |
| `hidden: true` | out of every picker; a reader who had chosen him falls back to the default reciter (their choice comes back if he is shown again). Never all reciters at once. |
| `timingsRevision` | as before (timed reciters) |
| `pageTurnCues` | the page-turn moments, same shape as for an added reciter; win over the compiled ones. `SSS.mp3` files for a timed recording, `SSSAAA.mp3` otherwise |
| `coveredAyat` (covered scheme: الحذيفي, الدوكالي) / `missingAyat` (any per-ayah scheme) | `{"5": [34]}`: the whole table, replaced |
| `recording` | swaps the audio for a whole-surah timed recording under the same id (the reader's choice and settings stay): `{"audioBaseUrl", "timingsBaseUrl", "cacheFolder" (new, unique), "timingsRevision"}`. The compiled cues are dropped (send `pageTurnCues` measured on the new audio, or the turn is estimated). About 40 s after launch the old recording's downloads are deleted. |

Top level `"order": ["zarrouq_qaloun", ...]`: these ids first, in this order,
then everyone else in the usual order.

**When they apply:** a reciters file read at launch applies in full. One that
lands during a run adds its new reciters at once, but its overrides wait for
the next launch, so nothing changes under a recitation or a download.

Example, the two labels the owner changed on 2026-11-17 (bundled in the next
release anyway; this is how it is done from now on):
```json
"overrides": {"trabulsi_qaloun": {"timingsRevision": 2, "riwaya": "رواية قالون بتقليل التوراة"},
              "zarrouq_qaloun": {"timingsRevision": 2, "riwaya": "رواية قالون بتقليل التوراة"}}
```
Replacing a bundled recording (e.g. الحصري with `husary_timed`) is the same
file; the publisher checks that `001.mp3` and `timings/001.json` are reachable.

### Correcting one surah of a timed reciter (the build after 1.5.8+145)
Owner, 2026-11-22: "I want to be able to update surats or their files."
Two keys, in an override, inside `recording`, or on a server-added reciter:

| key | effect |
|---|---|
| `surahFiles` | `{"40": "040_v2.mp3"}`: this surah's recording is now that file. The app plays it, downloads it, and on a phone that had downloaded the old file, fetches it about 45 s after launch (the old file keeps playing until then, offline too, then is deleted on a later launch). Only that surah's timings are fetched again. |
| `surahTimings` | `{"53": 2}`: new spans for a surah whose audio did not change; only that surah re-fetches (the reciter-wide `timingsRevision` re-fetches all 114). Only rises. |

**Never overwrite a published `SSS.mp3` of a live reciter.** Phones keep a
complete cached copy for good; new spans over the old audio play every later
ayah early or late. Publish the corrected audio under a NEW name
(`SSS_v2.mp3`, then `_v3`; letters a-z and digits only), and leave the old
file on R2: builds without this table, and phones still holding old spans,
play it. Order, each step only after the one before is live:

1. upload `SSS_v2.mp3` to the audio bucket;
2. upload `timings/<slug>/SSS.json` with `"file": "SSS_v2.mp3"`;
3. reciters.json: `"surahFiles": {"<n>": "SSS_v2.mp3"}` for this build and
   later, AND a `timingsRevision` bump for older builds (they only re-fetch on
   that, and they play the file the timings name);
4. bundle the same `surahFiles` (and revision) in `lib/models/reciter.dart`
   before the next release.

The publisher refuses `surahFiles` whose file or timings are not on the
server yet. A surah with a page-turn cue or an end cap needs them measured
on the new file (`pageTurnCues` / `endCaps` name files). Worked example:
al-Qryw 40:21 (`C:/Down/AlQryw/fix_040_2026-11-22/PUSH.md`, the uploader
`C:/Down/AlQryw/pipeline/push_fix_040_21.py`).

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

## tasmee_data_patch.json (build 140+)
Tasmee pronunciation fixes: whole ayat of `assets/data/page_phonemes.json`
plus `lexiconAdd` / `lexiconRemove` for `phoneme_lexicon.json`. Applied when
Tasmee first loads in a run (never during a session). Rules in
`lib/services/tasmee_data_patch.dart`: an ayah stays on its page with the same
number of words, each word in the file's 6-8 field shape. Joining or splitting
words needs a release.

Workflow: fix the two asset files as usual, then
`python tools/build_tasmee_data_patch.py --base <commit of the store build> --write`
once per release that reads the item (bases kept in `tasmee_data_bases.json`,
not published); afterwards plain `--write`. It lists every ayah that differs
from any base and the lexicon changes, and bumps `"ver"`. Publish
(`--dry-run` first). A release that bundles the current files raises
`ContentUpdateService.bundledVersions['tasmee_data']` to the patch's `ver`.
Checked 2026-11-17: HEAD's bundle plus a patch built against it reproduces
the working tree's page phonemes exactly.

## app_config.json (build 140+)
`{"ver": N, "values": {...}, "tafsirEditions": [...]}`. Read at launch; a
newer file applies at the next launch. Only the keys in
`lib/services/remote_config.dart` (`RemoteConfig.keys`) exist, each with its
bundled default and range; the publisher refuses an unknown key, a wrong type
or a value out of range (the app would ignore it). Current keys:

| key | default | what |
|---|---|---|
| `chat.enabled` | true | «راسلنا مباشرة» (false hides it) |
| `tasmee.drillsEnabled` | false | «تقوية الحفظ» tile |
| `tasmee.locateEnabled` | true | «التسميع من أي موضع» search |
| `tasmee.okDistance` / `unsureDistance` / `minMargin` / `minHeardFraction` / `lexiconDistance` | 0.15 / 0.4 / 0.35 / 0.34 / 0.12 | judge thresholds |
| `tasmee.commitDwell` / `settleFrames` / `fastSettleFrames` | 6 / 25 / 12 | phonemes / frames |
| `tasmee.settleMs` / `fastSettleMs` | 1000 / 500 | settle wait (ms) |
| `tasmee.earlyCommit` / `orphanVowel` | true / true | judge rules |
| `tasmee.verifyBeforeMs` / `verifyAfterMs` / `verifyMaxMs` | 3000 / 800 / 6000 | «تحقّق قبل التنبيه» window |
| `content.checkHours` | 24 | silent check interval (6-168) |

The ranges are in the Dart file. Tasmee numbers: change them only after a
replay study shows the gain; every phone on 1.5.7+140 and later takes them at its next
launch. To undo, publish a new `ver` without the key.

`tafsirEditions`: online tafsir editions added without a release,
`{"id": "baghawi", "name": "تفسير البغوي", "subtitle": "...", "approxDownloadMb": 40}`.
Upload the 602 pages to `quran-content.../tafsir/<id>/page_NNN.json` first
(the same format as the four online editions); the publisher checks pages 1,
300 and 602 are reachable.

## quran_data.json (build 140+)
Optional sections, each checked as a whole (`lib/services/quran_data_patch.dart`):
- `ayahRegions`: `{"<page>": <the page's entry of ayah_regions.json>}`, the
  ayah highlight and Tasmee masks. Same ayat in the same order as the bundle,
  otherwise the page keeps its boxes.
- `audioAyahMap`: the whole `map` of `audio_ayah_map.json`.
- `breathData`: `{"assets/data/<x>_continuations.json": <that whole file>}`.
- `narrationMap`: the whole `qalun_to_hafs` of `narration_map.json`.
- `tafsirFixes`: `[{"edition": "saddi" | "muyassar" | "jalalayn", "surah",
  "ayah" (Hafs numbering, as in that file), "text"}]`.

Read once per run when each data set first loads.

## notices.json (build 140+)
Messages shown once per install at launch, in the «ما الجديد» card, only on a
launch where neither «ما الجديد» nor the update dialog appeared:
```json
{"ver": 1, "notices": [{"id": "reciter-younsi", "title": "قارئ جديد",
  "lines": ["أضفنا تلاوة الشيخ علي اليونسي برواية قالون."],
  "from": "2026-11-20", "until": "2026-12-20", "minBuild": 141,
  "platforms": ["android", "ios"],
  "button": {"label": "افتح الصفحة", "action": "page:1"}}]}
```
`id` is lower-case latin (shown once per id; a new message needs a new id),
`from` / `until` local dates (inclusive, optional), `button.action` one of
`page:<1-604>`, `url:https://...`, `store:`, `chat:`. At most 20 notices and
8 lines. Western digits only (the publisher refuses Eastern ones).

## share_video.json (build 140+)
«مشاركة الآية» and «فيديو الآية». The source is the bundled
`assets/data/share_video.json` itself (like athkar): edit it, raise `ver`,
publish. Phones read it the next time a share sheet opens.
- `enabled` hides the share icon; `videoEnabled` hides only the video choice.
  Build 162+: `videoPlatforms` (`["android", "ios"]`: drop one to switch the
  video off there only) and `videoOffBuilds` (e.g. `[158]`: builds with a
  video bug; text sharing stays). Older builds read only `videoEnabled`.
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
  `bytes` is checked after download. Background set v3 (2026-11-18): 41
  forward-only loops under `video_bg/v3/`, cut with `tools\cut3.py`, uploaded
  with `tools\upload_v4.py` (no boomerang: a loop is 30 s or longer, or its
  return is hidden in a 1.5 s dissolve).
- Build 162+, all optional (missing = today's look and wording):
  - `strings`: `{"key": "text"}` replaces any wording of the share sheet, its
    progress steps and messages; `{n}`, `{limit}`, `{from}`, `{to}`, `{time}`
    are filled where the built-in text has them. The publisher refuses a key
    the app does not use (a typo) and em dashes. Keys and built-in text:
    `another` «فيديو آخر»,
    `ayat` «الآيات»,
    `back` «رجوع»,
    `background` «الخلفية»,
    `backgroundDownloadFailed` «تعذّر تنزيل الخلفية، تحقّق من الاتصال»,
    `breathNote` «يقرأ هذا القارئ الآيات {from} إلى {to} بنفَس واحد»,
    `breathWidened` «يقرأ القارئ هذه الآيات بنفَس واحد، فشمل الفيديو الآيات من {from} إلى {to}.»,
    `cancel` «إلغاء»,
    `close` «إغلاق»,
    `create` «إنشاء الفيديو»,
    `font` «خط اسم القارئ» (build 168+),
    `effect` «تأثير الصوت»,
    `from` «من»,
    `galleryDenied` «لم يُحفظ: اسمح للتطبيق بإضافة الصور من إعدادات الهاتف»,
    `galleryFailed` «تعذّر الحفظ في معرض الصور»,
    `galleryNoSpace` «لم يُحفظ: لا توجد مساحة كافية في الهاتف»,
    `gallerySaved` «تم الحفظ في معرض الصور»,
    `gallerySaving` «جارٍ الحفظ في معرض الصور…»,
    `length` «مدة التلاوة نحو {time}»,
    `lengthMeasuring` «مدة التلاوة…»,
    `limitAyat` «لا يزيد الفيديو على {n} آية»,
    `limitTime` «لا يزيد الفيديو على {limit}»,
    `minute` «دقيقة»,
    `minutes` «{n} دقائق»,
    `noBackgroundShape` «لا تتوفر هذه الخلفية بهذا الشكل»,
    `noCredit` «بدون سطر القارئ» (build 168+),
    `sizeSmall` «صغير», `sizeMedium` «وسط», `sizeLarge` «كبير» (build 171+,
    read aloud by screen readers on the size buttons),
    `noRecitation` «لا تتوفر تلاوة هذه الآيات بصوت هذا القارئ»,
    `pause` «إيقاف مؤقت»,
    `play` «تشغيل»,
    `playFailed` «تعذّر تشغيل الفيديو»,
    `preparing` «جارٍ التجهيز»,
    `privacyNote` «يُنشأ الفيديو على هاتفك، ولا يُرفع إلى أي مكان.»,
    `recitationDownloadFailed` «تعذّر تنزيل التلاوة، تحقّق من الاتصال»,
    `reciter` «القارئ»,
    `renderFailed` «تعذّر إنشاء الفيديو»,
    `retry` «حاول مرة أخرى»,
    `retrySave` «حاول مجددًا»,
    `seconds` «{n} ثانية»,
    `shape` «الشكل»,
    `shareVideo` «مشاركة الفيديو»,
    `sheetTitle` «مشاركة الآية»,
    `stepDone` «تم»,
    `stepDownloadBackground` «تنزيل الخلفية»,
    `stepDownloadRecitation` «تنزيل التلاوة»,
    `stepRecitation` «تجهيز التلاوة»,
    `stepRender` «إنشاء الفيديو»,
    `stepText` «تجهيز النص»,
    `textChoice` «نص الآية»,
    `textChoiceNote` «النص مع اسم السورة ورقم الآية»,
    `textCopied` «تم نسخ نص الآية، الصقه لمشاركته»,
    `textFailed` «تعذّر تجهيز نص الآية»,
    `to` «إلى»,
    `tooLong` «المقطع أطول من {limit}، قصّره»,
    `tooLongPick` «المقطع أطول من {limit}، اختر آيات أقل»,
    `twoMinutes` «دقيقتين»,
    `videoChoice` «فيديو الآية»,
    `videoChoiceNote` «تلاوة بخط المصحف على خلفية متحركة»,
    `videoTitle` «فيديو الآية».
  - `album`: the Android gallery album (default «المصحف الجامع»).
  - `video.colors`: `title`, `closingTop`, `closingBottom`, `closingText` as
    `"#RRGGBB"` or `"#AARRGGBB"`; `video.title.top` (share of the height,
    default 0.055).
  - `video.icon`: the app icon of the watermark and closing card as a picture
    on the bucket (square PNG; a new picture needs a new path). Missing or
    unreachable = the bundled icon.
- Build 168+ (ver 4, 2026-11-19), all optional:
  - Shape `4x5` (1080x1350, «منشور») after `9x16`: every background has a
    `4x5.mp4` under `video_bg/v3/<id>/`, cut by `tools\cut3.py` with
    `BG_SHAPES=4x5` from the same sources and loop points. Older builds show
    it as a fourth text chip and render it too (both renderers take any
    size). The shape picker draws each shape in proportion with the chosen
    background inside and `title` under it.
  - `video.credit`: the line under the surah name. `template` (`{reciter}` =
    the reciter's full name, `{riwaya}` = the riwayah note of the reciter
    list), `size` (share of the short side, 0.026), `opacity` (0.8), `gap`
    (0.01), `sizes` (build 171+: the small, medium and large buttons beside
    the font, times `size`, default `[0.8, 1, 1.25]`; three growing numbers
    within 0.5–2 or the default is used), `halo`, `haloWide`, `drop`
    (build 171+: the line's shadow the ayat's way, each a darkness 0–1: a
    tight halo drawn twice, a wide soft one (default 0.7 of `halo`) and a
    small shadow under the letters; all 0 = the first soft shadow). Missing
    `credit` = no line.
  - `fonts`: `list` in picker order, each `{id, title, file, bytes, scale,
    preview}`; no `file` = the phone's own font. `default` (first pick),
    `allowNone` («بدون سطر القارئ» first), `sample` (what the previews say:
    «اسم القارئ» since ver 5; the riwayah line made it look like the list
    picks the riwayah, so the pictures moved to `fonts/v1/<id>_name.png`).
    Files and previews live under `fonts/v1/` (C:\Down\AyahVideoBackgrounds\fonts:
    `prepare_fonts.py` trims to Arabic and one weight, except fonts whose
    licence reserves their name, which ship unmodified; the previews are drawn
    by Flutter itself). A font is downloaded only when picked; a bad entry
    drops that font only. `scale` enlarges fonts that draw small (Thuluth
    1.5, Diwani 1.8). A changed font needs a new path, like clips.
  - Uploaded with `tools\upload_v5.py` (it also writes this part of the json).

## Still needs a store release
New screens or behaviour (code); joining or splitting words; moving an ayah
to another page or renumbering; a new Tasmee model file; a new per-ayah
(non-timed) reciter; the Android Auto tile picture of a renamed reciter (the
tile has the name drawn in).

## Before every store release
1. Raise `ContentUpdateService.bundledVersions` to what the build bundles
   (a test checks tanzilat).
2. Record the release commit as a base: `build_quran_text_patch.py --base`
   and `build_tasmee_data_patch.py --base`.
3. Check `NEW_ITEMS_MIN_BUILD` in the publisher if the build number moved.
4. Add any missing server hook the release could carry (see the rule above).

## usul.json (build 141+)
«أحكام وأصول الرواية» (side menu, under الأذكار). The whole
`assets/data/usul.json`, written by `tools/build_usul_data.py` from the
reviewed mockup builder in C:/Down/Books/usul_qalun/mockup_2026-11-18 (every
example is looked up in output.json there; the build stops on a missing word).
Edit the mockup builder, raise `VER` in build_usul_data.py, rebuild, publish.
Phones read it the next time the section is opened. A block kind an older
build does not know is skipped; raise `v` (the format) only for a change old
builds must not show.

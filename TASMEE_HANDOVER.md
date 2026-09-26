# Tasmee (التسميع) handover — 2026-09-26

Audience: a Claude session starting cold (or the owner) continuing the Tasmee feature in
`D:\quran app\quran-app-main`, branch `main`. Replaces the 2026-09-21 handover. Everything
below was true at commit `f7d2115` (version `1.5.0+103`, not yet on the stores).

Tasmee is an on-device recitation-memorization test: the page's words are masked, the user
recites into the microphone, words uncover as they are recited correctly, mistakes hold the
session at the word. Riwaya Qalun (سكون وقصر), Libyan mushaf, 602 pages, 77,435 words.

---

## 0. How the owner wants this worked on (read first)

- **Do not trade detection for fewer false alarms silently.** Every judge change must be
  measured on (a) a sheikh's correct recitation (`tasmee_work/naihi/audit.jsonl`, 38.7k words)
  and (b) the owner's own phone logs, and the cost stated in numbers before it is applied.
  Several rules were measured and rejected (§6); do not retry them without new evidence.
- **Judge from the audio, not from what the model wrote.** The owner said: "I don't want you
  to judge based on what the model thinks it listened to". Claude cannot hear, but can render a
  spectrogram + loudness curve of the moment and cut a 2-3 s WAV for the owner to listen to
  (`tasmee_work/cmp_cutshort/make_spectrogram.py`). Model token timestamps are up to 0.3 s late
  and mark emission, not the sound. This method overturned a wrong conclusion once (p135 وَهْوَ:
  the word WAS said; the model dropped «هْوَ»).
- **Never mention another riwaya to the user.** No "Hafs" anywhere in the UI. A `hafs`-kind
  error is shown as «لم تُسمع صحيحة», nothing quoted.
- **Never show raw phonemes to users** (they looked like «مءهلكنامن» and alarmed the owner).
- **"I DON'T WANT YOU TO MESS IT UP MORE."** Said after the mask work covered surah banners.
  Tag before touching data (`git tag pre-<thing>-<date>`), measure on all sides of a trade-off,
  compare page by page against the data being replaced, and render pages before saying done.
- Never edit or commit `update.json` in the repo; the owner does it after a store release. A
  draft for this release is at `D:\AlQryw\pipeline\update.json` (1.5.0, build 103).
- Never paste secrets. `tools/r2_upload.json` (gitignored) holds the upload key; it is NOT in
  git, so a fresh checkout has no upload button until it is copied in (see §8).
- Bash heredocs containing Arabic break on this machine: write Python patch scripts with the
  Write tool and run them. Pass Windows paths to Python (`D:\...`), not `/c/...`.
- One heavy job at a time (a full mask regeneration ~12 min, a mask audit ~8 min, a session
  replay ~1 min/session, `flutter test` ~40 s); running two starved the machine before.

---

## 1. Architecture

| Step | Where | What |
|---|---|---|
| Recognizer | `lib/services/zipformer_recitation_engine.dart` | Streaming Zipformer2-CTC phoneme model (Quran-Lab `zipformer_p_arabic_v3.1` int8, 251 tokens) via `sherpa_onnx` in a worker isolate; decodes every 100 ms. Downloaded once from R2 (`AsrModelManager`). Licence NPL-1.2: feature stays free, no ads. |
| Tracker | `lib/utils/phoneme_tracker.dart` (`PhonemeTracker`) | Online edit-distance DP of heard phonemes against the page's expected phoneme string, with restart origins so repeats are re-judged from their first sound. |
| Judge | same file (`VerdictTracer`) | Per word: `ok`, `unsure`, `wrong`, `skipped`, `pending`; wrong reasons `hafs`, `word`, `extra`, `haraka`, or plain distance. |
| Session | `lib/services/memorization_test_service.dart` | Verdicts → word statuses, holds, page flow, reports, logs, basmala filter, extra-word notices. |
| Overlay | `lib/widgets/quran/memorization_test_overlay.dart` | Paints word masks over the page image; the floating session bar. |
| Data | `assets/data/page_phonemes.json`, `phoneme_lexicon.json`, `word_masks.json`, `ayah_regions.json` | See §3. |

**Tracker and judge exist twice**: Dart, and a Python mirror
`D:\quran app\tasmee_work\zipformer\eval_session.py` (reads the repo from env `TASMEE_REPO`,
default still `quran-app-big`; set it to `D:\quran app\quran-app-main`). Any change to
`phoneme_tracker.dart`'s tracker/judge must be mirrored and checked with the two parity tests
(`phoneme_tracker_test`, `phoneme_tracker_parity_p130_test`). Rules that live in the *service*
(basmala, extra-word target, half-word wait, strict wrong-word hold) have no mirror, and the
replay tools therefore differ from the app at those points.

There is **no demo/stub engine** any more (deleted 2026-09-20). No mic or no model → the
session does not start and a snackbar says why (`StubReason` kept its name).

### Session rules
- Where the session starts is the only free choice (any ayah of the page); no forward jumps.
- **Mistake**: hold at the word (pink, alert). Released by a correct re-read (`ok`, or
  distance ≤ 0.3), a help button, or 12 correct words further on. **Nothing after a word with a
  `wrong` verdict is uncovered**, even while that verdict is still deferred (owner request,
  2026-09-21; fixture `test/fixtures/tasmee_p132_wrong_word.json` fails on the old code).
- **Repair after moving on** (2026-09-26): while a word is held, restarting the DP path at it costs
  `heldRepeatCost` 3 instead of a repeat (10) / ayah jump (14) — `PhonemeTracker.heldWord`, mirrored as
  `held_word`. Before this, once the reciter had gone a few words past a mistake, a clean repeat of the
  ayah was absorbed as FORWARD progress with cheap substitutions (six repeats of «ملك يوم الدين» on p1
  never judged; `bestCell` kept climbing). Verified on that session in Python (`zipformer/debug_repeat.py`).
- **Skips**: one skipped word = soft hold; two or more, or a whole ayah = hard stop (tracker
  rebuilt at the held word behind a barrier). A mistake hold hardens when the words after it
  come back skipped.
- **Extra word** (2026-09-23): the judge attaches an `extra` verdict to the word BEFORE the
  gap, which is usually accepted already, so the app used to drop it («قالوا قد وجدنا» passed).
  `_mistakeTarget` moves it to the word after the gap as a short NOTICE: red + alert +
  «زدت كلمة», clears after 3 correct words / a re-read with new audio / a help button, the word
  then shows correct, error kind `extra` stays in the report. Nasal/vowel-only gaps («ںںں»)
  are not words. Cost: sheikh 13 per 77k words, owner 11 in 44 sessions (~3 real).
- **Basmala** (2026-09-23): not part of any surah's text in this mushaf (al-Fatiha starts at
  الحمد). `_basmalaFilter` buffers sounds at a surah opening (page top with any ayah 1 of a
  surah ≠ 1, 9; or tracker at the last word of the previous surah / first of the next) while
  they look like «بِسمِللَااهِررَحمَاانِررَحِۦۦم», drops them once complete, flushes on divergence
  or a 1 s pause. Pure decision `basmalaCut()`; logged `basmalaSkipped`.
- **Half a word while the voice still sounds** (2026-09-21): a `wrong` pause verdict on the
  word being said, whose heard form is an exact opening of the word, waits while the mic level
  was above 0.12 in the last 300 ms (cap 4 s). A long madd sends its opening then nothing.
- **Short word heard cut short** (2026-09-21, judge, mirrored): a 2-3 symbol opening heard
  exactly with only a held ending missing (كُن→كُ, مِن→مِ, مَا→مَ) is `unsure`, not `wrong`.
  57 particles, 5.3% of words. Lost: a dropped final nasal/madd on those.
- `unsure` (0.15 < d ≤ 0.4) reveals the word. This is why a substitution that shares letters
  passes (ويونس heard ولوطا, واتقوه heard ولا تكونن, يؤمنون heard ءامنوا, أكثرهم heard
  أكثر الناس). Tightening was measured and rejected (§6).
- Short words (≤3 letters) skipped with both neighbours heard are absorbed as correct (model
  drops them). Known blind spot: a dropped قل/من/ما/إن is never caught.
- Page complete → engine keeps running, text swaps to the next page (`pageAdvanced` pulses
  through 0 because a `ValueNotifier` is silent on an equal value). Only when a recorder
  exists. **«أعد الآية» at the top of a page the session flowed into restarts on the previous
  page at its last ayah** (`_continuedFrom`, `_repeatLastAyahOf`).
- Help buttons: كلمة, الآية, أعد الآية, تخطَّ, الصفحة (restart; inside a drill restarts the
  drill), إنهاء, إخفاء. The bar shows only silence / mistake / skip / not-on-page / engine
  error / page complete / drill label; everything else goes to the log (`feedback shown:false`).

### Startup, alerts, bar, guide (2026-09-21 → 24)
- «جارٍ تجهيز التسميع…» blocking notice while the model loads / portrait rotates (1-3 s).
- Alerts: two kinds (`TasmeeAlertKind.mistake` = double buzz / `tasmee_alert.wav`;
  `corrected` = one 60 ms pulse / soft chime `tasmee_ok.wav`, fired on `holdReleased
  how=repaired`). Both default vibrate. Tile «تنبيهات» in أدوات الحفظ, two dropdowns in a row.
- The session bar floats: long-press drag (also the folded dot), position saved in pref
  `tasmee_bar_pos` (page-box fractions), pulled to the centre when unfolding would run off the
  right edge.
- First-use guide `showTasmeeGuideOnce` (pref `tasmee_guide_seen`), also «شرح التسميع» in
  أدوات الحفظ: the bar drawn from the same icons with numbered callouts, all Arabic.
- Windows use `HifzPalette.of(context)` (light/dark like the Tilawah sheet).
- Reports: only real mushaf words are quoted («قرأت «ءامنوا»» via
  `PagePhonemeService.textFor`), kinds word/extra; `distance` and `hafs` show «لم تُسمع صحيحة»
  with nothing quoted; extra reads «كلمة زائدة: «قد» قبل «وجدنا»». Raw phonemes only in the log
  (`heardRaw`).

### تقوية الحفظ (drills) — HIDDEN
`kTasmeeDrillsEnabled = false` in `lib/widgets/hifz/hifz_tools_sheet.dart`. Weak points are still
collected (`tasmee_weak_point_store.dart`, capped 2,000). Do not re-enable without an opening
prompt: a drill whose start lands on a page's first ayah shows a fully blank page
("almost no one can start reciting with only the page number"). Other known drill faults: one
correct reading deletes a point forever (no spaced repetition), the intro sheet lists the
answers, a tablet two-page jump clears the queue.

---

## 2. Recitation highlight (same code family)
`lib/widgets/quran/playing_ayah_highlight.dart` tints the ayah being recited from
`ayah_regions.json` (multiply blend, ink stays dark; dark mode inverts the page after that layer,
so the dark tint is the inverse colour). For reciters who join ayat (Doukali 1,194 joined ayat
in 744 groups, longest 14 = 81:1-14; Abu Sneineh 1,080; Qaniwah 1,130; al-Hudaifi 24) the whole
joined group is tinted: `AudioService.currentAyahGroup` (pure rule in
`lib/utils/joined_ayah_group.dart`, stops at surah end / numbering gap / 40). "No audio of its
own" ≠ "joined": `isMissing` ayat are never joined; `timedSurah` only once timings are loaded;
al-Husary never. Toggle «تظليل الآية المتلوّة» (pref `highlightPlayingAyah`). Planned next: "soft
marks" (ayah start times inside a joined clip, from the CTC alignment the timed pipeline runs) so
the highlight steps ayah by ayah and the page turns mid-group.

---

## 3. Data

### `page_phonemes.json` — one entry per page / ayah / word
`[ text, phon, tanween, taMarbuta, hafsAlt, wasl, alts, accept ]`. `hafsAlt` = the Hafs form
when the Hafs check is ON for that word (ON 476 words, OFF ~700; where OFF the Hafs form is an
accepted form). `alts` = look-alike words from other ayahs at the same spot (13,552 words).
`accept` = equally-correct forms (mostly what the model produces for a correct Qalun reading).

Regeneration order (each rewrites the asset; `hafs_policy.py` reads original Hafs forms from
git commit `fb04503`, keep it reachable):
```
naihi/apply_audit.py --write
alqryw/learn_from_sheikhs.py qryw=... naihi=... --write
alqryw/hafs_policy.py        qryw=... naihi=... --write
alqryw/clean_forms.py --write
alqryw/fix_darajat.py <repo> --write      # 6:84, 12:76 «دَرَجَٰتِ مَن»: Hafs tanween+idgham carried over
alqryw/fix_israel.py  <repo> --write      # 7:136 «إسرائيل»: Hafs form was only the connected form
alqryw/fix_yadillu.py <repo> --write      # 9:37 «يَضِلُّ»: two-vowel difference scored below the policy's CLEAR bar
alqryw/restore_checks.py <repo> qryw=alqryw/audit_2026-09-26.jsonl naihi=naihi/audit.jsonl --write   # 27 more such words (see below)
zipformer/add_mutashabihat.py --write     # always last
zipformer/make_fixture2.py --write        # refresh the parity fixture
```
Both `fix_*` scripts exist because the generator (`zipformer/validate_qalun.py`) still has the
Hafs pairing bug and 8:71 misalignment; about 90 generator errors are patched as accepted forms.
`hafs_policy.py` keeps a check only when the difference is CLEAR (≥ 0.15) or its kind is known good, so
vowel-only differences were lost; `restore_checks.py` (2026-09-26) put 27 back ON where both sheikhs were
heard as the Qalun form every time: النبيئين ×13, هُزُؤًا ×4, البِيُوت ×2, لِتَحْسِبُوهُ, مِتُّم, حَرِجًا,
بِرِسَالَتِي, وَقَالَتُ (12:31), ظَعَنِكُم, لِنَبِيءٍ, فَنِعِمَّا — plus 9:37 by `fix_yadillu.py`. Now ON for 503
words. The al-Qryw audit against the current data is `alqryw/audit_2026-09-26.jsonl` (76,312 of 76,584
sheikh words ok; 103 flagged, 1 by the Hafs check); `alqryw/audit2.py` reads the repo from `TASMEE_REPO`. A scan for unjustified م/ن ghunnah runs found only the two درجات cases; a scan for Hafs forms
identical to the Qalun form (madd length / connected form only) found only إسرائيل.

### Masks — `ayah_regions.json` (from `tools/generate_ayah_regions.py`) and `word_masks.json` (from `tools/generate_word_masks.py`)
`tools/page_furniture.py` finds surah banners and basmala lines by template (cut from page
267); agrees with output.json on all 602 pages (112 banners, 111 basmalas).

Audit tools in `D:\quran app\tasmee_work\mask_audit\`: `audit4.py <regions> <masks> <out.json>
noclip` paints every page the way the app does (including the app's fallback to whole-ayah
rects when an ayah's mask count ≠ its word count) and gives THREE numbers per page: `text`
(ayah ink still visible), `banner` (banner/basmala ink covered), `ring` (marker gold covered).
`appview.py` renders a page old-beside-new. `markeroff.py` measures marker boxes against the
real ring. Original data kept there as `original_*_8a997af.json`.

State vs the original app (commit 8a997af): text visible 234,097 → 3,367 px (pages with none
244 → 588 of 602); banner/basmala covered 139,379 → 0; ring covered 872,586 → 373,957; zero
pages worse on any measure. What was wrong (all in the original data too):
- Every badly leaking page had a surah start: the last line above a banner fused with the
  banner box and lost its band; region rects reached 40-60 px into banners. Regions are now
  trimmed at banner/basmala edges; the mask generator excludes their ink and clips every rect.
- 655 of 6,203 markers were ~18 px left of their ring (one template cut off-centre);
  `centre_on_ring` fixes all but 1.
- Marker ink = digits within 15 px of the centre + brownish ring fragments (red−blue > 60);
  an alef beside the ring used to be thrown away with it. Word rects are cut away from the
  marker's 46 px box except where the word's own ink is.
- A word's run was registered only on its first ink group; the leftover sweep skipped
  anything wider than 0.6 pitch; a baseline could be a border rule. `cover_uncovered_ink` and
  `cover_cut_strokes` are last guarantees.
- A kasra (~10×9 px) between two lines went to the line below (7×14 limit); now up to 14×20 px
  may hang under the upper word when at most half as far from it as from the lower.
- Tried and removed: an app-side "keep the marker circle clear" rule (uncovered letters on
  467 pages). The overlay's painter is the original code.
Mask colour and edges (2026-09-26): `tools/sample_paper.py` stores per page `paper` / `hwPaper` (median
paper RGB inside the ayah rects of the plain scan / the هوامش scan; blue channel varies 213-235 across
pages) in word_masks.json; the overlay paints masks with it and feathers the edges (blur 1.2 px on a rect
grown by the same), which removed the pale blocks/streaks the owner saw on p1 in the margin view. The
margin placement of pages 1, 69, 289 was refitted on the text block (`tools/refit_hawamesh.py`, corr
0.76/0.80/0.85 -> 0.96/0.98/0.97); `hawamesh_transform.json` updated. Remaining: page 600 scores 2,772 px of "text" but renders clean (border lines counted); p267's
«كن» touches the banner rule. Review site `https://review.mushaf-qaloon.com`
(`collect_mask_reports.py`), 28 reports, 2 open.

---

## 4. Logs, uploads, tools

- Every page session writes WAV + JSONL (`tasmee_session_recorder.dart`), keeps 50 by default,
  uploads manually from the سجلات page to R2 bucket `tasmee-sessions` under
  `<installId>/`. The key ships in the APK (write-only token); "a Worker in front of the key"
  is still open. **Build with** `--dart-define-from-file=tools/r2_upload.json` **and the file
  must exist** (copy from `quran-app-big\tools\` — it is gitignored). Without it the button is
  grey and the logs page now says so.
  Testers: `flutter build apk --release --split-per-abi --dart-define-from-file=tools/r2_upload.json`.
- `tasmee_work/download_sessions.py` mirrors the bucket to `uploaded/<installId>/`. The
  owner's phone: `4f009d23…` (old builds) and `ef39ee8c…` (build 2102+). Audio ≈ 2 MB/min.
- `zipformer/trace_log.py <jsonl> [lo hi] --asset` replays the LOGGED phonemes and prints every
  verdict change (set `TASMEE_REPO`; use `PYTHONIOENCODING=utf-8`). It prints the last verdict
  per word and over-counts vs the app (the app ignores later verdicts for a correct word).
- `regress.py` replays everything (~25 min). `alqryw/audit2.py` replays a sheikh decode.
- Log events worth knowing: `hold`, `holdReleased {how: repaired|control|moved-on}`, `error
  {kind, heard, heardRaw}`, `verdicts {detail:[{w,s,d,h,r}]}`, `settleWait`, `basmalaSkipped`,
  `rewind`, `startAt`, `completed {continuedTo}`, `ui {what}`.

---

## 5. Timeline (befores and afters)

| Date | Change | Before → after |
|---|---|---|
| 09-20 | Drills hidden, demo engine deleted, drill restart fixed | Demo mode could "recite" and delete weak points; الصفحة inside a drill became a page test |
| 09-21 | Tasmee windows themed; repeat-segment options (each ayah ×N, continue/stop, remembered); loading notice | Windows were hard-coded dark |
| 09-21 | Strict wrong-word hold; cut-short rule; half-word wait; two data fixes (درجات مَن) | Word after a mistake was uncovered (21 of 74 stops); كُن stuck 58 s; أَتُحَٰٓجُّونِّے buzzed mid-madd |
| 09-21 | Mask audit + fixes (§3); playing-ayah highlight; joined-group highlight | Banners covered on 62 pages, 655 markers misplaced, kasras on the wrong line |
| 09-23 | Basmala filter; extra-word notice; repeat-ayah page-back; readable reports; upload hint | «الٓمٓصٓ» flagged after a basmala; «قد وجدنا» passed; reports showed «مءهلكنامن» |
| 09-24 | إسرائيل data fix; no riwaya names in UI; two alert kinds; floating bar; first-use guide; what's-new list; draft update.json | — |

Recovery tags: `pre-tasmee-cleanup-2026-09-20`, `pre-tasmee-round8-2026-09-21`,
`pre-masks-highlight-2026-09-21`, `pre-group-highlight-2026-09-21`.

Tests: 175 (`flutter test`), all passing at `f7d2115`. Key files: `phoneme_tracker_rules_test`,
`memorization_test_phoneme_flow_test` (skip stop, repeat ayah, drill, restart, strict hold with
the p132 fixture, half-word, basmala ×4, extra word ×2, page-back), `joined_ayah_group_test`
(walks the whole Quran with Doukali/Hudaifi data), `hafs_check_asset_test` (fails if page 3's
يخادعون check is ever switched off), the two parity tests, overlay/feedback/aligner tests.
Test hooks: `engineFactoryForTest`, `continuedFromForTest`, `engineOverride`, `stopPlayback`.

---

## 6. Measured and REJECTED (do not retry without new evidence)

- `unsureDistance` 0.4 → 0.3: sheikh only 17/38.7k words in that band, but the owner's phone
  sessions have 24 of 2,572 first verdicts there, nearly all correct readings with noise
  ≈ 1 extra stop per page.
- Lexicon check on the heard form with 1-2 trailing sounds trimmed: flips 30 verdicts in the
  owner's sessions, only 2 real (ويونس, يؤمنون); 28 are correct words (أرحام heard ءَرحَم).
- A "dropped opening consonant" rule for ayah-initial words: audio proved the model drops the
  «ق» of «قال» after a pause, but the heard forms carry glued noise («االَفَ»), and قال/قالوا
  were fine 65 of 69 times. Ayah-opening words are 8% of words but 24% of stops, largely real.
- A broad "pause = quiet mic" rule for the half-word case: 34 of 72 settles happen while the
  voice sounds; it would have delayed 5 real alarms 1-3 s. The narrow rule was kept instead.
- Accepting bare «وَ» for «وَهْوَ»: would let a skipped هو pass; the judge sees tokens, not
  durations (a duration-aware judge is the real fix).

---

## 7. Known model weaknesses (evidence in the logs / audio)

- Drops the first sound after a pause (وَيَوْمَ→يَوْمَ, قَالَ→اال/لَ). Dropped «و» at an ayah start
  is ALSO the classic memorization slip, so it stays caught.
- Drops a word-final madd when the reciter runs on (يُؤْمِنُوا→يُءمِنُ twice on p168; the third,
  longer reading was heard). Cannot be relaxed: «يؤمنُ» is a real look-alike.
- Cannot hear ظ in «ظُفُر» (heard زُبُر, وَففَر both times), ر/ل in «الغافرين» (heard الغافلين),
  و/ف at word start (4 in 39k sheikh words).
- Leans to the Hafs form for وَهْوَ ~75%, اتخذتم 100%, eased hamza ~55%; those checks are OFF.
- Ayah markers, pausal forms at a mid-ayah waqf need ~1 s of silence to be recognised.

---

## 8. Open items and recommendations, in order

1. **Phone-test this build** (nothing since 09-23 was run on a device): basmala at a surah
   start, «قالوا قد وجدنا», «أعد الآية» right after a page turn, the draggable bar (fold at the
   right edge then unfold), the two alerts, the first-use guide, reports wording.
2. **Labelled truth set**: a small review page listing every stop with its 2-3 s clip and two
   buttons (real mistake / false alarm). A few minutes of the owner's listening would replace
   the model's guesses as ground truth for every rule. (Offered, not built.)
3. **Soft marks for joined groups** (§2) — the owner liked it. Also lets the page turn mid-group.
4. **OTA data updates**: the app already downloads the ASR model; a versioned manifest for the
   Tasmee JSON files would let most fixes reach phones without a store release. Dart code
   cannot be updated that way on iOS (Android: sideload link; both: Shorebird).
5. Fix the generator's Hafs pairing / 8:71 bug instead of `accept` patches and `fix_*` scripts.
6. Finish the al-Naihi audit locally and run other reciters (al-Husary, Qaniwah, al-Doukali,
   Abu Sneineh) for independent evidence; the accepted forms were learned from the same
   recordings they were measured on.
7. Drills: opening prompt («سورة … من الآية N — بعد قوله تعالى: ﴿…﴾»), pass on 2-3 different
   days, refuse without the real engine, don't list the answers, keep the queue across a
   tablet spread. Then re-enable.
8. Pausal forms at a mid-ayah waqf sign; surface the tracker's `lost` flag; a Worker in front
   of the upload key; NPL-1.2 notice in the app; iOS build of the feature; trim logging before
   production (50 sessions ≈ 300 MB).
9. Duration-aware judging (would fix وَهْوَ→وَ and the final-madd class).

Older, more detailed notes: `D:\OneDrive - Oregon Health & Science University\Del\Claude Code\tasmee-research\`
(`PROJECT_HANDOFF_2026-09-20.md` etc.), the previous handover in `D:\new recitor time\`, and
Claude's memory files under `~/.claude/projects/d--quran-app-quran-app-main/memory/`
(`tasmee-round8-state`, `tasmee-round9-findings`, `tasmee-mask-audit`,
`playing-ayah-highlight`, `judge-tasmee-from-audio-not-model`).

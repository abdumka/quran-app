# Adding a reciter by TIME instead of cutting the MP3s

Handover for the "timed-surah" recitation scheme: the sheikh ships 114
whole-surah MP3s, we publish a small JSON per surah saying where each ayah
starts and ends, and the players seek inside the file instead of loading a
separate file per ayah.

Written 2026-09-20, after adding two reciters this way and fixing three
separate playback bugs that all came from the same misunderstanding. Read the
**Playback** section before touching any player — it is the part that keeps
costing days.

---

## Why this instead of cutting

The older method cuts a khatma into 6214 per-ayah files (`SSSAAA.mp3`). Five
reciters still work that way and nothing about them changed.

| | per-ayah cut | timed (this) |
|---|---|---|
| what ships | 6214 files | 114 files + 114 JSONs |
| joined ayat (الوقف الهبطي) | silent placeholder files + a `coveredAyat` table in Dart | just a missing key in the JSON |
| a bad boundary | truncates a file — audio lost for good | moves a seek point; audio never lost |
| offline download | 6214 requests | 114 requests, same bytes |
| source must be | anything | **constant bitrate** (see below) |

The truncation class of bug is simply not expressible here, which is the main
reason to prefer it. It cost 724 silently-truncated files once.

**Reciters on it today:** عبدالحميد القريو (`alqryw`) and محمد أبوسنينة
(`abusenainah_timed`). Everything else is per-ayah.

---

## The data contract

`timings/SSS.json`, one per surah:

```json
{"surah":103,"file":"103.mp3","duration_ms":26000,
 "ayat":{"1":[0,12730],"3":[12730,26000]}}
```

Four invariants every player and tool relies on. Break one and something
downstream breaks quietly:

1. **Spans tile contiguously.** Ayah N's end *is* ayah N+1's start — no gap, no
   overlap. Verified: 0 non-contiguous boundaries out of 11,098 across both
   reciters. The playback fix below depends on this being true.
2. **A missing ayah key means "no clip of its own"** — the sheikh read it inside
   a neighbour's breath, or it was joined deliberately. Playback just advances
   past it. In the example above, ayah 2 is read together with ayah 1, so ayah
   1's span covers both and ayah 2 has no key.
3. **The basmala is part of ayah 1's span.** No separate `"0"` key, ever, for
   any reciter. At-Tawba has no basmala at all. This was reversed once and
   reversed back — see the runbooks; do not "fix" al-Fatiha by splitting it out
   without asking.
4. **The last span ends where the audio ends**, except where a closing
   "صدق الله العظيم" was deliberately trimmed out of every span.

Spans start at the first ayah's measured onset, not at ms 0 — الاستعاذة sits
before that and is excluded on purpose.

---

## Producing the data

Two documents already exist and are the real instructions. They live **outside
this repo**, next to the audio, because the working set is gigabytes:

- **`D:/AlQryw/pipeline/NEW_RECITER_INSTRUCTIONS.md`** — start here. Written as
  instructions to a future Claude session: what "done" means, what to ask
  before starting, the standards not to deviate from.
- **`D:/AlQryw/pipeline/README-timed.md`** — the stage-by-stage runbook: source
  the audio → pre-flight checks → normalise to CBR → CTC forced alignment →
  build the spans → verification gates → integration → review page. Ends with
  ~23 numbered "distilled traps", each from a real bug.

The shape of it, so you know what you are agreeing to:

1. Get 114 whole-surah MP3s. Check the narration is **قالون عن نافع** and the
   collection is complete before anything else.
2. **Re-encode to constant bitrate BEFORE aligning.** VBR without a seek table
   makes a deep seek land seconds off, and every ayah boundary here is a seek.
   Aligning first and normalising after shifts every timestamp.
3. Align with a CTC forced aligner (runs in WSL), **with the basmala in the
   text** so the opening is anchored, then fold it into ayah 1.
4. Run every verification gate. `verify_all.py`, `check_margins.py`,
   `find_overlaps.py`.
5. Upload, then **audit all 114 files against what R2 actually serves** —
   `audit_live_timings.py --prefix <slug>`. Not a sample: a partial upload
   looks identical to a full one in a sample, and once left 76 of 114 surahs
   serving stale data undetected.

Two flags worth knowing: `build_timings.py --joined SURAH:AYAH,...` drops an
ayah the sheikh runs into the previous one (reported by ear; `verify_all.py`
takes the same flag so it expects the reduced count), and `--covered` does the
same systematically for a هبطي reciter from a JSON map.

---

## Where it is served, and why two buckets

| what | host |
|---|---|
| audio | `audio.mushaf-qaloon.com/<slug>/SSS.mp3` |
| timings | `quran-content.mushaf-qaloon.com/timings/<slug>/SSS.json` |

The MP3s are played by an audio element and need no CORS. The timings are
fetched with an XHR, which on the Flutter **web** build is cross-origin — and
`audio.mushaf-qaloon.com` sends no `Access-Control-Allow-Origin`, while
`quran-content` sends `*`. Putting the timings beside the audio makes the web
build silently play nothing. If you ever move them, give that bucket CORS
first.

---

## Wiring a new reciter in

Three places, all data, no branching logic:

**1. The Flutter app** — one entry in `lib/models/reciter.dart`, added to
`Reciter.all`:

```dart
static const Reciter xQaloun = Reciter(
  id: 'x_qaloun',
  name: '…', shortName: '…', riwaya: 'رواية قالون',
  audioBaseUrl: 'https://audio.mushaf-qaloon.com/<slug>/',
  cacheFolder: 'audio_cache_<slug>',
  scheme: AudioScheme.timedSurah,
  timingsBaseUrlOverride:
      'https://quran-content.mushaf-qaloon.com/timings/<slug>/',
);
```

That is the whole app change. A timed reciter needs no `coveredAyat`, no
`missingAyat`, no continuations asset. **Do not touch `_getAudioFilesForAyah`**
— the per-ayah reciters go through it unchanged; `_getClipsForAyah` is the only
seam. `test/reciter_audio_files_test.dart` guards this.

**2. The web player** — an entry in `RECITERS` in
`tools/build_web_player_data.py` with `"scheme": "timed"` and `"timingsDir"`,
then run it. It bundles `web-player/data/timings_<slug>.json`.

**3. The review page** — `build_review_page.py`, set `BASE_URL`, `RECITER`,
`RIWAYA`, `RECITER_ID`. The public review tracker backend is shared (one
Cloudflare Worker + D1 + KV for every reciter); a new reciter needs **zero** new
Cloudflare setup.

**Deploys of mushaf-qaloon.com are manual — `git push` does not update the
site.** Assemble `deploy_dist` (web-player + `build/web` under `app/`) and run
`wrangler pages deploy`. This has gone stale silently more than once.

---

## Playback: three players, one invariant

This is the part that bites. **There are three separate implementations of
timed playback**, and a fix in one does not reach the others:

| where | file |
|---|---|
| Flutter app (phones + web) | `lib/services/audio_service.dart` |
| public web player | `web-player/js/player-engine.js` |
| review/listening page | generated by `build_review_page.py` |

The invariant all three must uphold: **an ayah must stop at its own boundary,
and nothing else may still be playing.** Because the spans are contiguous,
anything that overruns plays the start of the next ayah, and anything left
running underneath overlaps it. Each implementation broke this in its own way:

- **Review page (trap #10):** a logical clip end is not the file ending, so the
  element must be explicitly paused or the inter-ayah gap keeps playing forward.
- **Web player (2026-09-13):** it gapless-transitions between two alternating
  `<audio>` elements. For a timed reciter both point at the *same* file, so
  swapping which is "active" without pausing the outgoing one left it running —
  audible overlap, compounding each ayah.
- **Flutter web (2026-09-16):** `just_audio_web` enforces a clip's end only from
  the HTML `timeupdate` event (~4×/sec), so a clip overran by up to ~250 ms —
  the next ayah's opening, which the next clip then replayed («و… وما أدراك ما
  القارعة»). Fixed with a position watch that closes the boundary to ~40 ms.
  Native players clip sample-accurately, so phones never showed it.

If a fourth player is ever written, verify this by ear on ayat 2–3 of a
multi-clip surah before shipping. Whole-file reciters never trigger it, so it
ships silently broken.

---

## The silent gap between ayat (2026-09-20)

Reported as "there is no audio at all between the two ayat". Worth reading
because the diagnosis method generalises.

**Finding it.** A screen recording contained 15 stretches of *exact zero
samples*, median 474 ms. Recorded recitation always carries room tone, so
digital silence is the app emitting nothing — not the sheikh pausing. Matching
the per-ayah durations against every reciter's spans identified which reciter
and confirmed the audio itself was correct.

**The cause.** The app reloaded the whole surah file for *every* ayah, just to
play a different slice. Measured: **200 ms – 1.9 s streamed**, ~170 ms from a
downloaded file. Silent, and landing exactly between two ayat.

**The fix** (in `_playClip`): when the next ayah is in the file already loaded,
stay in it. Three parts, all needed:

1. Load the surah **unclipped** and keep `_loadedSurahUri`; seek within it for
   later ayat instead of calling `setAudioSource` again.
2. **Do not seek when already at the boundary.** The clip watch stops a few tens
   of ms past the end, which — spans being contiguous — is already where the
   next ayah begins. Seeking anyway makes the player re-buffer (~200 ms, the
   very gap being removed). Only seek when the position is genuinely elsewhere:
   a tapped ayah, a repeat, a jump.
3. **Retry the load once when the surah changes.** Leaving a surah mid-file
   keeps its transfer open; handing the player a new source aborts it, which
   `just_audio` reports against the *new* load ("Connection aborted" /
   "Loading interrupted"). Without the retry the recitation stopped dead on
   roughly one surah change in four while streaming.

Result, measured over a full page on an emulator: **799 ms → 40 ms** median,
and 3 file loads per page instead of 15.

**Two consequences to remember:**

- Because the surah is loaded unclipped, `ClippingAudioSource` no longer ends
  the ayah — the position watch does, on **every** platform, not just web.
- The OS media notification updates only when a source is loaded, i.e. **once
  per surah**, so its ayah number goes stale within a surah. There is no public
  API to refresh it without the reload that causes the gap. The in-app bar is
  unaffected. Option if it matters: drop the ayah number from the notification
  title for timed reciters.

**Per-ayah reciters cannot use any of this** — each ayah genuinely is a
different file, so a load is unavoidable. Their overhead is ~200 ms streamed,
mostly source preparation rather than download (a cached file still costs
~150 ms). Removing it would need playlist preloading, which is a real rewrite
of the advance/repeat logic. Not attempted.

---

## Shipping checklist

- [ ] `verify_all.py` clean; ayah count matches the app text (6214 minus any
      declared joins)
- [ ] `check_margins.py` / `find_overlaps.py` show no new flags
- [ ] `audit_live_timings.py --prefix <slug>` reports **114/114 identical**
- [ ] Spans contiguous, no `"0"` key anywhere
- [ ] `Reciter` entry added to `Reciter.all`; `flutter test` passes;
      `_getAudioFilesForAyah` untouched
- [ ] `tools/build_web_player_data.py` rerun; `timings_<slug>.json` bundled
- [ ] Review page built, uploaded to its stable `mushaf_<slug>.html` URL
- [ ] **Listened to by ear** across at least one surah boundary and one joined
      ayah — the tiling invariant proves nothing is lost, not that boundaries
      sit where a listener would put them
- [ ] Site deployed manually (`deploy_dist` + `wrangler pages deploy`)

## Still open

- Web build of the gap fix is **untested**; it changed shared code and web
  deploys are manual.
- The two copies of `build_timings.py` (`D:/AlQryw/pipeline` and
  `D:/AbuSenainahTimed/pipeline`) have diverged — each carries flags the other
  lacks. Check both before copying one for a new reciter.
- Version numbers: iOS and Android share pubspec's `+N` but have separate store
  histories. iOS was already at build 100 while Android was at 26; the shared
  number now starts from 101.

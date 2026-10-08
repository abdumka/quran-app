# Recording a whole khatma as a video

One MP4 of the entire mushaf — two pages at a time, as the book opens — with
continuous تلاوة from page 1 to page 602, for any reciter the app ships.

`tools/make_khatma_video.py` builds it. It is **not** a screen recording: the
frames are assembled from the page images and the page turns are computed from
the recitation timings, so a 29-hour khatma costs about 40 minutes of unattended
encoding rather than 29 hours of sitting in front of the app, and every turn
lands on the exact moment the sheikh reaches that page.

```
python tools/make_khatma_video.py --reciter alqryw --audio-root D:/mirrors --spreads 1-3 --out test.mp4
python tools/make_khatma_video.py --reciter alqryw --audio-root D:/mirrors
```

Always run the three-spread smoke test first — it finishes in under a minute and
shows the framing, the crop and the first turns.

## What it needs

* **ffmpeg and ffprobe** on PATH, and **Pillow**.
* **The audio, locally.** It is not in this repo. Mirror the reciter's folder
  from `audio.mushaf-qaloon.com` — `--audio-root` is the parent of those folders
  and the folder name comes from `web-player/data/reciters.json`, so one root
  serves every reciter. `--audio-dir` points at a single folder instead.

Everything else is already here: `assets/images/page_*.webp`,
`assets/data/output.json`, the timings and overrides under `web-player/data/`,
and the crop rects in `lib/data/page_crops.dart`.

## Pick a timed reciter if you can

| | timed (naihi, abusenainah, alqryw, rajab) | per-ayah (husary, qaniwah, hudaifi, doukali) |
|---|---|---|
| to mirror | 114 files | 6214 files |
| continuity | already continuous | joined at 6214 seams |
| ayah onsets | read from the timings file | measured, one ffprobe per clip |
| first run | about a minute of setup | a few minutes of probing |

Both work and both are correct — the quirks of the per-ayah mirrors (merged
tails, separate basmala files, ayat recited inside a neighbour's breath) are
already encoded in `overrides_*.json`, and the script resolves through the same
table the web player does, collapsing a clip two ayat share so it is heard once.
The timed scheme is simply less to move and less to go wrong.

## How a page turn is decided

`output.json` files an ayah under the page its rosette is printed on, so the
first ayah of page *p* gives the moment to turn to *p*. The five pages this
mushaf breaks in the middle of an ayah are the exception, and
`lib/page_span_data.dart` says how far into that ayah the break falls — the turn
waits that long instead of pulling the page out from under the words still in
front of the reader. It is the same table the app's reader uses, parsed from the
generated Dart so the two cannot drift apart.

Page 1 starts at 0:00, so the الاستعاذة before al-Fatiha plays on the opening
spread. The same holds between surahs: a surah's intro plays while the previous
page is still up, and the turn comes on ayah 1's own onset.

`--timeline-only` prints the whole table — spread, pages, in, out, duration —
and encodes nothing. Worth reading before committing to a long render.

## Framing

Spread *k* is pages 2k−1 and 2k, **odd page on the right**, so pages 1 and 2 face
each other exactly as the mushaf opens. Both pages are drawn at the same height
and butted against the gutter so they meet at the spine.

By default each page is cropped to its frame interior, the way the reader shows
it with عرض الهوامش off (`--margins full` for the whole هوامش scan instead). At
the default 2560×1440 the text is close to the native scan resolution.

## Cost

For a 29-hour khatma at the defaults: roughly 40 minutes of encoding on a normal
desktop and about 2–3 GB of MP4, most of it audio. The frames are static, so
`--fps 2` is enough — it is also the page-turn granularity, which lands every
turn within half a second. Keyframes are most of the video bitrate; every page
turn is a scene cut and gets one regardless, and `--gop-seconds` only sets how
finely you can scrub within a spread. Drop to `--width 1920 --height 1080` or
raise `--crf` if the file matters more than the sharpness.

The concatenated audio and the rendered spreads are cached under `--work` and
reused, so a second pass with different encode settings skips the slow parts.

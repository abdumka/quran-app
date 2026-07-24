#!/usr/bin/env python3
"""Generates word-level bounding boxes for page 1 (Al-Fatihah) of the mushaf,
for the memorization-test-mode proof of concept.

## Why this isn't a generic, page-independent algorithm

An earlier version of this script tried pure automated segmentation (crop
each ayah's line rect from `assets/data/ayah_positions.json`, threshold to
find ink, project columns, split on gaps). That approach hit three real
problems, discovered by actually running it and inspecting the output:

1. **`ayah_positions.json`'s "ayah" numbering is offset by one for Surah 1
   specifically.** Its rect labeled `ayah: 1` is visually the Basmala line;
   `output.json`'s `ayah: 1` is "الحمد لله رب العالمين" (the Basmala isn't a
   numbered ayah in this app's Qaloon convention at all). Verified directly:
   cropping the `ayah_positions.json` ayah-1 rect renders the Basmala, not
   Alhamdu. `ayah_positions.json` is otherwise unused for rendering today
   (only `search_page.dart` consults it, for page-lookup, where a
   within-page offset is invisible) so this had never surfaced before.
2. **Those rects are noticeably looser than word-segmentation needs.**
   They bleed horizontally into the decorative gold border and into
   neighboring ayahs, and vertically into adjacent print lines -- fine for
   their original purpose (a generous highlight/search-lookup box), not
   fine as a crop boundary for column-projection.
3. **Some adjacent word pairs render with *zero* pixel gap between them**
   (e.g. "الرحمن الرحيم" in ayah 2) -- there is no threshold that finds a
   gap that doesn't exist. Cursive Arabic typesetting doesn't guarantee a
   column gap at every word boundary.

Given all three, this script does NOT attempt fully-automatic segmentation.
Instead it:
  - Locates each of the page's 6 real text lines itself, from row-wise ink
    density (independent of `ayah_positions.json`), landing on Y-bands that
    were then confirmed against the page's own printed ayah-end markers
    (the small circled digits) by visual inspection.
  - Runs column-projection *within* each line (which works cleanly once the
    line is correctly and tightly bounded) to get raw ink runs.
  - Uses those runs as a visual reference, cross-checked by eye against a
    3x-scaled, run-annotated crop of each line, to hand-assign every run
    (or group of runs, or split of one run) to a specific word from
    `output.json`. The pixel ranges below are the result of that visual
    pass, not a formula -- see `tools/scratch_line_*_annotated.png`-style
    debug crops generated during development for the reasoning trail.

This is honest about being a one-page, hand-calibrated artifact, matching
the memorization-test-mode plan's expectation that the manual correction
pass -- not an algorithm -- is what actually guarantees correctness here.
It is NOT intended to generalize to other pages without redoing this same
visual process (extending it to all 602 pages would need either a lot more
of this manual work or a fundamentally different approach, e.g. an
ML-based text detector -- out of scope for this proof of concept).

Output: assets/data/word_positions.json (page-relative 0..1 ratios, same
convention as assets/data/ayah_positions.json) plus a debug PNG with every
word box drawn and labeled, for a final visual sanity check.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parent.parent
PAGE_IMAGE = REPO_ROOT / "assets" / "images" / "page_1.webp"
OUTPUT_JSON = REPO_ROOT / "assets" / "data" / "output.json"
WORD_POSITIONS_JSON = REPO_ROOT / "assets" / "data" / "word_positions.json"
DEBUG_IMAGE = REPO_ROOT / "tools" / "word_positions_page1_debug.png"

PAGE = 1

# Y-bands for the 6 real recitation text lines (the Basmala line and the
# surah-name header box are deliberately excluded -- neither is numbered
# ayah text). Found via row-wise ink density, confirmed against the page's
# own printed ayah-end markers by visual inspection (see module docstring).
LINE_Y = {
    "B": (733, 805),  # ayah 1 + ayah 2
    "C": (825, 903),  # ayah 3 + ayah 4 (start)
    "D": (903, 973),  # ayah 4 (end) + ayah 5
    "E": (1001, 1061),  # ayah 6 + ayah 7 (start)
    "F": (1061, 1141),  # ayah 7 (rest)
}

# Word boxes as (line, x_start, x_end) in pixels *relative to X_ORIGIN*
# (i.e. add X_ORIGIN to get absolute page-pixel X). Hand-determined by
# visually matching column-projection runs to glyphs -- see module
# docstring. Ordered per ayah in reading (RTL, right-to-left = descending
# x) order, matching the word order in output.json's ayah text.
X_ORIGIN = 115

WORD_BOXES: dict[int, list[tuple[str, int, int]]] = {
    1: [("B", 355, 422), ("B", 322, 349), ("B", 281, 320), ("B", 198, 276)],
    2: [("B", 107, 151), ("B", 62, 106)],
    3: [("C", 373, 418), ("C", 334, 369), ("C", 298, 331)],
    4: [("C", 196, 268), ("C", 137, 195), ("C", 39, 133), ("D", 340, 416)],
    5: [("D", 239, 308), ("D", 147, 237), ("D", 59, 144)],
    6: [("E", 339, 419), ("E", 262, 329), ("E", 186, 258), ("E", 113, 179)],
    7: [("E", 32, 80), ("F", 316, 422), ("F", 234, 309), ("F", 186, 229), ("F", 70, 193)],
}


def load_ayah_words_for_page(page: int) -> dict[int, list[str]]:
    with OUTPUT_JSON.open(encoding="utf-8") as f:
        data = json.load(f)
    page_entry = next(p for p in data if p["page"] == page)
    return {a["ayah"]: a["text"].split() for a in page_entry["ayahs"]}


def main() -> None:
    page_img = Image.open(PAGE_IMAGE)
    page_w, page_h = page_img.size
    print(f"page_1.webp size: {page_w}x{page_h}")

    ayah_words = load_ayah_words_for_page(PAGE)

    debug_img = page_img.convert("RGB").copy()
    draw = ImageDraw.Draw(debug_img)

    output_ayahs = []
    total_words = 0

    for ayah, boxes in WORD_BOXES.items():
        words_text = ayah_words[ayah]
        assert len(boxes) == len(words_text), (
            f"ayah {ayah}: {len(boxes)} boxes but {len(words_text)} words "
            f"in output.json ({words_text})"
        )

        word_entries = []
        for word_idx, ((line, x_start, x_end), word_text) in enumerate(
            zip(boxes, words_text)
        ):
            y_top, y_bottom = LINE_Y[line]
            abs_x = X_ORIGIN + x_start
            abs_w = x_end - x_start
            word_entries.append(
                {
                    "index": word_idx,
                    "text": word_text,
                    "x": round(abs_x / page_w, 6),
                    "y": round(y_top / page_h, 6),
                    "width": round(abs_w / page_w, 6),
                    "height": round((y_bottom - y_top) / page_h, 6),
                }
            )
            draw.rectangle(
                [abs_x, y_top, abs_x + abs_w, y_bottom],
                outline=(220, 30, 30),
                width=2,
            )
            draw.text((abs_x + 2, y_top - 14), str(word_idx), fill=(0, 90, 220))
            total_words += 1

        output_ayahs.append({"surah": 1, "ayah": ayah, "words": word_entries})
        preview = " | ".join(w["text"] for w in word_entries)
        print(f"  ayah {ayah}: {len(word_entries)} words -> {preview}")

    result = [{"page": PAGE, "ayahs": output_ayahs}]
    WORD_POSITIONS_JSON.parent.mkdir(parents=True, exist_ok=True)
    with WORD_POSITIONS_JSON.open("w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    debug_img.save(DEBUG_IMAGE)

    print(f"\nwrote {WORD_POSITIONS_JSON} ({total_words} words)")
    print(f"wrote {DEBUG_IMAGE} -- inspect this before trusting the JSON")


if __name__ == "__main__":
    main()

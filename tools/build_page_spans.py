"""Generate lib/page_span_data.dart — the ayat printed across a page break.

assets/data/output.json files an ayah under the page its gold rosette is
printed on ("the page it ends on"), so an ayah that starts near the foot of one
page and finishes on the next belongs, as far as the app is concerned, to the
next page. During التلاوة that turned the page the moment such an ayah began,
while the words being recited were still printed in front of the reader.

This mushaf almost always breaks its pages at an ayah end, so the problem is
confined to a handful of pages. Which ones is decided here rather than by hand:
every page image is scanned for its rosettes and the ones whose last rosette is
*not* at the foot of the page are the page-spanning cases. For each, the last
word printed before the break (SPLIT_WORDS below, read off the page image) says
where in the ayah the reader should be moved on.

Turning that word into a moment in the recitation is what
tools/measure_page_span_pauses.py does, by timing where each of the app's
reciters pauses; this script prefers that where they agree, and falls back to
an estimate from the printed run and the ayah's letter count where they do not.

Needs Pillow and assets/images/. Run from the repo root:

    python tools/build_page_spans.py              # reuses the measurement cache
    python tools/build_page_spans.py --remeasure  # rescans the page images

Scanning takes about half an hour, so the per-page measurements are kept in
tools/page_span_measure.json alongside this script. Rescan whenever the page
images change; an output.json re-cut alone does not need it.
"""

import json
import os
import re
import sys
from collections import deque

from PIL import Image, ImageChops, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGES = os.path.join(ROOT, 'assets', 'images', 'page_%d.webp')
OUTPUT_JSON = os.path.join(ROOT, 'assets', 'data', 'output.json')
DART_OUT = os.path.join(ROOT, 'lib', 'page_span_data.dart')
CACHE = os.path.join(ROOT, 'tools', 'page_span_measure.json')
AUDIO = os.path.join(ROOT, 'tools', 'page_span_audio.json')

# How far apart two reciters' page-break timings may be and still count as
# agreeing, as a fraction of the ayah. Where the break carries a waqf mark they
# come in inside 0.04 of each other; where it does not, most sheikhs read
# straight past it and the readings scatter over half the ayah.
AGREEMENT = 0.06

PAGES = 602
LINES = 15          # every page of this mushaf is a 15-line block
FOOT = 14.8         # a last rosette past this sits at the foot of the page

# The last word printed on the earlier page, for each page-spanning ayah — read
# off the page image, keyed by the page the ayah is *listed* on (the page turned
# to). The word is matched against the ayah's text in output.json after both are
# stripped of their vowel marks, so it can be written plainly here.
SPLIT_WORDS = {
    35: 'والاخرة',    # 2:218  — قل العفو … في الدنيا والآخرة | ويسألونك عن اليتامى
    86: 'السبيل',     # 4:44   — … ويريدون أن تضلوا السبيل | والله أعلم بأعدائكم
    259: 'السماء',    # 14:27  — … أصلها ثابت وفرعها في السماء | تؤتي أكلها
    355: 'والاصال',   # 24:36  — … يسبح له فيها بالغدو والآصال | رجال لا تلهيهم
    356: 'بالابصار',  # 24:42  — … يكاد سنا برقه يذهب بالأبصار | يقلب الله الليل
}

# Pages the detector under-counts — it finds no rosette at their foot and so
# reads them as page-spanning — but whose last line was checked against the
# image and does end at an ayah's rosette.
PAGE_ENDS_AT_AYAH = {
    1: 'al-Fatiha inside an ornamental gold frame, which swamps the detector',
    537: 'the 57:23 rosette at the foot prints too pale to detect',
}

# Vowel marks and the pause symbols, which carry no length of their own. The
# superscript alef is the exception — it is a long ā, written small — so it is
# folded into a plain alef first and counted like one.
_MARKS = re.compile('[\u064B-\u065F\u06D6-\u06ED\u0640]')
_LETTERS = re.compile('[\u0621-\u064A\u0671-\u06D3]')
_ALEF = re.compile('[\u0622\u0623\u0625\u0670\u0671\u0672\u0673]')


# ── page text ────────────────────────────────────────────────────────────────

def load_pages():
    """output.json as {page: [ayah, …]} (its tail is a nested list)."""
    with open(OUTPUT_JSON, encoding='utf-8') as f:
        raw = json.load(f)
    flat = []

    def add(item):
        if isinstance(item, list):
            for sub in item:
                add(sub)
        else:
            flat.append(item)

    for item in raw:
        add(item)
    return {page['page']: page['ayahs'] for page in flat}


def bare(word):
    """A word reduced to its plain letters, for matching and for counting."""
    return _ALEF.sub('\u0627', _MARKS.sub('', word)).replace('\u0649', '\u064A')


def letters(word):
    """Roughly how long a word takes to recite: one unit per sounded letter."""
    return len(_LETTERS.findall(bare(word)))


# ── rosette detection ────────────────────────────────────────────────────────
#
# Two detectors, because neither is complete on its own: the high-pass loses
# rosettes printed over the scans' yellow corner staining, where the local R-B
# baseline is already as high as the gold itself, and the colour rule loses the
# occasional pale one. Every miss of one is a hit of the other.

def _blobs(mask, w, h, minpix=30):
    seen = bytearray(w * h)
    out = []
    for start in range(w * h):
        if not mask[start] or seen[start]:
            continue
        seen[start] = 1
        queue = deque([start])
        x0 = x1 = start % w
        y0 = y1 = start // w
        n = 0
        while queue:
            i = queue.popleft()
            n += 1
            y, x = divmod(i, w)
            x0, x1 = min(x0, x), max(x1, x)
            y0, y1 = min(y0, y), max(y1, y)
            for ny in (y - 1, y, y + 1):
                if ny < 0 or ny >= h:
                    continue
                base = ny * w
                for nx in (x - 1, x, x + 1):
                    if 0 <= nx < w:
                        j = base + nx
                        if mask[j] and not seen[j]:
                            seen[j] = 1
                            queue.append(j)
        if n >= minpix:
            out.append([x0, y0, x1, y1, n])
    return out


def _merge(boxes, gap=6):
    changed = True
    while changed:
        changed = False
        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                a, b = boxes[i], boxes[j]
                if (a[0] - gap <= b[2] and b[0] - gap <= a[2]
                        and a[1] - gap <= b[3] and b[1] - gap <= a[3]):
                    boxes[i] = [min(a[0], b[0]), min(a[1], b[1]),
                                max(a[2], b[2]), max(a[3], b[3]), a[4] + b[4]]
                    boxes.pop(j)
                    changed = True
                    break
            if changed:
                break
    return boxes


def _highpass_mask(im, thresh=16):
    r, _, b = im.split()
    rb = ImageChops.subtract(r, b)              # gold ink, plus the vignette
    blur = rb.filter(ImageFilter.GaussianBlur(18))
    return bytearray(ImageChops.subtract(rb, blur)
                     .point(lambda v: 255 if v > thresh else 0).tobytes())


def _colour_mask(im):
    """Gold is far darker than the paper but much warmer than the text."""
    r, g, b = im.split()
    mask = ImageChops.subtract(r, b).point(lambda v: 255 if v >= 70 else 0)
    for other in (
        ImageChops.subtract(r, g).point(lambda v: 255 if v >= 8 else 0),
        ImageChops.subtract(g, b).point(lambda v: 255 if v >= 30 else 0),
        r.point(lambda v: 255 if v <= 245 else 0),
        b.point(lambda v: 255 if v <= 130 else 0),
    ):
        mask = ImageChops.multiply(mask, other)
    return bytearray(mask.tobytes())


def rosettes(path):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    boxes = []
    for mask in (_highpass_mask(im), _colour_mask(im)):
        for x0, y0, x1, y1, area in _merge(_blobs(mask, w, h)):
            if area >= 120 and 18 <= x1 - x0 + 1 <= 60 and 26 <= y1 - y0 + 1 <= 80:
                boxes.append([x0, y0, x1, y1, area])
    boxes = _merge(boxes, gap=4)
    return [b for b in boxes
            if 20 <= b[2] - b[0] + 1 <= 62 and 26 <= b[3] - b[1] + 1 <= 80]


# ── page geometry ────────────────────────────────────────────────────────────

MARGIN = 14


def grid(path):
    """(ytop, line pitch, xleft, xright) of the page's 15-line text block.

    Fitted from the ink's extent rather than detected band by band: the lines
    touch through their diacritics, so band detection merges or splits them
    depending on the page.
    """
    im = Image.open(path).convert('L')
    w, h = im.size
    im = im.crop((MARGIN, MARGIN, w - MARGIN, h - MARGIN))
    cw, ch = im.size
    ink = im.point(lambda v: 255 if v < 140 else 0)
    rows = list(ink.resize((1, ch), Image.BOX).tobytes())
    cols = list(ink.resize((cw, 1), Image.BOX).tobytes())
    ys = [y for y, n in enumerate(rows) if n > max(2, max(rows) // 20)]
    xs = [x for x, n in enumerate(cols) if n > max(2, max(cols) // 20)]
    ytop, ybot = min(ys) + MARGIN, max(ys) + MARGIN
    return ytop, (ybot - ytop) / LINES, min(xs) + MARGIN, max(xs) + MARGIN


def reading_position(box, page_grid):
    """How far into the page a rosette sits, in line units (0 … 15)."""
    ytop, pitch, xleft, xright = page_grid
    xc, yc = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    line = max(0, min(LINES - 1, int((yc - ytop) / pitch)))
    across = (xright - xc) / max(1, xright - xleft)
    return line + max(0.0, min(1.0, across))


# ── main ─────────────────────────────────────────────────────────────────────

def measure_page(page):
    """(first rosette, last rosette) of a page, in line units."""
    path = IMAGES % page
    boxes = rosettes(path)
    if not boxes:
        return None
    positions = [reading_position(b, grid(path)) for b in boxes]
    return [min(positions), max(positions), len(boxes)]


def measure_all(remeasure):
    if not remeasure and os.path.exists(CACHE):
        with open(CACHE, encoding='utf-8') as f:
            print(f'reusing {CACHE} (--remeasure to rescan)')
            return {int(k): v for k, v in json.load(f).items()}
    measured = {}
    for page in range(1, PAGES + 1):
        result = measure_page(page)
        if result is None:
            print(f'  page {page}: no rosettes found — skipped')
            continue
        measured[page] = result
        print(f'{page}\t{result[2]}\t{result[1]:.2f}', flush=True)
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, 'w', encoding='utf-8') as f:
        json.dump(measured, f)
    return measured


def main():
    pages = load_pages()
    measured = measure_all('--remeasure' in sys.argv)
    audio = {}
    if os.path.exists(AUDIO):
        with open(AUDIO, encoding='utf-8') as f:
            audio = json.load(f)
    else:
        print(f'note: no {AUDIO} — run tools/measure_page_span_pauses.py to '
              f'time the page breaks against the recordings')
    spanning = [(page, last, counted, len(pages.get(page, [])))
                for page, (_, last, counted) in sorted(measured.items())
                if last < FOOT and page not in PAGE_ENDS_AT_AYAH]

    print()
    for page, why in sorted(PAGE_ENDS_AT_AYAH.items()):
        if measured.get(page, (0, LINES, 0))[1] >= FOOT:
            print(f'  note: page {page} is detected correctly now — its '
                  f'PAGE_ENDS_AT_AYAH entry ({why}) can go')
    print(f'{len(spanning)} page(s) do not end at an ayah boundary:')
    entries = {}
    problems = []
    for page, last, counted, listed in spanning:
        note = '' if counted == listed else \
            f'  (!! {counted} rosettes detected, output.json lists {listed})'
        nxt = pages.get(page + 1)
        if not nxt:
            problems.append(f'page {page}: no page {page + 1} in output.json')
            continue
        ayah = nxt[0]
        words = ayah['text'].split()
        want = SPLIT_WORDS.get(page + 1)
        print(f'  page {page} -> {page + 1}  {ayah["surah"]}:{ayah["ayah"]}'
              f'  last rosette at line {last:.2f}{note}')
        if want is None:
            problems.append(
                f'page {page + 1}: {ayah["surah"]}:{ayah["ayah"]} spans the '
                f'break but has no SPLIT_WORDS entry — read the last word of '
                f'page {page} off its image and add it')
            continue
        hits = [i for i, w in enumerate(words) if bare(w) == bare(want)]
        if len(hits) != 1:
            problems.append(
                f'page {page + 1}: "{want}" matches {len(hits)} words of '
                f'{ayah["surah"]}:{ayah["ayah"]} — expected exactly one')
            continue
        index = hits[0]
        # Two independent readings of the same split, averaged because each is
        # only a proxy for the thing that actually matters — how long the head
        # of the ayah takes to recite. Letters track syllables but not the
        # stretching of a madd; the printed run tracks the real break but not
        # how fast each hand-set line reads. They come out within a couple of
        # words of each other, and of where the reciter's own pause falls.
        total = sum(letters(w) for w in words)
        head = sum(letters(w) for w in words[:index + 1])
        by_letters = head / total
        after = max(0.0, LINES - last)
        before = max(0.0, measured[page + 1][0])
        by_ink = after / (after + before) if after + before else 0.0
        estimate = (by_letters + by_ink) / 2
        flag = '' if abs(by_ink - by_letters) < 0.12 else '   <-- CHECK'
        print(f'      split after word {index + 1}/{len(words)} "{want}": '
              f'{head}/{total} letters = {by_letters:.3f}, '
              f'printed run = {by_ink:.3f}  ->  {estimate:.3f}{flag}')
        # The recordings beat both estimates where the reciters agree on where
        # the break falls — see tools/measure_page_span_pauses.py.
        heard = sorted(audio.get(str(page + 1), {}).values())
        fraction, source = estimate, 'estimated from the page and the text'
        if len(heard) >= 2:
            mid = len(heard) // 2
            median = (heard[mid] if len(heard) % 2
                      else (heard[mid - 1] + heard[mid]) / 2)
            agree = [v for v in heard if abs(v - median) <= AGREEMENT]
            print(f'      reciters heard: '
                  + ' '.join(f'{v:.3f}' for v in heard)
                  + f'  median {median:.3f}, {len(agree)}/{len(heard)} agree')
            if len(agree) * 2 >= len(heard):
                fraction, source = median, f'median of {len(heard)} reciters'
            else:
                print('      -> they do not agree; keeping the estimate')
        entries[page + 1] = (fraction, source)

    if problems:
        print()
        for p in problems:
            print('  !! ' + p)
        print('\nNothing written.')
        return 1

    unused = set(SPLIT_WORDS) - set(entries)
    if unused:
        print()
        print('  !! SPLIT_WORDS has pages that no longer span a break: '
              + ', '.join(str(p) for p in sorted(unused)))
        return 1

    with open(DART_OUT, 'w', encoding='utf-8') as f:
        f.write('''// Ayat printed across a page break — آيات ممتدة بين صفحتين.
//
// assets/data/output.json lists an ayah under the page its rosette is printed
// on, so an ayah running across the break belongs to the page it *ends* on. The
// reader, though, is still looking at the page it *starts* on, and turning the
// page the moment such an ayah begins throws them forward off words still in
// front of them.
//
// Keyed by the page the ayah is listed on (the page being turned to); the value
// is the fraction of that ayah's recitation printed on the page before it — how
// long the turn waits. This mushaf breaks its pages at an ayah end everywhere
// else, which is why there are so few.
//
// Each value is where the reciters are actually heard to reach the break: their
// pauses are timed against the ayah's waqf stops and the median taken, which
// they agree on inside a few per cent. It falls back to an estimate from the
// printed page and the letter count where the break carries no waqf mark and
// most sheikhs read straight past it.
//
// Generated by tools/build_page_spans.py (and tools/measure_page_span_pauses.py
// for the timings) — do not edit by hand.
const Map<int, double> spannedAyahHead = {
''')
        for page in sorted(entries):
            ayah = pages[page][0]
            fraction, source = entries[page]
            f.write(f'  // {ayah["surah"]}:{ayah["ayah"]} — page {page - 1} '
                    f'ends at «{SPLIT_WORDS[page]}»; {source}.\n'
                    f'  {page}: {fraction:.3f},\n')
        f.write('};\n')
    print(f'\nwrote {DART_OUT} ({len(entries)} entries)')
    return 0


if __name__ == '__main__':
    sys.exit(main())

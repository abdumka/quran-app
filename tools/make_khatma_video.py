"""Render a whole khatma as one video: two mushaf pages at a time, continuous تلاوة.

The video is built offline from assets this repo already carries — it is not a
screen recording of the app, so a 30-hour khatma takes an unattended encode
rather than 30 hours of real time, and every page turn lands on the exact
millisecond the sheikh reaches that page.

Three things are stitched together:

  * `assets/images/page_N.webp` — the 602 page images, pasted two to a frame
    (odd page on the RIGHT, as the mushaf opens: 1-2, 3-4, … 601-602).
  * `assets/data/output.json` — which ayat are printed on each page, which is
    what turns a moment in the recitation into a page number.
  * the reciter's own audio, concatenated into one continuous track.

Both audio schemes the app ships are supported, and the timing comes out of the
same data the players use, so a turn here happens where a turn in the app does:

  * TIMED reciters (naihi / abusenainah / alqryw / rajab) — 114 whole-surah
    MP3s plus `web-player/data/timings_<id>.json`. Easiest by far: the audio is
    already continuous, so concatenating 114 files is the whole job, and the
    timings give each ayah's onset directly.
  * PER-AYAH reciters (husary / qaniwah / hudaifi / doukali) — 6214 `SSSAAA.mp3`
    files resolved through `web-player/data/overrides_<id>.json`, which already
    encodes that mirror's quirks (merged tails, separate basmala files, ayat
    recited inside a neighbour's breath). Each ayah's onset is then just the
    running sum of the clip durations before it.

`lib/page_span_data.dart` is honoured for the five pages this mushaf breaks in
the middle of an ayah: the turn waits until the reciter has passed the words
printed on the page before, instead of pulling the page out from under them.

Needs ffmpeg/ffprobe on PATH and Pillow. The audio is NOT in this repo — point
`--audio-dir` at a local mirror of the reciter's folder from
audio.mushaf-qaloon.com (`001.mp3`… for timed, `001001.mp3`… for per-ayah).

    # smoke test first: three spreads, ~2 minutes of encode
    python tools/make_khatma_video.py --reciter alqryw \
        --audio-dir /mnt/audio/alqryw --spreads 1-3 --out test.mp4

    # the whole khatma
    python tools/make_khatma_video.py --reciter alqryw \
        --audio-dir /mnt/audio/alqryw --out khatma_alqryw.mp4

Everything intermediate (the concatenated audio, the 301 spread images, the
ffmpeg lists) is kept under --work and reused on a re-run, so a second pass with
different encode settings does not redo the slow parts.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT_JSON = ROOT / 'assets' / 'data' / 'output.json'
SPAN_DART = ROOT / 'lib' / 'page_span_data.dart'
CROPS_DART = ROOT / 'lib' / 'data' / 'page_crops.dart'
RECITERS_JSON = ROOT / 'web-player' / 'data' / 'reciters.json'
WEB_DATA = ROOT / 'web-player' / 'data'
PAGE_COUNT = 602


# --------------------------------------------------------------------------- #
# repo data
# --------------------------------------------------------------------------- #

def load_pages() -> dict[int, list[tuple[int, int]]]:
    """page -> the (surah, ayah) pairs printed on it, in recitation order.

    output.json is a list of per-page records whose tail happens to be nested
    one level deeper (pages 551-602 sit inside a single list element). Flatten
    whatever shape it is rather than trusting the nesting.
    """
    raw = json.loads(OUTPUT_JSON.read_text(encoding='utf-8'))
    pages: dict[int, list[tuple[int, int]]] = {}

    def walk(node):
        if isinstance(node, list):
            for item in node:
                walk(item)
        elif isinstance(node, dict) and 'page' in node:
            pages[int(node['page'])] = [
                (int(a['surah']), int(a['ayah'])) for a in node.get('ayahs', [])
            ]

    walk(raw)
    missing = [p for p in range(1, PAGE_COUNT + 1) if p not in pages]
    if missing:
        sys.exit(f'output.json is missing pages: {missing[:10]}')
    return pages


def load_spanned_heads() -> dict[int, float]:
    """page -> fraction of that page's first ayah already printed on the page before.

    Parsed out of the generated Dart table so the two never drift apart.
    """
    if not SPAN_DART.exists():
        return {}
    body = re.search(
        r'spannedAyahHead\s*=\s*\{(.*?)\};', SPAN_DART.read_text(encoding='utf-8'), re.S
    )
    if not body:
        return {}
    return {
        int(page): float(frac)
        for page, frac in re.findall(r'^\s*(\d+)\s*:\s*([0-9.]+)\s*,', body.group(1), re.M)
    }


class PageCrop:
    """Where a page's frame interior sits inside its full هوامش scan, as ratios.

    The same rect `PageImageCrop` uses in the reader, so the video shows the
    page the way the app does with عرض الهوامش off: text filling the frame
    instead of a postage stamp inside the ornamental border.
    """

    __slots__ = ('left', 'top', 'width', 'height', 'paper', 'trim')

    def __init__(self, left, top, width, height, paper, trim):
        self.left, self.top, self.width, self.height = left, top, width, height
        self.paper = paper
        self.trim = trim  # left, top, right, bottom — the frame line to cover


def load_page_crops() -> list[PageCrop]:
    """Parse the generated kPageCrops table; empty list if it is not there."""
    if not CROPS_DART.exists():
        return []
    text = CROPS_DART.read_text(encoding='utf-8')
    rows = re.findall(
        r'PageCrop\(([^)]*Color\(0x([0-9A-Fa-f]{8})\)[^)]*)\)\s*,\s*//\s*(\d+)', text
    )
    crops: list[PageCrop] = []
    for args, argb, page in rows:
        nums = [float(n) for n in re.findall(r'-?\d+\.\d+', args)]
        paper = (int(argb[2:4], 16), int(argb[4:6], 16), int(argb[6:8], 16))
        trim = (nums[4:8] + [0.0, 0.0, 0.0, 0.0])[:4]
        crops.append(PageCrop(nums[0], nums[1], nums[2], nums[3], paper, trim))
    if len(crops) != PAGE_COUNT:
        sys.exit(f'page_crops.dart gave {len(crops)} rows, expected {PAGE_COUNT}')
    return crops


def load_reciter(reciter_id: str) -> dict:
    data = json.loads(RECITERS_JSON.read_text(encoding='utf-8'))
    for r in data['reciters']:
        if r['id'] == reciter_id:
            return r
    ids = ', '.join(r['id'] for r in data['reciters'])
    sys.exit(f'unknown reciter {reciter_id!r}. Known ids: {ids}')


# --------------------------------------------------------------------------- #
# ffmpeg helpers
# --------------------------------------------------------------------------- #

def require_tools() -> None:
    for tool in ('ffmpeg', 'ffprobe'):
        if shutil.which(tool) is None:
            sys.exit(f'{tool} not found on PATH')


def probe_duration(path: Path) -> float:
    out = subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
         '-of', 'default=nw=1:nk=1', str(path)],
        capture_output=True, text=True,
    )
    if out.returncode != 0 or not out.stdout.strip():
        sys.exit(f'ffprobe could not read {path}: {out.stderr.strip()}')
    return float(out.stdout.strip())


def probe_all(paths: list[Path], jobs: int) -> list[float]:
    for p in paths:
        if not p.exists():
            sys.exit(f'missing audio file: {p}')
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        return list(pool.map(probe_duration, paths))


def write_concat_list(dest: Path, entries: list[tuple[Path, float | None]]) -> None:
    """ffmpeg concat demuxer list. A trailing duration needs its file repeated."""
    lines = []
    for path, duration in entries:
        lines.append(f"file '{path.as_posix()}'")
        if duration is not None:
            lines.append(f'duration {duration:.6f}')
    if entries and entries[-1][1] is not None:
        lines.append(f"file '{entries[-1][0].as_posix()}'")
    dest.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def run(cmd: list[str]) -> None:
    print('+ ' + ' '.join(cmd), flush=True)
    if subprocess.run(cmd).returncode != 0:
        sys.exit('ffmpeg failed')


# --------------------------------------------------------------------------- #
# the recitation timeline
# --------------------------------------------------------------------------- #

class Timeline:
    """Absolute start/end seconds for every ayah in one continuous khatma track.

    `files` is what gets concatenated to produce that track, in order.
    """

    def __init__(self, files: list[Path], starts: dict, ends: dict, total: float):
        self.files = files
        self.starts = starts
        self.ends = ends
        self.total = total


def timeline_timed(reciter: dict, audio_dir: Path, jobs: int) -> Timeline:
    name = reciter.get('timingsFile') or f"timings_{reciter['id']}.json"
    bundled = WEB_DATA / name
    if bundled.exists():
        timings = json.loads(bundled.read_text(encoding='utf-8'))['timings']
    else:
        # Fall back to the per-surah files that ship next to the audio.
        timings = {}
        for s in range(1, 115):
            f = audio_dir / 'timings' / f'{s:03d}.json'
            if not f.exists():
                sys.exit(f'no timings for surah {s}: neither {bundled} nor {f}')
            timings[str(s)] = json.loads(f.read_text(encoding='utf-8'))['ayat']

    files = [audio_dir / f'{s:03d}.mp3' for s in range(1, 115)]
    print(f'measuring {len(files)} surah files…', flush=True)
    durations = probe_all(files, jobs)

    starts: dict[tuple[int, int], float] = {}
    ends: dict[tuple[int, int], float] = {}
    offset = 0.0
    for s, dur in zip(range(1, 115), durations):
        for ayah, span in timings.get(str(s), {}).items():
            if ayah == '0':
                continue  # basmala span, folded into ayah 1 by the data contract
            starts[(s, int(ayah))] = offset + span[0] / 1000.0
            ends[(s, int(ayah))] = offset + span[1] / 1000.0
        offset += dur

    return Timeline(files, starts, ends, offset)


def timeline_per_ayah(
    reciter: dict, audio_dir: Path, order: list[tuple[int, int]], jobs: int
) -> Timeline:
    overrides: dict[str, dict] = {}
    name = reciter.get('overridesFile')
    if name:
        blob = json.loads((WEB_DATA / name).read_text(encoding='utf-8'))
        overrides = blob.get('overrides', blob)

    # Lay the clips out in recitation order, collapsing a clip that two
    # consecutive ayat share onto one playback — a merged tail or a breath group
    # must be heard once, not once per ayah it covers.
    seq: list[str] = []
    span_of: dict[tuple[int, int], tuple[int, int]] = {}
    for key in order:
        entry = overrides.get(f'{key[0]}-{key[1]}')
        stems = entry['f'] if entry else [f'{key[0]:03d}{key[1]:03d}']
        if not stems:
            continue  # recited inside a neighbour's breath — no clip of its own
        first = last = None
        for stem in stems:
            if seq and seq[-1] == stem:
                idx = len(seq) - 1
            else:
                seq.append(stem)
                idx = len(seq) - 1
            first = idx if first is None else first
            last = idx
        span_of[key] = (first, last)

    files = [audio_dir / f'{stem}.mp3' for stem in seq]
    print(f'measuring {len(files)} ayah files (this is the slow part)…', flush=True)
    durations = probe_all(files, jobs)

    cumulative = [0.0]
    for d in durations:
        cumulative.append(cumulative[-1] + d)

    starts = {k: cumulative[a] for k, (a, _) in span_of.items()}
    ends = {k: cumulative[b + 1] for k, (_, b) in span_of.items()}
    return Timeline(files, starts, ends, cumulative[-1])


def page_turn_times(
    pages: dict[int, list[tuple[int, int]]], tl: Timeline, heads: dict[int, float]
) -> list[float]:
    """1-indexed turn time per page; index 0 is unused.

    Page 1 starts at 0 so the الاستعاذة before al-Fatiha plays on the first spread.
    """
    turns = [0.0] * (PAGE_COUNT + 1)
    for page in range(2, PAGE_COUNT + 1):
        when = None
        for key in pages[page]:
            if key in tl.starts:
                when = tl.starts[key]
                frac = heads.get(page)
                if frac:
                    # The ayah opening this page is partly printed on the page
                    # before; hold the turn until the reciter has passed it.
                    when += frac * (tl.ends[key] - when)
                break
        # No ayah on the page has audio of its own (a whole page inside one
        # breath does not happen, but do not crash if the data says so).
        turns[page] = max(turns[page - 1], when if when is not None else turns[page - 1])
    return turns


# --------------------------------------------------------------------------- #
# spread images
# --------------------------------------------------------------------------- #

def load_page(page: int, images: Path, crop: PageCrop | None):
    """The page as it should appear on screen — cropped to its frame if asked."""
    from PIL import Image

    src = images / f'page_{page}.webp'
    if not src.exists():
        sys.exit(f'missing page image: {src}')
    with Image.open(src) as raw:
        im = raw.convert('RGB')
    if crop is None:
        return im

    full_w, full_h = im.size
    box_w = max(1, round(crop.width * full_w))
    box_h = max(1, round(crop.height * full_h))
    x0, y0 = round(crop.left * full_w), round(crop.top * full_h)

    # A couple of rects run a sliver past the scan's edge; fill with the page's
    # own paper colour so no seam shows, exactly as the reader does.
    out = Image.new('RGB', (box_w, box_h), crop.paper)
    sx0, sy0 = max(0, x0), max(0, y0)
    sx1, sy1 = min(full_w, x0 + box_w), min(full_h, y0 + box_h)
    if sx1 > sx0 and sy1 > sy0:
        out.paste(im.crop((sx0, sy0, sx1, sy1)), (sx0 - x0, sy0 - y0))

    # Cover the frame's own line where it falls inside the crop.
    from PIL import ImageDraw

    d = ImageDraw.Draw(out)
    tl, tt, tr, tb = crop.trim
    if tl > 0:
        d.rectangle([0, 0, round(tl * box_w), box_h], fill=crop.paper)
    if tr > 0:
        d.rectangle([box_w - round(tr * box_w), 0, box_w, box_h], fill=crop.paper)
    if tt > 0:
        d.rectangle([0, 0, box_w, round(tt * box_h)], fill=crop.paper)
    if tb > 0:
        d.rectangle([0, box_h - round(tb * box_h), box_w, box_h], fill=crop.paper)
    return out


def render_spread(
    right_page: int,
    left_page: int,
    dest: Path,
    images: Path,
    crops: list[PageCrop],
    opts: argparse.Namespace,
) -> Path:
    """One frame: the odd page on the RIGHT, as the mushaf opens.

    Both pages are drawn at the same height and butted up against the gutter so
    they meet at the spine; the slack ends up in the outer margins, which is
    what makes it read as one open mushaf rather than two floating scans.
    """
    from PIL import Image

    if dest.exists() and not opts.rerender:
        return dest

    pages = []
    for page in (left_page, right_page):
        if page is None or page > PAGE_COUNT:
            pages.append(None)
            continue
        pages.append(load_page(page, images, crops[page - 1] if crops else None))

    avail_w = opts.width - 2 * opts.margin
    avail_h = opts.height - 2 * opts.margin
    gutter = opts.gutter if all(p is not None for p in pages) else 0

    height = avail_h
    widths = [round(height * (p.width / p.height)) if p else 0 for p in pages]
    if sum(widths) + gutter > avail_w:
        shrink = (avail_w - gutter) / sum(widths)
        height = max(1, round(height * shrink))
        widths = [round(height * (p.width / p.height)) if p else 0 for p in pages]

    canvas = Image.new('RGB', (opts.width, opts.height), opts.bg)
    total_w = sum(widths) + gutter
    x = (opts.width - total_w) // 2
    y = (opts.height - height) // 2
    for page_im, w in zip(pages, widths):
        if page_im is not None:
            canvas.paste(page_im.resize((w, height), Image.LANCZOS), (x, y))
            x += w + gutter

    dest.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dest, quality=opts.quality, subsampling=0, optimize=True)
    return dest


# --------------------------------------------------------------------------- #

def parse_range(text: str, hi: int) -> tuple[int, int]:
    m = re.fullmatch(r'(\d+)(?:-(\d+))?', text.strip())
    if not m:
        sys.exit(f'bad range {text!r}, expected N or N-M')
    a = int(m.group(1))
    b = int(m.group(2) or m.group(1))
    if not (1 <= a <= b <= hi):
        sys.exit(f'range {text!r} outside 1-{hi}')
    return a, b


def main() -> None:
    spreads_total = PAGE_COUNT // 2

    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--reciter', required=True, help='reciter id, e.g. alqryw')
    ap.add_argument('--audio-dir', type=Path,
                    help='local mirror of this reciter folder from audio.mushaf-qaloon.com')
    ap.add_argument('--audio-root', type=Path,
                    help='parent of the mirrored reciter folders; the folder name comes '
                         'from reciters.json, so this works for every reciter unchanged')
    ap.add_argument('--out', type=Path, help='default khatma_<reciter>.mp4')
    ap.add_argument('--work', type=Path, help='scratch dir, default build/khatma_<reciter>')
    ap.add_argument('--images', type=Path, default=ROOT / 'assets' / 'images',
                    help='page image dir (try image_sets/high_fidelity for the other set)')
    ap.add_argument('--margins', choices=('crop', 'full'), default='crop',
                    help="'crop' shows the frame interior like the reader does with "
                         "عرض الهوامش off; 'full' shows the whole هوامش scan")
    ap.add_argument('--spreads', default=f'1-{spreads_total}',
                    help=f'spread range to render, 1-{spreads_total} (spread k = pages 2k-1, 2k)')
    ap.add_argument('--width', type=int, default=2560)
    ap.add_argument('--height', type=int, default=1440)
    ap.add_argument('--margin', type=int, default=48)
    ap.add_argument('--gutter', type=int, default=24, help='gap between the two pages')
    ap.add_argument('--bg', default='#fffee0', help='paper colour behind the pages')
    ap.add_argument('--quality', type=int, default=90, help='spread JPEG quality')
    ap.add_argument('--fps', type=int, default=2,
                    help='output frame rate; the frames are static, so low is cheap. '
                         'Also the page-turn granularity — 2 fps lands a turn within 0.5s')
    ap.add_argument('--gop-seconds', type=int, default=120,
                    help='forced keyframe interval. Every page turn is a scene cut and '
                         'gets its own keyframe regardless; this only sets how finely you '
                         'can scrub within a spread, and keyframes are most of the file')
    ap.add_argument('--crf', type=int, default=23)
    ap.add_argument('--preset', default='veryfast')
    ap.add_argument('--audio-bitrate', default='128k')
    ap.add_argument('--jobs', type=int, default=min(16, (os.cpu_count() or 4) * 2))
    ap.add_argument('--rerender', action='store_true', help='rebuild cached spreads and audio')
    ap.add_argument('--timeline-only', action='store_true',
                    help='print the page-turn table and stop; no encoding')
    opts = ap.parse_args()

    require_tools()
    first_spread, last_spread = parse_range(opts.spreads, spreads_total)
    out = opts.out or ROOT / f'khatma_{opts.reciter}.mp4'
    work = opts.work or ROOT / 'build' / f'khatma_{opts.reciter}'
    work.mkdir(parents=True, exist_ok=True)

    crops = load_page_crops() if opts.margins == 'crop' else []
    if opts.margins == 'crop' and not crops:
        sys.exit('--margins crop needs lib/data/page_crops.dart; pass --margins full')
    reciter = load_reciter(opts.reciter)
    audio_dir = opts.audio_dir or (
        opts.audio_root / reciter['folder'] if opts.audio_root else None)
    if audio_dir is None:
        sys.exit('pass --audio-dir (this reciter folder) or --audio-root (their parent)')
    if not audio_dir.is_dir():
        sys.exit(f'no such audio dir: {audio_dir}')
    pages = load_pages()
    heads = load_spanned_heads()
    order = [key for page in range(1, PAGE_COUNT + 1) for key in pages[page]]

    if reciter['scheme'] == 'timed':
        tl = timeline_timed(reciter, audio_dir, opts.jobs)
    else:
        tl = timeline_per_ayah(reciter, audio_dir, order, opts.jobs)

    turns = page_turn_times(pages, tl, heads)
    print(f"{reciter['name']} — {tl.total / 3600:.2f} h of تلاوة, "
          f'{len(tl.files)} source files, {len(tl.starts)} timed ayat')

    # Spread k shows pages 2k-1 and 2k; it stays up until the turn onto 2k+1.
    plan = []
    for k in range(first_spread, last_spread + 1):
        right, left = 2 * k - 1, 2 * k
        start = turns[right]
        end = turns[2 * k + 1] if 2 * k + 1 <= PAGE_COUNT else tl.total
        plan.append((k, right, left, start, max(end, start)))

    window_start, window_end = plan[0][3], plan[-1][4]
    if opts.timeline_only:
        for k, right, left, start, end in plan:
            print(f'spread {k:3d}  pages {right:3d}+{left:3d}  '
                  f'{start:9.2f}s -> {end:9.2f}s  ({end - start:6.2f}s)')
        print(f'window {window_start:.2f}s -> {window_end:.2f}s '
              f'({(window_end - window_start) / 3600:.2f} h)')
        return

    # --- audio: one continuous track for the chosen window ------------------ #
    audio_list = work / 'audio_concat.txt'
    write_concat_list(audio_list, [(p, None) for p in tl.files])
    audio = work / f'audio_{first_spread}_{last_spread}.m4a'
    if opts.rerender or not audio.exists():
        cmd = ['ffmpeg', '-hide_banner', '-y', '-f', 'concat', '-safe', '0', '-i', str(audio_list)]
        if window_start > 0:
            cmd += ['-ss', f'{window_start:.3f}']
        if window_end < tl.total:
            cmd += ['-to', f'{window_end:.3f}']
        run(cmd + ['-vn', '-c:a', 'aac', '-b:a', opts.audio_bitrate, str(audio)])
    else:
        print(f'reusing {audio}')

    # --- spreads ------------------------------------------------------------ #
    spread_dir = work / f'spreads_{opts.width}x{opts.height}_{opts.margins}'
    print(f'rendering {len(plan)} spreads into {spread_dir}…', flush=True)
    with ThreadPoolExecutor(max_workers=opts.jobs) as pool:
        futures = [
            pool.submit(render_spread, right, left, spread_dir / f'spread_{k:03d}.jpg',
                        opts.images, crops, opts)
            for k, right, left, _, _ in plan
        ]
        for f in futures:
            f.result()

    video_list = work / f'spreads_{first_spread}_{last_spread}.txt'
    write_concat_list(video_list, [
        (spread_dir / f'spread_{k:03d}.jpg', end - start)
        for k, _, _, start, end in plan
    ])

    # --- mux ---------------------------------------------------------------- #
    run(['ffmpeg', '-hide_banner', '-y',
         '-f', 'concat', '-safe', '0', '-i', str(video_list),
         '-i', str(audio),
         '-map', '0:v:0', '-map', '1:a:0',
         '-c:v', 'libx264', '-preset', opts.preset, '-crf', str(opts.crf),
         '-pix_fmt', 'yuv420p', '-r', str(opts.fps),
         '-g', str(max(1, opts.fps * opts.gop_seconds)),
         '-c:a', 'copy', '-movflags', '+faststart', '-shortest', str(out)])

    print(f'\n{out}  ({(window_end - window_start) / 3600:.2f} h, '
          f'spreads {first_spread}-{last_spread})')


if __name__ == '__main__':
    main()

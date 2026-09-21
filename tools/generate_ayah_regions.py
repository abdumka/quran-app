"""Generate ayah-level regions (+ marker boxes) for every page of the app's
720x1640 page images, in the app's 0..1 ratio convention.

Usage: python ayah_geometry.py <repo_root> <outdir> [pages...]
Writes <outdir>/ayah_regions.json, <outdir>/report.json, overlays for sample pages.
"""
import json, os, sys
import cv2, numpy as np

root, outdir = sys.argv[1], sys.argv[2]
only = [int(p) for p in sys.argv[3:]]
os.makedirs(outdir, exist_ok=True)
OVERLAY_PAGES = set(only) if only else {3, 49, 150, 300, 450, 500, 560, 600, 602}

raw = json.load(open(os.path.join(root, 'assets/data/output.json'), encoding='utf-8'))
flat = []
for e in raw:
    flat.extend(e if isinstance(e, list) else [e])
by_page = {p['page']: p['ayahs'] for p in flat}

def ayah_ends(page):
    ay = by_page[page]
    nxt = by_page.get(page + 1)
    ends = [(a['surah'], a['ayah']) for a in ay]
    if nxt and (nxt[0]['surah'], nxt[0]['ayah']) == ends[-1]:
        ends = ends[:-1]
    return ends

MARGIN = 0.015

def yellow(bgr):
    b, g, r = [bgr[:, :, i].astype(np.float32) for i in range(3)]
    return np.clip(r - b, 0, 255).astype(np.uint8)

def _crop(page, cx, cy, size=46):
    bgr = cv2.imread(os.path.join(root, 'assets/images/page_%d.webp' % page))
    y = yellow(bgr)
    return y[cy - size // 2: cy + size // 2, cx - size // 2: cx + size // 2]

TEMPLATES = [_crop(49, 399, 400), _crop(49, 32, 1040), _crop(483, 425, 292), _crop(483, 37, 400)]
# the two illuminated opening pages use a smaller, paler marker; positions derived from page-1 word boxes
SMALL_TEMPLATES = [_crop(1, 290, 769, 32), _crop(1, 439, 938, 32)]
TM_THR, TM_NMS, TM_PAD = 0.5, 34, 24

def detect_markers(bgr, templates=None):
    templates = templates or TEMPLATES
    y = cv2.copyMakeBorder(yellow(bgr), TM_PAD, TM_PAD, TM_PAD, TM_PAD, cv2.BORDER_REPLICATE)
    H, W = bgr.shape[:2]
    best = None
    for t in templates:
        res = cv2.matchTemplate(y, t, cv2.TM_CCOEFF_NORMED)
        best = res if best is None else np.maximum(best, res)
    th, tw = templates[0].shape
    out = []
    r = best.copy()
    while True:
        _, mx, _, loc = cv2.minMaxLoc(r)
        if mx < TM_THR:
            break
        x, yy = loc
        cx, cy = x + tw / 2.0 - TM_PAD, yy + th / 2.0 - TM_PAD
        if -8 <= cx <= W + 8 and -8 <= cy <= H + 8:
            out.append(dict(x=int(cx - 19), y=int(cy - 19), w=38, h=38, cx=cx, cy=cy, score=float(mx)))
        cv2.rectangle(r, (x - TM_NMS, yy - TM_NMS), (x + TM_NMS, yy + TM_NMS), 0, -1)
    return out, float(mx)

# illuminated opening pages: analyse only the text panel inside the frame (x0, y0, x1, y1)
CROP = {1: (140, 640, 545, 1150), 2: (165, 640, 555, 1140)}

# the opening pages' small pale markers defeat the template; positions read off the overlays (px)
MANUAL_MARKERS = {
    1: [(290, 769), (160, 772), (370, 853), (441, 938), (160, 940), (215, 1022), (163, 1108)],
    2: [(172, 772), (345, 940), (165, 1022), (165, 1100)],
}

def analyse(page):
    full = cv2.imread(os.path.join(root, 'assets/images/page_%d.webp' % page), cv2.IMREAD_COLOR)
    if page in CROP:
        an = _analyse_image(full[CROP[page][1]:CROP[page][3], CROP[page][0]:CROP[page][2]].copy(), SMALL_TEMPLATES)
        ox, oy = CROP[page][0], CROP[page][1]
        for m in an['markers']:
            m['x'] += ox; m['y'] += oy; m['cx'] += ox; m['cy'] += oy
        if page in MANUAL_MARKERS:
            an['markers'] = [dict(x=cx - 14, y=cy - 14, w=28, h=28, cx=float(cx), cy=float(cy), score=1.0)
                             for cx, cy in MANUAL_MARKERS[page]]
        for b in an['bands']:
            b['top'] += oy; b['bot'] += oy; b['left'] += ox; b['right'] += ox
        an['w'], an['h'], an['bgr'] = full.shape[1], full.shape[0], full
        return an
    return _analyse_image(full)

def _analyse_image(bgr, templates=None):
    h, w = bgr.shape[:2]
    mx = int(w * MARGIN)
    b, g, r = [bgr[:, :, i].astype(int) for i in range(3)]
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    S = hsv[:, :, 1]
    gold = ((r - b > 45) & (r > g) & (g > b)).astype(np.uint8) * 255
    gold[:, :mx] = 0; gold[:, w - mx:] = 0
    # strip long gold rules (page-edge border lines glue markers together)
    gb = (gold > 0).astype(np.int32)
    run = np.zeros_like(gb); best = np.zeros(w, dtype=np.int32)
    for yy in range(h):
        run[yy] = (run[yy - 1] + 1) * gb[yy] if yy else gb[yy]
        best = np.maximum(best, run[yy])
    gold[:, best > 150] = 0
    rowfrac = (gold > 0).sum(axis=1) / float(w)
    gold[rowfrac > 0.5, :] = 0
    gold = cv2.morphologyEx(gold, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    ink = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 21, 10)
    ink = cv2.bitwise_and(ink, cv2.bitwise_not(cv2.dilate(gold, np.ones((5, 5), np.uint8))))
    ink = cv2.medianBlur(ink, 3)
    ink[:, :mx] = 0; ink[:, w - mx:] = 0
    ink[:6, :] = 0; ink[h - 6:, :] = 0

    # markers (template matching on the yellowness channel)
    markers, next_score = detect_markers(bgr, templates)

    # bands (line pitch on this crop is ~105-110 px)
    proj = (ink > 0).sum(axis=1).astype(float)
    sm = np.convolve(proj, np.ones(9) / 9, mode='same')
    norm = np.clip(sm / max(sm.max(), 1) * 255, 0, 255).astype(np.uint8)
    t, _ = cv2.threshold(norm, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    cut = min(max((t / 255.0) * sm.max(), 0.08 * sm.max()), 0.45 * sm.max())
    on = sm > cut
    bands, s = [], None
    for i, v in enumerate(on):
        if v and s is None: s = i
        elif not v and s is not None: bands.append([s, i]); s = None
    if s is not None: bands.append([s, len(on)])
    merged = [bands[0]] if bands else []
    for aa, bb in bands[1:]:
        if aa - merged[-1][1] < 24: merged[-1][1] = bb
        else: merged.append([aa, bb])
    cores = [(aa, bb) for aa, bb in merged if (bb - aa) >= 8]
    c = [(aa + bb) / 2 for aa, bb in cores]
    pitch = float(np.median(np.diff(c))) if len(c) > 1 else 109.0
    # A core is the dense baseline row of one line (~20 px). A surah's last
    # line often fuses with the header box under it into one tall core whose
    # centre lies inside the header; measured from that centre, the boundary
    # with the line above lands half a line too low and the last line is cut
    # out of its own band. Towards the line above, a tall core counts from
    # its first baseline (its top edge) instead.
    heights = [bb - aa for aa, bb in cores if bb - aa < 60]
    base_h = float(np.median(heights)) if heights else 22.0
    up = [aa + base_h / 2 if (bb - aa) > 0.9 * pitch else (aa + bb) / 2 for aa, bb in cores]
    lines = []
    for i, (aa, bb) in enumerate(cores):
        top = (c[i - 1] + up[i]) / 2 if i else up[i] - pitch / 2
        bot = (c[i] + up[i + 1]) / 2 if i < len(cores) - 1 else c[i] + pitch / 2
        lines.append((int(max(0, min(top, aa))), int(min(h, max(bot, bb))), aa, bb))

    # classify bands
    kinds = []
    for (top, bot, ca, cb) in lines:
        strip = ink[ca:cb, :]
        col = (strip > 0).sum(axis=0)
        cols = np.where(col > max(1, 0.03 * (cb - ca)))[0]
        left, right = (int(cols.min()), int(cols.max())) if len(cols) else (w // 2, w // 2)
        width = (right - left) / float(w)
        has_marker = any(top <= m['cy'] < bot and m['score'] >= 0.75 for m in markers)
        # header ornament: a single connected component spanning most of the width
        nn, ll, ss, _ = cv2.connectedComponentsWithStats(strip, 8)
        big = max((ss[i][2] for i in range(1, nn)), default=0) / float(w)
        if big > 0.55:
            kind = 'header'
        elif has_marker:
            kind = 'text'
        elif width < 0.86:
            kind = 'basmala'
        else:
            kind = 'text'
        kinds.append(dict(top=top, bot=bot, left=left, right=right, kind=kind, big=round(big, 2), width=round(width, 2)))

    # a surah's last line often fuses with the header box below it: split it back out
    split = []
    for b in kinds:
        strong = [m for m in markers if b['top'] <= m['cy'] < b['bot'] and m['score'] >= 0.8]
        if b['kind'] == 'header' and strong and (b['bot'] - b['top']) > 1.4 * pitch:
            cut = int(max(m['cy'] for m in strong) + pitch / 2)
            cut = min(cut, b['bot'] - 40)
            split.append(dict(b, kind='text', bot=cut))
            split.append(dict(b, top=cut))
        else:
            split.append(b)
    kinds = split
    return dict(w=w, h=h, markers=markers, bands=kinds, bgr=bgr, next_score=0.0, min_score=0.0)

def build_regions(page, an):
    w, h = an['w'], an['h']
    bands = an['bands']
    text_bands = [i for i, b in enumerate(bands) if b['kind'] == 'text']
    if not text_bands:
        return None, 'no text bands'
    tl = min(bands[i]['left'] for i in text_bands)
    tr = max(bands[i]['right'] for i in text_bands)
    # candidates inside text bands, best score first; keep exactly the expected count
    ends = ayah_ends(page)
    cands = []
    for m in an['markers']:
        bi = next((i for i, b in enumerate(bands) if b['top'] <= m['cy'] < b['bot']), None)
        if bi is None or bands[bi]['kind'] != 'text':
            continue
        cands.append((bi, m))
    cands.sort(key=lambda t: -t[1]['score'])
    if len(cands) < len(ends):
        return None, 'markers %d < expected %d' % (len(cands), len(ends))
    an['min_score'] = cands[len(ends) - 1][1]['score'] if ends else 1.0
    an['next_score'] = cands[len(ends)][1]['score'] if len(cands) > len(ends) else 0.0
    ms = sorted(cands[:len(ends)], key=lambda t: (t[0], -t[1]['cx']))
    ms = [(bi, -m['cx'], m) for bi, m in ms]
    regions = []
    prev = None  # (band idx, x_left of previous marker)
    for (bi, _, m), (surah, ayah) in zip(ms, ends):
        rects = []
        if prev is None:
            start_bi, start_x = text_bands[0], tr
        else:
            start_bi, start_x = prev
        if start_bi == bi:
            rects.append((m['x'] + m['w'], bands[bi]['top'], start_x, bands[bi]['bot']))
        else:
            rects.append((tl, bands[start_bi]['top'], start_x, bands[start_bi]['bot']))
            for k in text_bands:
                if start_bi < k < bi:
                    rects.append((tl, bands[k]['top'], tr, bands[k]['bot']))
            rects.append((m['x'] + m['w'], bands[bi]['top'], tr, bands[bi]['bot']))
        rects = [r for r in rects if r[2] > r[0]]
        regions.append(dict(
            surah=surah, ayah=ayah,
            rects=[dict(x=round(x0 / w, 5), y=round(y0 / h, 5), width=round((x1 - x0) / w, 5), height=round((y1 - y0) / h, 5)) for x0, y0, x1, y1 in rects],
            marker=dict(x=round(m['x'] / w, 5), y=round(m['y'] / h, 5), width=round(m['w'] / w, 5), height=round(m['h'] / h, 5)),
        ))
        prev = (bi, m['x'])
    # trailing ayah continuing to next page
    ay = by_page[page]
    if len(ay) > len(ends):
        surah, ayah = ay[-1]['surah'], ay[-1]['ayah']
        bi, x = prev if prev else (text_bands[0], tr)
        rects = [(tl, bands[bi]['top'], x, bands[bi]['bot'])] + [(tl, bands[k]['top'], tr, bands[k]['bot']) for k in text_bands if k > bi]
        rects = [r for r in rects if r[2] > r[0]]
        regions.append(dict(surah=surah, ayah=ayah, rects=[dict(x=round(x0 / w, 5), y=round(y0 / h, 5), width=round((x1 - x0) / w, 5), height=round((y1 - y0) / h, 5)) for x0, y0, x1, y1 in rects], marker=None))
    return regions, None

def overlay(page, an, regions, path):
    vis = an['bgr'].copy()
    for b in an['bands']:
        color = {'text': (255, 0, 0), 'header': (0, 0, 255), 'basmala': (0, 160, 0)}[b['kind']]
        cv2.rectangle(vis, (2, b['top']), (an['w'] - 3, b['bot']), color, 1)
    if regions:
        rng = np.random.RandomState(7)
        for reg in regions:
            col = tuple(int(v) for v in rng.randint(60, 220, 3))
            for r in reg['rects']:
                x0, y0 = int(r['x'] * an['w']), int(r['y'] * an['h'])
                x1, y1 = x0 + int(r['width'] * an['w']), y0 + int(r['height'] * an['h'])
                sub = vis[y0:y1, x0:x1]
                vis[y0:y1, x0:x1] = (0.65 * sub + 0.35 * np.array(col)).astype(np.uint8)
            if reg['marker']:
                m = reg['marker']
                cv2.rectangle(vis, (int(m['x'] * an['w']), int(m['y'] * an['h'])),
                              (int((m['x'] + m['width']) * an['w']), int((m['y'] + m['height']) * an['h'])), (0, 140, 255), 2)
    cv2.imwrite(path, vis)

pages = only or list(range(1, 603))
out, report = [], []
for page in pages:
    an = analyse(page)
    regions, err = build_regions(page, an)
    kinds = ''.join(b['kind'][0].upper() for b in an['bands'])
    report.append(dict(page=page, markers=len(an['markers']), expected=len(ayah_ends(page)), bands=kinds, error=err,
                       min_score=round(an['min_score'], 2), next_score=round(an['next_score'], 2)))
    if regions:
        out.append(dict(page=page, ayahs=regions))
        if an['min_score'] < 0.72 or an['next_score'] > 0.62:
            print('page %3d  WEAK margin: accepted min %.2f, next rejected %.2f' % (page, an['min_score'], an['next_score']))
    if page in OVERLAY_PAGES:
        overlay(page, an, regions, os.path.join(outdir, 'ayah_%03d.png' % page))
    if err:
        print('page %3d  %-22s  bands %s' % (page, err, kinds))

json.dump(out, open(os.path.join(outdir, 'ayah_regions.json'), 'w', encoding='utf-8'), ensure_ascii=False)
json.dump(report, open(os.path.join(outdir, 'report.json'), 'w'), indent=1)
ok = sum(1 for r in report if not r['error'])
print('pages OK: %d / %d' % (ok, len(report)))
from collections import Counter
print('band-count histogram:', dict(sorted(Counter(len(r['bands']) for r in report).items())))

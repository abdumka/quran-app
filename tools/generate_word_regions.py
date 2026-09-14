"""Generate assets/data/word_regions.json: a box for every word of every
page, derived from the page images and assets/data/ayah_regions.json.

Method (see tasmee_work/word_boxes.py for the exploratory version):
  * every ayah's line rects come from ayah_regions.json, in reading order;
  * inside a rect, candidate word boundaries are vertical ink gaps
    (columns with no dark pixels, >= 2 px wide) within the ink extent;
  * how many words each rect holds is decided by a width model (relative
    letter widths, scaled to the ayah's total ink width) and a DP over
    the rects; the boundaries are then the candidate gaps closest to the
    model's predicted cut positions (a DP keeps them ordered), with a
    small bonus for wider gaps;
  * the first and last word of a rect are stretched to the rect edges so
    the union of word boxes covers the rect exactly (no paper strips).

Output format (ratios of the 720x1640 page image, 5 decimals):
  [{"page": N, "ayahs": [{"surah": S, "ayah": A,
      "lines": [{"y": .., "h": .., "words": [[x, width], ...]}]}]}]
Words within a line are listed in reading order (right to left); lines
in reading order; concatenating all lines' words gives the ayah's words in
order, matching output.json.

usage: python tools/generate_word_regions.py [--pages 1,2,3] [--check]
"""
import argparse, json, os, re, sys
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIAC = re.compile(r"[ؐ-ًؚ-ٟۖ-ٰۭ]")

W = {
    'ا': 0.30, 'أ': 0.30, 'إ': 0.30, 'آ': 0.35, 'ٱ': 0.30, 'ل': 0.45, 'ر': 0.55, 'ز': 0.55,
    'و': 0.60, 'ؤ': 0.60, 'د': 0.65, 'ذ': 0.65, 'ب': 0.85, 'ت': 0.85, 'ث': 0.85, 'ن': 0.70,
    'ي': 0.95, 'ى': 0.95, 'ئ': 0.90, 'ے': 0.95, 'ف': 0.95, 'ق': 0.90, 'ك': 1.05, 'م': 0.70,
    'ه': 0.75, 'ة': 0.70, 'ج': 1.05, 'ح': 1.05, 'خ': 1.05, 'س': 1.60, 'ش': 1.60, 'ص': 1.70,
    'ض': 1.70, 'ط': 1.25, 'ظ': 1.25, 'ع': 1.00, 'غ': 1.00, 'ء': 0.25, '۞': 1.2,
}
SPACE = 0.9


def word_width(w):
    return sum(W.get(c, 0.8) for c in DIAC.sub('', w)) + 0.3


def ink_mask(img):
    return (cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) < 120).astype(np.uint8)


def gaps_in(mask, x0, x1, y0, y1, min_gap=2, band=(0.25, 0.75)):
    """Empty column runs inside the rect, measured on the middle `band` of
    the line height (the baseline strip) so descenders and ascenders of the
    neighbouring lines, which the full-height rect includes, do not bridge
    real word gaps. The ink extent is measured on the full height."""
    h = y1 - y0
    by0, by1 = y0 + int(h * band[0]), y0 + int(h * band[1])
    col = mask[by0:by1, x0:x1].sum(axis=0)
    empty = col == 0
    runs = []
    i, n = 0, len(empty)
    while i < n:
        if empty[i]:
            j = i
            while j < n and empty[j]:
                j += 1
            if j - i >= min_gap:
                runs.append((x0 + i, x0 + j))
            i = j
        else:
            i += 1
    inked = np.where(mask[y0:y1, x0:x1].sum(axis=0) > 0)[0]
    if len(inked) == 0:
        return runs, None
    return runs, (x0 + int(inked[0]), x0 + int(inked[-1]) + 1)


def assign_counts(widths, rect_widths):
    n, k = len(widths), len(rect_widths)
    if k == 0 or n == 0:
        return [0] * k, k != 0
    total_w = sum(widths) + SPACE * (n - 1)
    scale = sum(rect_widths) / max(total_w, 1e-6)
    pref = np.cumsum([0] + list(widths))
    INF = 1e18
    dp = [[INF] * (n + 1) for _ in range(k + 1)]
    back = [[-1] * (n + 1) for _ in range(k + 1)]
    dp[0][0] = 0
    for r in range(1, k + 1):
        for j in range(0, n + 1):
            for i in range(0, j):
                if dp[r - 1][i] >= INF:
                    continue
                cnt = j - i
                est = (pref[j] - pref[i] + SPACE * (cnt - 1)) * scale
                cost = dp[r - 1][i] + (est - rect_widths[r - 1]) ** 2
                if cost < dp[r][j]:
                    dp[r][j] = cost
                    back[r][j] = i
    if dp[k][n] >= INF:
        # fewer words than rects: put everything in the first rects
        counts = [1] * k
        counts[0] += n - k
        return counts, True
    counts = []
    j = n
    for r in range(k, 0, -1):
        i = back[r][j]
        counts.append(j - i)
        j = i
    return counts[::-1], False


def split_rect(mask, rect_px, words):
    """Word spans (x0, x1) in px, reading order (rightmost first), covering
    the rect from edge to edge."""
    x0, x1, y0, y1 = rect_px
    n = len(words)
    runs, extent = gaps_in(mask, x0, x1, y0, y1)
    fell_back = False
    if extent is None or n == 1:
        cuts = []
        if n > 1:
            step = (x1 - x0) / n
            cuts = [x1 - (i + 1) * step for i in range(n - 1)]
            fell_back = True
    else:
        ex0, ex1 = extent
        widths = [word_width(w) for w in words]
        total = sum(widths) + SPACE * (n - 1)
        scale = (ex1 - ex0) / total
        preds = []
        acc = 0.0
        for i in range(n - 1):
            acc += widths[i] + SPACE / 2
            preds.append(ex1 - acc * scale)
            acc += SPACE / 2
        cands = [((a + b) / 2, b - a) for a, b in runs if a > ex0 and b < ex1]
        if len(cands) < n - 1:
            cuts = preds
            fell_back = True
        else:
            cands.sort(key=lambda c: -c[0])
            m = len(cands)
            INF = 1e18
            dp = [[INF] * m for _ in range(n - 1)]
            bk = [[-1] * m for _ in range(n - 1)]

            def score(k, g):
                pos, gw = cands[g]
                return abs(pos - preds[k]) - min(gw, 12) * 0.8

            for g in range(m):
                dp[0][g] = score(0, g)
            for k in range(1, n - 1):
                for g in range(k, m):
                    best, bg = INF, -1
                    for h in range(k - 1, g):
                        if dp[k - 1][h] < best:
                            best, bg = dp[k - 1][h], h
                    if bg >= 0:
                        dp[k][g] = best + score(k, g)
                        bk[k][g] = bg
            g = int(np.argmin(dp[n - 2]))
            chosen = []
            for k in range(n - 2, -1, -1):
                chosen.append(cands[g][0])
                g = bk[k][g]
            cuts = chosen[::-1]
    edges = [x1] + [int(round(c)) for c in cuts] + [x0]
    return [(edges[i + 1], edges[i]) for i in range(n)], fell_back


def process_page(page, regions, text):
    img = cv2.imread(os.path.join(ROOT, 'assets/images/page_%d.webp' % page), cv2.IMREAD_COLOR)
    H, Wd = img.shape[:2]
    mask = ink_mask(img)
    ayahs_out = []
    fallbacks = 0
    for ra, ta in zip(regions['ayahs'], text['ayahs']):
        assert ra['surah'] == ta['surah'] and ra['ayah'] == ta['ayah'], (page, ra, ta)
        words = [w for w in ta['text'].split() if w]
        rects = [(int(r['x'] * Wd), int((r['x'] + r['width']) * Wd), int(r['y'] * H), int((r['y'] + r['height']) * H)) for r in ra['rects']]
        rect_widths = []
        for (x0, x1, y0, y1) in rects:
            _, ext = gaps_in(mask, x0, x1, y0, y1)
            rect_widths.append((ext[1] - ext[0]) if ext else (x1 - x0))
        if not rects or not words:
            # An ayah with no rect on this page (e.g. only its marker is
            # here) or no words: nothing to place; the app falls back to
            # ayah-level masking for it.
            ayahs_out.append({'surah': ra['surah'], 'ayah': ra['ayah'], 'lines': []})
            print('page', page, 'ayah', ra['ayah'], 'unplaced:', len(words), 'words', len(rects), 'rects', file=sys.stderr)
            continue
        if len(rects) == 1:
            counts, fb = [len(words)], False
        else:
            counts, fb = assign_counts([word_width(w) for w in words], rect_widths)
        fallbacks += fb
        lines = []
        wi = 0
        for rect, cnt in zip(rects, counts):
            seg = words[wi:wi + cnt]
            wi += cnt
            if not seg:
                continue
            spans, fb2 = split_rect(mask, rect, seg)
            fallbacks += fb2
            lines.append({
                'y': round(rect[2] / H, 5),
                'h': round((rect[3] - rect[2]) / H, 5),
                'words': [[round(a / Wd, 5), round((b - a) / Wd, 5)] for a, b in spans],
            })
        assert sum(len(l['words']) for l in lines) == len(words), (page, ra['ayah'])
        ayahs_out.append({'surah': ra['surah'], 'ayah': ra['ayah'], 'lines': lines})
    return {'page': page, 'ayahs': ayahs_out}, fallbacks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pages', default=None)
    ap.add_argument('--out', default=os.path.join(ROOT, 'assets/data/word_regions.json'))
    args = ap.parse_args()
    regions = {p['page']: p for p in json.load(open(os.path.join(ROOT, 'assets/data/ayah_regions.json'), encoding='utf-8'))}
    raw = json.load(open(os.path.join(ROOT, 'assets/data/output.json'), encoding='utf-8'))
    flat = []
    for e in raw:  # the last element nests the remaining pages in a list
        flat.extend(e if isinstance(e, list) else [e])
    texts = {p['page']: p for p in flat if isinstance(p, dict) and 'page' in p}
    pages = [int(x) for x in args.pages.split(',')] if args.pages else sorted(regions)
    out = []
    total_fb = 0
    for p in pages:
        res, fb = process_page(p, regions[p], texts[p])
        total_fb += fb
        out.append(res)
        if fb:
            print('page', p, 'fallbacks', fb, file=sys.stderr)
    json.dump(out, open(args.out, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    words = sum(len(l['words']) for pg in out for a in pg['ayahs'] for l in a['lines'])
    print('pages', len(out), 'words', words, 'fallbacks', total_fb, '->', args.out)


if __name__ == '__main__':
    main()

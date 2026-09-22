"""Areas of a page image that are never ayah text: the surah banners and the
basmala line under them. Both are printed identically on every page, so they
are found by template matching (templates cut from page 267), which does not
depend on any line geometry. Checked against output.json: every page has
exactly as many banners as surah starts and as many basmalas as surahs that
open with one (112 and 111).

zones(page) -> [(kind, x, y, w, h)] in 720x1640 px, top to bottom.
"""
import os

import cv2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 720, 1640
_T = {}


def _templates():
    if not _T:
        g = cv2.imread(os.path.join(ROOT, "assets/images/page_267.webp"), cv2.IMREAD_GRAYSCALE)
        _T["rosette"] = g[655:860, 590:715].copy()   # right corner ornament of a banner
        _T["basmala"] = g[885:962, 95:630].copy()
    return _T


def _matches(g, t, thr, sep):
    res = cv2.matchTemplate(g, t, cv2.TM_CCOEFF_NORMED)
    out = []
    while True:
        _, mx, _, loc = cv2.minMaxLoc(res)
        if mx < thr:
            break
        out.append((loc[0], loc[1]))
        cv2.rectangle(res, (0, max(0, loc[1] - sep)), (res.shape[1], loc[1] + sep), 0, -1)
    return out


def zones(page, gray=None):
    if page <= 2:          # the two illuminated opening pages have their own layout
        return []
    g = gray if gray is not None else cv2.imread(
        os.path.join(ROOT, f"assets/images/page_{page}.webp"), cv2.IMREAD_GRAYSCALE)
    if g.shape != (H, W):
        g = cv2.resize(g, (W, H))
    t = _templates()
    out = []
    # a banner runs the full width between its two border rules: 11 px above
    # the ornament's top to 11 px under its bottom (a banner at the very top
    # of a page scores ~0.4, a page without one ~0.1)
    for _x, y in _matches(g, t["rosette"], 0.3, 120):
        y0 = max(0, y - 11)
        out.append(("banner", 0, y0, W, y + t["rosette"].shape[0] + 11 - y0))
    for x, y in _matches(g, t["basmala"], 0.55, 50):
        out.append(("basmala", max(0, x - 6), max(0, y - 6), t["basmala"].shape[1] + 12, t["basmala"].shape[0] + 12))
    return sorted(out, key=lambda z: z[2])

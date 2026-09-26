"""Add to assets/data/word_masks.json, per page, the paper colour the Tasmee masks should be painted
with: "paper" [r,g,b] from the bundled page image and "hwPaper" [r,g,b] from the margin-view (هوامش) image
(D:/quran app/tasmee_work/hawamesh/page_N.webp, placed by the page's "hw" rect). One fixed colour used to
serve every page; the scans differ (blue channel 187-227), and on the margin images the difference shows as
pale streaks. Median of the bright pixels inside the ayah rects, which is the paper between the words.

usage: python tools/sample_paper.py [--write]
"""
import json
import os
import sys

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASKS = os.path.join(ROOT, "assets", "data", "word_masks.json")
REGIONS = os.path.join(ROOT, "assets", "data", "ayah_regions.json")
HAWAMESH = r"D:\quran app\tasmee_work\hawamesh"


def paper_of(img, rects):
    """rects in image pixels; median colour of the bright (paper) pixels inside them."""
    px = []
    for x0, y0, x1, y1 in rects:
        sub = img[max(0, y0):y1, max(0, x0):x1].reshape(-1, 3)
        if sub.size:
            px.append(sub)
    if not px:
        return None
    a = np.concatenate(px)
    g = a.mean(axis=1)
    bright = a[g > 200]
    if len(bright) < 100:
        return None
    m = np.median(bright, axis=0)  # BGR
    return [int(m[2]), int(m[1]), int(m[0])]


def main():
    raw = open(MASKS, "rb").read()
    masks = json.loads(raw.decode("utf-8"))
    regions = {p["page"]: p for p in json.load(open(REGIONS, encoding="utf-8"))}
    done = 0
    for m in masks:
        page = m["page"]
        rects = [(int(r["x"] * 720), int(r["y"] * 1640), int((r["x"] + r["width"]) * 720), int((r["y"] + r["height"]) * 1640))
                 for a in regions[page]["ayahs"] for r in a["rects"]]
        img = cv2.imread(os.path.join(ROOT, "assets", "images", f"page_{page}.webp"))
        if img is not None:
            if img.shape[:2] != (1640, 720):
                img = cv2.resize(img, (720, 1640))
            c = paper_of(img, rects)
            if c:
                m["paper"] = c
        hw = m.get("hw")
        hpath = os.path.join(HAWAMESH, f"page_{page}.webp")
        if hw and os.path.exists(hpath):
            himg = cv2.imread(hpath)
            H, W = himg.shape[:2]
            hx, hy, hwid, hh = hw
            hrects = [(int((hx + x0 / 720 * hwid) * W), int((hy + y0 / 1640 * hh) * H),
                       int((hx + x1 / 720 * hwid) * W), int((hy + y1 / 1640 * hh) * H)) for x0, y0, x1, y1 in rects]
            c = paper_of(himg, hrects)
            if c:
                m["hwPaper"] = c
        done += 1
    have = sum(1 for m in masks if "paper" in m), sum(1 for m in masks if "hwPaper" in m)
    print(f"pages {done}: paper on {have[0]}, hwPaper on {have[1]}")
    for p in (1, 2, 3, 50, 600):
        m = next(x for x in masks if x["page"] == p)
        print(p, "paper", m.get("paper"), "hwPaper", m.get("hwPaper"))
    if "--write" in sys.argv:
        open(MASKS, "wb").write(json.dumps(masks, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + (b"\n" if raw.endswith(b"\n") else b""))
        print("written")


if __name__ == "__main__":
    main()

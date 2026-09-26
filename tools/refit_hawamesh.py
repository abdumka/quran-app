"""Re-fit where a page image sits inside its margin-view (هوامش) image by matching the TEXT BLOCK
(the union of the page's ayah rects) at a grid of scales, instead of the whole page: the illuminated
opening pages and a few others fitted badly (corr 0.76-0.85) and their Tasmee masks drifted sideways.
usage: python refit_hawamesh.py <page> [page...]   -> writes refit_hw.json {page: {corr, oldCorr, hw}}"""
import json, sys
import cv2, numpy as np

REPO = r"D:\quran app\quran-app-main"
R = {p["page"]: p for p in json.load(open(REPO + r"\assets\data\ayah_regions.json", encoding="utf-8"))}
T = json.load(open(r"D:\quran app\tasmee_work\hawamesh_transform.json", encoding="utf-8"))
ink = lambda g: (255 - g).astype(np.float32)
results = {}
for page in [int(a) for a in sys.argv[1:]]:
    pg = cv2.imread(REPO + rf"\assets\images\page_{page}.webp", cv2.IMREAD_GRAYSCALE)
    hw_img = cv2.imread(rf"D:\quran app\tasmee_work\hawamesh\page_{page}.webp", cv2.IMREAD_GRAYSCALE)
    H, W = hw_img.shape
    rects = [r for a in R[page]["ayahs"] for r in a["rects"]]
    x0 = int(min(r["x"] for r in rects) * 720) - 10; x1 = int(max(r["x"] + r["width"] for r in rects) * 720) + 10
    y0 = int(min(r["y"] for r in rects) * 1640) - 10; y1 = int(max(r["y"] + r["height"] for r in rects) * 1640) + 10
    block = ink(pg[y0:y1, x0:x1]); target = ink(hw_img)
    best = None
    for sx in np.arange(1.45, 1.75, 0.01):
        for sy in np.arange(1.03, 1.12, 0.005):
            t = cv2.resize(block, None, fx=sx, fy=sy, interpolation=cv2.INTER_AREA)
            if t.shape[0] >= H or t.shape[1] >= W: continue
            _, mx, _, loc = cv2.minMaxLoc(cv2.matchTemplate(target, t, cv2.TM_CCOEFF_NORMED))
            if best is None or mx > best[0]: best = (mx, sx, sy, loc)
    mx, sx, sy, (X, Y) = best
    hw = [round(float((X - x0 * sx) / W), 5), round(float((Y - y0 * sy) / H), 5), round(float(720 * sx / W), 5), round(float(1640 * sy / H), 5)]
    old = T[str(page)]
    print(f"page {page}: corr {old['corr']:.4f} -> {mx:.4f}  hw {hw}")
    results[page] = dict(corr=float(mx), oldCorr=old["corr"], hw=hw)
json.dump(results, open(r"D:\quran app\tasmee_work\refit_hw.json", "w"), indent=1)

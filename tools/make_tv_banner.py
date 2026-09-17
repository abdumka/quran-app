"""
Regenerates the Android TV launcher banner.

The TV launcher shows ONLY this image -- it never draws @string/app_name beside
it -- so the app's name must be part of the artwork. Google requires exactly
320x180 (xhdpi).

    python tools/make_tv_banner.py <source image>
    python tools/make_tv_banner.py store_assets/my_new_graphic.png

The source is centre-cropped to 16:9 and scaled down, so give it something whose
text already sits near the middle.

NOTE: the banner shipped on 2026-09-16 was built from
store_assets/feature_graphic_gold_text_only_1024x500.png, which still carries the
OLD app name (مصحف الجماهيرية). The app itself is المصحف الجامع. Point this at a
corrected graphic before any store submission.
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(
    ROOT, "android", "app", "src", "main", "res", "drawable-xhdpi", "tv_banner.png"
)

if len(sys.argv) < 2:
    raise SystemExit(__doc__)

src = sys.argv[1]
if not os.path.isabs(src):
    src = os.path.join(ROOT, src)

im = Image.open(src).convert("RGB")
tw, th = 320, 180
sw, sh = im.size
target = tw / th
if sw / sh > target:          # too wide -> crop the sides
    nw, nh = int(round(sh * target)), sh
else:                          # too tall -> crop top and bottom
    nw, nh = sw, int(round(sw / target))
left, top = (sw - nw) // 2, (sh - nh) // 2
im = im.crop((left, top, left + nw, top + nh)).resize((tw, th), Image.LANCZOS)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
im.save(OUT, "PNG", optimize=True)
print(f"{src} {sw}x{sh} -> {OUT} {tw}x{th} ({os.path.getsize(OUT)} bytes)")

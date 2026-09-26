"""
Builds the 1280x720 "TV banner" that the Play Console store listing requires
for the Android TV form factor.

This is NOT the same asset as the in-app launcher banner: that one is exactly
320x180 and lives in res/drawable-xhdpi/tv_banner.png (see make_tv_banner.py).
Play wants its own, much larger copy for the TV storefront.

    python tools/make_tv_store_banner.py [source image] [-o out.png]

Defaults to store_assets/feature_graphic_gold_text_only_large_1024x500.png,
which is the only feature graphic carrying the current name (المصحف الجامع) --
the others still say مصحف الجماهيرية.

The source is 1024x500, i.e. 2.05:1, and the banner is 16:9. Cropping to fit
would cut 13% off the sides and take the decorative frame with it, so the
artwork is scaled to fit and matted instead. The matte is the source itself,
stretched to the full canvas and blurred to a smooth gold field, so the added
strips carry exactly the artwork's own colours and gradient rather than a flat
colour that would band against it.
"""
import argparse
import os

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SRC = os.path.join(
    ROOT, "store_assets", "feature_graphic_gold_text_only_large_1024x500.png"
)
DEFAULT_OUT = os.path.join(ROOT, "store_assets", "tv_banner_1280x720.png")

CANVAS = (1280, 720)
# Horizontal margin. The vertical one falls out of the aspect difference and is
# necessarily larger; that reads as a deliberate matte.
MARGIN_X = 40


def build(src_path: str, out_path: str) -> None:
    im = Image.open(src_path).convert("RGB")

    # Matte: the artwork stretched over the whole canvas, then blurred past all
    # legibility. Only its colour field survives, which is the point.
    matte = im.resize(CANVAS, Image.LANCZOS).filter(ImageFilter.GaussianBlur(60))

    fg_w = CANVAS[0] - (MARGIN_X * 2)
    fg_h = int(round(fg_w * im.height / im.width))
    if fg_h > CANVAS[1]:
        raise SystemExit(f"source too tall to matte: would need {fg_h}px")
    fg = im.resize((fg_w, fg_h), Image.LANCZOS)

    matte.paste(fg, (MARGIN_X, (CANVAS[1] - fg_h) // 2))

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    matte.save(out_path, "PNG", optimize=True)
    print(
        f"{src_path} {im.width}x{im.height} -> {out_path} "
        f"{CANVAS[0]}x{CANVAS[1]} ({os.path.getsize(out_path)} bytes)"
    )


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("source", nargs="?", default=DEFAULT_SRC)
    ap.add_argument("-o", "--out", default=DEFAULT_OUT)
    args = ap.parse_args()
    build(args.source, args.out)

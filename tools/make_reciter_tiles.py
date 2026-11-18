"""Reciter name tiles for Android Auto and the media notification.

Each reciter gets a 200x200 tile: first name small, surname large, its own
colour, gold ring. No photos (owner's rule: no people in the app's imagery).

  python tools/make_reciter_tiles.py
      Re-renders every tile in BUNDLED into
      android/app/src/main/assets/reciter_art/ (ships in the next release).

  python tools/make_reciter_tiles.py --one <id> <first> <last> <#colour> [--upload]
      Renders one tile into build/reciter_art/<id>.png. With --upload it goes
      to the public quran-content bucket as reciter_art/<id>.png, where builds
      149+ fetch it for a reciter that has no bundled tile, so a reciter added
      from the server gets its tile without a store release.

The id is the reciter's id in reciters.json (e.g. younsi_qaloun). A reciter
whose id has no tile falls back, in this order: downloaded tile, bundled
<id>.png, bundled <first part of id>_qaloun.png (so husary_timed shows the
husary_qaloun tile), generic.png. See ReciterArtProvider.kt.

Rendering uses headless Chrome (Arabic shaping) and the Sakkal Majalla Bold
font that ships with Windows. Western digits only, no em dashes.
"""

import os
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_DIR = os.path.join(ROOT, "android", "app", "src", "main", "assets", "reciter_art")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
FONT = "file:///C:/Windows/Fonts/majallab.ttf"

# id, first name (small), surname (large), colour
BUNDLED = [
    ("husary_qaloun", "محمود خليل", "الحصري", "#1f4e5f"),
    ("naihi_qaloun", "وليد علي", "النائحي", "#5a3a1a"),
    ("qaniwah_qaloun", "الأمين محمد", "قنيوه", "#2e4a2a"),
    ("abusenainah_qaloun", "محمد", "أبوسنينة", "#4a2747"),
    ("hudaifi_qaloun", "علي بن عبدالرحمن", "الحذيفي", "#183a6b"),
    ("doukali_qaloun", "الدوكالي محمد", "العالم", "#6b2a2a"),
    ("alqryw_qaloun", "عبدالحميد", "القريو", "#2a5a55"),
    ("rajab_qaloun", "أحمد صالح", "رجب", "#3d3d6b"),
    ("almislati_qaloun", "نورالدين", "المسلاتي", "#5b4a12"),
    ("trabulsi_qaloun", "أحمد خضر", "الطرابلسي", "#1d5a3a"),
    ("zarrouq_qaloun", "محمد خليل", "الزروق", "#4b2f5e"),
    # Prepared, not yet published (owner's review): ready when they go live.
    ("younsi_qaloun", "علي", "اليونسي", "#5e3a2b"),
    ("ahmed_qleab_qaloun", "أحمد", "القليب", "#2b4f6b"),
    ("generic", "", "قارئ", "#2f3a36"),
]

CELL = 256
OUT = 200
COLS = 5


def render(tiles, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    cells = []
    for i, (_, first, last, colour) in enumerate(tiles):
        x, y = (i % COLS) * CELL, (i // COLS) * CELL
        small = f'<div class="f">{first}</div>' if first else ""
        size = 74 if len(last) <= 6 else (62 if len(last) <= 8 else 54)
        cells.append(
            f'<div class="t" style="left:{x}px;top:{y}px;'
            f'background:radial-gradient(circle at 35% 30%, {colour}ee, {colour} 55%, #0b0f0d 130%)">'
            f'<div class="r"></div>{small}<div class="l" style="font-size:{size}px">{last}</div></div>'
        )
    rows = (len(tiles) + COLS - 1) // COLS
    w, h = COLS * CELL, rows * CELL
    html = f"""<!DOCTYPE html><html dir="rtl"><head><meta charset="utf-8"><style>
@font-face{{font-family:M;src:url("{FONT}")}}
body{{margin:0;background:#000;width:{w}px;height:{h}px;position:relative}}
.t{{position:absolute;width:{CELL}px;height:{CELL}px;display:flex;flex-direction:column;align-items:center;justify-content:center;font-family:M;color:#fff;overflow:hidden}}
.r{{position:absolute;inset:14px;border:3px solid #d8b45a;border-radius:24px;opacity:.9}}
.f{{font-size:34px;color:#e9d6a0;line-height:1;margin-bottom:4px}}
.l{{line-height:1.05;font-weight:bold;text-shadow:0 2px 6px rgba(0,0,0,.45)}}
</style></head><body>{''.join(cells)}</body></html>"""
    with tempfile.TemporaryDirectory() as tmp:
        page = os.path.join(tmp, "tiles.html")
        sheet = os.path.join(tmp, "sheet.png")
        with open(page, "w", encoding="utf-8") as fh:
            fh.write(html)
        subprocess.run(
            [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
             "--allow-file-access-from-files", "--force-device-scale-factor=1",
             f"--window-size={w},{h}", f"--screenshot={sheet}",
             "file:///" + page.replace("\\", "/")],
            check=True, capture_output=True,
        )
        im = Image.open(sheet).convert("RGB")
        written = []
        for i, (tid, *_rest) in enumerate(tiles):
            x, y = (i % COLS) * CELL, (i // COLS) * CELL
            tile = (im.crop((x, y, x + CELL, y + CELL))
                    .resize((OUT, OUT), Image.LANCZOS)
                    .quantize(colors=64, method=Image.Quantize.MEDIANCUT,
                              dither=Image.Dither.NONE))
            path = os.path.join(out_dir, f"{tid}.png")
            tile.save(path, optimize=True)
            written.append(path)
        return written


def upload(path, key):
    import truststore
    truststore.inject_into_ssl()
    import boto3
    from botocore.config import Config
    cfg = {}
    with open(os.path.join(ROOT, "tools", ".r2_secret"), encoding="utf-8") as fh:
        for line in fh:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                cfg[k] = v
    s3 = boto3.client(
        "s3", endpoint_url=cfg["R2_ENDPOINT"],
        aws_access_key_id=cfg["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=cfg["R2_SECRET_ACCESS_KEY"],
        config=Config(region_name="auto",
                      request_checksum_calculation="when_required",
                      response_checksum_validation="when_required"),
    )
    s3.upload_file(path, "quran-content", key,
                   ExtraArgs={"ContentType": "image/png",
                              "CacheControl": "public, max-age=86400"})
    print("uploaded https://quran-content.mushaf-qaloon.com/" + key)


def main(argv):
    if argv and argv[0] == "--one":
        if len(argv) < 5:
            sys.exit(__doc__)
        tid, first, last, colour = argv[1:5]
        out_dir = os.path.join(ROOT, "build", "reciter_art")
        (path,) = render([(tid, first, last, colour)], out_dir)
        print("wrote", path)
        if "--upload" in argv:
            upload(path, f"reciter_art/{tid}.png")
        return
    paths = render(BUNDLED, ASSET_DIR)
    total = sum(os.path.getsize(p) for p in paths)
    print(f"{len(paths)} tiles, {total // 1024} KB -> {ASSET_DIR}")


if __name__ == "__main__":
    main(sys.argv[1:])

"""
Captures Play Store screenshots from a booted Android TV emulator.

Play wants 16:9 PNG or JPEG for the TV form factor; a 1080p TV AVD screencaps
at exactly 1920x1080, so nothing is resized. The alpha channel screencap emits
is stripped, because Play rejects assets with transparency.

    python tools/capture_tv_screenshots.py --serial emulator-5556 --name reader

Each call captures one frame; drive the UI with `adb shell input keyevent`
between calls. Files land in store_assets/tv_screenshots/.
"""
import argparse
import io
import os
import subprocess

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "store_assets", "tv_screenshots")
ADB = os.environ.get("ADB", r"D:/AndroidSdk/platform-tools/adb.exe")


def capture(serial: str, name: str) -> str:
    raw = subprocess.run(
        [ADB, "-s", serial, "exec-out", "screencap", "-p"],
        capture_output=True,
        check=True,
    ).stdout
    im = Image.open(io.BytesIO(raw)).convert("RGB")
    if im.size != (1920, 1080):
        raise SystemExit(f"expected 1920x1080, got {im.size} -- wrong AVD?")
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"{name}.png")
    im.save(path, "PNG", optimize=True)
    return path


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--serial", default="emulator-5556")
    ap.add_argument("--name", required=True)
    args = ap.parse_args()
    p = capture(args.serial, args.name)
    print(f"{p} ({os.path.getsize(p)} bytes)")

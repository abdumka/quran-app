"""
Publishes the Android TV release APK to the public R2 bucket so it can be
sideloaded onto a TV with the "Downloader" app (AFTVnews) -- you type the URL
on the remote, it fetches and installs.

Credentials come from tools/.r2_secret, same as the audio/tafsir mirrors
(R2_BUCKET / R2_ENDPOINT / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY). R2_PREFIX
is ignored -- see below.

The key is deliberately short: the whole URL has to be typed with a D-pad on an
on-screen keyboard, so every character costs.

Usage:
    python tools/upload_tv_apk_to_r2.py                 # publish build/app/outputs/flutter-apk/app-release.apk
    python tools/upload_tv_apk_to_r2.py --key tv-b27.apk
    python tools/upload_tv_apk_to_r2.py --delete        # take it back down
"""
import io
import os
import sys

import truststore
truststore.inject_into_ssl()
import boto3
from botocore.config import Config

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

args = sys.argv[1:]
delete = "--delete" in args
key = "tv.apk"
if "--key" in args:
    key = args[args.index("--key") + 1]

apk = os.path.join(ROOT, "build", "app", "outputs", "flutter-apk", "app-release.apk")

cfg = {}
with open(os.path.join(ROOT, "tools", ".r2_secret"), encoding="utf-8") as fh:
    for line in fh:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            cfg[k] = v

# R2_BUCKET in .r2_secret tracks whatever was mirrored last (it was set to the
# "quran-audio" bucket on 2026-09-16), but the public host
# quran-content.mushaf-qaloon.com is backed by the "quran-content" bucket --
# uploading to the wrong one returns a 404 from that domain. Pin it, with an
# override for the rare case it moves.
BUCKET = "quran-content"
if "--bucket" in args:
    BUCKET = args[args.index("--bucket") + 1]
# R2_PREFIX is deliberately IGNORED here. It tracks whichever reciter folder was
# last mirrored (e.g. "abusenainah"), and this is an app build, not content --
# it belongs at the bucket root. It also keeps the URL short, which matters:
# the whole thing gets typed on a D-pad keyboard.
OBJECT_KEY = key

s3 = boto3.client(
    "s3", endpoint_url=cfg["R2_ENDPOINT"],
    aws_access_key_id=cfg["R2_ACCESS_KEY_ID"],
    aws_secret_access_key=cfg["R2_SECRET_ACCESS_KEY"],
    config=Config(region_name="auto",
                  request_checksum_calculation="when_required",
                  response_checksum_validation="when_required"),
)

if delete:
    s3.delete_object(Bucket=BUCKET, Key=OBJECT_KEY)
    print(f"deleted {OBJECT_KEY}")
    raise SystemExit(0)

if not os.path.exists(apk):
    raise SystemExit(f"missing {apk} -- run: flutter build apk --release")

size = os.path.getsize(apk)
print(f"uploading {size / (1024 * 1024):.1f} MB -> {OBJECT_KEY}", flush=True)

# Android refuses to install anything served as text/html, and some CDNs will
# sniff that for an unknown type, so set the APK type explicitly.
s3.upload_file(
    apk, BUCKET, OBJECT_KEY,
    ExtraArgs={"ContentType": "application/vnd.android.package-archive"},
)
print(f"done: {OBJECT_KEY}")

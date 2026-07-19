"""
Uploads the per-page tafsir files produced by build_tafsir_pages.py to our
Cloudflare R2 bucket, so the app's online editions (Ibn Kathir, Tabari, Qurtubi,
Zad al-Masir) can fetch them page-by-page. Same credential handling as the audio
mirrors (tools/.r2_secret with R2_BUCKET / R2_ENDPOINT / R2_ACCESS_KEY_ID /
R2_SECRET_ACCESS_KEY; R2_PREFIX optional).

Layout on R2 (matches TafsirEdition.pageBaseUrl in lib/models/tafsir_edition.dart):
    <prefix?>/tafsir/<edition_id>/page_001.json … page_604.json

Run AFTER build_tafsir_pages.py. Idempotent: skips objects already present unless
--force. The online editions stay non-functional in the app until this upload has
run and the bucket is public at the URL configured in tafsir_edition.dart.

Usage:
    python tools/mirror_tafsir_to_r2.py                 # upload all built editions
    python tools/mirror_tafsir_to_r2.py ibn_kathir      # one edition
    python tools/mirror_tafsir_to_r2.py --force          # re-upload everything
"""
import hashlib
import io
import os
import sys
from concurrent.futures import ThreadPoolExecutor

import truststore
truststore.inject_into_ssl()
import boto3
from botocore.config import Config

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build", "tafsir")

ONLINE_EDITIONS = ["ibn_kathir", "tabari", "qurtubi"]

args = [a for a in sys.argv[1:]]
force = "--force" in args
only = [a for a in args if not a.startswith("--")]
editions = only or ONLINE_EDITIONS

cfg = {}
with open(os.path.join(ROOT, "tools", ".r2_secret"), encoding="utf-8") as fh:
    for line in fh:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            cfg[k] = v
BUCKET = cfg["R2_BUCKET"]
# Base prefix (optional). Files live under "<prefix>/tafsir/<id>/…"; with no
# prefix they live under "tafsir/<id>/…".
BASE = cfg.get("R2_PREFIX", "").strip("/")
KEY_ROOT = (BASE + "/tafsir") if BASE else "tafsir"

s3 = boto3.client(
    "s3", endpoint_url=cfg["R2_ENDPOINT"],
    aws_access_key_id=cfg["R2_ACCESS_KEY_ID"],
    aws_secret_access_key=cfg["R2_SECRET_ACCESS_KEY"],
    config=Config(region_name="auto", max_pool_connections=40,
                  request_checksum_calculation="when_required",
                  response_checksum_validation="when_required"),
)

# Map each existing object key -> ETag (md5 hex for single-part PUTs). We compare
# this against each local file's md5 so only CHANGED pages are re-uploaded — no
# --force needed when regenerating tafsir content.
existing = {}
for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=KEY_ROOT + "/"):
    for o in page.get("Contents", []):
        existing[o["Key"]] = o.get("ETag", "").strip('"')
print(f"in R2 under {KEY_ROOT}/: {len(existing)} objects", flush=True)

jobs = []
for edition_id in editions:
    src_dir = os.path.join(BUILD, edition_id)
    if not os.path.isdir(src_dir):
        print(f"[{edition_id}] SKIP — {src_dir} missing (run build_tafsir_pages.py first)")
        continue
    for name in sorted(os.listdir(src_dir)):
        if name.endswith(".json"):
            key = f"{KEY_ROOT}/{edition_id}/{name}"
            jobs.append((os.path.join(src_dir, name), key))
print(f"files to consider: {len(jobs)}", flush=True)


def work(job):
    path, key = job
    with open(path, "rb") as fh:
        body = fh.read()
    # Skip only when the object already there has identical content (matching md5).
    if not force and existing.get(key) == hashlib.md5(body).hexdigest():
        return "skip"
    s3.put_object(
        Bucket=BUCKET, Key=key, Body=body,
        ContentType="application/json; charset=utf-8",
    )
    return "up"


up = skip = 0
with ThreadPoolExecutor(max_workers=16) as ex:
    for i, status in enumerate(ex.map(work, jobs), 1):
        if status == "up":
            up += 1
        else:
            skip += 1
        if i % 300 == 0:
            print(f"progress {i}/{len(jobs)} up={up} skip={skip}", flush=True)

print(f"\nDONE up={up} skip={skip} (total {len(jobs)})")
print(f"Verify a URL resolves, e.g. {cfg['R2_ENDPOINT'].rstrip('/')}… or the public "
      f"r2.dev domain configured in lib/models/tafsir_edition.dart.")

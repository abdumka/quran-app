#!/usr/bin/env python3
"""Publish the server-updatable data the app fetches without a store release
(lib/services/content_update_service.dart) to the quran-content R2 bucket:

    data/manifest.json                       what is current (never cached long)
    data/tanzilat/tanzilat_v<N>.json         assets/data/tanzilat.json, N = its "ver"
    data/word_masks/patch_v<N>.json          tools/content_updates/word_masks_patch.json
    data/reciters/reciters_v<N>.json         tools/content_updates/reciters.json

Each payload is uploaded under its version (immutable, cached for a year) and
the manifest is rewritten last, so a phone never sees a manifest pointing at a
file that is not there yet. A version already on the bucket is never
overwritten: bump "ver" in the source file instead.

Bumping: a tanzilat change -> VER in build_tanzilat_data.py; a word-box fix ->
"ver" in word_masks_patch.json (the list is cumulative); a new reciter -> "ver"
in reciters.json. A build's ContentUpdateService.bundledVersions must equal the
versions its assets carry; "minBuild" below is the first build that reads this
data at all.

Usage:
    python tools/publish_content_updates.py            # upload + manifest
    python tools/publish_content_updates.py --dry-run  # show the manifest only
Credentials: tools/.r2_secret (the quran-content block). Same handling as the
tafsir mirror; never print the secret.
"""
import hashlib
import io
import json
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "content_updates"
MIN_BUILD = 126  # the first build with ContentUpdateService
PUBLIC = "https://quran-content.mushaf-qaloon.com/"
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ITEMS = {
    # name: (source file, key pattern)
    "tanzilat": (ROOT / "assets" / "data" / "tanzilat.json", "data/tanzilat/tanzilat_v{ver}.json"),
    "word_masks": (SRC / "word_masks_patch.json", "data/word_masks/patch_v{ver}.json"),
    "reciters": (SRC / "reciters.json", "data/reciters/reciters_v{ver}.json"),
}
EASTERN = set("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹")


def secret_block(bucket):
    blocks, cur = [], {}
    for line in (ROOT / "tools" / ".r2_secret").read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        k, v = line.strip().split("=", 1)
        if k == "R2_BUCKET" and cur:
            blocks.append(cur)
            cur = {}
        cur[k] = v
    if cur:
        blocks.append(cur)
    for b in blocks:
        if b.get("R2_BUCKET") == bucket:
            return b
    sys.exit(f"ABORT: no credentials block for bucket {bucket!r}")


def main():
    dry = "--dry-run" in sys.argv
    manifest = {"v": 1, "items": {}}
    uploads = []
    for name, (src, pattern) in ITEMS.items():
        if not src.exists():
            print(f"{name}: no source file ({src.relative_to(ROOT)}), left out of the manifest")
            continue
        body = src.read_bytes()
        data = json.loads(body)
        ver = data.get("ver")
        if not isinstance(ver, int) or ver < 1:
            print(f"{name}: no usable \"ver\" in {src.name}, left out")
            continue
        if name == "tanzilat" and "groups" not in data:
            sys.exit(f"ABORT: {src} has no groups")
        if name == "word_masks" and not isinstance(data.get("patches"), list):
            sys.exit(f"ABORT: {src} has no patches list")
        if name == "reciters" and not isinstance(data.get("reciters"), list):
            sys.exit(f"ABORT: {src} has no reciters list")
        if name != "tanzilat" and any(c in EASTERN for c in body.decode("utf-8")):
            sys.exit(f"ABORT: Eastern digits in {src}")
        key = pattern.format(ver=ver)
        manifest["items"][name] = {
            "ver": ver,
            "url": key,
            "sha256": hashlib.sha256(body).hexdigest(),
            "bytes": len(body),
            "minBuild": MIN_BUILD,
        }
        uploads.append((name, key, body))
        print(f"{name}: v{ver} {len(body):,} bytes -> {key}")
    manifest_body = json.dumps(manifest, separators=(",", ":")).encode("utf-8")
    print(manifest_body.decode("utf-8"))
    if dry:
        return

    import truststore
    truststore.inject_into_ssl()
    import boto3
    from botocore.config import Config
    from botocore.exceptions import ClientError

    cfg = secret_block("quran-content")
    s3 = boto3.client(
        "s3", endpoint_url=cfg["R2_ENDPOINT"], aws_access_key_id=cfg["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=cfg["R2_SECRET_ACCESS_KEY"],
        config=Config(region_name="auto", request_checksum_calculation="when_required",
                      response_checksum_validation="when_required"))
    bucket = cfg["R2_BUCKET"]
    for name, key, body in uploads:
        try:
            head = s3.head_object(Bucket=bucket, Key=key)
            have = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
            if have == body:
                print(f"  {key}: already published, unchanged")
                continue
            sys.exit(f"ABORT: {key} is already published with different content; bump its ver")
        except ClientError as e:
            if e.response["Error"]["Code"] not in ("404", "NoSuchKey", "NotFound"):
                raise
        s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType="application/json; charset=utf-8",
                      CacheControl="public, max-age=31536000, immutable")
        got = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        assert got == body, key
        print(f"  {key}: uploaded and verified")
    s3.put_object(Bucket=bucket, Key="data/manifest.json", Body=manifest_body,
                  ContentType="application/json; charset=utf-8", CacheControl="no-cache")
    got = s3.get_object(Bucket=bucket, Key="data/manifest.json")["Body"].read()
    assert got == manifest_body
    print("  data/manifest.json: uploaded and verified")
    # The public URL is what phones read: it must serve the same bytes, untouched.
    req = urllib.request.Request(PUBLIC + "data/manifest.json", headers={"User-Agent": "Mozilla/5.0 Chrome/120", "Cache-Control": "no-cache"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            public = r.read()
        print("  public manifest:", "identical" if public == manifest_body else "DIFFERENT (CDN cache or injected content?)")
    except Exception as e:  # noqa: BLE001
        print("  public manifest: could not fetch from this network:", e)


if __name__ == "__main__":
    main()

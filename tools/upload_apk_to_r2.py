#!/usr/bin/env python3
"""Park a test APK on the public content bucket (quran-content, served at
https://quran-content.mushaf-qaloon.com) under an unlisted `builds/` prefix, so
the owner can install it from a link instead of a cable. Nothing links to the
prefix and R2 public buckets cannot be listed, so the file is reachable only by
whoever has the URL.

Uploads two objects: a dated, commit-stamped copy that is never overwritten,
and `builds/<name>-latest.apk` that always points at the newest build.

usage: python tools/upload_apk_to_r2.py [<apk path>] [--name tasmee] [--no-latest]

Credentials: the quran-content block of quran-app-main\\tools\\.r2_secret
(S3 keys; multipart upload handles the ~400 MB debug APK). The file is never
printed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import pathlib
import subprocess
import sys

import truststore

truststore.inject_into_ssl()

import boto3  # noqa: E402
from boto3.s3.transfer import TransferConfig  # noqa: E402
from botocore.config import Config  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SECRET = ROOT.parent / "quran-app-main" / "tools" / ".r2_secret"
PUBLIC_BASE = "https://quran-content.mushaf-qaloon.com"
DEFAULT_APK = ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-debug.apk"


def credentials(bucket_wanted: str = "quran-content") -> dict:
    """First R2_* block of .r2_secret whose R2_BUCKET matches."""
    blocks, cur = [], {}
    for line in SECRET.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if "=" in line and line.startswith("R2_"):
            k, v = line.split("=", 1)
            if k == "R2_BUCKET" and cur:
                blocks.append(cur)
                cur = {}
            cur[k] = v.strip().strip('"').strip("'")
    if cur:
        blocks.append(cur)
    for b in blocks:
        if b.get("R2_BUCKET") == bucket_wanted:
            return b
    raise SystemExit(f"no block for bucket {bucket_wanted} in {SECRET}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("apk", nargs="?", default=str(DEFAULT_APK))
    ap.add_argument("--name", default="tasmee")
    ap.add_argument("--no-latest", action="store_true")
    args = ap.parse_args()
    apk = pathlib.Path(args.apk)
    if not apk.exists():
        raise SystemExit(f"missing {apk}")
    sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip() or "nosha"
    branch = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip() or "nobranch"
    stamp = dt.datetime.fromtimestamp(apk.stat().st_mtime).strftime("%Y-%m-%d_%H%M")
    keys = [f"builds/{args.name}-{stamp}-{branch}-{sha}.apk"]
    if not args.no_latest:
        keys.append(f"builds/{args.name}-latest.apk")

    cred = credentials()
    ca = ROOT / "tools" / "_merged_ca_bundle.pem"
    s3 = boto3.client(
        "s3",
        verify=str(ca) if ca.exists() else True,
        endpoint_url=cred["R2_ENDPOINT"],
        aws_access_key_id=cred["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=cred["R2_SECRET_ACCESS_KEY"],
        region_name="auto",
        config=Config(request_checksum_calculation="when_required", response_checksum_validation="when_required"),
    )
    cfg = TransferConfig(multipart_threshold=64 * 1024 * 1024, multipart_chunksize=64 * 1024 * 1024, max_concurrency=4)
    size_mb = apk.stat().st_size / 1e6
    for key in keys:
        print(f"uploading {size_mb:.0f} MB -> {key}", flush=True)
        s3.upload_file(
            str(apk), cred["R2_BUCKET"], key, Config=cfg,
            ExtraArgs={"ContentType": "application/vnd.android.package-archive", "CacheControl": "no-cache"},
        )
        print(f"  {PUBLIC_BASE}/{key}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Mirror Mahmoud Khalil Al-Husary Qaloun MP3 files from GitHub raw to R2.

Prompts for R2 connection info at runtime. Defaults target:
  bucket: quran-audio
  prefix: alhosary
  endpoint: https://e5d964bef851ec4a941f20639353457b.r2.cloudflarestorage.com

The script is resumable: existing R2 objects are skipped, and file hashes are
saved in tools/_husary_hashes.json. With the settings above, files are uploaded
as alhosary/001001.mp3 etc.
"""

from __future__ import annotations

import hashlib
import getpass
import io
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor

import boto3
from botocore.config import Config
from botocore.exceptions import SSLError as BotoSSLError

try:
    import certifi
except ImportError:
    certifi = None

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HASHFILE = os.path.join(ROOT, "tools", "_husary_hashes.json")
MERGED_CA_BUNDLE = os.path.join(ROOT, "tools", "_merged_ca_bundle.pem")
DEFAULT_BUCKET = "quran-audio"
DEFAULT_PREFIX = "alhosary"
DEFAULT_ENDPOINT = (
    "https://e5d964bef851ec4a941f20639353457b.r2.cloudflarestorage.com"
)
SOURCE_BASE_URL = (
    "https://raw.githubusercontent.com/"
    "quran-by-verses/alhosary-qaloon-32/main/verses/"
)

# This mirrors the legacy Husary file list used by AudioDownloadService.
SURAH_AYAH_COUNTS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109,
    123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
    112, 78, 118, 64, 77, 227, 93, 88, 69, 60,
    34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
    54, 53, 89, 59, 37, 35, 38, 29, 18, 45,
    60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
    14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
    28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
    29, 19, 36, 25, 22, 17, 19, 26, 30, 20,
    15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
    11, 8, 3, 9, 5, 4, 7, 3, 6, 3,
    5, 4, 5, 6,
]

MERGED_THRESHOLDS = {
    5: 120,
    6: 165,
    8: 75,
    9: 129,
    13: 43,
    14: 52,
    23: 118,
    27: 93,
    47: 38,
    56: 96,
    71: 28,
    89: 30,
    91: 15,
    96: 19,
    106: 4,
}


def load_config() -> dict[str, str]:
    print("Cloudflare R2 upload target")
    print("Press Enter to accept the value in brackets.\n")

    bucket = prompt("Bucket", DEFAULT_BUCKET)
    prefix = prompt("Prefix/folder", DEFAULT_PREFIX)
    endpoint = prompt("S3 endpoint", DEFAULT_ENDPOINT)
    ca_bundle = prompt_ca_bundle()
    access_key_id = prompt_required("Access Key ID")
    secret_access_key = prompt_secret("Secret Access Key")

    return {
        "R2_BUCKET": bucket,
        "R2_PREFIX": prefix,
        "R2_ENDPOINT": endpoint,
        "CA_BUNDLE": ca_bundle,
        "R2_ACCESS_KEY_ID": access_key_id,
        "R2_SECRET_ACCESS_KEY": secret_access_key,
    }


def prompt(label: str, default: str) -> str:
    value = input(f"{label} [{default}]: ").strip()
    return value or default


def prompt_required(label: str) -> str:
    while True:
        value = input(f"{label}: ").strip()
        if value:
            return value
        print(f"{label} is required.")


def prompt_ca_bundle() -> str | None:
    default = certifi.where() if certifi else ""
    label = "CA bundle path"
    if default:
        value = input(f"{label} [{default}]: ").strip()
        return value or default

    value = input(f"{label} [system default]: ").strip()
    return value or None


def build_ca_bundle(ca_bundle: str | None) -> str | bool:
    default_bundle = certifi.where() if certifi else None
    if not ca_bundle:
        return True
    if default_bundle and os.path.normcase(ca_bundle) == os.path.normcase(default_bundle):
        return ca_bundle
    if not os.path.exists(ca_bundle):
        raise SystemExit(f"CA bundle file not found: {ca_bundle}")
    if not default_bundle:
        return ca_bundle

    with open(default_bundle, "rb") as base_file:
        base_bytes = base_file.read()
    with open(ca_bundle, "rb") as custom_file:
        custom_bytes = custom_file.read()

    with open(MERGED_CA_BUNDLE, "wb") as merged_file:
        merged_file.write(base_bytes.rstrip() + b"\n")
        merged_file.write(custom_bytes.lstrip())
        if not custom_bytes.endswith(b"\n"):
            merged_file.write(b"\n")
    return MERGED_CA_BUNDLE


def prompt_secret(label: str) -> str:
    while True:
        value = masked_input(f"{label}: ").strip()
        if value:
            return value
        print(f"{label} is required.")


def masked_input(prompt_text: str) -> str:
    if os.name != "nt":
        return getpass.getpass(prompt_text)

    import msvcrt

    sys.stdout.write(prompt_text)
    sys.stdout.flush()
    chars: list[str] = []
    while True:
        char = msvcrt.getwch()
        if char in ("\r", "\n"):
            sys.stdout.write("\n")
            return "".join(chars)
        if char == "\003":
            raise KeyboardInterrupt
        if char == "\b":
            if chars:
                chars.pop()
                sys.stdout.write("\b \b")
                sys.stdout.flush()
            continue
        if char in ("\x00", "\xe0"):
            msvcrt.getwch()
            continue

        chars.append(char)
        sys.stdout.write("*")
        sys.stdout.flush()


def husary_filenames() -> list[str]:
    filenames: set[str] = set()
    for surah in range(1, 115):
        surah_str = str(surah).zfill(3)
        merged_from = MERGED_THRESHOLDS.get(surah)
        for ayah in range(1, SURAH_AYAH_COUNTS[surah - 1] + 1):
            audio_ayah = merged_from if merged_from and ayah >= merged_from else ayah
            filenames.add(f"{surah_str}{str(audio_ayah).zfill(3)}.mp3")
    return sorted(filenames)


def load_hashes() -> dict[str, str]:
    if not os.path.exists(HASHFILE):
        return {}
    with open(HASHFILE, encoding="utf-8") as f:
        return json.load(f)


def save_hashes(hashes: dict[str, str]) -> None:
    with open(HASHFILE, "w", encoding="utf-8") as f:
        json.dump(hashes, f, indent=1, sort_keys=True)


cfg = load_config()
bucket = cfg["R2_BUCKET"]
prefix = cfg["R2_PREFIX"].strip("/")
endpoint = cfg["R2_ENDPOINT"].rstrip("/")
ca_bundle = build_ca_bundle(cfg["CA_BUNDLE"])
download_ssl_context = (
    ssl.create_default_context(cafile=ca_bundle) if isinstance(ca_bundle, str)
    else ssl.create_default_context()
)
parsed_endpoint = urlparse(endpoint)
if parsed_endpoint.path and parsed_endpoint.path.strip("/") == bucket:
    endpoint = endpoint[: -len(parsed_endpoint.path)]

s3 = boto3.client(
    "s3",
    endpoint_url=endpoint,
    aws_access_key_id=cfg["R2_ACCESS_KEY_ID"],
    aws_secret_access_key=cfg["R2_SECRET_ACCESS_KEY"],
    verify=ca_bundle,
    config=Config(
        region_name="auto",
        max_pool_connections=40,
        request_checksum_calculation="when_required",
        response_checksum_validation="when_required",
    ),
)

existing: set[str] = set()
try:
    for page in s3.get_paginator("list_objects_v2").paginate(
        Bucket=bucket,
        Prefix=prefix + "/",
    ):
        for obj in page.get("Contents", []):
            existing.add(obj["Key"])
except BotoSSLError as exc:
    raise SystemExit(
        "\nSSL certificate verification failed while connecting to R2.\n"
        "If your network inserts a self-signed/root certificate, export that "
        "root certificate as a PEM file and enter its path at the "
        "'CA bundle path' prompt.\n\n"
        f"Details: {exc}"
    ) from exc

hashes = load_hashes()
jobs = husary_filenames()
print(f"in R2: {len(existing)} | known hashes: {len(hashes)} | files: {len(jobs)}")


def work(filename: str) -> tuple[str, str, str | None]:
    key = f"{prefix}/{filename}"
    have_obj = key in existing
    have_hash = filename in hashes
    if have_obj and have_hash:
        return ("skip", filename, hashes[filename])

    request = urllib.request.Request(
        SOURCE_BASE_URL + filename,
        headers={"User-Agent": "Mozilla/5.0"},
    )
    for _ in range(4):
        try:
            data = urllib.request.urlopen(
                request,
                timeout=60,
                context=download_ssl_context,
            ).read()
            if len(data) < 200:
                return ("small", filename, None)
            digest = hashlib.md5(data).hexdigest()
            if not have_obj:
                s3.put_object(
                    Bucket=bucket,
                    Key=key,
                    Body=data,
                    ContentType="audio/mpeg",
                    CacheControl="public, max-age=31536000, immutable",
                )
            return ("up", filename, digest)
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return ("404", filename, None)
        except Exception:
            pass
    return ("err", filename, None)


uploaded = skipped = bad = done = 0
with ThreadPoolExecutor(max_workers=16) as executor:
    for status, filename, digest in executor.map(work, jobs):
        done += 1
        if digest:
            hashes[filename] = digest
        if status == "up":
            uploaded += 1
        elif status == "skip":
            skipped += 1
        else:
            bad += 1
            if bad <= 30:
                print(f"  {status} {filename}", flush=True)

        if done % 300 == 0:
            save_hashes(hashes)
            print(
                f"progress {done}/{len(jobs)} "
                f"up={uploaded} skip={skipped} bad={bad}",
                flush=True,
            )

save_hashes(hashes)
print(f"\nDONE up={uploaded} skip={skipped} bad={bad}")
print(f"R2 prefix: {prefix}/")

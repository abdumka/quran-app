#!/usr/bin/env python3
"""Mirrors the margin-pages (هوامش) pack to Cloudflare R2 so the **web** build
can stream them, since a browser has no filesystem to unpack the release zip
into (native builds keep downloading/extracting hawamesh.zip as before).

Uploads `page_1.webp … page_602.webp` to `quran-content/hawamesh/`, which is
the same bucket that serves the online tafsir and already has the CORS policy
CanvasKit needs for image byte-fetches.

Usage:
    python tools/mirror_hawamesh_to_r2.py <extracted_pages_dir>

Uploads via the authenticated `wrangler` CLI (no S3 keys needed). Skips objects
that already exist, so it is safe to re-run / resume after an interruption.
"""
from __future__ import annotations

import concurrent.futures as cf
import subprocess
import sys
import urllib.request
from pathlib import Path

BUCKET = "quran-content"
PREFIX = "hawamesh"
PAGE_COUNT = 602
WORKERS = 12
PUBLIC_BASE = "https://quran-content.mushaf-qaloon.com"


def is_published(page: int) -> int | None:
    """Returns `page` when it is already live on the CDN, else None."""
    req = urllib.request.Request(
        f"{PUBLIC_BASE}/{PREFIX}/page_{page}.webp", method="HEAD"
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return page if resp.status == 200 else None
    except Exception:
        return None


def upload(path: Path, key: str) -> bool:
    r = subprocess.run(
        [
            "npx", "wrangler", "r2", "object", "put", f"{BUCKET}/{key}",
            "--file", str(path),
            "--content-type", "image/webp",
            # Margin pages are immutable once published; let browsers keep them.
            "--cache-control", "public, max-age=31536000, immutable",
            # WITHOUT --remote wrangler writes to a local sandbox and the object
            # never reaches R2 (it 404s on the CDN) — easy to miss, since the
            # command still reports "Upload complete".
            "--remote",
        ],
        capture_output=True,
        text=True,
        shell=True,
        # wrangler emits box-drawing/ANSI bytes that the console's cp1252
        # codec can't decode on Windows — decode leniently instead of dying.
        encoding="utf-8",
        errors="replace",
    )
    if r.returncode != 0:
        print(f"  FAILED {key}: {(r.stderr or '').strip()[:200]}")
    return r.returncode == 0


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("usage: mirror_hawamesh_to_r2.py <extracted_pages_dir>")
    src = Path(sys.argv[1])
    if not src.is_dir():
        sys.exit(f"not a directory: {src}")

    missing = [n for n in range(1, PAGE_COUNT + 1) if not (src / f"page_{n}.webp").exists()]
    if missing:
        sys.exit(f"missing {len(missing)} page files locally, first few: {missing[:10]}")

    # Skip pages already published (cheap HEAD against the CDN — far faster
    # than asking wrangler), so an interrupted run resumes instead of redoing.
    print("checking which pages are already live ...", flush=True)
    with cf.ThreadPoolExecutor(max_workers=32) as pool:
        live = set(pool.map(is_published, range(1, PAGE_COUNT + 1)))
    todo = [n for n in range(1, PAGE_COUNT + 1) if n not in live]
    print(f"{PAGE_COUNT - len(todo)} already live, {len(todo)} to upload", flush=True)

    # Each upload spawns a wrangler process (~3-5s of startup), so serial
    # uploads would take hours. They are independent objects — run a pool.
    done = failed = 0
    completed = 0
    with cf.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {
            pool.submit(upload, src / f"page_{n}.webp", f"{PREFIX}/page_{n}.webp"): n
            for n in todo
        }
        for fut in cf.as_completed(futures):
            completed += 1
            if fut.result():
                done += 1
            else:
                failed += 1
            if completed % 25 == 0 or completed == len(todo):
                print(
                    f"[{completed}/{len(todo)}] uploaded={done} failed={failed}",
                    flush=True,
                )

    print(f"\nDONE uploaded={done} failed={failed} (skipped {PAGE_COUNT - len(todo)})")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()

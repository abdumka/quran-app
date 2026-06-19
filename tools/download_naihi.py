#!/usr/bin/env python3
"""
Mirror the Walid Ali al-Naihi (وليد علي النائحي) Qaloun recitation off nquran.com
into a local folder, ready to push to your own GitHub raw mirror so the app never
depends on nquran.com at runtime.

HOW THE SOURCE WORKS (reverse-engineered from the nquran jPlayer):
  * Audio is streamed via:  https://www.nquran.com/globals/readaudio.php?mp3=<TOKEN>
  * <TOKEN> = base64( 's:<LEN>:"<PATH>";|_*7H_' )  where <PATH> is the real file
    path and <LEN> is its UTF-8 byte length (PHP-serialized-string + a fixed signature).
  * For al-Naihi (Qaloun, rewaya=3, qareeid=30) the path is:
        moshaf/qaloon/waleed_allebi/<SSS>/<AAA>.mp3
    where <SSS> = zero-padded surah, <AAA> = zero-padded ayah.
  * <AAA> = 000 is the BASMALA (present for every surah except 9). Ayah files are
    001..max. The ayah numbering is MADANI/QALOUN counting, which matches the
    counting used by the app's page data (assets/data/output.json).

OUTPUT NAMING (native Madani numbering, 1:1 with the app's ayah numbers):
        <out>/<SSS><AAA>.mp3      e.g.  001000.mp3 (Fatiha basmala),
                                        001001.mp3 (الحمد لله ...),
                                        005122.mp3 (Qaloun-only extra ayah).
  Push the contents of <out> to the `verses/` folder of your al-Naihi repo and set
  Reciter.naihiQaloun.audioBaseUrl to that repo's raw URL.

USAGE:
    python tools/download_naihi.py                # all surahs -> ./tools/naihi_verses
    python tools/download_naihi.py --out D:/mirror/verses
    python tools/download_naihi.py --surah 1      # one surah only (testing)
    python tools/download_naihi.py --surah 1-5    # a range

The script is resumable (skips files already downloaded with non-zero size),
polite (small delay + retries), and prints a summary with any surah whose Qaloun
count differs from standard Hafs (useful for cross-checking the in-app mapping).
"""

import argparse
import base64
import os
import sys
import time
import json
import urllib.request
import urllib.error

NQURAN = "https://www.nquran.com"
READAUDIO = NQURAN + "/globals/readaudio.php?mp3="
GETAYA = NQURAN + "/ar/quranplayer/ajax/nindex.php?sora={s}&page=getayanumbers&rewayano=3"
AUDIO_PATH = "moshaf/qaloon/waleed_allebi/{s:03d}/{a:03d}.mp3"
SIGNATURE = "|_*7H_"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "Referer": "https://www.nquran.com/ar/quranplayer/?rewayano=3&sorano=1&ayano=1",
    "X-Requested-With": "XMLHttpRequest",
}

# Standard Hafs ayah counts — only used to report Qaloun/Hafs differences.
HAFS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128,
    111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73,
    54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60,
    49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
    28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26, 30,
    20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
]


def make_token(path: str) -> str:
    inner = 's:{}:"{}";{}'.format(len(path.encode("utf-8")), path, SIGNATURE)
    return base64.b64encode(inner.encode("utf-8")).decode("ascii")


def http_get(url: str, retries: int = 4, timeout: int = 30) -> bytes:
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise
            last = e
        except Exception as e:  # noqa: BLE001 - network resilience
            last = e
        time.sleep(1.5 * (attempt + 1))
    raise last if last else RuntimeError("unknown error")


def get_inventory(surah: int) -> tuple[int, int]:
    """Return (minaya, maxaya) for a surah from nquran's authoritative endpoint."""
    data = json.loads(http_get(GETAYA.format(s=surah)).decode("utf-8"))
    first = data[0]
    return int(first["minaya"]), int(first["maxaya"])


def download_ayah(surah: int, ayah: int, dest: str) -> int:
    token = make_token(AUDIO_PATH.format(s=surah, a=ayah))
    body = http_get(READAUDIO + token)
    if len(body) < 200:
        raise RuntimeError("suspiciously small file ({} bytes)".format(len(body)))
    with open(dest, "wb") as f:
        f.write(body)
    return len(body)


def parse_surah_arg(arg: str) -> list[int]:
    if not arg:
        return list(range(1, 115))
    if "-" in arg:
        lo, hi = arg.split("-", 1)
        return list(range(int(lo), int(hi) + 1))
    return [int(arg)]


def main() -> int:
    ap = argparse.ArgumentParser(description="Mirror al-Naihi Qaloun recitation from nquran.com")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "naihi_verses"),
                    help="output folder (default: tools/naihi_verses)")
    ap.add_argument("--surah", default="", help="single surah (e.g. 5) or range (e.g. 1-10)")
    ap.add_argument("--delay", type=float, default=0.25, help="seconds between downloads")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    surahs = parse_surah_arg(args.surah)

    total, downloaded, skipped, failed = 0, 0, 0, 0
    diffs = []

    for s in surahs:
        try:
            minaya, maxaya = get_inventory(s)
        except Exception as e:  # noqa: BLE001
            print("  surah {:3d}: inventory FAILED: {}".format(s, e))
            failed += 1
            continue

        qaloun_count = maxaya  # ayah files 1..maxaya (000 is basmala, not an ayah)
        if qaloun_count != HAFS[s - 1]:
            diffs.append((s, qaloun_count, HAFS[s - 1]))

        # 000 basmala for every surah except where minaya==1 (surah 9)
        start = 0 if minaya == 0 else 1
        for a in range(start, maxaya + 1):
            total += 1
            dest = os.path.join(args.out, "{:03d}{:03d}.mp3".format(s, a))
            if os.path.exists(dest) and os.path.getsize(dest) > 0:
                skipped += 1
                continue
            try:
                n = download_ayah(s, a, dest)
                downloaded += 1
                if downloaded % 50 == 0:
                    print("  ... {} downloaded (last {:03d}{:03d} = {} bytes)".format(
                        downloaded, s, a, n))
                time.sleep(args.delay)
            except urllib.error.HTTPError as e:
                print("  MISSING {:03d}{:03d}: HTTP {}".format(s, a, e.code))
                failed += 1
            except Exception as e:  # noqa: BLE001
                print("  ERROR {:03d}{:03d}: {}".format(s, a, e))
                failed += 1

        print("surah {:3d} done: ayahs {}..{} (basmala={})".format(
            s, 1, maxaya, "yes" if start == 0 else "no"))

    print("\n========== SUMMARY ==========")
    print("expected files : {}".format(total))
    print("downloaded     : {}".format(downloaded))
    print("already present: {}".format(skipped))
    print("failed/missing : {}".format(failed))
    print("output folder  : {}".format(os.path.abspath(args.out)))
    if diffs:
        print("\nSurahs where Qaloun count != Hafs (cross-check in-app mapping):")
        for s, q, h in diffs:
            print("  surah {:3d}: Qaloun={} Hafs={} (delta {:+d})".format(s, q, h, q - h))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

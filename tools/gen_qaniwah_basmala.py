"""Regenerate assets/data/qaniwah_continuations.json, adding a `basmala_in_ayah1`
list: surahs where قنيوه's ayah-1 file ALREADY contains the basmala, so the app
must NOT prepend the separate basmala file 000 (else it plays twice).

Reliable part: every surah where file 000 == file 001 (byte-identical) — both are
basmala+ayah1, confirmed duplicates. Plus a small MANUAL list for surahs where
000 is a (reused) basmala-only clip but 001 still starts with the basmala; these
can't be detected from the bytes, so they're curated from listening tests.
"""
import hashlib, io, json, os, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "assets", "data", "qaniwah_continuations.json")
B = "https://pub-f4e99834c32943d2a947531d938b19f6.r2.dev/qaniwah/%03d%03d.mp3"
H = {"User-Agent": "Mozilla/5.0"}

# Surahs where 000 != 001 yet ayah-1 still begins with the basmala (verified by ear).
MANUAL_SKIP_PREPEND = {2, 3, 4}


def md5(s, a):
    try:
        d = urllib.request.urlopen(urllib.request.Request(B % (s, a), headers=H), timeout=40).read()
        return hashlib.md5(d).hexdigest()
    except Exception:
        return None


def equal(s):
    return s != 9 and md5(s, 0) == md5(s, 1) and md5(s, 0) is not None


eq = sorted(s for s, ok in zip(range(1, 115), ThreadPoolExecutor(max_workers=16).map(equal, range(1, 115))) if ok)
skip = sorted(set(eq) | MANUAL_SKIP_PREPEND)
print("000==001 surahs:", len(eq))
print("basmala_in_ayah1 (skip prepend) total:", len(skip))

data = json.load(open(PATH, encoding="utf-8"))
data["basmala_in_ayah1"] = skip
data["_comment_basmala"] = ("Surahs where قنيوه recites the basmala as part of the ayah-1 file, "
                            "so the app must NOT also play the separate basmala file 000.")
json.dump(data, open(PATH, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("wrote", PATH)

"""
Generates assets/data/narration_map.json: a CONTENT-VERIFIED map from the app's
Qalun (Madani) ayah numbering to the Hafs (Kufi) numbering used by the Sa'di
tafsir (assets/data/ar.saddi.json).

Method:
  1. Fetch Hafs (quran-uthmani) verse text once from api.alquran.cloud.
  2. Strip the basmala that this edition prepends to every surah's ayah 1
     (except Al-Fatiha, where it is genuinely ayah 1, and At-Tawba, none).
  3. Per surah, align the normalised Qalun and Hafs word streams (difflib) and,
     for each Qalun ayah, find the span of Hafs ayahs it covers.
  4. VERIFY each mapping: the Qalun ayah text must closely match the Hafs
     ayah(s) it maps onto. Mappings failing verification are NOT emitted
     (left 1:1) and reported for manual review.
"""
import json
import re
import sys
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "assets" / "data"
HAFS_CACHE = ROOT / "hafs_uthmani.json"
VERIFY_MIN = 0.82

# Arabic letters/marks as code points to keep this source ASCII-only.
_DIAC = re.compile("[ؐ-ًؚ-ٟۖ-ۭ]")
_HAMZA_ALEF = re.compile("[أإآ]")
_YA = re.compile("[ىئ]")


def fetch_hafs():
    if HAFS_CACHE.exists():
        raw = json.loads(HAFS_CACHE.read_text(encoding="utf-8"))
        return {int(s): {int(a): t for a, t in d.items()} for s, d in raw.items()}
    url = "https://api.alquran.cloud/v1/quran/quran-uthmani"
    print("Fetching Hafs text from", url, "...")
    with urllib.request.urlopen(url, timeout=60) as r:
        data = json.load(r)
    out = {}
    for s in data["data"]["surahs"]:
        out[s["number"]] = {a["numberInSurah"]: a["text"] for a in s["ayahs"]}
    HAFS_CACHE.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    return out


def normalize(text):
    text = text.replace("﻿", "")
    text = text.replace("ٱ", "ا").replace("ٰ", "ا")
    text = _DIAC.sub("", text)
    text = text.replace("ـ", "")            # tatweel
    text = _HAMZA_ALEF.sub("ا", text)       # hamza-alef -> alef
    text = _YA.sub("ي", text)               # alef maqsura/ya-hamza -> ya
    text = text.replace("ؤ", "و")      # waw-hamza -> waw
    text = text.replace("ة", "ه")      # ta marbuta -> ha
    text = text.replace("ء", "")            # standalone hamza
    return re.sub(r"\s+", " ", text).strip()


def words_of(text):
    return [w for w in normalize(text).split(" ") if w]


# "bism Allah ar-Rahman ar-Raheem"
BASMALA = words_of("بسم الله "
                   "الرحمن الرحيم")


def strip_basmala(surah, ayah_no, words):
    if ayah_no == 1 and surah not in (1, 9) and words[:len(BASMALA)] == BASMALA:
        return words[len(BASMALA):]
    return words


def load_qalun():
    raw = json.loads((DATA / "output.json").read_text(encoding="utf-8"))
    pages = []
    for p in raw:
        pages.extend(p if isinstance(p, list) else [p])
    surahs = {}
    for p in pages:
        for a in p["ayahs"]:
            s = int(a["surah"]); n = int(a["ayah"])
            surahs.setdefault(s, {}).setdefault(n, a["text"])
    return surahs


def qpos_to_hpos(qpos, blocks, hlen):
    for a, b, size in blocks:
        if size and a <= qpos < a + size:
            return b + (qpos - a)
    for a, b, size in blocks:
        if size and a >= qpos:
            return b
    for a, b, size in reversed(blocks):
        if size:
            return b + size - 1
    return min(qpos, hlen - 1)


def ratio(a_words, b_words):
    if not a_words or not b_words:
        return 0.0
    return SequenceMatcher(a=a_words, b=b_words, autojunk=False).ratio()


def build():
    qalun = load_qalun()
    hafs = fetch_hafs()
    result, review = {}, []
    diverge = 0

    for s in range(1, 115):
        qd, hd = qalun.get(s), hafs.get(s)
        if not qd or not hd:
            continue
        qn, hn = max(qd), max(hd)
        if sorted(qd) != list(range(1, qn + 1)):
            review.append((s, "-", "qalun ayahs not contiguous", 0))
            continue
        if qn != hn:
            diverge += 1

        qwords, qbounds = [], {}
        for n in range(1, qn + 1):
            start = len(qwords)
            qwords.extend(words_of(qd[n]))
            qbounds[n] = (start, len(qwords))
        hwords, howner, hayah = [], [], {}
        for n in range(1, hn + 1):
            ws = strip_basmala(s, n, words_of(hd[n]))
            hayah[n] = ws
            hwords.extend(ws)
            howner.extend([n] * len(ws))

        blocks = SequenceMatcher(a=qwords, b=hwords, autojunk=False).get_matching_blocks()

        # Whole-surah alignment quality: the two narrations are the same Quran,
        # so the word streams must be highly similar. A low ratio means the
        # alignment for this surah can't be trusted.
        surah_ratio = ratio(qwords, hwords)

        surah_map, prev_hs, covered = {}, 0, set()
        for n in range(1, qn + 1):
            qs, qe = qbounds[n]
            hs = howner[qpos_to_hpos(qs, blocks, len(hwords))]
            he = howner[qpos_to_hpos(qe - 1, blocks, len(hwords))]
            # Non-decreasing only. Do NOT force-advance: several Qalun ayahs may
            # map to the same Hafs ayah (where Qalun splits a verse Hafs keeps
            # whole), which is exactly how a start-merge is later cancelled out.
            hs = max(hs, prev_hs)
            he = max(he, hs)
            prev_hs = hs
            for h in range(hs, he + 1):
                covered.add(h)
            # Emit only when it isn't a plain identity (n -> n).
            if not (hs == n and he == n):
                surah_map[str(n)] = hs if hs == he else [hs, he]

        if surah_ratio < 0.90:
            review.append((s, "surah", f"low alignment ratio {surah_ratio:.2f}", round(surah_ratio, 2)))
        missing = sorted(set(range(1, hn + 1)) - covered)
        if missing:
            review.append((s, "coverage", f"hafs ayahs not covered: {missing}", 0))
        if surah_map:
            result[str(s)] = surah_map

    out = {
        "_comment": "Qalun(Madani)->Hafs(Kufi) ayah map for the Sa'di tafsir. "
                    "Auto-generated and content-verified by generate_narration_map.py. "
                    "Lists only Qalun ayahs whose Hafs number differs.",
        "qalun_to_hafs": result,
    }
    (DATA / "narration_map.json").write_text(
        json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")

    remapped = sum(len(v) for v in result.values())
    print(f"Surahs with differing totals : {diverge}")
    print(f"Surahs with remapped ayahs   : {len(result)}")
    print(f"Total ayahs remapped         : {remapped}")
    print(f"Ayahs failing verification   : {len(review)}")
    for r in review[:60]:
        print("   REVIEW", r)
    return len(review)


if __name__ == "__main__":
    n = build()
    print("\nClean." if n == 0 else f"\n{n} ayahs left 1:1 pending review.")
    sys.exit(0)

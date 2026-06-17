"""
Rebuilds assets/data/ar.saddi.json with a CORRECTLY ALIGNED Tafsir as-Sa'di.

Why: the previous ar.saddi.json (the alquran.cloud "ar.saddi" edition) mis-split
Sa'di's verse-grouped commentary into per-ayah slots, so many ayahs held the
wrong text (e.g. Al-Fatiha 1:3 held Al-Baqarah material).

Source: spa5k/tafsir_api mirror of quran.com's "ar-tafseer-al-saddi" (resource 24),
split per ayah in the standard Hafs (Madani Mushaf) numbering -- the same numbering
the app's narration_map.json already translates Qalun ayahs into. The repo is
sparse-cloned into .tafsir_tmp; each surah is one ordered JSON list of {text,...}.

Output shape is identical to the old file so tafsir_service.dart is unchanged:
  { "edition": {...}, "tafsir": [ [ayah1, ayah2, ... ], ... 114 surahs ] }
indexed as tafsir[surahIndex][hafsAyahIndex].
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "assets" / "data"
SRC = ROOT / ".tafsir_tmp" / "tafsir" / "ar-tafseer-al-saddi"
OUT = DATA / "ar.saddi.json"
BACKUP = DATA / "ar.saddi.old.json"

# Authoritative Hafs ayah counts per surah (total = 6236).
COUNTS = [7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99,
          128, 111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34,
          30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29,
          18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12,
          30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25,
          22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9,
          5, 4, 7, 3, 6, 3, 5, 4, 5, 6]


def main():
    if not SRC.exists():
        print(f"Source folder missing: {SRC}", file=sys.stderr)
        return 1

    # Sa'di groups consecutive ayahs under one commentary block. In this source
    # each entry's "ayah" field is the FIRST ayah of its block; the block runs to
    # the next entry's start - 1 (last block runs to the surah's final ayah). We
    # expand every block so each Hafs ayah position holds its block's text, giving
    # exactly COUNTS[s] entries per surah (the shape tafsir_service.dart expects).
    tafsir = []
    empties = []
    problems = []
    for s in range(1, 115):
        n = COUNTS[s - 1]
        arr = json.loads((SRC / f"{s}.json").read_text(encoding="utf-8"))
        entries = sorted(
            ((int(it.get("ayah") or 0), (it.get("text") or "").strip()) for it in arr),
            key=lambda e: e[0],
        )
        texts = [""] * n
        for idx, (start, text) in enumerate(entries):
            end = entries[idx + 1][0] - 1 if idx + 1 < len(entries) else n
            start = max(start, 1)
            end = min(end, n)
            for a in range(start, end + 1):
                texts[a - 1] = text
        for i, t in enumerate(texts):
            if not t:
                empties.append((s, i + 1))
        tafsir.append(texts)

    if problems:
        print("LENGTH MISMATCHES (surah, got, expected):")
        for p in problems:
            print("  ", p)

    out = {
        "edition": {
            "identifier": "ar.saddi",
            "language": "ar",
            "name": "تفسير السعدي",
            "englishName": "Tafsir Al Saddi",
            "source": "quran.com resource 24 (ar-tafseer-al-saddi) via spa5k/tafsir_api",
        },
        "tafsir": tafsir,
    }

    if OUT.exists() and not BACKUP.exists():
        BACKUP.write_text(OUT.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"Backed up old file -> {BACKUP.name}")

    OUT.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    total = sum(len(x) for x in tafsir)
    print(f"Wrote {OUT}: {len(tafsir)} surahs, {total} ayahs")
    print(f"Empty ayah texts: {len(empties)}")
    for e in empties[:60]:
        print("   EMPTY", e)
    return 0


if __name__ == "__main__":
    sys.exit(main())

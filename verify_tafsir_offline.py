"""
OFFLINE verifier for the Qalun->Hafs tafsir mapping. Uses ONLY the bundled
assets (no network, no surahquran.com):

  - assets/data/output.json        (app Qalun ayah text)
  - assets/data/ar.saddi.json      (Sa'di tafsir; quotes each verse in {braces})
  - assets/data/narration_map.json (the mapping under test)

For every Qalun ayah it finds the tafsir slot whose {quoted} verse text best
matches that ayah, and compares it to where the map points. A genuine mapping
error shows up as a SMALL slot offset (±1..3); large jumps are just repeated
refrains (e.g. Ar-Rahman) and are ignored. Prints any real mismatch.

Run:  python verify_tafsir_offline.py
Exit code 0 = clean, 1 = real mismatches found.
"""
import json
import re
import sys
from difflib import SequenceMatcher
from pathlib import Path

DATA = Path(__file__).resolve().parent / "assets" / "data"

_DIAC = re.compile("[ؐ-ًؚ-ٟۖ-ۭ]")
_HZA = re.compile("[أإآ]")
_YA = re.compile("[ىئ]")


def norm(t):
    t = t.replace("﻿", "").replace("ٱ", "ا").replace("ٰ", "ا")
    t = _DIAC.sub("", t).replace("ـ", "")
    t = _HZA.sub("ا", t)
    t = _YA.sub("ي", t).replace("ؤ", "و").replace("ة", "ه").replace("ء", "")
    return re.sub(r"\s+", " ", t).strip()


def words(t):
    return [w for w in norm(t).split(" ") if w]


def contain(quote_w, ayah_w):
    """Fraction of quote words found, in order, inside the ayah words."""
    if len(quote_w) < 4:
        return -1.0
    matched = sum(b.size for b in
                  SequenceMatcher(a=quote_w, b=ayah_w, autojunk=False).get_matching_blocks())
    return matched / len(quote_w)


def load():
    raw = json.loads((DATA / "output.json").read_text(encoding="utf-8"))
    pages = []
    for p in raw:
        pages.extend(p if isinstance(p, list) else [p])
    app = {}
    for p in pages:
        for a in p["ayahs"]:
            app.setdefault(int(a["surah"]), {}).setdefault(int(a["ayah"]), a["text"])
    taf = json.loads((DATA / "ar.saddi.json").read_text(encoding="utf-8"))["tafsir"]
    nmap = json.loads((DATA / "narration_map.json").read_text(encoding="utf-8"))["qalun_to_hafs"]
    return app, taf, nmap


def targets(nmap, s, n):
    v = nmap.get(str(s), {}).get(str(n))
    if v is None:
        return [n]
    return [v] if isinstance(v, int) else list(range(v[0], v[1] + 1))


def main():
    app, taf, nmap = load()
    errors = []
    for s in range(1, 115):
        if s not in app:
            continue
        slots = taf[s - 1]
        quotes = [words(" ".join(re.findall(r"\{([^}]*)\}", str(x)))) for x in slots]
        for n in sorted(app[s]):
            aw = words(app[s][n])
            scored = [(contain(quotes[k], aw), k + 1) for k in range(len(quotes))]
            best_c, best_slot = max(scored) if scored else (-1, n)
            if best_c < 0.85:
                continue  # no slot quotes this ayah clearly enough to judge
            tg = targets(nmap, s, n)
            if best_slot in tg:
                continue  # map agrees with the quote
            # Ignore far-away matches: those are repeated refrains, not errors.
            if min(abs(best_slot - t) for t in tg) > 3:
                continue
            mc = max((contain(quotes[t - 1], aw) for t in tg if 1 <= t <= len(quotes)),
                     default=-1)
            if best_c > mc + 0.2:
                errors.append((s, n, tg, best_slot, round(best_c, 2), round(mc, 2)))

    if not errors:
        print("CLEAN: every ayah's tafsir matches the verse it is shown for.")
        return 0
    print(f"REAL MISMATCHES: {len(errors)}")
    for s, n, tg, best, bc, mc in errors:
        print(f"  surah {s} ayah {n}: map -> {tg} (match {mc}) but slot {best} quotes it (match {bc})")
    return 1


if __name__ == "__main__":
    sys.exit(main())

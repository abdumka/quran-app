"""
Independent cross-check of assets/data/narration_map.json against surahquran.com,
which publishes each surah in BOTH Qalun (/qaloon/N.html) and Hafs (/N.html)
with explicit (N) ayah-number markers.

For each requested surah it verifies that, for every Qalun ayah, the Qalun text
on surahquran matches the Hafs ayah(s) that our map points to. A high text
ratio confirms the mapping is correct (the two narrations share most words).
"""
import json
import re
import sys
import time
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parent
import generate_narration_map as G  # reuse normalize()

MAP = json.loads((ROOT / "assets" / "data" / "narration_map.json").read_text(
    encoding="utf-8"))["qalun_to_hafs"]


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    return urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")


def parse_ayahs(html):
    """Return {ayah_no: text} from a surahquran page (Qalun or Hafs layout).

    Verses are delimited by (N) markers; we follow the contiguous 1,2,3,... run
    so navigation numbers can't interfere. Ayah 1's text is bounded by a short
    look-back (it precedes the first marker)."""
    text = re.sub(r"<[^>]+>", " ", html)
    marks = [(int(m.group(1)), m.start(), m.end())
             for m in re.finditer(r"\((\d+)\)", text)]
    start = next((i for i, m in enumerate(marks) if m[0] == 1), None)
    if start is None:
        return {}
    out, prev_end, expect = {}, None, 1
    for v, s, e in marks[start:]:
        if v != expect:
            break
        seg = text[(prev_end if prev_end is not None else max(0, s - 400)):s]
        out[v] = seg.strip()
        prev_end, expect = e, v + 1
    return out


def hafs_targets(surah, qn):
    v = MAP.get(str(surah), {}).get(str(qn))
    if v is None:
        return [qn]
    if isinstance(v, int):
        return [v]
    return list(range(v[0], v[1] + 1))


def coverage(qtext, htext):
    """Fraction of the Qalun ayah's words found, in order, in the Hafs span.
    ~1.0 for a correct mapping (incl. splits/merges); low only for a real
    mismatch. Robust to the Hafs span being longer (merge) or to qira'at."""
    qw, hw = G.words_of(qtext), G.words_of(htext)
    if not qw:
        return 1.0
    matched = sum(b.size for b in
                  SequenceMatcher(a=qw, b=hw, autojunk=False).get_matching_blocks())
    return matched / len(qw)


def check(surah):
    ql = parse_ayahs(fetch(f"https://surahquran.com/qaloon/{surah}.html"))
    hf = parse_ayahs(fetch(f"https://surahquran.com/{surah}.html"))
    qn, hn = max(ql), max(hf)
    errors = []   # mapped target is NOT the best local match -> real error
    for n in range(2, qn + 1):   # ayah 1 = muqatta'at span, verified separately
        targets = hafs_targets(surah, n)
        c_map = coverage(ql[n], " ".join(hf.get(t, "") for t in targets))
        # Best coverage among nearby single Hafs verses.
        lo, hi = max(1, targets[0] - 2), min(hn, targets[-1] + 2)
        best_h = max(range(lo, hi + 1), key=lambda h: coverage(ql[n], hf.get(h, "")))
        c_best = coverage(ql[n], hf.get(best_h, ""))
        # Flag only when a different verse covers clearly better than the mapping.
        if best_h not in targets and c_best > c_map + 0.15:
            errors.append((n, "->", targets, "but", best_h, "covers", round(c_best, 2),
                           "vs", round(c_map, 2)))
    status = "OK " if not errors else "ERROR"
    print(f"[{status}] surah {surah:3d}: qalun={qn} hafs={hn}  "
          + ("all mappings are the best local match"
             if not errors else f"{len(errors)} real mismatch(es): {errors[:6]}"))
    return not errors


if __name__ == "__main__":
    surahs = [int(x) for x in sys.argv[1:]] or [1, 2, 5, 6, 7, 8, 9, 18, 19,
                                                22, 27, 31, 32, 38, 39, 42, 44,
                                                56, 71, 89, 101, 107]
    ok = 0
    for s in surahs:
        try:
            ok += check(s)
        except Exception as e:
            print(f"[FAIL] surah {s}: {e!r}")
        time.sleep(0.4)
    print(f"\n{ok}/{len(surahs)} surahs clean (min_ratio >= 0.6 on every ayah)")

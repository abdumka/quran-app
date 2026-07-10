# -*- coding: utf-8 -*-
"""Builds the thumn -> (startSurah, startAyah) boundary table.

Each of the 480 athman in assets/data/athman_page_hizb.csv is defined by its
start page and its opening words. This script pins every thumn to the exact
ayah (in the app's own output.json numbering) whose text begins with those
words, so the audio layer can repeat a whole thumn precisely -- including
thumns that start mid-page and pages that contain two thumn starts.

Matching strategy:
  * Normalize both texts to a bare consonant stream: strip harakat/quranic
    marks, unify hamza/alef/ya variants, drop spaces, collapse doubled
    letters (handles the mushaf's fused orthography).
  * Candidates are the ayahs on the thumn's start page (fallback: +/-1 page).
  * Score = length of the common prefix of the two streams; best score wins.
  * Enforce that the 480 results are strictly increasing in (surah, ayah);
    any violation or low-score match is reported for manual review.

Output: lib/thumn_data.dart regenerated with startSurah/startAyah fields.
"""
import csv
import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def norm(s):
    out = []
    for c in s:
        o = ord(c)
        if 0x0600 <= o <= 0x06FF and (
            (0x064B <= o <= 0x065F)
            or o in (0x0670, 0x0640)
            or (0x06D6 <= o <= 0x06ED)
            or (0x0610 <= o <= 0x061A)
        ):
            continue
        out.append(c)
    s = "".join(out)
    for a, b in [
        ("أ", "ا"),  # أ -> ا
        ("إ", "ا"),  # إ -> ا
        ("آ", "ا"),  # آ -> ا
        ("ٱ", "ا"),  # ٱ -> ا
        ("ى", "ي"),  # ى -> ي
        ("ے", "ي"),  # yeh barree (this mushaf's final ya) -> ي
        ("ة", "ه"),  # ة -> ه
        ("ؤ", "و"),  # ؤ -> و
        ("ئ", "ي"),  # ئ -> ي
        ("ء", ""),        # ء removed
    ]:
        s = s.replace(a, b)
    # Drop alef entirely: this mushaf's orthography writes many alefs as
    # superscript marks (ثَلَٰثِين) or hamza carriers (يَسْـَٔلُونَك) that the
    # mark-stripping above removes, so plain-text alefs never line up.
    s = s.replace("ا", "")
    # keep only arabic letters
    s = "".join(c for c in s if "ء" <= c <= "ي")
    # collapse doubled adjacent letters (يا + أيها -> يايها in the mushaf)
    out = []
    for c in s:
        if not out or out[-1] != c:
            out.append(c)
    return "".join(out)


def common_prefix_len(a, b):
    n = min(len(a), len(b))
    i = 0
    while i < n and a[i] == b[i]:
        i += 1
    return i


def substr_score(key, na):
    """Longest prefix of [key] that appears as a substring of [na], +2 bonus
    when it sits at the very start of the ayah (a true ayah-start thumn).
    Handles thumns that begin mid-ayah: the containing ayah still scores the
    full key length."""
    best = 0
    at_start = False
    for k in range(min(len(key), len(na)), 2, -1):
        idx = na.find(key[:k])
        if idx != -1:
            best = k
            at_start = idx == 0
            break
    return best + (2 if at_start and best else 0)


def main():
    # ---- load ayah data (output.json is a nested list of page objects) ----
    with io.open(os.path.join(ROOT, "assets", "data", "output.json"), encoding="utf-8") as f:
        raw = json.load(f)
    flat = []
    for it in raw:
        if isinstance(it, list):
            flat.extend(it)
        else:
            flat.append(it)
    pages = {p["page"]: p for p in flat if isinstance(p, dict) and "page" in p}

    # page -> [(surah, ayah, normtext)]
    norm_pages = {
        pg: [(a["surah"], a["ayah"], norm(a["text"])) for a in pages[pg]["ayahs"]]
        for pg in pages
    }

    # ---- load thumns ----
    thumns = []
    with io.open(os.path.join(ROOT, "assets", "data", "athman_page_hizb.csv"), encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            thumns.append(
                (
                    int(row["رقم الثمن"]),  # رقم الثمن
                    row["الثمن"],                            # الثمن
                    int(row["الصفحة"]),                 # الصفحة
                    int(row["الحزب"]),                       # الحزب
                )
            )
    thumns.sort(key=lambda t: t[0])
    assert len(thumns) == 480, len(thumns)

    # ---- match each thumn to its start ayah ----
    # The mushaf sometimes writes ئ as a combining hamza mark (stripped by
    # norm), while the CSV uses the full letter; try both key spellings.
    def keys_for(text):
        ks = {norm(text), norm(text.replace("ئ", ""))}
        return [k for k in ks if k]

    def best_substr_score(text, na):
        return max(substr_score(k, na) for k in keys_for(text))

    results = {}   # num -> (surah, ayah, score, page_used)
    problems = []
    for num, text, pg, hizb in thumns:
        key = norm(text)
        best = None  # (score, surah, ayah, page_used)
        for pp in (pg, pg + 1, pg - 1):
            if pp not in norm_pages:
                continue
            for (s, a, na) in norm_pages[pp]:
                sc = best_substr_score(text, na)
                # require a meaningful overlap: whole key or >= 8 letters
                if sc < min(len(key), 8):
                    continue
                cand = (sc, s, a, pp)
                if best is None or cand[0] > best[0]:
                    best = cand
            if best is not None and best[0] >= min(len(key) + 2, 12):
                break  # good enough on this page; don't drift further
        if best is None:
            problems.append((num, pg, text[:40], "NO MATCH"))
        else:
            results[num] = (best[1], best[2], best[0], best[3])

    # ---- second pass: sandwich unmatched thumns between resolved neighbors ----
    # A thumn's start ayah must lie strictly after the previous thumn's start
    # and strictly before the next thumn's start (boundaries are ordered), and
    # it sits on the thumn's start page. Within that window, take the best
    # common-prefix score with no minimum-length requirement.
    def neighbor(num, step):
        n = num + step
        while 1 <= n <= 480:
            if n in results:
                return (results[n][0], results[n][1])
            n += step
        return (0, 0) if step < 0 else (999, 999)

    still = []
    for (num, pg, snippet, why) in problems:
        text = next(t[1] for t in thumns if t[0] == num)
        key = norm(text)
        lo = neighbor(num, -1)
        hi = neighbor(num, +1)
        best = None
        for pp in (pg, pg + 1, pg - 1):
            if pp not in norm_pages:
                continue
            for (s, a, na) in norm_pages[pp]:
                if not (lo < (s, a) < hi):
                    continue
                sc = best_substr_score(text, na)
                cand = (sc, s, a, pp)
                if best is None or cand[0] > best[0]:
                    best = cand
            if best is not None and best[0] >= 6:
                break
        if best is not None and best[0] >= 5:
            results[num] = (best[1], best[2], best[0], best[3])
        else:
            still.append((num, pg, snippet, "no candidate in window" if best is None else "score %d" % best[0]))
    problems = still

    # ---- verify strict monotonic order over all matched ----
    prev = (0, 0)
    order_bad = []
    for num in sorted(results):
        s, a, sc, pp = results[num]
        if (s, a) <= prev:
            order_bad.append((num, prev, (s, a)))
        prev = (s, a)

    # report goes to a UTF-8 file (Windows console can't print Arabic)
    rep = io.open(os.path.join(ROOT, "tools", "thumn_boundaries_report.txt"), "w", encoding="utf-8")
    rep.write("matched %d / %d\n" % (len(results), len(thumns)))
    rep.write("order violations: %d\n" % len(order_bad))
    for x in order_bad:
        rep.write("  ORDER %s\n" % (x,))
    for x in problems:
        rep.write("  PROBLEM %s\n" % (x,))
    # low-score matches for manual eyeballing
    rep.write("low-score matches (score < 10):\n")
    for num in sorted(results):
        s, a, sc, pp = results[num]
        if sc < 10:
            text = next(t[1] for t in thumns if t[0] == num)
            rep.write("  thumn %d p%d score %d -> %d:%d  [%s]\n" % (num, next(t[2] for t in thumns if t[0] == num), sc, s, a, text[:50]))
    rep.close()

    print("matched %d / %d" % (len(results), len(thumns)))
    print("order violations: %d" % len(order_bad))
    print("problems: %d  (see tools/thumn_boundaries_report.txt)" % len(problems))
    if problems or order_bad:
        print("NOT WRITING dart file -- fix problems first")
        sys.exit(1)

    # ---- regenerate lib/thumn_data.dart ----
    out = io.StringIO()
    out.write("// Thumn (ثمن) index data — 480 athman.\n")
    out.write("// Each entry: number (1-480), starting text, page (real 1-based), hizb (1-60),\n")
    out.write("// and the exact starting ayah (surah/ayah in the app's output.json numbering).\n")
    out.write("// Generated by tools/build_thumn_boundaries.py from\n")
    out.write("// assets/data/athman_page_hizb.csv + assets/data/output.json — do not edit by hand.\n")
    out.write("class ThumnEntry {\n")
    out.write("  final int number;\n")
    out.write("  final String text;\n")
    out.write("  final int page;\n")
    out.write("  final int hizb;\n\n")
    out.write("  /// Surah of the ayah this thumn starts at.\n")
    out.write("  final int startSurah;\n\n")
    out.write("  /// Ayah (within [startSurah]) this thumn starts at.\n")
    out.write("  final int startAyah;\n\n")
    out.write("  const ThumnEntry(this.number, this.text, this.page, this.hizb,\n")
    out.write("      this.startSurah, this.startAyah);\n")
    out.write("}\n\n")
    out.write("const List<ThumnEntry> thumnEntries = [\n")
    for num, text, pg, hizb in thumns:
        s, a, sc, pp = results[num]
        out.write("  ThumnEntry(%d, '%s', %d, %d, %d, %d),\n" % (num, text, pg, hizb, s, a))
    out.write("];\n")

    with io.open(os.path.join(ROOT, "lib", "thumn_data.dart"), "w", encoding="utf-8", newline="\n") as f:
        f.write(out.getvalue())
    print("wrote lib/thumn_data.dart")


if __name__ == "__main__":
    main()

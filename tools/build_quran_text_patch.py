#!/usr/bin/env python3
"""Build tools/content_updates/quran_text_patch.json: the Qur'an text
corrections the app downloads without a store release (item `quran_text` of
lib/services/content_update_service.dart, rules in lib/services/quran_text_patch.dart).

How it works: fix the text in assets/data/output.json as usual (only the places
the owner listed). This script compares that file with the output.json of every
RELEASE whose build reads the patch (a "base", a git commit) and lists every
ayah whose text differs, with the texts it may replace ("from"). The list is
therefore cumulative by construction: one file serves every such build.

Rules (the app refuses the whole file if one entry breaks them):
  * the same ayat on both sides (no ayah added, removed or renumbered);
  * the same number of words in the ayah (words split on one space);
  * whether the ayah opens with the basmala does not change;
  * only the characters the mushaf text uses (no digits, no ayah-end sign).
Anything else, and any change to how a word is READ (Tasmee judges by the
phonemes in page_phonemes.json, which the patch does not change), needs a
release and the derived-artifact rebuild.

Usage:
    python tools/build_quran_text_patch.py                  # show, write nothing
    python tools/build_quran_text_patch.py --write          # write the file
    python tools/build_quran_text_patch.py --base <commit>  # add a release base
    python tools/build_quran_text_patch.py --out <file>     # write elsewhere (tests)
The bases are recorded in quran_text_bases.json (not published), so --base is
given once per release. "ver" goes up by one whenever the list changes; publish
with tools/publish_content_updates.py (--dry-run first).
"""
import argparse
import io
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "assets" / "data" / "output.json"
PATCH = ROOT / "tools" / "content_updates" / "quran_text_patch.json"
# The release bases live beside the patch, not in it: the published file
# changes only when the corrections do.
BASES = ROOT / "tools" / "content_updates" / "quran_text_bases.json"
MAX_ENTRIES = 1000  # QuranTextPatch.maxEntries
BASMALA = ["بسم", "الله", "الرحمن", "الرحيم"]
TASHKEEL = re.compile("[ؐ-ًؚ-ٰٟۖ-ۭـ]")


def allowed_char(u):
    """QuranTextPatch.allowedChar."""
    return (u == 0x20 or 0x0621 <= u <= 0x065F or u == 0x0670 or u == 0x06D2
            or 0x06D6 <= u <= 0x06DC or 0x06DF <= u <= 0x06ED)


def well_formed(text):
    """QuranTextPatch.wellFormed."""
    if not isinstance(text, str) or not text or text[0] == " " or text[-1] == " ":
        return False
    if "  " in text:
        return False
    return all(allowed_char(ord(c)) for c in text)


def word_count(text):
    return len(text.split(" "))


def opens_with_basmala(text):
    words = text.split(" ")
    if len(words) < len(BASMALA):
        return False
    return all(TASHKEEL.sub("", w).replace("ٱ", "ا") == b for w, b in zip(words, BASMALA))


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def check_patch(data):
    """The app's QuranTextPatch.parse, in Python. Returns a list of problems."""
    if not isinstance(data, dict) or not is_int(data.get("ver")):
        return ["no integer ver"]
    patches = data.get("patches")
    if not isinstance(patches, list):
        return ["no patches list"]
    problems = []
    if len(patches) > MAX_ENTRIES:
        problems.append(f"{len(patches)} patches, more than {MAX_ENTRIES}")
    seen = set()
    for p in patches:
        if not isinstance(p, dict):
            problems.append("an entry is not an object")
            continue
        s, a, text, frm = p.get("surah"), p.get("ayah"), p.get("text"), p.get("from")
        where = f"{s}:{a}"
        if not is_int(s) or not 1 <= s <= 114:
            problems.append(f"{where}: bad surah")
        if not is_int(a) or not 1 <= a <= 286:
            problems.append(f"{where}: bad ayah")
        if (s, a) in seen:
            problems.append(f"{where}: listed twice")
        seen.add((s, a))
        if not well_formed(text):
            problems.append(f"{where}: text has a character or spacing the app refuses")
            continue
        if not isinstance(frm, list) or not frm:
            problems.append(f'{where}: no "from"')
            continue
        for old in frm:
            if not well_formed(old) or old == text:
                problems.append(f'{where}: a "from" text is malformed or equal to the fix')
            elif word_count(old) != word_count(text):
                problems.append(f"{where}: word count {word_count(old)} -> {word_count(text)}")
            elif opens_with_basmala(old) != opens_with_basmala(text):
                problems.append(f"{where}: changes whether the ayah opens with the basmala")
    return problems


def ayahs_of(raw):
    """({(surah, ayah): text}, [keys listed twice]) of an output.json."""
    out, dup = {}, []

    def walk(x):
        for item in x:
            if isinstance(item, list):
                walk(item)
            else:
                for a in item["ayahs"]:
                    k = (a["surah"], a["ayah"])
                    if k in out:
                        dup.append(k)
                    out[k] = a["text"]

    walk(json.loads(raw))
    return out, dup


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True).stdout


def resolve(ref):
    return git("rev-parse", "--verify", f"{ref}^{{commit}}").decode().strip()


def current_ayahs():
    current, dup = ayahs_of(OUTPUT.read_bytes())
    if dup:
        sys.exit(f"ABORT: output.json lists {dup[:3]} twice")
    return current


def build_entries(bases, current):
    """The entries for these base commits against the current text, or exit."""
    texts_by_key = {k: set() for k in current}
    for commit in bases:
        old, dup = ayahs_of(git("show", f"{commit}:assets/data/output.json"))
        if dup:
            sys.exit(f"ABORT: base {commit[:10]} lists {dup[:3]} twice")
        if set(old) != set(current):
            gone = sorted(set(old) - set(current))[:5]
            new = sorted(set(current) - set(old))[:5]
            sys.exit(f"ABORT: the ayat differ from base {commit[:10]} (only in base: {gone}, "
                     f"only now: {new}). Numbering changes need a release, not a patch.")
        for k, t in old.items():
            if t != current[k]:
                texts_by_key[k].add(t)
    return [
        {"surah": k[0], "ayah": k[1], "text": current[k], "from": sorted(olds)}
        for k, olds in sorted(texts_by_key.items()) if olds
    ]


def word_diff(old, new):
    ow, nw = old.split(" "), new.split(" ")
    if len(ow) != len(nw):
        return [f"word count {len(ow)} -> {len(nw)}"]
    return [f"word {i + 1}: {o} -> {n}" for i, (o, n) in enumerate(zip(ow, nw)) if o != n]


def render(data):
    """One entry per line, so a change reads clearly in git."""
    lines = [json.dumps(p, ensure_ascii=False) for p in data["patches"]]
    head = '{"ver": %d, "patches": [' % data["ver"]
    if not lines:
        return head + "]}\n"
    return head + "\n  " + ",\n  ".join(lines) + "\n]}\n"


def load_patch():
    if PATCH.exists():
        return json.loads(PATCH.read_text(encoding="utf-8"))
    return {"ver": 0, "patches": []}


def load_bases():
    if BASES.exists():
        return json.loads(BASES.read_text(encoding="utf-8"))["bases"]
    return []


def expected_entries():
    """What the patch must list for the current output.json and the recorded
    bases (the publish tool refuses a file that differs)."""
    return build_entries([b["commit"] for b in load_bases()], current_ayahs())


def main():
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    ap = argparse.ArgumentParser(description="Build the quran_text server patch.")
    ap.add_argument("--base", action="append", default=[],
                    help="a release commit whose build reads the patch")
    ap.add_argument("--write", action="store_true", help="write the patch file")
    ap.add_argument("--out", type=Path, help="write here instead (the bases file is left alone)")
    args = ap.parse_args()

    recorded = load_patch()
    bases = load_bases()
    known = len(bases)
    for ref in args.base:
        commit = resolve(ref)
        if all(b["commit"] != commit for b in bases):
            bases.append({"ref": ref, "commit": commit})
    if not bases:
        print("No release base yet: the patch stays empty until a release that reads it exists.")
        print("After that release: --base <its commit> --write")
        return

    entries = build_entries([b["commit"] for b in bases], current_ayahs())
    ver = recorded.get("ver", 0)
    if entries != recorded.get("patches"):
        ver += 1
    data = {"ver": ver, "patches": entries}

    print("bases: " + ", ".join(f"{b['commit'][:10]} ({b['ref']})" for b in bases))
    print(f"{len(entries)} ayat differ from a base; ver {recorded.get('ver', 0)} -> {ver}")
    for e in entries:
        for old in e["from"]:
            print(f"  {e['surah']}:{e['ayah']}  " + "; ".join(word_diff(old, e["text"])))
    problems = check_patch(data)
    if problems:
        print("REFUSED, the app would reject this file:")
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print("All rules pass. Check that every place above is one the owner listed.")
    print("Tasmee still judges these words by each build's page_phonemes.json: "
          "a fix that changes how a word is read needs a release.")
    out = args.out or (PATCH if args.write else None)
    if out is None:
        print("(nothing written; add --write)")
        return
    out.write_text(render(data), encoding="utf-8", newline="\n")
    assert json.loads(out.read_text(encoding="utf-8")) == data
    print(f"written: {out}")
    if args.out is None and len(bases) != known:
        BASES.write_text(json.dumps({"bases": bases}, ensure_ascii=False, indent=1) + "\n",
                         encoding="utf-8", newline="\n")
        print(f"written: {BASES}")


if __name__ == "__main__":
    main()

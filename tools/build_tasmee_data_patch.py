#!/usr/bin/env python3
"""Build tools/content_updates/tasmee_data_patch.json: the Tasmee pronunciation
fixes the app downloads without a store release (item `tasmee_data` of
lib/services/content_update_service.dart, rules in
lib/services/tasmee_data_patch.dart).

How it works: fix assets/data/page_phonemes.json / phoneme_lexicon.json as
usual. This script compares them with the files of every RELEASE whose build
reads the patch (a "base", a git commit) and lists:
  * every ayah whose words differ from some base (the whole ayah, as now);
  * lexiconAdd / lexiconRemove: what turns any base's lexicon into the
    current one.
The list is cumulative by construction: one file serves every such build.

Rules (the app refuses the whole file if one entry breaks them, and skips an
ayah whose page or word count differs from its bundle):
  * an ayah stays on the same page with the same number of words;
  * each word has the shape of page_phonemes.json
    [text, phon, tanween, taMarbuta 0/1, hafsAlt, wasl 0/1, alts?, accept?].
Joining or splitting words, or moving an ayah to another page, needs a release.

Usage:
    python tools/build_tasmee_data_patch.py                  # show, write nothing
    python tools/build_tasmee_data_patch.py --write          # write the file
    python tools/build_tasmee_data_patch.py --base <commit>  # add a release base
    python tools/build_tasmee_data_patch.py --out <file>     # write elsewhere (tests)
The bases are recorded in tasmee_data_bases.json (not published), so --base is
given once per release (the commit the store build was made from). "ver" goes
up by one whenever the content changes; publish with
tools/publish_content_updates.py (--dry-run first). When a release bundles the
current files, raise ContentUpdateService.bundledVersions['tasmee_data'] to
this file's "ver".
"""
import argparse
import io
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PHONEMES = "assets/data/page_phonemes.json"
LEXICON = "assets/data/phoneme_lexicon.json"
PATCH = ROOT / "tools" / "content_updates" / "tasmee_data_patch.json"
BASES = ROOT / "tools" / "content_updates" / "tasmee_data_bases.json"
MAX_AYAHS = 6236          # TasmeeDataPatch.maxAyahs
MAX_LEXICON = 30000       # TasmeeDataPatch.maxLexiconChanges
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


def valid_word(w):
    """TasmeeDataPatch.validWord."""
    if not isinstance(w, list) or not 6 <= len(w) <= 8:
        return False

    def s(v, non_empty=False):
        return isinstance(v, str) and len(v) <= 64 and (not non_empty or v != "")

    def bit(v):
        return v in (0, 1) and not isinstance(v, bool)

    def strings(v):
        return isinstance(v, list) and len(v) <= 32 and all(s(x, True) for x in v)

    if not s(w[0], True) or not s(w[1], True):
        return False
    if not s(w[2]) or not bit(w[3]) or not s(w[4]) or not bit(w[5]):
        return False
    if len(w) > 6 and not strings(w[6]):
        return False
    if len(w) > 7 and not strings(w[7]):
        return False
    return True


def check_patch(data, current_pages=None):
    """Every rule the app applies; with current_pages also that each ayah is on
    that page with that word count now. Returns a list of problems."""
    problems = []
    if not isinstance(data, dict) or not isinstance(data.get("ver"), int) or isinstance(data.get("ver"), bool):
        return ["no int ver"]
    ayahs = data.get("ayahs", [])
    if not isinstance(ayahs, list) or len(ayahs) > MAX_AYAHS:
        return ["bad ayahs list"]
    seen = set()
    for a in ayahs:
        if not isinstance(a, dict):
            problems.append("an ayah is not an object")
            continue
        page, key, words = a.get("page"), a.get("key"), a.get("w")
        if not isinstance(page, int) or not 1 <= page <= 604:
            problems.append(f"bad page {page}")
            continue
        try:
            s, n = (int(x) for x in key.split(":"))
            ok_key = 1 <= s <= 114 and 1 <= n <= 286 and key == f"{s}:{n}"
        except Exception:  # noqa: BLE001
            ok_key = False
        if not ok_key:
            problems.append(f"bad key {key}")
            continue
        if (page, key) in seen:
            problems.append(f"{key} twice")
        seen.add((page, key))
        if not isinstance(words, list) or not words or not all(valid_word(w) for w in words):
            problems.append(f"{key}: bad words")
            continue
        if current_pages is not None:
            now = current_pages.get(page, {}).get(key)
            if now is None:
                problems.append(f"{key} is not on page {page} now")
            elif len(now) != len(words):
                problems.append(f"{key}: {len(words)} words, the page has {len(now)}")
    for name in ("lexiconAdd", "lexiconRemove"):
        v = data.get(name, [])
        if not isinstance(v, list) or len(v) > MAX_LEXICON or not all(isinstance(x, str) and 0 < len(x) <= 64 for x in v):
            problems.append(f"bad {name}")
    if set(data.get("lexiconAdd", [])) & set(data.get("lexiconRemove", [])):
        problems.append("an entry is both added and removed")
    return problems


def pages_of(raw):
    """{page: {key: words}} of a page_phonemes.json."""
    return {p["page"]: {a["key"]: a["w"] for a in p["ayahs"]} for p in json.loads(raw)}


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True).stdout


def resolve(ref):
    return git("rev-parse", "--verify", f"{ref}^{{commit}}").decode().strip()


def current():
    return (pages_of((ROOT / PHONEMES).read_bytes()),
            json.loads((ROOT / LEXICON).read_bytes()))


def build(bases, pages, lexicon):
    """(ayah entries, lexiconAdd, lexiconRemove, warnings) for these bases."""
    differ = set()
    warnings = []
    lex_now = set(lexicon)
    add, remove = set(), set()
    for commit in bases:
        old_pages = pages_of(git("show", f"{commit}:{PHONEMES}"))
        old_lex = set(json.loads(git("show", f"{commit}:{LEXICON}")))
        add |= lex_now - old_lex
        remove |= old_lex - lex_now
        for page, ayahs in pages.items():
            for key, words in ayahs.items():
                old = old_pages.get(page, {}).get(key)
                if old is None:
                    warnings.append(f"{key} is not on page {page} in base {commit[:10]}: needs a release there")
                    continue
                if old == words:
                    continue
                if len(old) != len(words):
                    warnings.append(f"{key}: word count {len(old)} -> {len(words)} vs base {commit[:10]}: "
                                    "the app keeps its bundle for this ayah there")
                differ.add((page, key))
    entries = [{"page": p, "key": k, "w": pages[p][k]}
               for p, k in sorted(differ, key=lambda x: (x[0], [int(n) for n in x[1].split(":")]))]
    add.discard("")
    remove.discard("")
    return entries, sorted(add), sorted(remove), warnings


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--base", action="append", default=[])
    ap.add_argument("--out")
    args = ap.parse_args()

    bases = json.loads(BASES.read_text(encoding="utf-8")) if BASES.exists() else []
    for ref in args.base:
        c = resolve(ref)
        if c not in bases:
            bases.append(c)
    if not bases:
        sys.exit("No release base yet: run with --base <commit of the store build> "
                 "once the first build that reads tasmee_data is released.")
    pages, lexicon = current()
    entries, add, remove, warnings = build(bases, pages, lexicon)
    for w in warnings:
        print("WARNING:", w)
    out = Path(args.out) if args.out else PATCH
    old = json.loads(out.read_text(encoding="utf-8")) if out.exists() else {"ver": 0}
    data = {"ver": old.get("ver", 0), "ayahs": entries, "lexiconAdd": add, "lexiconRemove": remove}
    same = {k: old.get(k) for k in ("ayahs", "lexiconAdd", "lexiconRemove")} == \
        {k: data[k] for k in ("ayahs", "lexiconAdd", "lexiconRemove")}
    if not same:
        data["ver"] = old.get("ver", 0) + 1
    problems = check_patch(data, pages)
    if problems:
        sys.exit("ABORT: " + "; ".join(problems[:10]))
    print(f"bases: {[b[:10] for b in bases]}")
    print(f"ayat: {len(entries)}, lexicon +{len(add)} -{len(remove)}, ver {data['ver']}"
          + (" (unchanged)" if same else ""))
    if not args.write:
        print("(dry run: nothing written; add --write)")
        return
    out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    if not args.out:
        BASES.write_text(json.dumps(bases, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()

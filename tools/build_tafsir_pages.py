"""
Builds the tafsir data for the app's multi-tafsir feature from the spa5k/tafsir_api
mirror of quran.com (the same source as the existing Sa'di edition).

Two kinds of output, both aligned to OUR Mushaf, not a standard one:

  * BUNDLED  (Muyassar): one file assets/data/ar.muyassar.json in the exact shape
    of ar.saddi.json — tafsir[surahIdx][hafsAyahIdx] = text. The app translates
    Qalun->Hafs at runtime (TafsirService._bundledPage), same as Sa'di.

  * ONLINE   (Ibn Kathir, Tabari, Qurtubi, Zad al-Masir): per-page files
    build/tafsir/<id>/page_NNN.json = [{"surah":s,"ayah":a,"text":"..."}], one
    entry per ayah on OUR page N, with the Qalun->Hafs mapping and multi-ayah
    joining ALREADY baked in. Upload these to R2 with mirror_tafsir_to_r2.py.

ALIGNMENT (critical):
  - Page boundaries: per-page files are generated from OUR own page->ayah data in
    assets/data/output.json (Qalun numbering). We never use a standard mushaf's
    page layout, so where our pages start/end is irrelevant — it always follows
    our data.
  - Ayah numbering: every app ayah (surah, qalunAyah) is translated to Hafs via
    assets/data/narration_map.json using hafs_ayahs_for(), a byte-for-byte port of
    TafsirService._hafsAyahsFor in Dart. Source tafaseer are Hafs-numbered.
  - Verse-grouped commentary (Tabari/Qurtubi/Ibn Kathir put several ayat under one
    block whose entry "ayah" = block start) is expanded across its range, exactly
    like rebuild_saddi.py.

The tool runs an automated alignment check over all 604 pages x every app ayah and
refuses to declare success if any app ayah fails to resolve.

Usage:
    python tools/build_tafsir_pages.py            # build every edition below
    python tools/build_tafsir_pages.py ibn_kathir # build a single edition id

Source files are fetched per-surah from the spa5k jsDelivr CDN (114 small files
per edition) and cached under .tafsir_tmp/tafsir/<folder>/ so reruns are offline.
Only a build-time dependency — the app itself never touches spa5k/jsDelivr.
"""
import html
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "assets" / "data"
TMP = ROOT / ".tafsir_tmp"
SRC_ROOT = TMP / "tafsir"
OUT_ROOT = ROOT / "build" / "tafsir"
CDN = "https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir"

# Authoritative Hafs ayah counts per surah (total = 6236) — from rebuild_saddi.py.
HAFS_COUNTS = [7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99,
               128, 111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34,
               30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29,
               18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12,
               30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25,
               22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9,
               5, 4, 7, 3, 6, 3, 5, 4, 5, 6]

# our edition id -> (display, exact spa5k folder, bundled?)
# Folder names verified against the spa5k/tafsir_api repo (= quran.com resources).
# NOTE: Zad al-Masir (Ibn al-Jawzi) is NOT published by quran.com/spa5k, so it is
# not buildable from this source. Other famous available editions can be enabled
# by adding a line here (and a matching TafsirEdition in Dart), e.g.:
#   "jalalayn": ("تفسير الجلالين", "ar-tafsir-al-jalalayn", False),
#   "baghawi":  ("تفسير البغوي",    "ar-tafsir-al-baghawi",  False),
EDITIONS = {
    "muyassar":   ("التفسير الميسر", "ar-tafsir-muyassar",    True),
    "jalalayn":   ("تفسير الجلالين", "ar-tafsir-al-jalalayn", True),
    "ibn_kathir": ("ابن كثير",       "ar-tafsir-ibn-kathir",  False),
    "tabari":     ("الطبري",         "ar-tafsir-al-tabari",   False),
    "qurtubi":    ("القرطبي",        "ar-tafseer-al-qurtubi", False),
}


def ensure_source(folder):
    """Downloads a spa5k edition's 114 per-surah files to .tafsir_tmp (cached)."""
    dest = SRC_ROOT / folder
    dest.mkdir(parents=True, exist_ok=True)
    missing = [s for s in range(1, 115) if not (dest / f"{s}.json").exists()]
    if missing:
        print(f"  fetching {len(missing)} surah files for {folder}…", flush=True)
    for s in missing:
        url = f"{CDN}/{folder}/{s}.json"
        req = urllib.request.Request(url, headers={"User-Agent": "build-tafsir"})
        data = urllib.request.urlopen(req, timeout=60).read()
        (dest / f"{s}.json").write_bytes(data)
    return dest


_TAG_BLOCK = re.compile(r"</(p|div|h[1-6]|li)\s*>", re.I)
_TAG_BR = re.compile(r"<br\s*/?>", re.I)
_TAG_ANY = re.compile(r"<[^>]+>")
_WS_INLINE = re.compile(r"[ \t]+")
_WS_NL = re.compile(r"\n{3,}")


def clean_text(t):
    """Source texts for the classical tafaseer often carry HTML; the app renders
    plain text, so flatten block tags to newlines and strip the rest."""
    if not t:
        return ""
    t = t.replace("\r", "")
    t = _TAG_BLOCK.sub("\n", t)
    t = _TAG_BR.sub("\n", t)
    t = _TAG_ANY.sub("", t)
    t = html.unescape(t)
    t = _WS_INLINE.sub(" ", t)
    t = _WS_NL.sub("\n\n", t)
    return t.strip()


def load_surah_entries(folder, surah):
    """Returns a list of (ayah:int, text:str) for one surah file, tolerating the
    few shapes spa5k uses (bare list, or {"ayahs":[…]})."""
    path = folder / f"{surah}.json"
    raw = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(raw, dict):
        raw = raw.get("ayahs") or list(raw.values())
    out = []
    for it in raw:
        if not isinstance(it, dict):
            continue
        out.append((int(it.get("ayah") or 0), clean_text(it.get("text") or "")))
    return out


def expand_to_hafs(folder):
    """Per-surah list of Hafs-ayah-indexed texts (block-expanded). Shape matches
    ar.saddi.json's `tafsir`: tafsir[surahIdx][hafsAyahIdx]."""
    tafsir = []
    for s in range(1, 115):
        n = HAFS_COUNTS[s - 1]
        entries = sorted(load_surah_entries(folder, s), key=lambda e: e[0])
        texts = [""] * n
        for idx, (start, text) in enumerate(entries):
            end = entries[idx + 1][0] - 1 if idx + 1 < len(entries) else n
            # The first block also covers any leading gap: some editions (e.g.
            # Jalalayn for surahs 84/106/109) start at ayah 2, folding ayah 1's
            # meaning into the first block — so extend it down to ayah 1 rather
            # than leaving ayah 1 blank. No effect on editions that start at 1.
            start = 1 if idx == 0 else max(start, 1)
            end = min(end, n)
            for a in range(start, end + 1):
                texts[a - 1] = text
        tafsir.append(texts)
    return tafsir


def hafs_ayahs_for(narration, surah, qalun_ayah):
    """Port of TafsirService._hafsAyahsFor (Dart). Keep in lockstep with it."""
    surah_map = narration.get(str(surah))
    if isinstance(surah_map, dict):
        v = surah_map.get(str(qalun_ayah))
        if isinstance(v, int):
            return [v]
        if isinstance(v, list) and len(v) == 2:
            start, end = int(v[0]), int(v[1])
            if end >= start:
                return list(range(start, end + 1))
    return [qalun_ayah]  # 1:1 fallback


def tafsir_for_hafs(tafsir, surah_idx, hafs_ayah):
    ai = hafs_ayah - 1
    if 0 <= surah_idx < len(tafsir) and 0 <= ai < len(tafsir[surah_idx]):
        return tafsir[surah_idx][ai]
    return ""


def load_pages():
    raw = json.loads((DATA / "output.json").read_text(encoding="utf-8"))
    pages = []
    for item in raw:
        # output.json is occasionally nested one level; flatten like QuranJsonService.
        if isinstance(item, list):
            pages.extend(item)
        else:
            pages.append(item)
    return pages


def build_online(edition_id, tafsir, pages, narration):
    """Write per-page files and return (written, empty_ayahs list)."""
    out_dir = OUT_ROOT / edition_id
    out_dir.mkdir(parents=True, exist_ok=True)
    empties = []
    written = 0
    for page in pages:
        page_no = page["page"]
        ayat = []
        for ayah in page["ayahs"]:
            s, a = ayah["surah"], ayah["ayah"]
            parts = []
            for h in hafs_ayahs_for(narration, s, a):
                part = tafsir_for_hafs(tafsir, s - 1, h)
                # Collapse consecutive identical parts: when a Qalun ayah spans
                # several Hafs ayahs inside one grouped commentary block they hold
                # the same text, and must not be repeated. Mirrors the runtime
                # join in TafsirService._bundledPage — keep the two in lockstep.
                if part.strip() and (not parts or parts[-1] != part):
                    parts.append(part)
            text = "\n\n".join(parts)
            if not text.strip():
                empties.append((page_no, s, a))
            ayat.append({"surah": s, "ayah": a, "text": text})
        (out_dir / f"page_{page_no:03d}.json").write_text(
            json.dumps(ayat, ensure_ascii=False), encoding="utf-8"
        )
        written += 1
    return written, empties


def build_bundled(edition_id, display, tafsir):
    out = {
        "edition": {
            "identifier": f"ar.{edition_id}",
            "language": "ar",
            "name": display,
            "source": "quran.com via spa5k/tafsir_api",
        },
        "tafsir": tafsir,
    }
    path = DATA / f"ar.{edition_id}.json"
    path.write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    total = sum(len(x) for x in tafsir)
    return path, total


def check_alignment(edition_id, tafsir, pages, narration):
    """Every app ayah must resolve to a valid Hafs slot; report non-empty coverage."""
    total = missing = empty = 0
    gaps = []
    for page in pages:
        for ayah in page["ayahs"]:
            s, a = ayah["surah"], ayah["ayah"]
            total += 1
            hs = hafs_ayahs_for(narration, s, a)
            resolved = [h for h in hs if 0 <= s - 1 < len(tafsir)
                        and 0 <= h - 1 < len(tafsir[s - 1])]
            if not resolved:
                missing += 1
                if len(gaps) < 40:
                    gaps.append(("UNRESOLVED", page["page"], s, a, hs))
                continue
            if not any(tafsir_for_hafs(tafsir, s - 1, h).strip() for h in resolved):
                empty += 1
                if len(gaps) < 40:
                    gaps.append(("EMPTY", page["page"], s, a, hs))
    print(f"  [{edition_id}] alignment: {total} app ayat | "
          f"unresolved={missing} empty={empty}")
    for kind, pg, s, a, hs in gaps:
        print(f"      {kind} page {pg}  {s}:{a} -> hafs {hs}")
    return missing == 0


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    pages = load_pages()
    narration = json.loads(
        (DATA / "narration_map.json").read_text(encoding="utf-8")
    ).get("qalun_to_hafs", {})

    ok_all = True
    for edition_id, (display, src_folder, bundled) in EDITIONS.items():
        if only and edition_id != only:
            continue
        print(f"[{edition_id}] source: {src_folder}", flush=True)
        folder = ensure_source(src_folder)
        tafsir = expand_to_hafs(folder)
        ok_all &= check_alignment(edition_id, tafsir, pages, narration)
        if bundled:
            path, total = build_bundled(edition_id, display, tafsir)
            print(f"  wrote {path.relative_to(ROOT)} ({total} hafs ayat)")
        else:
            written, empties = build_online(edition_id, tafsir, pages, narration)
            print(f"  wrote {written} pages -> build/tafsir/{edition_id}/ "
                  f"(app ayat with no text: {len(empties)})")

    print("\nDONE." if ok_all else "\nDONE with gaps — review the report above.")
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Generates web-player/data/*.json (the standalone audio player site's data)
from the app's own Quran data sources:

- assets/data/output.json            -> quran_text.json (shared text + ayah counts)
- assets/data/audio_ayah_map.json    -> native-scheme (naihi/qaniwah) ayah remap
- assets/data/qaniwah_continuations.json -> qaniwah breath-continuation skips
- lib/thumn_data.dart                -> thumn_index.json
- https://audio.mushaf-qaloon.com/mushaf3.html / mushaf_doukali.html
  -> hudaifi/doukali "covered ayah" data (cached under tools/_sources/ after
     first fetch so subsequent runs need no network access)

Every reciter's per-ayah audio resolution is flattened into ONE shape,
{"f": [<file stems>], "cov": <"s-a" or null>}, keyed "<surah>-<ayah>" in the
displayed (output.json) numbering, sparse (only non-default entries stored).
Adding a new reciter later = one new RECITERS entry + (if it's a genuinely new
scheme) one new build_overrides_* function.

Run from the repo root: python tools/build_web_player_data.py
"""
from __future__ import annotations

import json
import math
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets" / "data"
WEB_DATA = ROOT / "web-player" / "data"
SOURCES_CACHE = ROOT / "tools" / "_sources"

# Husary ("direct" scheme): trailing ayat past the threshold all collapse onto
# one file. Copied from lib/services/audio_service.dart's _getAudioFilesForAyah
# (the merge table there, verbatim).
HUSARY_MERGE_TABLE = [
    (5, 120, "005120"),
    (6, 165, "006165"),
    (8, 75, "008075"),
    (9, 129, "009129"),
    (13, 43, "013043"),
    (14, 52, "014052"),
    (23, 118, "023118"),
    (27, 93, "027093"),
    (47, 38, "047038"),
    (56, 96, "056096"),
    (71, 28, "071028"),
    (89, 30, "089030"),
    (91, 15, "091015"),
    (96, 19, "096019"),
    (106, 4, "106004"),
]

RECITERS = [
    {
        "id": "husary",
        "name": "محمود خليل الحصري",
        "riwaya": "رواية قالون",
        "folder": "alhosary",
        "scheme": "direct",
        "breathCombining": False,
    },
    {
        "id": "naihi",
        "name": "وليد علي النائحي",
        "riwaya": "رواية قالون",
        "folder": "Alnaihi",
        "scheme": "native",
        "breathCombining": False,
    },
    {
        "id": "qaniwah",
        "name": "الأمين محمد قنيوه",
        "riwaya": "رواية قالون",
        "folder": "qaniwah",
        "scheme": "native",
        "breathCombining": True,
    },
    # These two came from the ad-hoc single-reciter test pages. Any whose
    # ayah↔audio alignment has not been proof-listened end to end keeps an
    # "underReview" flag, which the UI renders as a "قيد المراجعة حالياً" badge.
    {
        "id": "hudaifi",
        "name": "علي بن عبدالرحمن الحذيفي",
        # The full name ellipsizes in the narrow card/dropdown slots.
        "shortName": "علي الحذيفي",
        "riwaya": "رواية قالون",
        "folder": "Hudaifi",
        "scheme": "covered",
        "coveredSourceUrl": "https://audio.mushaf-qaloon.com/mushaf3.html",
    },
    {
        "id": "doukali",
        "name": "محمد الدوكالي",
        "riwaya": "رواية قالون",
        "folder": "doukali",
        "scheme": "covered",
        "underReview": True,
        "coveredSourceUrl": "https://audio.mushaf-qaloon.com/mushaf_doukali.html",
    },
]

# Badge text shown for reciters still being reviewed.
REVIEW_LABEL = "قيد المراجعة حالياً"


def write_json(name: str, obj) -> Path:
    WEB_DATA.mkdir(parents=True, exist_ok=True)
    path = WEB_DATA / name
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))
    return path


def load_output_json() -> dict[int, dict]:
    with open(ASSETS / "output.json", encoding="utf-8") as f:
        data = json.load(f)
    # output.json's top-level array has a nesting quirk: some entries are
    # themselves lists of pages instead of a single page dict. The app's own
    # QuranJsonService._flattenIfNeeded does the same one-level flatten.
    flat = []
    for item in data:
        if isinstance(item, list):
            flat.extend(item)
        else:
            flat.append(item)

    per_surah: dict[int, dict] = {}
    for page in flat:
        for a in page["ayahs"]:
            s, n, t, name = a["surah"], a["ayah"], a["text"], a["surahName"]
            entry = per_surah.setdefault(s, {"name": name, "ayahs": {}})
            entry["ayahs"][n] = t
    return per_surah


def build_quran_text(per_surah: dict[int, dict]) -> dict[int, int]:
    surahs = []
    total = 0
    for s in sorted(per_surah):
        ayahs_map = per_surah[s]["ayahs"]
        max_a = max(ayahs_map)
        assert set(ayahs_map) == set(range(1, max_a + 1)), f"surah {s} has ayah gaps"
        ordered = [ayahs_map[a] for a in range(1, max_a + 1)]
        surahs.append(
            {
                "number": s,
                "name": per_surah[s]["name"],
                "ayahCount": max_a,
                "ayahs": ordered,
            }
        )
        total += max_a

    assert len(surahs) == 114, f"expected 114 surahs, got {len(surahs)}"
    assert total == 6214, f"expected 6214 total ayat, got {total}"
    assert surahs[1]["number"] == 2 and surahs[1]["ayahCount"] == 285, (
        "al-Baqarah ayah count regression (expected 285)"
    )
    assert surahs[113]["number"] == 114 and surahs[113]["ayahCount"] == 6, (
        "an-Nas missing/wrong — canary for the output.json flattening bug"
    )

    write_json("quran_text.json", {"surahs": surahs})
    return {s["number"]: s["ayahCount"] for s in surahs}


def load_audio_ayah_map() -> dict[int, dict[int, list[int]]]:
    with open(ASSETS / "audio_ayah_map.json", encoding="utf-8") as f:
        d = json.load(f)
    out: dict[int, dict[int, list[int]]] = {}
    for s, m in d["map"].items():
        out[int(s)] = {int(a): v for a, v in m.items()}
    return out


def load_qaniwah_continuations() -> tuple[dict[int, set[int]], set[int]]:
    with open(ASSETS / "qaniwah_continuations.json", encoding="utf-8") as f:
        d = json.load(f)
    continuations = {int(s): set(v) for s, v in d["continuations"].items()}
    basmala_in_ayah1 = set(d["basmala_in_ayah1"])
    return continuations, basmala_in_ayah1


def build_overrides_direct(ayah_counts: dict[int, int]) -> dict[str, dict]:
    """Husary: displayed ayah -> file directly, except trailing ayat past a
    per-surah threshold which all collapse onto one merged file. The
    threshold ayah itself already matches its natural default filename, so
    only ayat strictly past it are actual overrides."""
    overrides: dict[str, dict] = {}
    for surah, threshold, file_stem in HUSARY_MERGE_TABLE:
        max_a = ayah_counts[surah]
        for a in range(threshold + 1, max_a + 1):
            overrides[f"{surah}-{a}"] = {"f": [file_stem], "cov": None}
    return overrides


def _native_mapped_ints(
    audio_map: dict[int, dict[int, list[int]]], max_a: int, s: int, a: int
) -> list[int]:
    raw = audio_map.get(s, {}).get(a, [a])
    return [n for n in raw if 1 <= n <= max_a]


def build_overrides_native(
    ayah_counts: dict[int, int],
    audio_map: dict[int, dict[int, list[int]]],
    breath_combining: bool,
    continuations: dict[int, set[int]],
    basmala_in_ayah1: set[int],
) -> dict[str, dict]:
    """al-Naihi / Qaniwah: native per-ayah numbering, basmala prepended
    before ayah 1 (except surah 9, and except reciters whose ayah-1 file
    already contains the basmala), displayed ayah -> native file(s) via
    audio_ayah_map with dedup against the previous ayah's mapped max, and
    (Qaniwah only) breath-continuation ayat dropped entirely. Ported 1:1 from
    AudioService._getAudioFilesForAyah in lib/services/audio_service.dart."""
    overrides: dict[str, dict] = {}
    for s in range(1, 115):
        max_a = ayah_counts[s]
        cont_set = continuations.get(s, set()) if breath_combining else set()
        last_audible: int | None = None
        for a in range(1, max_a + 1):
            mapped = _native_mapped_ints(audio_map, max_a, s, a)
            if a > 1:
                prev = _native_mapped_ints(audio_map, max_a, s, a - 1)
                if prev:
                    prev_max = max(prev)
                    mapped = [n for n in mapped if n > prev_max]

            files: list[str] = []
            basmala_in_1 = breath_combining and s in basmala_in_ayah1
            if a == 1 and s != 9 and not basmala_in_1:
                files.append(f"{s:03d}000")
            for n in mapped:
                if breath_combining and n in cont_set:
                    continue
                files.append(f"{s:03d}{n:03d}")

            default_files = [f"{s:03d}{a:03d}"]
            if files:
                last_audible = a
            if files != default_files:
                cov = None if files else (f"{s}-{last_audible}" if last_audible else None)
                overrides[f"{s}-{a}"] = {"f": files, "cov": cov}
    return overrides


def fetch_covered_source(url: str, cache_path: Path) -> dict[str, str]:
    """Extracts the {surah: [{n, c}]} 'covered ayah' data embedded in one of
    the user's existing single-reciter test players. Cached after first
    fetch so reruns don't need network access."""
    if cache_path.exists():
        with open(cache_path, encoding="utf-8") as f:
            return json.load(f)

    print(f"  fetching {url} ...")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        html = resp.read().decode("utf-8")

    m = re.search(
        r'<script id="quran-data" type="application/json">(.*?)</script>',
        html,
        re.DOTALL,
    )
    if not m:
        raise RuntimeError(f"quran-data script block not found in {url}")
    data = json.loads(m.group(1))

    covered: dict[str, str] = {}
    for s_str, sd in data.items():
        s = int(s_str)
        for ay in sd["ayat"]:
            c = ay.get("c")
            if c:
                cs, ca = c.split(":")
                covered[f"{s}-{ay['n']}"] = f"{int(cs)}-{int(ca)}"

    SOURCES_CACHE.mkdir(parents=True, exist_ok=True)
    with open(cache_path, "w", encoding="utf-8") as f:
        json.dump(covered, f, ensure_ascii=False, indent=1, sort_keys=True)
    return covered


def build_overrides_covered(covered_map: dict[str, str]) -> dict[str, dict]:
    return {key: {"f": [], "cov": cov} for key, cov in covered_map.items()}


THUMN_RE = re.compile(
    r"ThumnEntry\(\s*(\d+)\s*,\s*'((?:[^'\\]|\\.)*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,?\s*\)",
    re.DOTALL,
)


def parse_thumn_entries() -> list[dict]:
    text = (ROOT / "lib" / "thumn_data.dart").read_text(encoding="utf-8")
    matches = THUMN_RE.findall(text)
    assert len(matches) == 480, f"expected 480 thumn entries, got {len(matches)}"

    entries = []
    for num, txt, page, hizb, s, a in matches:
        entries.append(
            {
                "number": int(num),
                "text": txt,
                "page": int(page),
                "hizb": int(hizb),
                "startSurah": int(s),
                "startAyah": int(a),
            }
        )
    entries.sort(key=lambda e: e["number"])
    assert min(e["hizb"] for e in entries) == 1 and max(e["hizb"] for e in entries) == 60

    for i, e in enumerate(entries):
        nxt = entries[i + 1] if i + 1 < len(entries) else None
        e["endSurah"] = nxt["startSurah"] if nxt else None
        e["endAyah"] = nxt["startAyah"] if nxt else None
        e["juz"] = math.ceil(e["hizb"] / 2)

    write_json("thumn_index.json", {"thumns": entries})
    return entries


def main() -> None:
    print("Loading output.json ...")
    per_surah = load_output_json()
    ayah_counts = build_quran_text(per_surah)
    print(f"  quran_text.json: 114 surahs, {sum(ayah_counts.values())} ayat")

    print("Building Husary overrides (direct scheme) ...")
    husary_overrides = build_overrides_direct(ayah_counts)
    write_json("overrides_husary.json", {"reciterId": "husary", "overrides": husary_overrides})
    print(f"  {len(husary_overrides)} overrides")

    audio_map = load_audio_ayah_map()
    continuations, basmala_in_ayah1 = load_qaniwah_continuations()

    print("Building Naihi overrides (native scheme) ...")
    naihi_overrides = build_overrides_native(ayah_counts, audio_map, False, {}, set())
    write_json("overrides_naihi.json", {"reciterId": "naihi", "overrides": naihi_overrides})
    print(f"  {len(naihi_overrides)} overrides")

    print("Building Qaniwah overrides (native scheme + breath-combining) ...")
    qaniwah_overrides = build_overrides_native(
        ayah_counts, audio_map, True, continuations, basmala_in_ayah1
    )
    write_json("overrides_qaniwah.json", {"reciterId": "qaniwah", "overrides": qaniwah_overrides})
    print(f"  {len(qaniwah_overrides)} overrides")

    print("Fetching/loading Hudaifi covered-ayah data ...")
    hudaifi_covered = fetch_covered_source(
        "https://audio.mushaf-qaloon.com/mushaf3.html", SOURCES_CACHE / "hudaifi_covered.json"
    )
    assert len(hudaifi_covered) == 20, f"hudaifi covered count changed: {len(hudaifi_covered)}"
    write_json(
        "overrides_hudaifi.json",
        {"reciterId": "hudaifi", "overrides": build_overrides_covered(hudaifi_covered)},
    )
    print(f"  {len(hudaifi_covered)} overrides")

    print("Fetching/loading Doukali covered-ayah data ...")
    doukali_covered = fetch_covered_source(
        "https://audio.mushaf-qaloon.com/mushaf_doukali.html", SOURCES_CACHE / "doukali_covered.json"
    )
    assert len(doukali_covered) == 1194, f"doukali covered count changed: {len(doukali_covered)}"
    write_json(
        "overrides_doukali.json",
        {"reciterId": "doukali", "overrides": build_overrides_covered(doukali_covered)},
    )
    print(f"  {len(doukali_covered)} overrides")

    print("Parsing thumn boundaries ...")
    thumns = parse_thumn_entries()
    print(f"  {len(thumns)} thumn entries")

    print("Writing reciters.json ...")
    reciters_out = []
    for r in RECITERS:
        reciters_out.append(
            {
                "id": r["id"],
                "name": r["name"],
                "shortName": r.get("shortName", r["name"]),
                "riwaya": r["riwaya"],
                "folder": r["folder"],
                "scheme": r["scheme"],
                "breathCombining": r.get("breathCombining", False),
                "overridesFile": f"overrides_{r['id']}.json",
                # Present only for reciters awaiting review, so the UI can
                # render the badge without hardcoding which ones they are.
                **({"reviewNote": REVIEW_LABEL} if r.get("underReview") else {}),
            }
        )
    write_json("reciters.json", {"reciters": reciters_out})

    # Spot checks matching the plan's verification table.
    assert naihi_overrides["2-255"] == {"f": ["002255", "002256"], "cov": None}
    assert naihi_overrides["2-256"] == {"f": [], "cov": "2-255"}
    assert qaniwah_overrides["2-255"]["f"] == ["002255", "002256"]
    assert husary_overrides["5-121"]["f"] == ["005120"]
    assert "5-120" not in husary_overrides  # threshold ayah == its own default, not stored

    print("\nAll checks passed.")


if __name__ == "__main__":
    main()

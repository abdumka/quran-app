#!/usr/bin/env python3
"""Publish the server-updatable data the app fetches without a store release
(lib/services/content_update_service.dart) to the quran-content R2 bucket:

    data/manifest.json                       what is current (never cached long)
    data/tanzilat/tanzilat_v<N>.json         assets/data/tanzilat.json, N = its "ver"
    data/word_masks/patch_v<N>.json          tools/content_updates/word_masks_patch.json
    data/tanzilat_paint/paint_v<N>.bin       assets/data/tanzilat_paint.bin, N = its header's "ver"
    data/reciters/reciters_v<N>.json         tools/content_updates/reciters.json
    data/quran_text/patch_v<N>.json          tools/content_updates/quran_text_patch.json
    data/tasmee_data/patch_v<N>.json         tools/content_updates/tasmee_data_patch.json
    data/app_config/config_v<N>.json         tools/content_updates/app_config.json
    data/quran_data/patch_v<N>.json          tools/content_updates/quran_data.json
    data/notices/notices_v<N>.json           tools/content_updates/notices.json
    data/share_video/share_video_v<N>.json   assets/data/share_video.json, N = its "ver"
    data/athkar/athkar_v<N>.json             assets/data/athkar.json, N = its "ver" (VER in build_athkar_data.py)
    data/khilaf/khilaf_v<N>.json             assets/data/khilaf.json, N = its "ver" (VER in build_khilaf_data.py)
    data/usul/usul_v<N>.json                 assets/data/usul.json, N = its "ver" (VER in build_usul_data.py)

Each payload is uploaded under its version (immutable, cached for a year) and
the manifest is rewritten last, so a phone never sees a manifest pointing at a
file that is not there yet. A version already on the bucket is never
overwritten: bump "ver" in the source file instead.

Bumping: a tanzilat change -> VER in build_tanzilat_data.py; a word-box fix ->
"ver" in word_masks_patch.json (the list is cumulative); a new reciter -> "ver"
in reciters.json; a Qur'an text fix -> fix output.json, then
tools/build_quran_text_patch.py --write (it bumps "ver"); a Tasmee pronunciation fix ->
fix page_phonemes.json / phoneme_lexicon.json, then tools/build_tasmee_data_patch.py --write;
app_config / quran_data / notices -> edit the file and bump its "ver" by hand
(rules: tools/content_updates/README.md); repainted colours or ANY tanzilat bump -> rebuild the pictures
(build_tanzilat_paint.py, bump its VER): a pack is shown only with the tanzilat
version it names. A build's ContentUpdateService.bundledVersions must equal the
versions its assets carry; "minBuild" below is the first build that reads this
data at all.

Usage:
    python tools/publish_content_updates.py --dry-run  # show the manifest only
    python tools/publish_content_updates.py --publish  # upload + manifest
    python tools/publish_content_updates.py            # same as --publish
    python tools/publish_content_updates.py --only=share_video --publish
        publish only the named items (comma-separated); every other item
        keeps exactly the entry the live manifest has (or stays out)
Any other argument (--help included) prints this text and publishes nothing.
Credentials: tools/.r2_secret (the quran-content block). Same handling as the
tafsir mirror; never print the secret.
"""
import hashlib
import io
import json
import re
import os
import struct
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "content_updates"
MIN_BUILD = 126  # the first build with ContentUpdateService
# tanzilat_paint: the first build that shows the pictures. word_masks: from patch v6 (2026-11-10,
# Tasmee leak fix) coloured words may gain boxes; builds 126-132 colour from the boxes, so they
# keep the v5 they have and only builds that colour from the pictures take newer boxes.
# tasmee_data / app_config / quran_data / notices: the first build with their code
# (2026-11-17 work, the release after 1.5.6+140). Older builds do not know these items
# and ignore them anyway; the number only keeps the manifest honest. That release went to
# the App Store as 1.5.7+140 (2026-11-18), the same build number as 1.5.6+140, so the gate
# is 140: 1.5.6+140 does not know these items and skips them, 1.5.7+140 and later read them.
NEW_ITEMS_MIN_BUILD = 140
MIN_BUILD_OF = {"tanzilat_paint": 133, "word_masks": 133,
                "tasmee_data": NEW_ITEMS_MIN_BUILD, "app_config": NEW_ITEMS_MIN_BUILD,
                "quran_data": NEW_ITEMS_MIN_BUILD, "notices": NEW_ITEMS_MIN_BUILD,
                "athkar": NEW_ITEMS_MIN_BUILD, "khilaf": NEW_ITEMS_MIN_BUILD,
                # «مشاركة الآية» / «فيديو الآية»: first in test build 151 (2026-11-17).
                "share_video": NEW_ITEMS_MIN_BUILD,
                # «أحكام وأصول الرواية»: first in 1.5.7+141 (2026-11-19).
                "usul": 141}
PUBLIC = "https://quran-content.mushaf-qaloon.com/"
NUL = os.devnull
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ITEMS = {
    # name: (source file, key pattern)
    "tanzilat": (ROOT / "assets" / "data" / "tanzilat.json", "data/tanzilat/tanzilat_v{ver}.json"),
    "word_masks": (SRC / "word_masks_patch.json", "data/word_masks/patch_v{ver}.json"),
    "reciters": (SRC / "reciters.json", "data/reciters/reciters_v{ver}.json"),
    "tanzilat_paint": (ROOT / "assets" / "data" / "tanzilat_paint.bin", "data/tanzilat_paint/paint_v{ver}.bin"),
    "quran_text": (SRC / "quran_text_patch.json", "data/quran_text/patch_v{ver}.json"),
    "tasmee_data": (SRC / "tasmee_data_patch.json", "data/tasmee_data/patch_v{ver}.json"),
    "app_config": (SRC / "app_config.json", "data/app_config/config_v{ver}.json"),
    "quran_data": (SRC / "quran_data.json", "data/quran_data/patch_v{ver}.json"),
    "notices": (SRC / "notices.json", "data/notices/notices_v{ver}.json"),
    # «الأذكار»: texts, sections and the athkar voices (tools/build_athkar_data.py
    # writes it; bump VER there). Phones take it only when ver > the bundled one.
    "athkar": (ROOT / "assets" / "data" / "athkar.json", "data/athkar/athkar_v{ver}.json"),
    # «مشاركة الآية»: share text, link, video backgrounds, effects, watermark, closing
    # card. Edit assets/data/share_video.json, bump "ver", publish. Background clips
    # live under video_bg/<id>/ on the same bucket (upload them first; a changed clip
    # needs a NEW path, phones cache by path).
    "share_video": (ROOT / "assets" / "data" / "share_video.json", "data/share_video/share_video_v{ver}.json"),
    # «خلافات القراء»: the whole file (tools/build_khilaf_data.py writes it; raise VER
    # there). Phones take it only when ver > the bundled one.
    "khilaf": (ROOT / "assets" / "data" / "khilaf.json", "data/khilaf/khilaf_v{ver}.json"),
    # «أحكام وأصول الرواية»: the whole file (tools/build_usul_data.py writes it; raise VER
    # there). Phones take it only when ver > the bundled one.
    "usul": (ROOT / "assets" / "data" / "usul.json", "data/usul/usul_v{ver}.json"),
}
EASTERN = set("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹")


def secret_block(bucket):
    blocks, cur = [], {}
    for line in (ROOT / "tools" / ".r2_secret").read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        k, v = line.strip().split("=", 1)
        if k == "R2_BUCKET" and cur:
            blocks.append(cur)
            cur = {}
        cur[k] = v
    if cur:
        blocks.append(cur)
    for b in blocks:
        if b.get("R2_BUCKET") == bucket:
            return b
    sys.exit(f"ABORT: no credentials block for bucket {bucket!r}")


def paint_header(body):
    if body[:4] != b"TZP1":
        sys.exit("ABORT: tanzilat_paint.bin has a bad magic")
    n = struct.unpack("<I", body[4:8])[0]
    return json.loads(body[8:8 + n])


def check_quran_text(data):
    """The app's rules, and the file must match output.json and the bases."""
    sys.path.insert(0, str(ROOT / "tools"))
    import build_quran_text_patch as qt
    problems = qt.check_patch(data)
    if problems:
        sys.exit("ABORT: quran_text_patch.json breaks the app's rules: " + "; ".join(problems))
    if data["patches"] != qt.expected_entries():
        sys.exit("ABORT: quran_text_patch.json is not up to date with output.json: "
                 "run tools/build_quran_text_patch.py --write")


def abort(name, problems):
    if problems:
        sys.exit(f"ABORT: {name} breaks the app's rules: " + "; ".join(problems[:12]))


def check_tasmee_data(data):
    sys.path.insert(0, str(ROOT / "tools"))
    import build_tasmee_data_patch as td
    pages, _ = td.current()
    abort("tasmee_data_patch.json", td.check_patch(data, pages))


def remote_keys():
    """{key: (kind, default, min, max)} parsed from lib/services/remote_config.dart,
    so the app's list is the only list."""
    src = (ROOT / "lib" / "services" / "remote_config.dart").read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r"'([A-Za-z0-9_.]+)': RemoteKey\.(flag|number|integer)\(([^)]*)\)", src):
        args = [a.strip() for a in m.group(3).split(",") if a.strip()]
        out[m.group(1)] = (m.group(2), *args)
    if len(out) < 5:
        sys.exit("ABORT: could not read the keys of remote_config.dart")
    return out


BUNDLED_TAFSIR = {"saddi", "muyassar", "jalalayn", "ibn_kathir", "tabari", "qurtubi", "zad_almasir"}


def reachable(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "Mozilla/5.0 Chrome/120"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status == 200
    except Exception:  # noqa: BLE001
        return False


def check_app_config(data):
    keys, problems = remote_keys(), []
    values = data.get("values")
    if not isinstance(values, dict):
        abort("app_config.json", ["no values object"])
    for k, v in values.items():
        if k not in keys:
            problems.append(f"unknown key {k}")
            continue
        kind, *rng = keys[k]
        if kind == "flag":
            if not isinstance(v, bool):
                problems.append(f"{k} must be true/false")
        elif kind == "integer":
            if not isinstance(v, int) or isinstance(v, bool) or not float(rng[1]) <= v <= float(rng[2]):
                problems.append(f"{k} must be a whole number in {rng[1]}..{rng[2]}")
        else:
            if not isinstance(v, (int, float)) or isinstance(v, bool) or not float(rng[1]) <= v <= float(rng[2]):
                problems.append(f"{k} must be a number in {rng[1]}..{rng[2]}")
    ids = set()
    for e in data.get("tafsirEditions", []):
        i = e.get("id") if isinstance(e, dict) else None
        if not isinstance(i, str) or not re.fullmatch(r"[a-z][a-z0-9_]{1,30}", i) or i in BUNDLED_TAFSIR or i in ids:
            problems.append(f"bad tafsir id {i}")
            continue
        ids.add(i)
        name, sub = e.get("name"), e.get("subtitle")
        if not isinstance(name, str) or not name.strip() or len(name) > 40:
            problems.append(f"tafsir {i}: bad name")
        if not isinstance(sub, str) or len(sub) > 60:
            problems.append(f"tafsir {i}: bad subtitle")
        for page in (1, 300, 602):
            url = f"{PUBLIC}tafsir/{i}/page_{page:03d}.json"
            if not reachable(url):
                problems.append(f"tafsir {i}: {url} is not reachable (upload the pages first)")
    abort("app_config.json", problems)


def check_quran_data(data):
    problems = []
    regions = json.loads((ROOT / "assets" / "data" / "ayah_regions.json").read_bytes())
    bundled = {p["page"]: [(a["surah"], a["ayah"]) for a in p["ayahs"]] for p in regions}

    def ratio(v):
        return isinstance(v, (int, float)) and not isinstance(v, bool) and -0.05 <= v <= 1.05

    def rect(r):
        return (isinstance(r, dict) and all(ratio(r.get(k)) for k in ("x", "y", "width", "height"))
                and r["width"] > 0 and r["height"] > 0 and r["x"] + r["width"] <= 1.05 and r["y"] + r["height"] <= 1.05)

    def region(a):
        return (isinstance(a, dict) and isinstance(a.get("surah"), int) and isinstance(a.get("ayah"), int)
                and isinstance(a.get("rects"), list) and a["rects"] and all(rect(r) for r in a["rects"])
                and (a.get("marker") is None or rect(a["marker"])))

    for k, v in (data.get("ayahRegions") or {}).items():
        page = int(k) if k.isdigit() else None
        if page not in bundled:
            problems.append(f"region page {k} is not a page")
            continue
        if not isinstance(v, dict) or not isinstance(v.get("ayahs"), list) or not all(region(a) for a in v["ayahs"]):
            problems.append(f"page {k}: bad regions")
            continue
        if [(a["surah"], a["ayah"]) for a in v["ayahs"]] != bundled[page]:
            problems.append(f"page {k}: other ayat than the bundle (the app would keep its own)")
        if v.get("continues") is not None and not region(v["continues"]):
            problems.append(f"page {k}: bad continues")
    for sk, ayahs in (data.get("audioAyahMap") or {}).items():
        if not sk.isdigit() or not 1 <= int(sk) <= 114 or not isinstance(ayahs, dict):
            problems.append(f"audio surah {sk}")
            continue
        for ak, files in ayahs.items():
            if not ak.isdigit() or not isinstance(files, list) or not all(isinstance(f, int) and 0 <= f <= 286 for f in files):
                problems.append(f"audio {sk}:{ak}")
    for asset, v in (data.get("breathData") or {}).items():
        if not asset.startswith("assets/data/") or ".." in asset or not (ROOT / asset).exists():
            problems.append(f"breath asset {asset} is not a bundled file")
        elif not isinstance(v, dict) or not isinstance(v.get("continuations"), dict):
            problems.append(f"{asset}: no continuations")
    for sk, ayahs in (data.get("narrationMap") or {}).items():
        if not sk.isdigit() or not isinstance(ayahs, dict):
            problems.append(f"narration surah {sk}")
            continue
        for ak, v in ayahs.items():
            ok = (isinstance(v, int) and 1 <= v <= 286) or (
                isinstance(v, list) and len(v) == 2 and all(isinstance(n, int) for n in v) and v[0] <= v[1])
            if not ak.isdigit() or not ok:
                problems.append(f"narration {sk}:{ak}")
    for f in data.get("tafsirFixes") or []:
        e = f.get("edition") if isinstance(f, dict) else None
        if e not in ("saddi", "muyassar", "jalalayn"):
            problems.append(f"tafsir fix for {e}: only bundled editions")
            continue
        book = json.loads((ROOT / "assets" / "data" / f"ar.{e}.json").read_bytes())["tafsir"]
        s_, a_ = f.get("surah"), f.get("ayah")
        if not (isinstance(s_, int) and 1 <= s_ <= len(book) and isinstance(a_, int) and 1 <= a_ <= len(book[s_ - 1])):
            problems.append(f"tafsir fix {e} {s_}:{a_} is not in that edition (Hafs numbering)")
        elif not isinstance(f.get("text"), str) or not f["text"].strip():
            problems.append(f"tafsir fix {e} {s_}:{a_}: empty text")
    # index labels: thumn openings (1..480) and hizb titles (1..60)
    for name, top, longest in (("thumnTexts", 480, 200), ("hizbTitles", 60, 60)):
        for k, v in (data.get(name) or {}).items():
            if not (k.isascii() and k.isdigit() and 1 <= int(k) <= top):
                problems.append(f"{name} {k}: not 1..{top}")
            elif not isinstance(v, str) or not v.strip() or len(v) > longest or "\n" in v:
                problems.append(f"{name} {k}: one line of 1..{longest} characters")
            elif any(c.isdigit() and not c.isascii() for c in v):
                problems.append(f"{name} {k}: Eastern Arabic digits (use 0-9)")
    abort("quran_data.json", problems)


def check_notices(data):
    problems, ids = [], set()
    notices = data.get("notices")
    if not isinstance(notices, list) or len(notices) > 20:
        abort("notices.json", ["notices must be a list of at most 20"])
    for n in notices:
        i = n.get("id") if isinstance(n, dict) else None
        if not isinstance(i, str) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,39}", i) or i in ids:
            problems.append(f"bad or repeated id {i}")
            continue
        ids.add(i)
        t, lines = n.get("title"), n.get("lines")
        if not isinstance(t, str) or not t.strip() or len(t) > 60:
            problems.append(f"{i}: title (1-60 characters)")
        if not isinstance(lines, list) or not 1 <= len(lines) <= 8 or not all(
                isinstance(x, str) and x.strip() and len(x) <= 400 for x in lines):
            problems.append(f"{i}: lines (1-8, each up to 400 characters)")
        for d in ("from", "until"):
            v = n.get(d)
            if v is not None and not (isinstance(v, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", v)):
                problems.append(f"{i}: {d} must be YYYY-MM-DD")
        if n.get("from") and n.get("until") and n["until"] < n["from"]:
            problems.append(f"{i}: until is before from")
        for b in ("minBuild", "maxBuild"):
            v = n.get(b, 0)
            if not isinstance(v, int) or v < 0:
                problems.append(f"{i}: {b}")
        if "platforms" in n and (not isinstance(n["platforms"], list) or not n["platforms"]
                                 or not set(n["platforms"]) <= {"android", "ios"}):
            problems.append(f"{i}: platforms (android / ios)")
        btn = n.get("button")
        if btn is not None:
            a = btn.get("action") if isinstance(btn, dict) else None
            ok = isinstance(a, str) and bool(a in ("store:", "chat:") or re.fullmatch(r"page:[1-9]\d{0,2}", a)
                                             or re.fullmatch(r"url:https://\S+", a))
            if ok and a.startswith("page:") and int(a[5:]) > 604:
                ok = False
            lb = btn.get("label") if isinstance(btn, dict) else None
            if not ok or not isinstance(lb, str) or not lb.strip() or len(lb) > 30:
                problems.append(f"{i}: button needs a label (up to 30) and action page:<n> / url:https://... / store: / chat:")
        text = " ".join([t or ""] + (lines if isinstance(lines, list) else []))
        if "\u2014" in text:
            print(f"  note: notice {i} contains an em dash")
    abort("notices.json", problems)


RECITER_OVERRIDE_KEYS = {"name", "shortName", "riwaya", "hidden", "timingsRevision", "recording",
                         "pageTurnCues", "coveredAyat", "missingAyat",
                         "surahFiles", "surahTimings"}


def bundled_reciter_urls(src):
    """id -> (audioBaseUrl, timingsBaseUrl) of the bundled reciters in reciter.dart."""
    out = {}
    for block in src.split("static const Reciter ")[1:]:
        rid = re.search(r"id: '([a-z0-9_]+)'", block)
        audio = re.search(r"audioBaseUrl: '([^']+)'", block)
        if not rid or not audio:
            continue
        timings = re.search(r"timingsBaseUrlOverride:\s*'([^']+)'", block)
        out[rid.group(1)] = (audio.group(1),
                             timings.group(1) if timings else audio.group(1) + "timings/")
    return out


def check_surah_corrections(who, o, urls, problems):
    """`surahFiles` / `surahTimings` of one timed recording (owner, 2026-11-22). A
    corrected surah is a NEW file (phones keep a cached SSS.mp3 for good): it must
    already be on R2, and the surah's timings on R2 must name it, before any phone
    is told about it."""
    files, revs = o.get("surahFiles"), o.get("surahTimings")
    if files is not None:
        if not isinstance(files, dict):
            problems.append(f"{who}: surahFiles must be an object")
            files = {}
        for k, f in files.items():
            s = int(k) if str(k).isdigit() else 0
            if not 1 <= s <= 114 or not isinstance(f, str) or \
                    not re.fullmatch(rf"{s:03d}(_[a-z0-9]{{1,16}})?\.mp3", f):
                problems.append(f"{who}: surahFiles {k}: {f!r} is not a file of that surah"
                                " (SSS_<tag>.mp3, tag a-z 0-9)")
                continue
            if f == f"{s:03d}.mp3":
                continue
            if urls is None:
                problems.append(f"{who}: surahFiles {k}: unknown recording URLs")
                continue
            audio, timings = urls
            if not reachable(audio + f):
                problems.append(f"{who}: surahFiles {k}: {audio}{f} is not on the server (upload it first)")
            try:
                req = urllib.request.Request(f"{timings}{s:03d}.json",
                                             headers={"User-Agent": "Mozilla/5.0 Chrome/120"})
                with urllib.request.urlopen(req, timeout=30) as r:
                    named = json.loads(r.read().decode("utf-8")).get("file")
            except Exception:  # noqa: BLE001
                named = None
            if named != f:
                problems.append(f"{who}: surahFiles {k}: {timings}{s:03d}.json names {named!r},"
                                f" not {f!r} (upload the timings first)")
    if revs is not None:
        if not isinstance(revs, dict) or any(
                not (str(k).isdigit() and 1 <= int(k) <= 114 and isinstance(v, int) and v >= 1)
                for k, v in revs.items()):
            problems.append(f"{who}: surahTimings must be {{\"<surah>\": <revision 1+>}}")


def check_reciters(data):
    """The overrides for bundled reciters (build 148+ reads all of these keys; older
    builds only timingsRevision)."""
    problems = []
    src = (ROOT / "lib" / "models" / "reciter.dart").read_text(encoding="utf-8")
    bundled_ids = set(re.findall(r"id: '([a-z0-9_]+)'", src))
    folders = set(re.findall(r"cacheFolder: '([a-z0-9_]+)'", src))
    folders |= {r.get("cacheFolder") for r in data.get("reciters", []) if isinstance(r, dict)}
    known = bundled_ids | {r.get("id") for r in data.get("reciters", []) if isinstance(r, dict)}
    urls = bundled_reciter_urls(src)
    for r in data.get("reciters", []):
        if isinstance(r, dict) and ("surahFiles" in r or "surahTimings" in r):
            check_surah_corrections(r.get("id"), r, (r.get("audioBaseUrl"), r.get("timingsBaseUrl")),
                                    problems)
    for rid, o in (data.get("overrides") or {}).items():
        if rid not in bundled_ids:
            problems.append(f"override for {rid}: not a bundled reciter")
            continue
        if not isinstance(o, dict):
            problems.append(f"{rid}: not an object")
            continue
        for k in o:
            if k not in RECITER_OVERRIDE_KEYS:
                problems.append(f"{rid}: unknown key {k}")
        for k, mx in (("name", 60), ("shortName", 18), ("riwaya", 40)):
            if k in o and (not isinstance(o[k], str) or not o[k].strip() or len(o[k].strip()) > mx):
                problems.append(f"{rid}: {k} must be 1-{mx} characters")
        if "hidden" in o and not isinstance(o["hidden"], bool):
            problems.append(f"{rid}: hidden must be true/false")
        rec = o.get("recording")
        if rec is not None:
            ok_hosts = all(isinstance(rec.get(k), str)
                           and re.fullmatch(r"https://([a-z0-9-]+\.)*mushaf-qaloon\.com/.*/", rec[k])
                           for k in ("audioBaseUrl", "timingsBaseUrl"))
            cf = rec.get("cacheFolder")
            if not ok_hosts:
                problems.append(f"{rid}: recording URLs must be https on mushaf-qaloon.com, ending in /")
            elif not reachable(rec["timingsBaseUrl"] + "001.json") or not reachable(rec["audioBaseUrl"] + "001.mp3"):
                problems.append(f"{rid}: recording files not reachable (001.mp3 / timings 001.json)")
            if not isinstance(cf, str) or not re.fullmatch(r"[a-z][a-z0-9_]{1,39}", cf) or cf in folders:
                problems.append(f"{rid}: recording cacheFolder must be new and unique")
            folders.add(cf)
            if ok_hosts:
                check_surah_corrections(f"{rid} recording", rec,
                                        (rec["audioBaseUrl"], rec["timingsBaseUrl"]), problems)
        check_surah_corrections(rid, o, urls.get(rid), problems)
    order = data.get("order", [])
    if not isinstance(order, list) or any(i not in known for i in order):
        problems.append("order names an unknown reciter")
    abort("reciters.json", problems)


def check_share_video(data):
    """The rules ShareVideoConfig.parse applies, plus a HEAD of every clip and picture."""
    for key in ("baseUrl", "link"):
        u = data.get(key, "")
        if not (isinstance(u, str) and u.startswith("https://") and
                re.match(r"https://([a-z0-9-]+\.)*mushaf-qaloon\.com/", u + "/")):
            sys.exit(f"ABORT: share_video {key} {u!r} is not one of our hosts")
    if not data["baseUrl"].endswith("/"):
        sys.exit("ABORT: share_video baseUrl must end with /")
    if "{text}" not in (data.get("text") or {}).get("template", ""):
        sys.exit("ABORT: share_video text.template has no {text}")
    shapes = [s["id"] for s in data.get("shapes", [])]
    for s in data.get("shapes", []):
        w, h = s.get("width"), s.get("height")
        if not (isinstance(w, int) and isinstance(h, int) and 240 <= w <= 2160 and 240 <= h <= 2160 and w % 2 == 0 and h % 2 == 0):
            sys.exit(f"ABORT: share_video shape {s}")
    for e in data.get("effects", []):
        if e.get("type") not in ("none", "echo", "reverb"):
            sys.exit(f"ABORT: share_video effect {e}")
    cats = {c["id"] for c in data.get("categories", [])}
    ids = set()
    paths = []
    for b in data.get("backgrounds", []):
        if b["id"] in ids:
            sys.exit(f"ABORT: share_video duplicate background {b['id']}")
        ids.add(b["id"])
        if b.get("category") not in cats:
            sys.exit(f"ABORT: share_video {b['id']} has no category")
        paths.append(b["thumb"])
        for s in shapes:
            if s not in b.get("files", {}):
                sys.exit(f"ABORT: share_video {b['id']} has no {s} file")
            paths.append(b["files"][s]["path"])
    if not ids:
        sys.exit("ABORT: share_video has no backgrounds")
    # Server switches, wording and look (all optional; the app's defaults are
    # today's behaviour). A key the app never asks for is a typo: refuse it.
    known = set()
    for f in list((ROOT / "lib" / "services" / "share").glob("*.dart")) + list((ROOT / "lib" / "widgets" / "share").glob("*.dart")):
        known |= set(re.findall(r"(?:_t|ShareVideoConfig\.tr)\(\s*'([A-Za-z]+)'", f.read_text(encoding="utf-8")))
    strings = data.get("strings", {})
    if not isinstance(strings, dict):
        sys.exit("ABORT: share_video strings must be an object")
    for k, v in strings.items():
        if k not in known:
            sys.exit(f"ABORT: share_video strings key {k!r} is not used by the app (known: {', '.join(sorted(known))})")
        if not isinstance(v, str) or not v.strip() or len(v) > 400:
            sys.exit(f"ABORT: share_video strings {k!r} must be 1-400 characters")
        if "—" in v:
            sys.exit(f"ABORT: share_video strings {k!r} has an em dash")
    album = data.get("album", "")
    if album and (not isinstance(album, str) or len(album) > 60 or re.search(r'[/\\:*?"<>|]', album)):
        sys.exit(f"ABORT: share_video album {album!r}")
    if not set(data.get("videoPlatforms", ["android", "ios"])) <= {"android", "ios"}:
        sys.exit("ABORT: share_video videoPlatforms takes android / ios")
    if not all(isinstance(b, int) for b in data.get("videoOffBuilds", [])):
        sys.exit("ABORT: share_video videoOffBuilds must be build numbers")
    look = data.get("video", {})
    for k, v in (look.get("colors") or {}).items():
        if k not in ("title", "closingTop", "closingBottom", "closingText") or not re.fullmatch(r"#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})", str(v)):
            sys.exit(f"ABORT: share_video video.colors {k}: {v!r}")
    if look.get("icon"):
        paths.append(look["icon"])
    # Build 168+: the reciter line under the surah name and its fonts.
    credit = look.get("credit")
    if credit is not None:
        t = credit.get("template", "{reciter}") if isinstance(credit, dict) else None
        if not isinstance(t, str) or not t.strip() or len(t) > 120 or "—" in t:
            sys.exit(f"ABORT: share_video video.credit.template {t!r}")
    fonts = data.get("fonts")
    if fonts is not None:
        fids = []
        for f in fonts.get("list", []):
            fid, title = f.get("id"), f.get("title")
            if not (isinstance(fid, str) and re.fullmatch(r"[a-z0-9_]{1,32}", fid)) or fid in fids:
                sys.exit(f"ABORT: share_video font id {fid!r}")
            if not (isinstance(title, str) and title.strip() and len(title) <= 40) or "—" in title:
                sys.exit(f"ABORT: share_video font {fid} title {title!r}")
            scale = f.get("scale", 1)
            if not (isinstance(scale, (int, float)) and 0.5 <= scale <= 3):
                sys.exit(f"ABORT: share_video font {fid} scale {scale!r}")
            for k in ("file", "preview"):
                if f.get(k) is not None:
                    paths.append(f[k])
            fids.append(fid)
        if fonts.get("default") not in fids:
            sys.exit(f"ABORT: share_video fonts.default {fonts.get('default')!r} is not in the list")
    # The surah names cut from the mushaf (title.images), all 114 of them.
    title_images = (data.get("video", {}).get("title", {}) or {}).get("images")
    if title_images is not None:
        if "{surah}" not in str(title_images):
            sys.exit("ABORT: share_video title.images has no {surah}")
        paths += [title_images.replace("{surah}", f"{n:03d}") for n in range(1, 115)]
    missing = []
    for path in paths:
        if not re.fullmatch(r"[A-Za-z0-9_\-/.]+", path) or ".." in path or path.startswith("/"):
            sys.exit(f"ABORT: share_video bad path {path}")
        # curl, not urllib: Cloudflare answers Python's urllib with 403 on this host.
        code = subprocess.run(["curl", "-sI", "-o", NUL, "-w", "%{http_code}", "--max-time", "20",
                               data["baseUrl"] + path], capture_output=True, text=True).stdout.strip()
        if code != "200":
            missing.append(f"{path} (HTTP {code})")
    if missing:
        sys.exit("ABORT: share_video files not on the server: " + ", ".join(missing[:20]))


def live_manifest():
    # curl, not urllib: Cloudflare answers Python's urllib with 403 on this host.
    r = subprocess.run(["curl", "-s", "--max-time", "30", "-H", "Cache-Control: no-cache",
                        PUBLIC + "data/manifest.json"], capture_output=True, text=True, encoding="utf-8")
    try:
        return json.loads(r.stdout)
    except ValueError:
        sys.exit("ABORT: could not read the live manifest for --only")


def main():
    args = sys.argv[1:]
    only = None
    for a in list(args):
        if a.startswith("--only="):
            only = [x for x in a[len("--only="):].split(",") if x]
            args.remove(a)
    if only is not None and (not only or any(x not in ITEMS for x in only)):
        sys.exit(f"ABORT: --only takes item names from: {', '.join(ITEMS)}")
    if any(a not in ("--dry-run", "--publish") for a in args) or len(args) > 1:
        print(__doc__)
        return
    dry = "--dry-run" in args
    live = live_manifest()["items"] if only is not None else {}
    tanzilat_ver = json.loads((ROOT / "assets" / "data" / "tanzilat.json").read_bytes()).get("ver")
    manifest = {"v": 1, "items": {}}
    uploads = []
    for name, (src, pattern) in ITEMS.items():
        if only is not None and name not in only:
            if name in live:
                manifest["items"][name] = live[name]
                print(f"{name}: kept as live (v{live[name].get('ver')})")
            continue
        if not src.exists():
            print(f"{name}: no source file ({src.relative_to(ROOT)}), left out of the manifest")
            continue
        body = src.read_bytes()
        data = paint_header(body) if name == "tanzilat_paint" else json.loads(body)
        ver = data.get("ver")
        if not isinstance(ver, int) or ver < 1:
            print(f"{name}: no usable \"ver\" in {src.name}, left out")
            continue
        if name == "tanzilat" and "groups" not in data:
            sys.exit(f"ABORT: {src} has no groups")
        if name == "word_masks" and not isinstance(data.get("patches"), list):
            sys.exit(f"ABORT: {src} has no patches list")
        if name == "reciters" and not isinstance(data.get("reciters"), list):
            sys.exit(f"ABORT: {src} has no reciters list")
        if name == "quran_text":
            check_quran_text(data)
        if name == "reciters":
            check_reciters(data)
        if name == "tasmee_data":
            check_tasmee_data(data)
        if name == "app_config":
            check_app_config(data)
        if name == "quran_data":
            check_quran_data(data)
        if name == "notices":
            check_notices(data)
        if name == "share_video":
            check_share_video(data)
        if name == "athkar" and not (isinstance(data.get("sections"), list) and data["sections"]):
            sys.exit(f"ABORT: {src} has no sections")
        if name == "khilaf" and not (isinstance(data.get("a"), dict) and data["a"] and data.get("v") == 1):
            sys.exit(f"ABORT: {src} has no ayat (or a format this app cannot read)")
        if name == "usul" and not (isinstance(data.get("groups"), list) and data["groups"] and data.get("v") == 1):
            sys.exit(f"ABORT: {src} has no chapters (or a format this app cannot read)")
        if name == "tanzilat_paint" and data.get("tz") != tanzilat_ver:
            sys.exit(f"ABORT: the pictures are for tanzilat v{data.get('tz')}, the data is v{tanzilat_ver}: rebuild them")
        if name not in ("tanzilat", "tanzilat_paint") and any(c in EASTERN for c in body.decode("utf-8")):
            sys.exit(f"ABORT: Eastern digits in {src}")
        key = pattern.format(ver=ver)
        manifest["items"][name] = {
            "ver": ver,
            "url": key,
            "sha256": hashlib.sha256(body).hexdigest(),
            "bytes": len(body),
            "minBuild": MIN_BUILD_OF.get(name, MIN_BUILD),
        }
        uploads.append((name, key, body))
        print(f"{name}: v{ver} {len(body):,} bytes -> {key}")
    manifest_body = json.dumps(manifest, separators=(",", ":")).encode("utf-8")
    print(manifest_body.decode("utf-8"))
    if dry:
        return

    import truststore
    truststore.inject_into_ssl()
    import boto3
    from botocore.config import Config
    from botocore.exceptions import ClientError

    cfg = secret_block("quran-content")
    s3 = boto3.client(
        "s3", endpoint_url=cfg["R2_ENDPOINT"], aws_access_key_id=cfg["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=cfg["R2_SECRET_ACCESS_KEY"],
        config=Config(region_name="auto", request_checksum_calculation="when_required",
                      response_checksum_validation="when_required"))
    bucket = cfg["R2_BUCKET"]
    for name, key, body in uploads:
        try:
            head = s3.head_object(Bucket=bucket, Key=key)
            have = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
            if have == body:
                print(f"  {key}: already published, unchanged")
                continue
            sys.exit(f"ABORT: {key} is already published with different content; bump its ver")
        except ClientError as e:
            if e.response["Error"]["Code"] not in ("404", "NoSuchKey", "NotFound"):
                raise
        ct = "application/octet-stream" if key.endswith(".bin") else "application/json; charset=utf-8"
        s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType=ct,
                      CacheControl="public, max-age=31536000, immutable")
        got = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        assert got == body, key
        print(f"  {key}: uploaded and verified")
    s3.put_object(Bucket=bucket, Key="data/manifest.json", Body=manifest_body,
                  ContentType="application/json; charset=utf-8", CacheControl="no-cache")
    got = s3.get_object(Bucket=bucket, Key="data/manifest.json")["Body"].read()
    assert got == manifest_body
    print("  data/manifest.json: uploaded and verified")
    # The public URL is what phones read: it must serve the same bytes, untouched.
    req = urllib.request.Request(PUBLIC + "data/manifest.json", headers={"User-Agent": "Mozilla/5.0 Chrome/120", "Cache-Control": "no-cache"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            public = r.read()
        print("  public manifest:", "identical" if public == manifest_body else "DIFFERENT (CDN cache or injected content?)")
    except Exception as e:  # noqa: BLE001
        print("  public manifest: could not fetch from this network:", e)


if __name__ == "__main__":
    main()

"""
Builds the زاد المسير (Zad al-Masir, Ibn al-Jawzi) online tafsir pages from the
Shamela HTML export (assets/temp/001.htm … 004.htm, shamela.ws book 23619 —
دار الكتاب العربي edition, تحقيق عبد الرزاق المهدي).

Why not spa5k like the others: quran.com/spa5k do not publish Zad al-Masir.
Why not the DJVU OCR build: the OCR text is badly damaged (garbled Qur'anic
quotes, ء-for-، etc.) — the Shamela export is clean typed text.

STRUCTURE OF THE SOURCE
The Shamela export contains `<span id="aya-N">` anchors where N is the GLOBAL
Hafs ayah index (1..6236 across the whole Qur'an), placed where each ayah's
quoted verse-group begins. Commentary for a group runs until the next group's
first anchor. Gaps in anchor coverage (ayahs quoted mid-group) are covered by
their group's block — the same grouped-block expansion the spa5k editions use.
A handful of anchors re-appear later (the author returns to the same ayat);
that continuation text is appended to those ayahs' block.

Surah intros (فضل السورة / نزولها) sit between a `سورة X` heading and the
surah's first anchor; they are attached to the surah's first ayah block.

OUTPUT
build/tafsir/zad_almasir/page_NNN.json — identical shape/pipeline to the other
online editions: reuses build_tafsir_pages.py's page-baking (our output.json
Qalun pages + narration_map Qalun→Hafs + duplicate-collapsing join) and its
alignment check. Upload with mirror_tafsir_to_r2.py.

Usage:
    python tools/build_zad_almasir.py
"""
import html as htmllib
import io
import json
import re
import sys
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "assets" / "temp"
SRC_FILES = ["001.htm", "002.htm", "003.htm", "004.htm"]

sys.path.insert(0, str(ROOT / "tools"))
import build_tafsir_pages as bt  # noqa: E402  (page baking + alignment check)

EDITION_ID = "zad_almasir"

# Hafs cumulative ayah counts: global id g (1-based) -> (surah, ayah).
CUM = [0]
for c in bt.HAFS_COUNTS:
    CUM.append(CUM[-1] + c)


def global_to_sa(g):
    for s in range(114):
        if g <= CUM[s + 1]:
            return s + 1, g - CUM[s]
    return None


ANCHOR = "⁐AYA:%d⁑"  # private sentinel survives the HTML cleanup
ANCHOR_RE = re.compile("⁐AYA:(\\d+)⁑")


def load_and_clean():
    """Concatenates the four files, replaces aya anchors with sentinels, strips
    footnotes/page-heads/tags, and returns the cleaned linear text."""
    parts = []
    for name in SRC_FILES:
        raw = (SRC_DIR / name).read_text(encoding="utf-8", errors="replace")
        # Drop everything before the first real book page (each file opens with
        # a metadata PageText div: title/author/publisher).
        first_page = raw.find("<div class='PageText'><div class='PageHead'>")
        if first_page == -1:
            raise SystemExit(f"{name}: no PageHead found — unexpected export")
        parts.append(raw[first_page:])
    raw = "\n".join(parts)

    # Anchors -> sentinels BEFORE stripping tags.
    raw = re.sub(r'<span id="aya-(\d+)">', lambda m: ANCHOR % int(m.group(1)), raw)

    # Strip the muhaqqiq's footnote blocks (takhrij, not Ibn al-Jawzi's text)
    # and page headers. Neither nests.
    raw = re.sub(r"<div class='footnote'>.*?</div>", " ", raw, flags=re.S)
    raw = re.sub(r"<div class='PageHead'>.*?</div>", "\n", raw, flags=re.S)
    # In-body footnote reference marks: red (N) and «N».
    raw = re.sub(r"<font color=#be0000>\((\d+)\)</font>", " ", raw)
    raw = re.sub(r"«\s*\d+\s*»", " ", raw)
    # Paragraph breaks -> newlines, all remaining tags -> nothing/space.
    raw = re.sub(r"</p>|<p>", "\n", raw)
    raw = re.sub(r"<[^>]+>", " ", raw)
    raw = htmllib.unescape(raw)
    raw = raw.replace("‌", "")  # ZWNJ used as anchor filler
    raw = re.sub(r"[ \t]+", " ", raw)
    raw = re.sub(r"\s*\n\s*", "\n", raw)
    raw = re.sub(r"\n{3,}", "\n\n", raw)
    return raw


# Heading line for a new surah, e.g. "سورة البقرة" on its own line.
SURAH_HEADING_RE = re.compile(r"^سورة\s+[^\n]{1,40}$", re.M)


def build_hafs_tafsir(text):
    """Returns tafsir[surahIdx][hafsAyahIdx] built from the anchor stream."""
    anchors = [(m.start(), m.end(), int(m.group(1))) for m in ANCHOR_RE.finditer(text)]
    if not anchors:
        raise SystemExit("no aya anchors found after cleanup")

    # Group consecutive anchors separated only by whitespace.
    groups = []  # (ids, text_start) — text runs to the next group's first anchor
    i = 0
    while i < len(anchors):
        ids = [anchors[i][2]]
        end = anchors[i][1]
        j = i + 1
        while j < len(anchors) and not text[end:anchors[j][0]].strip():
            ids.append(anchors[j][2])
            end = anchors[j][1]
            j += 1
        groups.append((ids, anchors[i][0], end))
        i = j

    tafsir = [[""] * n for n in bt.HAFS_COUNTS]

    def put(gid, chunk):
        sa = global_to_sa(gid)
        if sa is None or not chunk:
            return
        s, a = sa
        cur = tafsir[s - 1][a - 1]
        tafsir[s - 1][a - 1] = (cur + "\n\n" + chunk) if cur else chunk

    max_seen = 0
    prev_surah = 0
    for k, (ids, _start, body_from) in enumerate(groups):
        body_to = groups[k + 1][1] if k + 1 < len(groups) else len(text)
        block = text[body_from:body_to]

        # If the NEXT group opens a new surah, this block's tail contains that
        # surah's heading + intro; split it off and prepend it to the next
        # surah's first ayah instead of leaving it on this surah's last ayah.
        intro_for_next = ""
        if k + 1 < len(groups):
            next_first = min(groups[k + 1][0])
            sa_next = global_to_sa(next_first)
            sa_here = global_to_sa(min(ids))
            if sa_next and sa_here and sa_next[0] != sa_here[0]:
                headings = list(SURAH_HEADING_RE.finditer(block))
                if headings:
                    cut = headings[-1].start()
                    intro_for_next = block[cut:]
                    block = block[:cut]

        block = block.strip()
        gmin, gmax = min(ids), max(ids)

        # Continuation (anchor re-appears): append to the exact ayat only.
        if gmin <= max_seen:
            for gid in sorted(set(ids)):
                put(gid, block)
        else:
            # Normal block: cover from gmin through the gap up to the next
            # group (grouped ayat without their own anchor share this block).
            next_first = groups[k + 1][0][0] if k + 1 < len(groups) else CUM[-1] + 1
            cover_to = max(gmax, next_first - 1) if next_first > gmin else gmax
            # never cross the surah boundary of gmin's surah
            s_here = global_to_sa(gmin)[0]
            cover_to = min(cover_to, CUM[s_here])
            cover_from = gmin
            # First block of a surah also covers any un-anchored opening ayat
            # (e.g. the export lacks anchors for Luqman 31:1-2) — same leading-
            # gap rule as build_tafsir_pages.expand_to_hafs.
            if s_here != prev_surah:
                cover_from = min(gmin, CUM[s_here - 1] + 1)
                prev_surah = s_here
            for gid in range(cover_from, cover_to + 1):
                put(gid, block)
        max_seen = max(max_seen, gmax)

        if intro_for_next:
            # Attach the intro to ayah 1 of the coming surah (its first block
            # then appends after it via put()'s ordering).
            s_next = global_to_sa(min(groups[k + 1][0]))[0]
            put(CUM[s_next - 1] + 1, intro_for_next.strip())

    return tafsir


def main():
    print("cleaning Shamela HTML…", flush=True)
    text = load_and_clean()
    print(f"cleaned text: {len(text):,} chars")

    tafsir = build_hafs_tafsir(text)
    filled = sum(1 for su in tafsir for t in su if t.strip())
    print(f"Hafs slots with text: {filled} / {CUM[-1]}")

    pages = bt.load_pages()
    narration = json.loads(
        (ROOT / "assets" / "data" / "narration_map.json").read_text(encoding="utf-8")
    ).get("qalun_to_hafs", {})

    ok = bt.check_alignment(EDITION_ID, tafsir, pages, narration)
    written, empties = bt.build_online(EDITION_ID, tafsir, pages, narration)
    print(f"wrote {written} pages -> build/tafsir/{EDITION_ID}/ "
          f"(app ayat with no text: {len(empties)})")
    for e in empties[:20]:
        print("   EMPTY", e)
    print("DONE." if ok and not empties else "DONE with gaps — review above.")
    return 0 if ok and not empties else 1


if __name__ == "__main__":
    sys.exit(main())

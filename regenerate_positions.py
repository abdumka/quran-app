"""
Regenerate ayah_positions.json using the SIMPLE approach:
- Detect golden ayah markers using ImageMagick
- Each ayah = ONE full-width rect between two consecutive markers
- This gives us clean, simple, accurate rects

Uses the SAME images as the app: assets/images/
"""
import json
import re
import subprocess
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

PROJECT = Path(__file__).resolve().parent
IMAGE_DIR = PROJECT / "assets" / "images"
HQ_IMAGE_DIR = Path(r"C:\Users\Mahfod501\Desktop\images")
OUTPUT_JSON = PROJECT / "assets" / "data" / "output.json"
POSITIONS_JSON = PROJECT / "assets" / "data" / "ayah_positions.json"

# Regex for connected components output (white = foreground = gold)
CC_RE = re.compile(
    r"^\s*(\d+):\s+(\d+)x(\d+)\+(\d+)\+(\d+)\s+([0-9.]+),([0-9.]+)\s+(\d+)\s+srgb\(255,255,255\)"
)

# ── Text area margins (normalized) ──
# The Quran text doesn't span edge-to-edge; there are decorative borders
TEXT_LEFT = 0.04     # left margin
TEXT_RIGHT = 0.96    # right margin


def read_image_size(path: Path) -> tuple[int, int]:
    r = subprocess.run(
        ["magick", str(path), "-format", "%w %h", "info:"],
        capture_output=True, text=True, check=True,
    )
    w, h = r.stdout.strip().split()
    return int(w), int(h)


def detect_gold_markers(page_num: int) -> list[dict]:
    """Detect golden ayah end-markers in the image."""
    # Try HQ images first, fall back to app images
    path = HQ_IMAGE_DIR / f"page_{page_num}.webp"
    if not path.exists():
        path = IMAGE_DIR / f"page_{page_num}.webp"
    if not path.exists():
        return []

    img_w, img_h = read_image_size(path)

    # Extract gold-colored regions
    r = subprocess.run(
        [
            "magick", str(path),
            "-colorspace", "sRGB",
            "-fx", "(r>0.72 && g>0.62 && b<0.50)?1:0",
            "-define", "connected-components:verbose=true",
            "-connected-components", "8",
            "null:",
        ],
        capture_output=True, text=True, check=False,
    )
    text = (r.stdout or "") + "\n" + (r.stderr or "")

    raw = []
    for line in text.splitlines():
        m = CC_RE.match(line)
        if not m:
            continue
        _, w, h, x, y, cx, cy, area = m.groups()
        w, h, x, y, area = int(w), int(h), int(x), int(y), int(area)
        cx, cy = float(cx), float(cy)
        # Filter: ayah markers are small golden circles
        if area < 12 or area > 2000:
            continue
        if w < 5 or w > 90 or h < 5 or h > 90:
            continue
        raw.append({"x": x, "y": y, "w": w, "h": h, "cx": cx, "cy": cy, "area": area})

    # Cluster nearby components into single markers
    raw.sort(key=lambda c: (c["cy"], c["cx"]))
    clusters = []
    for comp in raw:
        merged = False
        for cl in clusters:
            if abs(comp["cx"] - cl["cx"]) <= 34 and abs(comp["cy"] - cl["cy"]) <= 40:
                cl["members"].append(comp)
                cl["cx"] = sum(m["cx"] for m in cl["members"]) / len(cl["members"])
                cl["cy"] = sum(m["cy"] for m in cl["members"]) / len(cl["members"])
                cl["area"] = sum(m["area"] for m in cl["members"])
                merged = True
                break
        if not merged:
            clusters.append({"cx": comp["cx"], "cy": comp["cy"], "area": comp["area"], "members": [comp]})

    # Filter clusters: real markers have significant area and size
    markers = [
        cl for cl in clusters
        if cl["area"] >= 120
        and any(m["w"] >= 16 and m["h"] >= 16 for m in cl["members"])
    ]
    markers.sort(key=lambda m: m["cy"])

    return [{"cx": m["cx"] / img_w, "cy": m["cy"] / img_h} for m in markers]


def build_ayah_rects(
    markers: list[dict],
    ayah_count: int,
    page_num: int,
    is_surah_start: bool,
) -> list[list[dict]]:
    """
    Build one full-width rect per ayah using marker midpoints as boundaries.
    
    In the Mushaf, each ayah ENDS with a golden marker.
    So marker[0] is at the END of ayah[0], marker[1] at END of ayah[1], etc.
    
    This means:
    - ayah[0]: from page_top to marker[0] center
    - ayah[1]: from marker[0] center to marker[1] center
    - ayah[N-1]: from marker[N-2] center to page_bottom
    
    If markers count == ayah_count, the last marker is the end of the last ayah.
    If markers count == ayah_count - 1, the last ayah extends to page bottom.
    """
    if not markers or ayah_count == 0:
        return [[] for _ in range(ayah_count)]

    # Compute boundaries between consecutive marker centers
    boundaries = []
    
    # Top boundary: either page top or adjusted for surah header
    if is_surah_start:
        # Surah headers typically occupy ~15-20% of page height
        # Find the first marker and start a bit above it
        first_marker_y = markers[0]["cy"]
        # Start from the midpoint between surah header area and first marker
        header_end = min(0.18, first_marker_y * 0.7)
        boundaries.append(header_end)
    else:
        boundaries.append(0.0)
    
    # Intermediate boundaries: midpoints between consecutive markers
    for i in range(len(markers) - 1):
        mid = (markers[i]["cy"] + markers[i + 1]["cy"]) / 2.0
        boundaries.append(mid)
    
    # Bottom boundary
    boundaries.append(1.0)

    # Number of bands = len(boundaries) - 1
    num_bands = len(boundaries) - 1
    
    # Map bands to ayahs
    rects_per_ayah = [[] for _ in range(ayah_count)]
    
    if num_bands == ayah_count:
        # Perfect match: one band per ayah
        for i in range(ayah_count):
            top = boundaries[i]
            bottom = boundaries[i + 1]
            if bottom - top > 0.01:  # skip tiny slivers
                rects_per_ayah[i].append({
                    "x": round(TEXT_LEFT, 4),
                    "y": round(top, 4),
                    "width": round(TEXT_RIGHT - TEXT_LEFT, 4),
                    "height": round(bottom - top, 4),
                })
    elif num_bands == ayah_count + 1:
        # One extra band (e.g., from surah header detection)
        # Skip the first band (it's the header)
        for i in range(ayah_count):
            top = boundaries[i + 1]
            bottom = boundaries[i + 2]
            if bottom - top > 0.01:
                rects_per_ayah[i].append({
                    "x": round(TEXT_LEFT, 4),
                    "y": round(top, 4),
                    "width": round(TEXT_RIGHT - TEXT_LEFT, 4),
                    "height": round(bottom - top, 4),
                })
    elif num_bands == ayah_count - 1:
        # One fewer marker: last ayah goes to page bottom
        for i in range(num_bands):
            top = boundaries[i]
            bottom = boundaries[i + 1]
            if bottom - top > 0.01:
                rects_per_ayah[i].append({
                    "x": round(TEXT_LEFT, 4),
                    "y": round(top, 4),
                    "width": round(TEXT_RIGHT - TEXT_LEFT, 4),
                    "height": round(bottom - top, 4),
                })
        # Last ayah: from last boundary to page bottom
        if boundaries[-1] < 1.0:
            rects_per_ayah[-1].append({
                "x": round(TEXT_LEFT, 4),
                "y": round(boundaries[-1], 4),
                "width": round(TEXT_RIGHT - TEXT_LEFT, 4),
                "height": round(1.0 - boundaries[-1], 4),
            })
    else:
        # Fallback: evenly divide page
        step = 1.0 / ayah_count
        for i in range(ayah_count):
            top = i * step
            rects_per_ayah[i].append({
                "x": round(TEXT_LEFT, 4),
                "y": round(top, 4),
                "width": round(TEXT_RIGHT - TEXT_LEFT, 4),
                "height": round(step, 4),
            })

    return rects_per_ayah


def main():
    start_page = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    end_page = int(sys.argv[2]) if len(sys.argv) > 2 else 100

    # Load output.json for ayah counts
    raw = json.loads(OUTPUT_JSON.read_text(encoding="utf-8"))
    pages = []
    for item in raw:
        if isinstance(item, list):
            pages.extend(item)
        else:
            pages.append(item)
    page_map = {p["page"]: p for p in pages}

    # Detect surah-start pages
    surah_starts = set()
    for p in pages:
        for a in p["ayahs"]:
            if a["ayah"] == 1 and a["surah"] > 1:
                surah_starts.add(p["page"])
                break

    results = []
    errors = []
    
    for pg in range(start_page, end_page + 1):
        if pg not in page_map:
            continue
        
        page_data = page_map[pg]
        ayahs = page_data["ayahs"]
        ayah_count = len(ayahs)
        is_surah_start = pg in surah_starts
        
        try:
            markers = detect_gold_markers(pg)
            rects = build_ayah_rects(markers, ayah_count, pg, is_surah_start)
            
            page_result = {
                "page": pg,
                "ayahs": [
                    {
                        "surah": ayahs[i]["surah"],
                        "ayah": ayahs[i]["ayah"],
                        "rects": rects[i],
                    }
                    for i in range(ayah_count)
                ],
            }
            results.append(page_result)
            
            marker_info = f"markers={len(markers)}" if markers else "NO MARKERS"
            print(f"  Page {pg}: {ayah_count} ayahs, {marker_info}, surah_start={is_surah_start}")
            
        except Exception as e:
            errors.append(f"Page {pg}: {e}")
            print(f"  Page {pg}: ERROR - {e}")

    # Include page 1 (Al-Fatiha) with manual positions
    page1 = {
        "page": 1,
        "ayahs": [
            {"surah": 1, "ayah": 1, "rects": [{"x": 0.14, "y": 0.365, "width": 0.73, "height": 0.067}]},
            {"surah": 1, "ayah": 2, "rects": [{"x": 0.41, "y": 0.445, "width": 0.52, "height": 0.074}]},
            {"surah": 1, "ayah": 3, "rects": [{"x": 0.06, "y": 0.445, "width": 0.31, "height": 0.074}]},
            {"surah": 1, "ayah": 4, "rects": [{"x": 0.42, "y": 0.525, "width": 0.44, "height": 0.072}]},
            {"surah": 1, "ayah": 5, "rects": [{"x": 0.06, "y": 0.525, "width": 0.32, "height": 0.072}]},
            {"surah": 1, "ayah": 6, "rects": [{"x": 0.14, "y": 0.605, "width": 0.73, "height": 0.074}]},
            {"surah": 1, "ayah": 7, "rects": [
                {"x": 0.14, "y": 0.690, "width": 0.73, "height": 0.074},
                {"x": 0.30, "y": 0.775, "width": 0.57, "height": 0.074},
            ]},
        ],
    }
    results.insert(0, page1)

    # Sort and save
    results.sort(key=lambda p: p["page"])
    POSITIONS_JSON.write_text(
        json.dumps(results, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    
    print(f"\nSaved {len(results)} pages to {POSITIONS_JSON}")
    if errors:
        print(f"\nErrors ({len(errors)}):")
        for e in errors:
            print(f"  {e}")

    # Show sample
    print("\n=== Sample: Page 3 ===")
    for r in results:
        if r["page"] == 3:
            for a in r["ayahs"]:
                print(f"  s{a['surah']}:a{a['ayah']} -> {len(a['rects'])} rect(s)")
                for rect in a['rects']:
                    print(f"    y={rect['y']:.3f} h={rect['height']:.3f}")


if __name__ == "__main__":
    raise SystemExit(main())

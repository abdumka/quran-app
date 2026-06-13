import json
import re
import subprocess
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent
IMAGE_DIR = Path(r"C:\Users\Mahfod501\Desktop\images")
OUTPUT_JSON_PATH = PROJECT_ROOT / "assets" / "data" / "output.json"
POSITIONS_JSON_PATH = PROJECT_ROOT / "assets" / "data" / "ayah_positions.json"

GOLD_COMPONENT_RE = re.compile(
    r"^\s*(\d+):\s+(\d+)x(\d+)\+(\d+)\+(\d+)\s+([0-9.]+),([0-9.]+)\s+(\d+)\s+srgb\(255,255,255\)"
)
LINE_COMPONENT_RE = re.compile(
    r"^\s*(\d+):\s+(\d+)x(\d+)\+(\d+)\+(\d+)\s+([0-9.]+),([0-9.]+)\s+(\d+)\s+gray\(0\)"
)


def run_magick(args: list[str]) -> str:
    result = subprocess.run(
        ["magick", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "magick command failed")
    return (result.stdout or "") + "\n" + (result.stderr or "")


def read_image_size(image_path: Path) -> tuple[int, int]:
    result = subprocess.run(
        ["magick", str(image_path), "-format", "%w %h", "info:"],
        capture_output=True,
        text=True,
        check=True,
    )
    width_str, height_str = result.stdout.strip().split()
    return int(width_str), int(height_str)


def load_quran_pages() -> list[dict]:
    raw = json.loads(OUTPUT_JSON_PATH.read_text(encoding="utf-8"))
    pages: list[dict] = []
    for item in raw:
        if isinstance(item, list):
            pages.extend(item)
        else:
            pages.append(item)
    return pages


def load_existing_positions() -> dict[int, dict]:
    raw = json.loads(POSITIONS_JSON_PATH.read_text(encoding="utf-8"))
    return {item["page"]: item for item in raw}


def detect_raw_gold_components(image_path: Path) -> list[dict]:
    text = run_magick(
        [
            str(image_path),
            "-colorspace",
            "sRGB",
            "-fx",
            "(r>0.72 && g>0.62 && b<0.50)?1:0",
            "-define",
            "connected-components:verbose=true",
            "-connected-components",
            "8",
            "null:",
        ]
    )
    components: list[dict] = []
    for line in text.splitlines():
        match = GOLD_COMPONENT_RE.match(line)
        if not match:
            continue
        _, width, height, x, y, cx, cy, area = match.groups()
        width_i = int(width)
        height_i = int(height)
        area_i = int(area)
        if area_i < 12 or area_i > 2000:
            continue
        if width_i < 5 or width_i > 90 or height_i < 5 or height_i > 90:
            continue
        components.append(
            {
                "x": int(x),
                "y": int(y),
                "width": width_i,
                "height": height_i,
                "cx": float(cx),
                "cy": float(cy),
                "area": area_i,
            }
        )
    return components


def cluster_gold_components(components: list[dict]) -> list[dict]:
    clusters: list[dict] = []
    for component in sorted(components, key=lambda item: (item["cy"], item["cx"])):
        attached = None
        for cluster in clusters:
            if (
                abs(component["cx"] - cluster["cx"]) <= 34
                and abs(component["cy"] - cluster["cy"]) <= 40
            ):
                attached = cluster
                break
        if attached is None:
            attached = {"members": []}
            clusters.append(attached)
        attached["members"].append(component)

        xs = [item["x"] for item in attached["members"]]
        ys = [item["y"] for item in attached["members"]]
        rights = [item["x"] + item["width"] for item in attached["members"]]
        bottoms = [item["y"] + item["height"] for item in attached["members"]]

        attached["x"] = min(xs)
        attached["y"] = min(ys)
        attached["right"] = max(rights)
        attached["bottom"] = max(bottoms)
        attached["width"] = attached["right"] - attached["x"]
        attached["height"] = attached["bottom"] - attached["y"]
        attached["cx"] = sum(item["cx"] for item in attached["members"]) / len(
            attached["members"]
        )
        attached["cy"] = sum(item["cy"] for item in attached["members"]) / len(
            attached["members"]
        )
        attached["area"] = sum(item["area"] for item in attached["members"])
    return clusters


def select_markers(page_number: int, expected_ayah_count: int) -> list[dict]:
    image_path = IMAGE_DIR / f"page_{page_number}.webp"
    clusters = cluster_gold_components(detect_raw_gold_components(image_path))
    markers = [
        cluster
        for cluster in clusters
        if cluster["area"] >= 120
        and cluster["width"] >= 18
        and cluster["height"] >= 18
        and cluster["width"] <= 90
        and cluster["height"] <= 90
    ]
    markers.sort(key=lambda item: item["cy"])

    if page_number == 1:
        return []

    if page_number == 2:
        markers = [
            item
            for item in markers
            if 700 <= item["cy"] <= 1200 and item["area"] >= 450
        ]
        return markers[:expected_ayah_count]

    if page_number == 43:
        markers = [item for item in markers if item["cy"] > 200]

    if len(markers) == expected_ayah_count + 1:
        gaps = [
            markers[index + 1]["cy"] - markers[index]["cy"]
            for index in range(len(markers) - 1)
        ]
        if gaps:
            smallest_gap_index = min(range(len(gaps)), key=lambda index: gaps[index])
            if smallest_gap_index == 0 and markers[0]["cy"] < 180:
                markers = markers[1:]
            elif smallest_gap_index == len(gaps) - 1 and markers[-1]["cy"] > 1500:
                markers = markers[:-1]

    return markers


def detect_line_components(image_path: Path) -> list[dict]:
    text = run_magick(
        [
            str(image_path),
            "-colorspace",
            "Gray",
            "-fx",
            "u<0.72?1:0",
            "-morphology",
            "Close",
            "Rectangle:45x1",
            "-define",
            "connected-components:verbose=true",
            "-connected-components",
            "8",
            "null:",
        ]
    )

    components: list[dict] = []
    for line in text.splitlines():
        match = LINE_COMPONENT_RE.match(line)
        if not match:
            continue
        _, width, height, x, y, cx, cy, area = match.groups()
        width_i = int(width)
        height_i = int(height)
        area_i = int(area)
        if width_i < 70 or height_i < 10 or height_i > 150 or area_i < 900:
            continue
        components.append(
            {
                "x": int(x),
                "y": int(y),
                "width": width_i,
                "height": height_i,
                "right": int(x) + width_i,
                "bottom": int(y) + height_i,
                "cx": float(cx),
                "cy": float(cy),
                "area": area_i,
            }
        )

    components.sort(key=lambda item: (item["y"], item["x"]))
    return components


def vertical_overlap(a_top: float, a_bottom: float, b_top: float, b_bottom: float) -> float:
    return max(0.0, min(a_bottom, b_bottom) - max(a_top, b_top))


def build_bands(image_height: int, markers: list[dict], ayah_count: int) -> list[tuple[float, float]]:
    if not markers:
        step = image_height / max(ayah_count, 1)
        return [(index * step, (index + 1) * step) for index in range(ayah_count)]

    boundaries = [0.0]
    for index in range(len(markers) - 1):
        boundaries.append((markers[index]["cy"] + markers[index + 1]["cy"]) / 2.0)
    boundaries.append(float(image_height))

    if len(boundaries) == ayah_count + 1:
        return list(zip(boundaries[:-1], boundaries[1:]))

    if len(markers) == ayah_count:
        marker_centers = [item["cy"] for item in markers]
        starts = [0.0]
        for index in range(1, len(marker_centers)):
            starts.append((marker_centers[index - 1] + marker_centers[index]) / 2.0)
        ends = starts[1:] + [float(image_height)]
        return list(zip(starts, ends))

    if len(markers) == ayah_count - 1:
        return list(zip(boundaries[:-1], boundaries[1:]))

    raise ValueError(
        f"Page marker count mismatch: expected {ayah_count} ayahs, found {len(markers)} markers"
    )


def repair_marker_count(markers: list[dict], expected_ayah_count: int, image_height: int) -> list[dict]:
    if len(markers) != expected_ayah_count - 1 or not markers:
        return markers

    augmented = [dict(item) for item in markers]
    candidates = []

    first_gap = augmented[0]["cy"]
    candidates.append((first_gap, 0, first_gap / 2.0))

    for index in range(len(augmented) - 1):
        gap = augmented[index + 1]["cy"] - augmented[index]["cy"]
        midpoint = (augmented[index]["cy"] + augmented[index + 1]["cy"]) / 2.0
        candidates.append((gap, index + 1, midpoint))

    last_gap = image_height - augmented[-1]["cy"]
    candidates.append((last_gap, len(augmented), augmented[-1]["cy"] + (last_gap / 2.0)))

    gap_size, insert_index, synthetic_cy = max(candidates, key=lambda item: item[0])
    if gap_size < 80:
        return markers

    if insert_index == 0:
        synthetic_cx = augmented[0]["cx"]
    elif insert_index >= len(augmented):
        synthetic_cx = augmented[-1]["cx"]
    else:
        synthetic_cx = (augmented[insert_index - 1]["cx"] + augmented[insert_index]["cx"]) / 2.0

    augmented.insert(
        insert_index,
        {
            "cx": synthetic_cx,
            "cy": synthetic_cy,
            "x": synthetic_cx,
            "y": synthetic_cy,
            "width": 0,
            "height": 0,
            "right": synthetic_cx,
            "bottom": synthetic_cy,
            "area": 0,
            "synthetic": True,
        },
    )
    return augmented


def normalize_rect(x: float, y: float, width: float, height: float, image_width: int, image_height: int) -> dict | None:
    if width < 18 or height < 10:
        return None
    return {
        "x": round(max(0.0, min(1.0, x / image_width)), 6),
        "y": round(max(0.0, min(1.0, y / image_height)), 6),
        "width": round(max(0.0, min(1.0, width / image_width)), 6),
        "height": round(max(0.0, min(1.0, height / image_height)), 6),
    }


def build_fallback_rect(
    band_top: float,
    band_bottom: float,
    image_width: int,
    image_height: int,
    line_components: list[dict],
) -> dict | None:
    overlapping = [
        component
        for component in line_components
        if vertical_overlap(component["y"], component["bottom"], band_top, band_bottom)
        >= 8
    ]

    if overlapping:
        left = min(component["x"] for component in overlapping)
        right = max(component["right"] for component in overlapping)
        top = max(band_top, min(component["y"] for component in overlapping))
        bottom = min(band_bottom, max(component["bottom"] for component in overlapping))
        return normalize_rect(left, top, right - left, bottom - top, image_width, image_height)

    margin_x = image_width * 0.06
    top = min(image_height - 1.0, band_top + 6.0)
    bottom = max(top + 12.0, band_bottom - 6.0)
    return normalize_rect(
        margin_x,
        top,
        image_width - (margin_x * 2.0),
        bottom - top,
        image_width,
        image_height,
    )


def generate_page_positions(page_data: dict, existing_positions: dict[int, dict]) -> dict:
    page_number = page_data["page"]
    ayahs = page_data["ayahs"]
    image_path = IMAGE_DIR / f"page_{page_number}.webp"
    image_width, image_height = read_image_size(image_path)

    if page_number == 1 and page_number in existing_positions:
        return existing_positions[page_number]

    markers = select_markers(page_number, len(ayahs))
    markers = repair_marker_count(markers, len(ayahs), image_height)
    if len(markers) not in {len(ayahs), len(ayahs) - 1}:
        raise ValueError(
            f"Page {page_number}: expected {len(ayahs)} ayahs, found {len(markers)} markers"
        )

    bands = build_bands(image_height, markers, len(ayahs))
    line_components = detect_line_components(image_path)
    ayah_rects: list[list[dict]] = [[] for _ in ayahs]
    split_padding = 12.0

    for component in line_components:
        overlapping_indices = []
        for index, (band_top, band_bottom) in enumerate(bands):
            overlap = vertical_overlap(
                component["y"],
                component["bottom"],
                band_top,
                band_bottom,
            )
            if overlap >= min(18.0, component["height"] * 0.28):
                overlapping_indices.append(index)

        if not overlapping_indices:
            continue

        if len(overlapping_indices) == 1:
            index = overlapping_indices[0]
            band_top, band_bottom = bands[index]
            top = max(component["y"], band_top)
            bottom = min(component["bottom"], band_bottom)
            rect = normalize_rect(
                component["x"],
                top,
                component["width"],
                bottom - top,
                image_width,
                image_height,
            )
            if rect is not None:
                ayah_rects[index].append(rect)
            continue

        first_index = overlapping_indices[0]
        second_index = overlapping_indices[1]
        split_marker_index = min(first_index, len(markers) - 1)
        split_x = markers[split_marker_index]["cx"]

        first_top, first_bottom = bands[first_index]
        second_top, second_bottom = bands[second_index]

        right_rect = normalize_rect(
            max(component["x"], split_x + split_padding),
            max(component["y"], first_top),
            component["right"] - max(component["x"], split_x + split_padding),
            min(component["bottom"], first_bottom) - max(component["y"], first_top),
            image_width,
            image_height,
        )
        if right_rect is not None:
            ayah_rects[first_index].append(right_rect)

        left_rect = normalize_rect(
            component["x"],
            max(component["y"], second_top),
            min(component["right"], split_x - split_padding) - component["x"],
            min(component["bottom"], second_bottom) - max(component["y"], second_top),
            image_width,
            image_height,
        )
        if left_rect is not None:
            ayah_rects[second_index].append(left_rect)

    serialized_ayahs = []
    for index, (ayah, rects) in enumerate(zip(ayahs, ayah_rects)):
        if not rects:
            band_top, band_bottom = bands[index]
            fallback_rect = build_fallback_rect(
                band_top,
                band_bottom,
                image_width,
                image_height,
                line_components,
            )
            if fallback_rect is not None:
                rects.append(fallback_rect)
        serialized_ayahs.append(
            {
                "surah": ayah["surah"],
                "ayah": ayah["ayah"],
                "rects": sorted(rects, key=lambda item: (item["y"], item["x"])),
            }
        )

    return {"page": page_number, "ayahs": serialized_ayahs}


def main() -> int:
    start_page = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    end_page = int(sys.argv[2]) if len(sys.argv) > 2 else 100

    quran_pages = load_quran_pages()
    existing_positions = load_existing_positions()
    position_map = dict(existing_positions)

    page_lookup = {page["page"]: page for page in quran_pages}
    for page_number in range(start_page, end_page + 1):
        if page_number not in page_lookup:
            raise ValueError(f"Page {page_number} missing from output.json")
        position_map[page_number] = generate_page_positions(
            page_lookup[page_number],
            existing_positions,
        )
        print(f"Generated page {page_number}")

    ordered_pages = [position_map[page] for page in sorted(position_map)]
    POSITIONS_JSON_PATH.write_text(
        json.dumps(ordered_pages, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"Updated {POSITIONS_JSON_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

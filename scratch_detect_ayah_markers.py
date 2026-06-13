import re
import subprocess
import sys
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
IMAGE_DIR = ROOT / "assets" / "images"
DEFAULT_EXTERNAL_IMAGE_DIR = Path(r"C:\Users\Mahfod501\Desktop\images")


LINE_RE = re.compile(
    r"^\s*(\d+):\s+(\d+)x(\d+)\+(\d+)\+(\d+)\s+([0-9.]+),([0-9.]+)\s+(\d+)\s+srgb\(255,255,255\)"
)


def resolve_image_path(page_num: int, image_dir: Path | None = None) -> Path:
    search_dirs = []
    if image_dir is not None:
        search_dirs.append(image_dir)
    search_dirs.extend([DEFAULT_EXTERNAL_IMAGE_DIR, IMAGE_DIR])

    for directory in search_dirs:
        image_path = directory / f"page_{page_num}.webp"
        if image_path.exists():
            return image_path

    return (image_dir or DEFAULT_EXTERNAL_IMAGE_DIR) / f"page_{page_num}.webp"


def read_image_size(image_path: Path) -> tuple[int, int]:
    result = subprocess.run(
        ["magick", str(image_path), "-format", "%w %h", "info:"],
        capture_output=True,
        text=True,
        check=True,
    )
    width_str, height_str = result.stdout.strip().split()
    return int(width_str), int(height_str)


def detect_gold_components(page_num: int, image_dir: Path | None = None) -> list[dict]:
    image_path = resolve_image_path(page_num, image_dir)
    if not image_path.exists():
        raise FileNotFoundError(image_path)

    use_external_profile = image_path.parent == DEFAULT_EXTERNAL_IMAGE_DIR
    expression = (
        "(r>0.72 && g>0.62 && b<0.50)?1:0"
        if use_external_profile
        else "(r>0.72 && g>0.62 && b<0.50)?1:0"
    )
    min_area = 120 if use_external_profile else 12
    max_area = 900 if use_external_profile else 220
    min_width = 20 if use_external_profile else 5
    min_height = 18 if use_external_profile else 5
    max_width = 40 if use_external_profile else 35
    max_height = 60 if use_external_profile else 35

    command = [
        "magick",
        str(image_path),
        "-colorspace",
        "sRGB",
        "-fx",
        expression,
        "-define",
        "connected-components:verbose=true",
        "-connected-components",
        "8",
        "null:",
    ]

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )
    lines = (result.stdout or "") + "\n" + (result.stderr or "")
    components: list[dict] = []

    for line in lines.splitlines():
        match = LINE_RE.match(line)
        if not match:
            continue
        _, width, height, x, y, cx, cy, area = match.groups()
        width = int(width)
        height = int(height)
        x = int(x)
        y = int(y)
        area = int(area)
        cx = float(cx)
        cy = float(cy)

        # Ayah markers are small golden blobs; this filters out text noise.
        if area < min_area or area > max_area:
            continue
        if (
            width < min_width
            or height < min_height
            or width > max_width
            or height > max_height
        ):
            continue

        components.append(
            {
                "x": x,
                "y": y,
                "width": width,
                "height": height,
                "cx": cx,
                "cy": cy,
                "area": area,
            }
        )

    return components


def cluster_components(components: list[dict]) -> list[dict]:
    clusters: list[dict] = []

    for component in sorted(components, key=lambda item: (item["cy"], item["cx"])):
        attached = False
        for cluster in clusters:
            if (
                abs(component["cx"] - cluster["cx"]) <= 26
                and abs(component["cy"] - cluster["cy"]) <= 42
            ):
                cluster["members"].append(component)
                cluster["cx"] = sum(item["cx"] for item in cluster["members"]) / len(
                    cluster["members"]
                )
                cluster["cy"] = sum(item["cy"] for item in cluster["members"]) / len(
                    cluster["members"]
                )
                attached = True
                break
        if not attached:
            clusters.append(
                {
                    "cx": component["cx"],
                    "cy": component["cy"],
                    "members": [component],
                }
            )

    return clusters


def main() -> int:
    page_nums = [int(arg) for arg in sys.argv[1:]] or [4]
    output = []

    for page_num in page_nums:
        image_path = resolve_image_path(page_num)
        components = detect_gold_components(page_num)
        clusters = cluster_components(components)
        ordered_clusters = sorted(clusters, key=lambda item: item["cy"])
        _, image_height = read_image_size(image_path)
        ayah_bands = []
        for index, cluster in enumerate(ordered_clusters):
            if index == 0:
                top_y = 0.0
            else:
                top_y = (
                    ordered_clusters[index - 1]["cy"] + cluster["cy"]
                ) / 2.0

            if index == len(ordered_clusters) - 1:
                bottom_y = float(image_height)
            else:
                bottom_y = (
                    cluster["cy"] + ordered_clusters[index + 1]["cy"]
                ) / 2.0

            ayah_bands.append(
                {
                    "index": index + 1,
                    "topY": round(top_y, 3),
                    "bottomY": round(bottom_y, 3),
                    "markerY": round(cluster["cy"], 3),
                }
            )

        print(f"Page {page_num}")
        print(f"Image: {image_path}")
        print(f"Raw gold components: {len(components)}")
        print(f"Grouped marker candidates: {len(ordered_clusters)}")
        for index, cluster in enumerate(ordered_clusters, start=1):
            print(
                f"{index:02d}: cx={cluster['cx']:.1f}, cy={cluster['cy']:.1f}, parts={len(cluster['members'])}"
            )

        output.append(
            {
                "page": page_num,
                "markers": [
                    {
                        "index": index,
                        "cx": round(cluster["cx"], 3),
                        "cy": round(cluster["cy"], 3),
                        "parts": len(cluster["members"]),
                    }
                    for index, cluster in enumerate(ordered_clusters, start=1)
                ],
                "ayahBands": ayah_bands,
            }
        )

    print("\nJSON:")
    print(json.dumps(output, ensure_ascii=False, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

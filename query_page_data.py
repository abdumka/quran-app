import json
import sys
from pathlib import Path

def query_page(page_number: int):
    """
    Queries the output.json file to find the first and last ayah of a given page.
    """
    project_root = Path(__file__).resolve().parent
    output_json_path = project_root / "assets" / "data" / "output.json"

    if not output_json_path.exists():
        print(f"Error: Data file not found at {output_json_path}")
        return

    try:
        with open(output_json_path, 'r', encoding='utf-8') as f:
            quran_data_nested = json.load(f)
    except Exception as e:
        print(f"Error reading or parsing JSON file: {e}")
        return

    # The JSON can be a list of lists, so we need to flatten it.
    quran_data = []
    for item in quran_data_nested:
        if isinstance(item, list):
            quran_data.extend(item)
        else:
            quran_data.append(item)

    page_data = next((p for p in quran_data if p.get("page") == page_number), None)

    if not page_data or not page_data.get("ayahs"):
        print(f"No data found for page {page_number}.")
        return

    ayahs_on_page = page_data["ayahs"]
    first_ayah = ayahs_on_page[0]
    last_ayah = ayahs_on_page[-1]

    print(f"--- Page {page_number} ---")
    print(f"First Ayah: Surah {first_ayah['surah']} ({first_ayah['surahName']}), Ayah {first_ayah['ayah']}")
    print(f"Last Ayah:  Surah {last_ayah['surah']} ({last_ayah['surahName']}), Ayah {last_ayah['ayah']}")
    print(f"Total Ayahs on page: {len(ayahs_on_page)}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python query_page_data.py <page_number>")
        sys.exit(1)

    try:
        page_num_to_query = int(sys.argv[1])
        if not 1 <= page_num_to_query <= 604:
             raise ValueError("Page number must be between 1 and 604.")
        query_page(page_num_to_query)
    except ValueError as e:
        print(f"Invalid page number: {e}")
        sys.exit(1)
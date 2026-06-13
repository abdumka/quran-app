import json, sys
sys.stdout.reconfigure(encoding='utf-8')

with open(r'assets/data/ayah_positions.json', encoding='utf-8') as f:
    positions = json.load(f)

with open(r'assets/data/output.json', encoding='utf-8') as f:
    raw = json.load(f)

# Flatten if nested
output = []
for item in raw:
    if isinstance(item, list):
        output.extend(item)
    else:
        output.append(item)

# Check pages with surah starts
surah_start_pages = []
for page in output:
    for ayah in page['ayahs']:
        if ayah['ayah'] == 1 and ayah['surah'] > 1:
            surah_start_pages.append(page['page'])
            break

pos_map = {p['page']: p for p in positions}

print("=== Surah Header Pages (first 10) ===")
for pg in surah_start_pages[:10]:
    if pg not in pos_map:
        print(f"  Page {pg}: NO POSITION DATA")
        continue
    page_pos = pos_map[pg]
    print(f"\n  Page {pg}:")
    for ayah in page_pos['ayahs']:
        rects_info = []
        for r in ayah['rects']:
            rects_info.append(f"y={r['y']:.3f} h={r['height']:.3f}")
        print(f"    s{ayah['surah']}:a{ayah['ayah']} -> {', '.join(rects_info)}")

# Check overlap
print("\n=== Rect Overlap (pages 2-10) ===")
for pg_num in range(2, 11):
    if pg_num not in pos_map:
        continue
    ayahs = pos_map[pg_num]['ayahs']
    for i in range(len(ayahs) - 1):
        a1 = ayahs[i]
        a2 = ayahs[i + 1]
        for r1 in a1['rects']:
            for r2 in a2['rects']:
                r1_bottom = r1['y'] + r1['height']
                if r1_bottom > r2['y'] + 0.005:
                    print(f"  Page {pg_num}: s{a1['surah']}:a{a1['ayah']} bot={r1_bottom:.3f} > s{a2['surah']}:a{a2['ayah']} top={r2['y']:.3f}")

# Check specific page from screenshot (looks like page 50 area - Al-Imran)  
# The screenshot shows surah header so check a small surah start page
print("\n=== Page 44 (has surah start?) ===")
if 44 in pos_map:
    for ayah in pos_map[44]['ayahs']:
        for r in ayah['rects']:
            print(f"  s{ayah['surah']}:a{ayah['ayah']} x={r['x']:.3f} y={r['y']:.3f} w={r['width']:.3f} h={r['height']:.3f}")

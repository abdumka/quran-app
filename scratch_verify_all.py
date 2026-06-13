import json

with open('assets/data/output.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# Flatten if needed (some structures nest pages in sub-arrays)
flat_data = []
for item in data:
    if isinstance(item, list):
        flat_data.extend(item)
    else:
        flat_data.append(item)

print(f"Total pages in data: {len(flat_data)}")
print(f"First page number: {flat_data[0]['page']}")
print(f"Last page number: {flat_data[-1]['page']}")
print()

# Build page lookup
page_map = {p['page']: p for p in flat_data}

# Check pages 585 and 586 (Al-Mutaffifin / Al-Inshiqaq boundary)
for page_num in [585, 586]:
    if page_num not in page_map:
        print(f"Page {page_num}: NOT FOUND")
        continue
    p = page_map[page_num]
    ayahs = p['ayahs']
    first = ayahs[0]
    last = ayahs[-1]
    print(f"Page {page_num}:")
    print(f"  First: Surah {first['surah']} ({first['surahName']}), Ayah {first['ayah']}")
    print(f"  Last:  Surah {last['surah']} ({last['surahName']}), Ayah {last['ayah']}")
    print(f"  Total ayahs: {len(ayahs)}")
    
    surahs = set()
    for a in ayahs:
        surahs.add(f"{a['surah']}:{a['surahName']}")
    print(f"  Surahs: {sorted(surahs)}")
    print()

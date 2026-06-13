import json

with open(r'c:\Users\Mahfod501\Desktop\flutter\quran\quran_app\assets\data\ayah_positions.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

print(f"Total page entries: {len(data)}")
for page_entry in data[:5]:
    p = page_entry['page']
    a = len(page_entry['ayahs'])
    print(f"  Page {p}: {a} ayahs")

# Check pages that have rects with non-zero values
pages_with_data = 0
pages_empty_rects = 0
for page_entry in data:
    has_rects = False
    for ayah in page_entry.get('ayahs', []):
        if ayah.get('rects') and len(ayah['rects']) > 0:
            has_rects = True
            break
    if has_rects:
        pages_with_data += 1
    else:
        pages_empty_rects += 1

print(f"\nPages with actual rect data: {pages_with_data}")
print(f"Pages with no/empty rects: {pages_empty_rects}")
print(f"Max page number: {max(p['page'] for p in data)}")
print(f"Min page number: {min(p['page'] for p in data)}")

import json, sys
sys.stdout.reconfigure(encoding='utf-8')

d = json.load(open('assets/data/ayah_positions.json', 'r', encoding='utf-8'))

# Stats
match = 0
mismatch = 0
for p in d:
    for a in p['ayahs']:
        if len(a['rects']) == 1:
            match += 1
        elif len(a['rects']) == 0:
            mismatch += 1

print(f"Total ayahs with 1 rect: {match}")
print(f"Total ayahs with 0 rects: {mismatch}")

# Check page 3 and 50
for pg_num in [3, 50, 77]:
    pg = next((p for p in d if p['page'] == pg_num), None)
    if not pg:
        continue
    print(f"\nPage {pg_num}:")
    for a in pg['ayahs']:
        if a['rects']:
            r = a['rects'][0]
            print(f"  s{a['surah']}:a{a['ayah']} y={r['y']:.3f} h={r['height']:.3f}")
        else:
            print(f"  s{a['surah']}:a{a['ayah']} NO RECTS!")

import json

# Check output.json page data (used by AudioService)
with open(r'assets/data/output.json', encoding='utf-8') as f:
    output_data = json.load(f)

# Check ayah_positions.json 
with open(r'assets/data/ayah_positions.json', encoding='utf-8') as f:
    positions_data = json.load(f)

# Compare page 1
out_p1 = next(p for p in output_data if p['page'] == 1)
pos_p1 = next(p for p in positions_data if p['page'] == 1)

print("=== output.json Page 1 ===")
for a in out_p1['ayahs']:
    print(f"  surah={a['surah']}, ayah={a['ayah']}")

print("\n=== ayah_positions.json Page 1 ===")
for a in pos_p1['ayahs']:
    print(f"  surah={a['surah']}, ayah={a['ayah']}, rects={len(a['rects'])}")

# Compare page 2
out_p2 = next(p for p in output_data if p['page'] == 2)
pos_p2 = next(p for p in positions_data if p['page'] == 2)

print("\n=== output.json Page 2 ===")
for a in out_p2['ayahs']:
    print(f"  surah={a['surah']}, ayah={a['ayah']}")

print("\n=== ayah_positions.json Page 2 ===")
for a in pos_p2['ayahs']:
    print(f"  surah={a['surah']}, ayah={a['ayah']}, rects={len(a['rects'])}")

# Check a few more pages for consistency
for pnum in [3, 5, 10, 50, 100]:
    out_p = next((p for p in output_data if p['page'] == pnum), None)
    pos_p = next((p for p in positions_data if p['page'] == pnum), None)
    if out_p and pos_p:
        out_keys = set(f"{a['surah']}:{a['ayah']}" for a in out_p['ayahs'])
        pos_keys = set(f"{a['surah']}:{a['ayah']}" for a in pos_p['ayahs'])
        match = out_keys == pos_keys
        only_in_out = out_keys - pos_keys
        only_in_pos = pos_keys - out_keys
        print(f"\nPage {pnum}: match={match}, out_ayahs={len(out_keys)}, pos_ayahs={len(pos_keys)}")
        if only_in_out:
            print(f"  Only in output: {only_in_out}")
        if only_in_pos:
            print(f"  Only in positions: {only_in_pos}")

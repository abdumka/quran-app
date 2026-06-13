"""
Post-process ayah_positions.json:
1. Merge overlapping/adjacent rects within each ayah into fewer, larger rects
2. Detect surah header regions on surah-start pages and exclude them from ayah 1
"""
import json, sys
sys.stdout.reconfigure(encoding='utf-8')

INPUT = r'assets/data/ayah_positions.json'
OUTPUT_JSON = r'assets/data/output.json'

# ── Load data ──
with open(INPUT, encoding='utf-8') as f:
    positions = json.load(f)
with open(OUTPUT_JSON, encoding='utf-8') as f:
    raw = json.load(f)
output_pages = []
for item in raw:
    if isinstance(item, list):
        output_pages.extend(item)
    else:
        output_pages.append(item)
output_map = {p['page']: p for p in output_pages}

# ── Surah-start pages: find pages where ayah 1 of a surah > 1 appears ──
surah_start_pages = set()
for page in output_pages:
    for ayah in page['ayahs']:
        if ayah['ayah'] == 1 and ayah['surah'] > 1:
            surah_start_pages.add(page['page'])
            break

# Approximate normalized header height (surah title + bismillah)
# Based on typical mushaf layout: ~15-22% of page height
HEADER_MIN_Y = 0.14  # First ayah rects should start below this on header pages


def merge_rects(rects, vertical_gap=0.012, horizontal_gap=0.03):
    """Merge overlapping or very close rects into larger unified rects.
    
    Strategy: group rects into horizontal lines (by y overlap), 
    then merge rects on the same line.
    """
    if not rects:
        return []
    
    # Sort by y then x
    sorted_rects = sorted(rects, key=lambda r: (r['y'], r['x']))
    
    # Group into lines: rects with similar y values
    lines = []
    for rect in sorted_rects:
        added = False
        for line in lines:
            # Check if this rect is on the same vertical line as existing rects
            for existing in line:
                # Check vertical overlap
                r_top = rect['y']
                r_bot = rect['y'] + rect['height']
                e_top = existing['y']
                e_bot = existing['y'] + existing['height']
                overlap = min(r_bot, e_bot) - max(r_top, e_top)
                min_h = min(rect['height'], existing['height'])
                if min_h > 0 and overlap / min_h > 0.3:
                    line.append(rect)
                    added = True
                    break
                # Or very close vertically
                if abs(r_top - e_top) < vertical_gap and abs(r_bot - e_bot) < vertical_gap:
                    line.append(rect)
                    added = True
                    break
            if added:
                break
        if not added:
            lines.append([rect])
    
    # Merge each line into one bounding rect
    merged = []
    for line in lines:
        if not line:
            continue
        min_x = min(r['x'] for r in line)
        min_y = min(r['y'] for r in line)
        max_right = max(r['x'] + r['width'] for r in line)
        max_bottom = max(r['y'] + r['height'] for r in line)
        
        w = max_right - min_x
        h = max_bottom - min_y
        
        # Skip very small rects (noise)
        if w < 0.03 or h < 0.008:
            continue
        
        merged.append({
            'x': round(min_x, 6),
            'y': round(min_y, 6),
            'width': round(w, 6),
            'height': round(h, 6),
        })
    
    # Second pass: merge rects that are still vertically adjacent
    if len(merged) > 1:
        merged.sort(key=lambda r: r['y'])
        final = [merged[0]]
        for rect in merged[1:]:
            prev = final[-1]
            prev_bot = prev['y'] + prev['height']
            # If this rect starts very close to where the previous one ended
            # and they overlap horizontally significantly
            h_overlap = min(prev['x'] + prev['width'], rect['x'] + rect['width']) - max(prev['x'], rect['x'])
            if rect['y'] - prev_bot < vertical_gap and h_overlap > 0.1:
                # Merge
                new_x = min(prev['x'], rect['x'])
                new_y = min(prev['y'], rect['y'])
                new_right = max(prev['x'] + prev['width'], rect['x'] + rect['width'])
                new_bot = max(prev_bot, rect['y'] + rect['height'])
                final[-1] = {
                    'x': round(new_x, 6),
                    'y': round(new_y, 6),
                    'width': round(new_right - new_x, 6),
                    'height': round(new_bot - new_y, 6),
                }
            else:
                final.append(rect)
        merged = final
    
    return merged


def process_page(page_data):
    page_num = page_data['page']
    is_surah_start = page_num in surah_start_pages
    
    new_ayahs = []
    for ayah in page_data['ayahs']:
        rects = ayah['rects']
        
        # On surah-start pages, filter out rects that fall in the header region
        # for the first ayah (ayah == 1)
        if is_surah_start and ayah['ayah'] == 1:
            # Find first ayah that has rects clearly below header
            # Header is typically: surah name bar + bismillah, roughly top 14-22%
            filtered = [r for r in rects if r['y'] >= HEADER_MIN_Y]
            if filtered:
                rects = filtered
            else:
                # If all rects are in header region, keep rects below y=0.08 at minimum
                rects = [r for r in rects if r['y'] >= 0.08]
        
        merged = merge_rects(rects)
        
        new_ayahs.append({
            'surah': ayah['surah'],
            'ayah': ayah['ayah'],
            'rects': merged,
        })
    
    return {'page': page_num, 'ayahs': new_ayahs}


# ── Process all pages ──
new_positions = []
stats = {'total_rects_before': 0, 'total_rects_after': 0, 'pages': 0}

for page_data in positions:
    before_count = sum(len(a['rects']) for a in page_data['ayahs'])
    
    processed = process_page(page_data)
    after_count = sum(len(a['rects']) for a in processed['ayahs'])
    
    stats['total_rects_before'] += before_count
    stats['total_rects_after'] += after_count
    stats['pages'] += 1
    
    new_positions.append(processed)

# ── Save ──
with open(INPUT, 'w', encoding='utf-8') as f:
    json.dump(new_positions, f, ensure_ascii=False, indent=2)

print(f"Processed {stats['pages']} pages")
print(f"Rects: {stats['total_rects_before']} -> {stats['total_rects_after']} "
      f"({stats['total_rects_before'] - stats['total_rects_after']} removed)")
print(f"Surah-start pages affected: {len(surah_start_pages & set(p['page'] for p in positions))}")

# Show sample result
print("\n=== Sample: Page 50 (Al-Imran start) after processing ===")
for p in new_positions:
    if p['page'] == 50:
        for ayah in p['ayahs']:
            for r in ayah['rects']:
                print(f"  s{ayah['surah']}:a{ayah['ayah']} x={r['x']:.3f} y={r['y']:.3f} w={r['width']:.3f} h={r['height']:.3f}")

print("\n=== Sample: Page 2 (Al-Baqarah start) after processing ===")
for p in new_positions:
    if p['page'] == 2:
        for ayah in p['ayahs']:
            for r in ayah['rects']:
                print(f"  s{ayah['surah']}:a{ayah['ayah']} x={r['x']:.3f} y={r['y']:.3f} w={r['width']:.3f} h={r['height']:.3f}")

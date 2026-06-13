import json
import urllib.request
import re

def clean(text):
    return re.sub(r'[^\u0621-\u064A]', '', text).replace('ي', 'ی').replace('ے', 'ی').replace('ا', 'ا').replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا').replace('ة', 'ه')

# Load Qalon
with open('assets/data/output.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

qalon_ayahs = []
for page in data:
    # Handle list of pages or list of lists
    pages = page if isinstance(page, list) else [page]
    for p in pages:
        for a in p.get('ayahs', []):
            if a['surah'] == 18:
                qalon_ayahs.append(clean(a['text']))

# Load Hafs
with urllib.request.urlopen('https://api.alquran.cloud/v1/surah/18') as url:
    hafs_data = json.loads(url.read().decode())

hafs_ayahs = [clean(a['text']) for a in hafs_data['data']['ayahs']]
# Strip basmalah
if hafs_ayahs[0].startswith('بسماللهالرحمنالرحیم'):
    hafs_ayahs[0] = hafs_ayahs[0][len('بسماللهالرحمنالرحیم'):]

q = 0
h = 0
merges = []
while q < len(qalon_ayahs) and h < len(hafs_ayahs):
    if qalon_ayahs[q] == hafs_ayahs[h]:
        q += 1; h += 1; continue
        
    # Check if Q combines H and H+1
    if h + 1 < len(hafs_ayahs):
        combined = hafs_ayahs[h] + hafs_ayahs[h+1]
        # Allow slight differences
        if abs(len(qalon_ayahs[q]) - len(combined)) < 10:
            merges.append(q + 1) # 1-based index
            q += 1; h += 2; continue
            
    # Try 3 ayahs
    if h + 2 < len(hafs_ayahs):
        combined = hafs_ayahs[h] + hafs_ayahs[h+1] + hafs_ayahs[h+2]
        if abs(len(qalon_ayahs[q]) - len(combined)) < 10:
            merges.append(q + 1)
            q += 1; h += 3; continue

    # Fallback to simple skip if nothing matches exactly (rare)
    q += 1; h += 1

print("Merges found at Qalon Ayah numbers:", merges)

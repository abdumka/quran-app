"""assets/data/khilaf.json: the «خلافات القراء» sheet data (owner, 2026-11-17).

The source's cards verbatim, in the source's order: the word as the source writes it, the
readers as the source names them («باقي الرواة» included), the description word for word.
The only changes: (1) each card is filed under our (Qaloon) ayah number, from the verified
mapping in output/nquran_qaloon_native; (2) the row that covers Qalun is moved first.
Nothing is classified, reworded or added.

Inputs: C:/Down/Books/khilaf/review_2026-11-13/data/source_parsed.json (parse of the cached
source pages, checked 100% against them) + readers.json, and the mapping file above.
Format: {"v":1, "w":[reader labels], "d":[descriptions], "p":[card rows: [[w, d], ...]],
         "a":{"s:a":[[word, p], ...]}}   w/d/p index the lists; w = -1: no reader label
"""
import json, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
KH = Path(r'C:/Down/Books/khilaf/review_2026-11-13/data')
OUT = REPO / 'assets/data/khilaf.json'
QALUN = 2

src = json.loads((KH / 'source_parsed.json').read_text(encoding='utf-8'))
readers = json.loads((KH / 'readers.json').read_text(encoding='utf-8'))
name, reader_of, narrs = {}, {}, {}
for r in readers:
    name[r['id']] = r['name']; narrs[r['id']] = [n['id'] for n in r['narrators']]
    for n in r['narrators']:
        name[n['id']] = n['name']; reader_of[n['id']] = r['id']
ALL = {n for r in readers for n in narrs[r['id']]}

def gen(nm):
    return 'أبي ' + nm[4:] if nm.startswith('أبو ') else nm

def label(rids):
    parts = []
    for i, x in enumerate(rids):
        if x in reader_of:
            parts.append(f'{name[x]} عن {gen(name[rids[i + 1]])}' if i + 1 < len(rids) and rids[i + 1] == reader_of[x] else name[x])
        elif not (i and reader_of.get(rids[i - 1]) == x):
            parts.append(name[x])
    return '، '.join(parts)

def ids_of(rids):
    s = set()
    for i, x in enumerate(rids):
        if x in reader_of:
            s.add(x)
        elif not (i and reader_of.get(rids[i - 1]) == x):
            s |= set(narrs[x])
    return s

big = json.loads((REPO / 'output/nquran_qaloon_native/qaloon_all_readers.json').read_text(encoding='utf-8'))
place = {}
for s in big['surahs']:
    for a in s['ayahs']:
        for e in a['differences']:
            place[e['source']['id']] = (s['surah_number'], a['ayah_number'])
del big

W, D, Wi, Di, A, P, Pi = [], [], {}, {}, {}, [], {}
def idx(lst, ix, x):
    if x not in ix:
        ix[x] = len(lst); lst.append(x)
    return ix[x]

n_cards = moved = 0
for key, v in src.items():
    for ei, e in enumerate(v['entries'], 1):
        s, a = place[f'{key}:{ei}']
        named = set()
        for x in e['variants']:
            if not x['rest']:
                named |= ids_of(x['rids'])
        rows = []
        for x in e['variants']:
            who = 'باقي الرواة' if x['rest'] else label(x['rids'])
            ids = ALL - named if x['rest'] else ids_of(x['rids'])
            rows.append((QALUN not in ids, [idx(W, Wi, who) if who else -1, idx(D, Di, x['desc'])]))
        if rows and rows[0][0] and any(not q for q, _ in rows):
            moved += 1
        rows.sort(key=lambda r: r[0])  # stable: Qalun's row first, the rest keep the source's order
        A.setdefault(f'{s}:{a}', []).append([e['phrase'], idx(P, Pi, json.dumps([r for _, r in rows]))])
        n_cards += 1

OUT.write_text(json.dumps({'v': 1, 'w': W, 'd': D, 'p': [json.loads(x) for x in P], 'a': A}, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
print(f'{n_cards} cards in {len(A)} ayat; {len(W)} labels, {len(D)} descriptions, {len(P)} card shapes; Qalun row moved up in {moved}; '
      f'{OUT.stat().st_size / 1024:.0f} KB -> {OUT}')
assert n_cards == 33603, n_cards

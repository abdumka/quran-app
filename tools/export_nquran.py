"""Download and export NQuran's public al-ashr al-sughra difference tables.

Requires requests, beautifulsoup4 and lxml. Responses are cached for resumption.
Run: python tools/export_nquran.py
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import threading
import time
import unicodedata
from urllib.parse import urlencode

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'scratch' / 'nquran' / 'cache'
OUT = ROOT / 'output' / 'nquran'
BASE = 'https://www.nquran.com/ar/'
LOCAL = threading.local()


def text(node):
    return re.sub(r'\s+', ' ', node.get_text(' ', strip=True)).strip() if node else ''


def soup(data):
    try:
        decoded = data.decode('utf-8')
    except UnicodeDecodeError:
        decoded = data.decode('cp1256')
    return BeautifulSoup(decoded, 'lxml')


def fetch(key, path, params=None):
    file = CACHE / (key + '.html.gz')
    if file.exists():
        return gzip.decompress(file.read_bytes())
    if not hasattr(LOCAL, 'session'):
        LOCAL.session = requests.Session()
        LOCAL.session.headers['User-Agent'] = 'QuranReadingsResearchExport/1.0 (public reading tables; cached requests)'
    for attempt in range(6):
        try:
            r = LOCAL.session.get(BASE + path, params=params, timeout=(20, 90))
            r.raise_for_status()
            data = r.content
            if not data or b'cf-chl-' in data:
                raise ValueError('Empty response or challenge')
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(gzip.compress(data, mtime=0))
            time.sleep(0.12)
            return data
        except (requests.RequestException, ValueError):
            if attempt == 5:
                raise
            time.sleep(min(30, 2 ** attempt))


def save_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
    if re.search('[\u0660-\u0669\u06f0-\u06f9]', encoded):
        raise ValueError(f'Non-Western digits in {path}; review required before exporting Quran text')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(encoded, encoding='utf-8')


def index_surah(item):
    number, name = item
    data = fetch(f'index_{number:03}', 'jquery_tb/ajaxpages/ayat.php', {'tpath': 2, 'sora': number})
    options = soup(data).select('#ayano option')
    ayahs = []
    for option in options:
        value = option.get('value', '')
        if not re.fullmatch(r'\d+,\d+', value):
            continue
        a, source_id = map(int, value.split(','))
        preview = re.sub(r'^\d+\s*-\s*', '', text(option))
        ayahs.append({'ayah_number': a, 'source_ayah_selector': value,
                      'source_selector_id': source_id, 'source_ayah_preview': preview})
    if [a['ayah_number'] for a in ayahs] != list(range(1, len(ayahs) + 1)) or not ayahs:
        raise ValueError(f'Invalid ayah index: {number}')
    return {'surah_number': number, 'surah_name': name, 'ayah_count': len(ayahs), 'ayahs': ayahs}


def download_ayah(task):
    surah, ayah = task
    selector = ayah['source_ayah_selector']
    key = f"ayah_{surah['surah_number']:03}_{ayah['ayah_number']:03}"
    params = {'a': 1, 'qareeRwaistr': '', 'enfradtype': 0, 'enfradmode': 0,
              'tpath': 2, 'rid': selector, 'tareekid': '', 'aya': selector,
              'sora': surah['surah_number']}
    data = fetch(key, 'jquery_tb/ajaxpages/aqwal1.php', params)
    page = soup(data)
    if not page.select('.quran-page') and 'لا خلاف بين القراء في هذه الآية' not in text(page):
        raise ValueError(f'Unrecognized ayah response: {key}')
    return key


def download(workers):
    bootstrap = soup(fetch('bootstrap', 'index.php', {'group': 'tb1', 'tpath': 2,
                     'aya_no': '1,1', 'sorano': 1, 'mRwai': ''}))
    surah_options = [(int(o['value']), text(o)) for o in bootstrap.select('#sorano option') if o.get('value', '').isdigit()]
    if len(surah_options) != 114:
        raise ValueError('Expected 114 surahs')
    indexes = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for f in as_completed([pool.submit(index_surah, s) for s in surah_options]):
            indexes.append(f.result())
    indexes.sort(key=lambda x: x['surah_number'])
    save_json(CACHE / 'index.json', indexes)
    readers = []
    for option in bootstrap.select('#qaree option'):
        if not option.get('value', '').isdigit():
            continue
        rid = int(option['value'])
        data = fetch(f'reader_{rid:02}', 'jquery_tb/ajaxpages/rawi.php', {'tpath': 2, 'id': rid})
        narrators = [{'id': int(o['value']), 'name': text(o), 'reader_id': rid}
                     for o in soup(data).select('option') if o.get('value', '').isdigit()]
        if len(narrators) != 2:
            raise ValueError(f'Expected 2 narrators for {rid}')
        readers.append({'id': rid, 'name': text(option), 'narrators': narrators})
    save_json(CACHE / 'readers.json', readers)
    tasks = [(s, a) for s in indexes for a in s['ayahs']]
    print(f'Indexed {len(indexes)} surahs, {len(tasks)} ayahs, {len(readers)} readers', flush=True)
    errors = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        pending = {pool.submit(download_ayah, task): task for task in tasks}
        for n, f in enumerate(as_completed(pending), 1):
            try:
                f.result()
            except Exception as e:
                task = pending[f]
                errors.append({'surah': task[0]['surah_number'], 'ayah': task[1]['ayah_number'], 'error': str(e)})
                print(f'ERROR {errors[-1]}', flush=True)
            if n % 100 == 0 or n == len(tasks):
                print(f'Downloaded/verified {n}/{len(tasks)} ayahs; errors={len(errors)}', flush=True)
    save_json(CACHE / 'download_errors.json', errors)
    if errors:
        raise RuntimeError(f'{len(errors)} downloads failed. Rerun to resume.')


def normalize_for_matching(value):
    """Search key only; never used to replace any exported Quran quotation."""
    value = value.replace('ـ', '').replace('ٱ', 'ا')
    return ''.join(c for c in value if not unicodedata.category(c).startswith('M'))


def locate_phrase(phrase, ayah_text):
    tokens = ayah_text.split() if ayah_text else []
    wanted = [normalize_for_matching(t) for t in phrase.split()]
    actual = [normalize_for_matching(t) for t in tokens]
    candidates = []
    for i in range(len(actual) - len(wanted) + 1):
        if wanted and actual[i:i + len(wanted)] == wanted:
            candidates.append(list(range(i + 1, i + len(wanted) + 1)))
    return {'word_numbers': candidates[0] if len(candidates) == 1 else None,
            'candidate_word_number_spans': candidates,
            'status': 'unique_match' if len(candidates) == 1 else 'ambiguous_match' if candidates else 'unmatched_context',
            'numbering': '1-based whitespace tokens in source_ayah_text; not source database word IDs'}


def parse_ayah(surah, ayah, readers, narrators):
    sn, an = surah['surah_number'], ayah['ayah_number']
    key = f'ayah_{sn:03}_{an:03}'
    raw = gzip.decompress((CACHE / (key + '.html.gz')).read_bytes())
    page = soup(raw)
    cards = page.select('.quran-page')
    heads = [h for h in page.select('h2') if h.select('.quran-page')]
    if sum(len(h.select('.quran-page')) for h in heads) != len(cards):
        raise ValueError(f'Unparsed reading cards: {key}')
    source_texts = []
    source_numbers = []
    for font in page.select('font[color="#E17426"]'):
        m = re.fullmatch(r'\{(.*?)\}\s*-\s*رقم الآية:\s*(\d+)', text(font))
        if m:
            source_texts.append(m[1])
            source_numbers.append(int(m[2]))
    if heads and (not source_texts or set(source_numbers) != {an} or len(set(source_texts)) != 1):
        raise ValueError(f'Inconsistent ayah headings: {key}')
    no_differences = 'لا خلاف بين القراء في هذه الآية' in text(page)
    if not heads and not no_differences:
        raise ValueError(f'Neither differences nor explicit no-difference notice: {key}')
    if heads and no_differences:
        raise ValueError(f'Conflicting ayah status: {key}')
    full_text = source_texts[0] if source_texts else (ayah['source_ayah_preview'] if '...' not in ayah['source_ayah_preview'] else None)
    all_narrators = set(narrators)
    differences = []
    for di, h in enumerate(heads, 1):
        label = text(h.find('strong', recursive=False))
        if not label.startswith('{') or not label.endswith('}'):
            raise ValueError(f'Missing word heading: {key}/{di}')
        phrase = label[1:-1]
        variants = []
        for vi, card in enumerate(h.select('.quran-page'), 1):
            attribution = card.select_one('ol.rawa-list')
            description_node = card.select_one('li')
            if not attribution or not description_node:
                raise ValueError(f'Malformed reading: {key}/{di}/{vi}')
            linked = []
            for link in attribution.select('a[data-src]'):
                match = re.search(r'Rid=(\d+)', link['data-src'])
                if not match:
                    raise ValueError(f'Unknown attribution link: {key}')
                rid = int(match[1])
                catalog = readers.get(rid) or narrators.get(rid)
                if catalog is None:
                    raise ValueError(f'Unknown reader/narrator ID {rid}')
                linked.append({'id': rid, 'name_as_displayed': text(link),
                               'kind': 'reader' if rid in readers else 'narrator'})
            resolved = set()
            i = 0
            while i < len(linked):
                rid = linked[i]['id']
                if rid in narrators:
                    resolved.add(rid)
                    if i + 1 < len(linked) and linked[i + 1]['id'] == narrators[rid]['reader_id']:
                        i += 1  # "narrator عن reader" is one attribution, not both narrators.
                else:
                    resolved.update(n['id'] for n in readers[rid]['narrators'])
                i += 1
            attribution_text = text(attribution)
            if linked:
                kind = 'named'
            elif attribution_text == 'باقي الرواة':
                kind = 'remaining_narrators'
            elif attribution_text == 'كل الرواة':
                kind = 'all_narrators'
                resolved = set(all_narrators)
            else:
                raise ValueError(f'Unknown unlinked attribution {attribution_text!r}: {key}')
            description = text(description_node)
            if text(card) != attribution_text + ' ' + description:
                raise ValueError(f'Uncaptured reading-card text: {key}/{di}/{vi}')
            forms = re.findall(r'(?:قرأ|قرؤوا|قرا|قرءوا)\s*[（(]([^()（）]+)[）)]', description)
            variants.append({'variant_number': vi, 'attribution_text_ar': attribution_text,
                             'attribution_kind': kind, 'source_reader_narrator_references': linked,
                             'narrator_ids': sorted(resolved),
                             'reading_description_ar': description,
                             'explicit_reading_forms': forms,
                             'parenthetical_texts': re.findall(r'\(([^()]+)\)', description)})
        explicit = set().union(*(set(v['narrator_ids']) for v in variants if v['attribution_kind'] != 'remaining_narrators'))
        for v in variants:
            if v['attribution_kind'] == 'remaining_narrators':
                v['narrator_ids'] = sorted(all_narrators - explicit)
                v['attribution_resolution'] = 'minimum_set_by_complement'
                v['resolution_note'] = ('These IDs exclude all explicitly named narrators in this difference. '
                    'The source phrase may also include an explicitly named narrator for an alternative face '
                    'or condition; use the Arabic descriptions and source for those cases.')
            else:
                v['attribution_resolution'] = 'explicit_source_names_expanded_to_narrators'
        difference = {'difference_id': f'{sn}:{an}:{di}', 'difference_number': di,
                      'word_or_phrase': phrase, 'word_location': locate_phrase(phrase, full_text),
                      'variants': variants}
        differences.append(difference)
    url = BASE + 'index.php?' + urlencode({'group': 'tb1', 'tpath': 2,
          'aya_no': ayah['source_ayah_selector'], 'sorano': sn, 'mRwai': ''})
    result = {**ayah, 'source_url': url, 'source_ayah_text': full_text,
              'source_ayah_text_truncated': bool(full_text and '...' in full_text),
              'status': 'differences_listed' if differences else 'no_differences_listed',
              'difference_count': len(differences), 'differences': differences}
    evidence = {'surah_number': sn, 'ayah_number': an, 'cache_file': key + '.html.gz',
                'response_sha256': hashlib.sha256(raw).hexdigest(),
                'source_card_count': len(cards), 'exported_variant_count': sum(len(d['variants']) for d in differences)}
    return result, evidence


def add_boundary_locations(surahs):
    sequence = [(s, a) for s in surahs for a in s['ayahs']]
    for (s, a), (next_s, next_a) in zip(sequence, sequence[1:]):
        if not a['source_ayah_text'] or a['source_ayah_text_truncated']:
            continue
        before = a['source_ayah_text'].split()
        after = (next_a['source_ayah_text'] or next_a['source_ayah_preview']).split()
        cross_surah = s['surah_number'] != next_s['surah_number']
        paths = [([], before + after)]
        if cross_surah and next_s['surah_number'] != 9:
            basmala = 'بسم الله الرحمن الرحيم'.split()
            paths.append((basmala, before + basmala + after))
        for d in a['differences']:
            if d['word_location']['status'] != 'unmatched_context':
                continue
            contexts = []
            for alternative in d['word_or_phrase'].split(' - '):
                wanted = [normalize_for_matching(t) for t in alternative.split()]
                for basmala, joined in paths:
                    actual = [normalize_for_matching(t) for t in joined]
                    for start in range(len(before)):
                        end = start + len(wanted)
                        if end <= len(before) or actual[start:end] != wanted:
                            continue
                        segments = [{'kind': 'ayah', 'surah_number': s['surah_number'],
                                     'ayah_number': a['ayah_number'],
                                     'word_numbers': list(range(start + 1, len(before) + 1))}]
                        if basmala:
                            count = min(len(basmala), end - len(before))
                            segments.append({'kind': 'inter_surah_basmala',
                                'surah_number': next_s['surah_number'], 'ayah_number': None,
                                'word_numbers': list(range(1, count + 1)),
                                'numbering': '1-based tokens within the unnumbered inter-surah basmala'})
                        next_count = end - len(before) - len(basmala)
                        if next_count > 0:
                            segments.append({'kind': 'ayah', 'surah_number': next_s['surah_number'],
                                'ayah_number': next_a['ayah_number'], 'word_numbers': list(range(1, next_count + 1))})
                        contexts.append({'source_context': alternative, 'segments': segments})
            if contexts:
                spans = sorted({tuple(c['segments'][0]['word_numbers']) for c in contexts})
                d['word_location'].update({'status': 'cross_surah_match' if cross_surah else 'cross_ayah_match',
                    'word_numbers': list(spans[0]) if len(spans) == 1 else None,
                    'candidate_word_number_spans': [list(p) for p in spans], 'boundary_contexts': contexts})


def verify_public_pages(indexes):
    samples = [(1, 4), (1, 7), (2, 255), (3, 7), (9, 1), (18, 1),
               (36, 1), (55, 1), (76, 1), (96, 1), (112, 1), (114, 6)]
    checks = []
    for sn, an in samples:
        ayah = indexes[sn - 1]['ayahs'][an - 1]
        raw = fetch(f'public_{sn:03}_{an:03}', 'index.php', {'group': 'tb1', 'tpath': 2,
            'aya_no': ayah['source_ayah_selector'], 'sorano': sn, 'mRwai': ''})
        public = soup(raw).select_one('#detail')
        ajax = soup(gzip.decompress((CACHE / f'ayah_{sn:03}_{an:03}.html.gz').read_bytes()))
        matched = text(public) == text(ajax)
        if public is None or not matched:
            raise ValueError(f'Public page does not match AJAX data: {sn}:{an}')
        checks.append({'surah_number': sn, 'ayah_number': an,
                       'public_page_matches_ajax_text': matched,
                       'public_card_count': len(public.select('.quran-page'))})
    return checks


def export():
    indexes = json.loads((CACHE / 'index.json').read_text('utf-8'))
    catalog = json.loads((CACHE / 'readers.json').read_text('utf-8'))
    readers = {r['id']: r for r in catalog}
    narrators = {n['id']: n for r in catalog for n in r['narrators']}
    result_surahs, evidence, unmatched, ambiguous = [], [], [], []
    for surah in indexes:
        exported_ayahs = []
        for ayah in surah['ayahs']:
            result, proof = parse_ayah(surah, ayah, readers, narrators)
            exported_ayahs.append(result)
            evidence.append(proof)
        result_surahs.append({**surah, 'ayahs': exported_ayahs})
        if surah['surah_number'] % 10 == 0:
            print(f"Parsed {surah['surah_number']}/114 surahs", flush=True)
    add_boundary_locations(result_surahs)
    ayahs = [a for s in result_surahs for a in s['ayahs']]
    for a in ayahs:
        for d in a['differences']:
            issue = {'difference_id': d['difference_id'], 'word_or_phrase': d['word_or_phrase'],
                     'source_url': a['source_url']}
            if d['word_location']['status'] == 'unmatched_context':
                unmatched.append(issue)
            elif d['word_location']['status'] == 'ambiguous_match':
                ambiguous.append(issue)
    differences = [d for a in ayahs for d in a['differences']]
    stats = {'surahs': len(result_surahs), 'ayahs': len(ayahs), 'readers': len(readers),
             'narrators': len(narrators), 'ayahs_with_differences': sum(bool(a['differences']) for a in ayahs),
             'ayahs_with_no_differences_listed': sum(not a['differences'] for a in ayahs),
             'difference_entries': len(differences),
             'reading_variants': sum(len(d['variants']) for d in differences),
             'unique_word_locations': sum(d['word_location']['status'] == 'unique_match' for d in differences),
             'cross_ayah_word_locations': sum(d['word_location']['status'] == 'cross_ayah_match' for d in differences),
             'cross_surah_word_locations': sum(d['word_location']['status'] == 'cross_surah_match' for d in differences),
             'ambiguous_word_locations': len(ambiguous), 'unmatched_word_contexts': len(unmatched)}
    assert stats['surahs'] == 114 and stats['ayahs'] == 6236
    assert len(readers) == 10 and len(narrators) == 20
    assert all(p['source_card_count'] == p['exported_variant_count'] for p in evidence)
    public_checks = verify_public_pages(indexes)
    now = datetime.now(timezone.utc).isoformat()
    output = {'schema_version': '1.0.0', 'metadata': {
        'title': 'NQuran al-ashr al-sughra: differences by surah, ayah, word and reader',
        'source': 'https://www.nquran.com/ar/index.php?group=tb1&tpath=2',
        'source_section_ar': 'العشر الصغرى', 'source_tpath': 2,
        'exported_at_utc': now, 'coverage': 'Every ayah in the source section index, with the all-readers filter.',
        'numbering': 'Source ayah numbering (6236 ayahs). This may differ from the app narration numbering.',
        'reader_id_namespace': 'NQuran tpath=2 rawi_tarjama Rid / qaree / rawilist; NOT audio rewaya IDs.',
        'text_policy': 'Source Quran spellings and descriptions preserved; HTML removed and whitespace collapsed. No reading forms generated.',
        'word_locations': 'Computed by matching source headings against source_ayah_text; 1-based whitespace token numbers. Boundary contexts include following ayah/surah numbers. Ambiguous/unmatched locations and truncated source quotations are explicit, not guessed.',
        'remaining_narrators': 'Expanded narrator_ids are a minimum complement of named groups, not exhaustive across alternative faces or conditions. Arabic source descriptions remain authoritative.',
        'scope_limit': 'Complete extraction of this linked source section, not an independent scholarly verification or all tariqs of Tayyibat al-Nashr.',
        'statistics': stats}, 'readers': catalog, 'surahs': result_surahs}
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / 'nquran_ashr_sughra_differences.json'
    save_json(target, output)
    (OUT / (target.name + '.gz')).write_bytes(gzip.compress(target.read_bytes(), mtime=0))
    report = {'validated_at_utc': now, 'complete': True, 'statistics': stats,
              'checks': {'all_114_surahs': True, 'all_6236_source_ayahs': True,
                         'every_source_card_exported': True, 'no_unrecognized_attributions': True,
                         'source_heading_ayah_numbers_match': True, 'western_digits_only': True},
              'public_page_spot_checks': public_checks,
              'ambiguous_word_locations': ambiguous, 'unmatched_word_contexts': unmatched}
    save_json(OUT / 'validation_report.json', report)
    save_json(OUT / 'source_manifest.json', {'source': output['metadata']['source'], 'ayahs': evidence,
        'output_sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    save_json(OUT / 'example_fatiha_4.json', {
        'metadata': {'note': 'Small example only; the full dataset is nquran_ashr_sughra_differences.json'},
        'readers': catalog, 'surah_number': 1, 'surah_name': result_surahs[0]['surah_name'],
        'ayah': result_surahs[0]['ayahs'][3]})
    print(json.dumps(stats, ensure_ascii=False), flush=True)
    print(f'Wrote {target} ({target.stat().st_size:,} bytes)', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--export-only', action='store_true')
    parser.add_argument('--download-only', action='store_true')
    args = parser.parse_args()
    if not args.export_only:
        download(args.workers)
    if not args.download_only:
        export()

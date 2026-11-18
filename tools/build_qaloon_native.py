"""Build nested Qaloon-native data without changing any previous export or app asset."""
from collections import Counter, defaultdict
from datetime import datetime, timezone
from difflib import SequenceMatcher
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re

import adapt_nquran_qalun as previous

ROOT = previous.ROOT
OUT = ROOT / 'output/nquran_qaloon_native'
SOURCE = previous.SOURCE
APP = previous.APP
HAFS = previous.HAFS
INPUTS = [SOURCE, APP, HAFS, previous.MAP,
          ROOT / 'output/nquran_qalun/nquran_all_readers_qalun_numbering.json',
          ROOT / 'output/nquran_qalun/hafs_qalun_differences.json']


def compact_key(word, mode=0):
    value = previous.key(word)
    if mode:
        value = value.replace('ا', '')
    if mode == 2:
        value = re.sub('ي+', 'ي', value)
    if mode == 3:
        value = re.sub('[اويۥۦ]', '', value)
    return value


def word_correspondences(source, target):
    """Word matches plus character-supported correspondences inside merge/split blocks."""
    keys_h, keys_q = [previous.key(t) for t in source], [previous.key(t) for t in target]
    out = defaultdict(set)
    methods = {}
    for tag, i, j, k, l in SequenceMatcher(a=keys_h, b=keys_q, autojunk=False).get_opcodes():
        if tag == 'equal':
            for hi, qi in zip(range(i, j), range(k, l)):
                out[hi].add(qi)
                methods[hi, qi] = 'normalized_word_match'
        elif tag == 'replace':
            hs = ''.join(keys_h[i:j])
            qs = ''.join(keys_q[k:l])
            ho = [hi for hi in range(i, j) for _ in keys_h[hi]]
            qo = [qi for qi in range(k, l) for _ in keys_q[qi]]
            for block in SequenceMatcher(a=hs, b=qs, autojunk=False).get_matching_blocks():
                for offset in range(block.size):
                    hi, qi = ho[block.a + offset], qo[block.b + offset]
                    out[hi].add(qi)
                    methods[hi, qi] = 'character_supported_word_alignment'
            if j - i == l - k == 1 and not out[i]:
                out[i].add(k)
                methods[i, k] = 'single_word_substitution_between_anchors'
    return out, methods


def prepare():
    app = defaultdict(dict)
    for block in previous.load(APP):
        for page in block if isinstance(block, list) else [block]:
            for a in page['ayahs']:
                sn, an = int(a['surah']), int(a['ayah'])
                assert an not in app[sn]
                app[sn][an] = {'surah_number': sn, 'ayah_number': an,
                    'page_number': int(page['page']), 'text': a['text'],
                    'words': previous.tokens(a['text']), 'differences': []}
    baseline = {}
    basmala = [previous.key(t) for t in previous.tokens('بسم الله الرحمن الرحيم')]
    for s, aa in previous.load(HAFS).items():
        for a, txt in aa.items():
            sn, an = int(s), int(a)
            words = previous.tokens(txt)
            if an == 1 and sn not in (1, 9) and [previous.key(t) for t in words[:4]] == basmala:
                words = words[4:]
            baseline[sn, an] = words
    h_to_q = {}
    href_to_index = {}
    qrefs_by_surah = {}
    for sn in range(1, 115):
        hw, hrefs, qw, qrefs = [], [], [], []
        for (s, a), words in baseline.items():
            if s == sn:
                hw.extend(words)
                hrefs.extend((sn, a, wi) for wi in range(1, len(words) + 1))
        for an, a in sorted(app[sn].items()):
            qw.extend(a['words'])
            qrefs.extend((sn, an, wi) for wi in range(1, len(a['words']) + 1))
        pairs, methods = word_correspondences(hw, qw)
        for hi, ref in enumerate(hrefs):
            href_to_index[ref] = hi
            h_to_q[ref] = [{'ref': qrefs[qi], 'method': methods[hi, qi]} for qi in sorted(pairs[hi])]
        qrefs_by_surah[sn] = qrefs
    return app, baseline, h_to_q, href_to_index


def compact_candidates(phrase, sn, an, baseline):
    current = baseline[sn, an]
    following = (sn, an + 1) if (sn, an + 1) in baseline else (sn + 1, 1)
    after = baseline.get(following, [])
    cref = [(sn, an, w) for w in range(1, len(current) + 1)]
    paths = [(current, cref)]
    if after:
        aref = [(following[0], following[1], w) for w in range(1, len(after) + 1)]
        paths.append((current + after, cref + aref))
        if following[0] != sn and following[0] != 9:
            basmala = previous.tokens('بسم الله الرحمن الرحيم')
            paths.append((current + basmala + after, cref +
                [(following[0], None, w) for w in range(1, 5)] + aref))
    for mode in range(4):
        found = {}
        for alternative in phrase.split(' - '):
            needle = ''.join(compact_key(w, mode) for w in previous.tokens(alternative))
            if not needle:
                continue
            for words, refs in paths:
                keys = [compact_key(w, mode) for w in words]
                joined = ''.join(keys)
                owners = [wi for wi, word in enumerate(keys) for _ in word]
                start = joined.find(needle)
                while start != -1:
                    first, last = owners[start], owners[start + len(needle) - 1]
                    if first < len(current):
                        span = tuple(refs[first:last + 1])
                        found[span] = {'refs': list(span), 'method': f'compact_source_context_match_{mode}'}
                    start = joined.find(needle, start + 1)
        if found:
            return list(found.values())
    return []


def find_matches(d, sn, an, text, baseline):
    matches = previous.phrase_candidates(d['word_or_phrase'], sn, an, baseline, d['word_location'], text)
    if not matches:
        matches = compact_candidates(d['word_or_phrase'], sn, an, baseline)
    return matches


def disambiguate_occurrences(differences, matches):
    """Use repeated identical source entries in their displayed occurrence order."""
    grouped = defaultdict(list)
    for d in differences:
        fingerprint = (d['word_or_phrase'], json.dumps(d['variants'], ensure_ascii=False, sort_keys=True))
        grouped[fingerprint].append(d['difference_id'])
    resolutions = []
    for ids in grouped.values():
        if len(ids) < 2:
            continue
        starts = {m['refs'][0] for did in ids for m in matches[did] if m['refs']}
        if len(starts) != len(ids):
            continue
        ordered = sorted(starts)
        if not all({m['refs'][0] for m in matches[did]} == starts for did in ids):
            continue
        for did, start in zip(ids, ordered):
            matches[did] = [m for m in matches[did] if m['refs'][0] == start]
            for m in matches[did]:
                m['occurrence_resolution'] = 'identical_repeated_source_rule_in_display_order'
            resolutions.append(did)
    return resolutions


def map_matches(matches, h_to_q, app, d, known_omissions):
    results = {}
    for m in matches:
        refs = []
        unaligned = []
        methods = defaultdict(set)
        omission = None
        omitted_context_boundaries = []
        for h in m['refs']:
            if h[1] is None:
                continue
            aligned = h_to_q.get(h, [])
            if not aligned:
                unaligned.append(h)
            for q in aligned:
                ref = q['ref']
                methods[ref].add(q['method'])
                if ref not in refs:
                    refs.append(ref)
        for h in list(unaligned):
            if h not in known_omissions:
                continue
            hs, ha, hw = h
            left = h_to_q.get((hs, ha, hw - 1), [])
            right = h_to_q.get((hs, ha, hw + 1), [])
            if len(left) == len(right) == 1:
                lr, rr = left[0]['ref'], right[0]['ref']
                if lr[:2] == rr[:2] and lr[2] + 1 == rr[2]:
                    boundary = {'surah_number': lr[0], 'ayah_number': lr[1],
                                'before_word_number': lr[2], 'after_word_number': rr[2],
                                'evidence': 'Qaloon source row explicitly omits the word; the surrounding app words are adjacent.'}
                    if not refs:
                        refs = [lr, rr]
                        omission = boundary
                        methods[lr].add('verified_omission_boundary')
                        methods[rr].add('verified_omission_boundary')
                    omitted_context_boundaries.append(boundary)
                    unaligned.remove(h)
        refs.sort()
        if not refs:
            continue
        segments = []
        for sn, an, wi in refs:
            if not segments or (segments[-1]['surah_number'], segments[-1]['ayah_number']) != (sn, an):
                segments.append({'surah_number': sn, 'ayah_number': an, 'word_numbers': [], 'words': []})
            segments[-1]['word_numbers'].append(wi)
            segments[-1]['words'].append(app[sn][an]['words'][wi - 1])
        result = {'segments': segments, 'source_location_method': m['method'],
                  'complete': not unaligned, 'unaligned_source_words': unaligned,
                  'word_alignment_methods': sorted({method for vv in methods.values() for method in vv})}
        if m.get('occurrence_resolution'):
            result['occurrence_resolution'] = m['occurrence_resolution']
        if omission:
            result['omission_boundary'] = omission
        if omitted_context_boundaries:
            result['omitted_context_boundaries'] = omitted_context_boundaries
        signature = tuple(refs)
        results.setdefault(signature, result)
    return list(results.values())


def save(name, value):
    data = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    assert not re.search('[\u0660-\u0669\u06f0-\u06f9]', data.decode('utf-8'))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_bytes(data)
    if name in ('qaloon_all_readers.json', 'qaloon_hafs_differences.json'):
        (OUT / (name + '.gz')).write_bytes(gzip.compress(data, mtime=0))


def build(audit_only=False):
    before = {str(p.relative_to(ROOT)): previous.sha(p) for p in INPUTS}
    source = previous.load(SOURCE)
    app, baseline, h_to_q, _ = prepare()
    records, unresolved, repeated = [], [], []
    for s in source['surahs']:
        sn = s['surah_number']
        for a in s['ayahs']:
            an = a['ayah_number']
            matches = {d['difference_id']: find_matches(d, sn, an, a['source_ayah_text'], baseline) for d in a['differences']}
            repeated.extend(disambiguate_occurrences(a['differences'], matches))
            known_omissions = set()
            for d in a['differences']:
                if any(2 in v['narrator_ids'] and 'حذف كلمة' in v['reading_description_ar'] for v in d['variants']):
                    for m in matches[d['difference_id']]:
                        if len(m['refs']) == 1:
                            known_omissions.add(m['refs'][0])
            for d in a['differences']:
                spans = map_matches(matches[d['difference_id']], h_to_q, app, d, known_omissions)
                primaries = {(c['segments'][0]['surah_number'], c['segments'][0]['ayah_number']) for c in spans}
                item = {'d': d, 'sn': sn, 'an': an, 'source_url': a['source_url'], 'spans': spans}
                if len(primaries) == 1:
                    item['primary'] = next(iter(primaries))
                    records.append(item)
                else:
                    unresolved.append({'source_id': d['difference_id'], 'word_or_phrase': d['word_or_phrase'],
                        'candidate_primaries': sorted(primaries), 'spans': spans, 'source_ayah_text': a['source_ayah_text']})
        if sn % 20 == 0:
            print(f'Resolved surah {sn}/114', flush=True)
    audit = {'resolved': len(records), 'unresolved': len(unresolved),
             'repeated_source_entries_disambiguated': len(repeated), 'unresolved_entries': unresolved}
    if audit_only:
        save('location_audit.json', audit)
        print(json.dumps(audit, ensure_ascii=False, indent=2)[:40000], flush=True)
        return
    if unresolved:
        save('location_audit.json', audit)
        raise RuntimeError(f'{len(unresolved)} primary ayah assignments require resolution; inspect location_audit.json')
    focus_ids = set(previous.load(ROOT / 'output/nquran_qalun/hafs_qalun_differences.json')['differences'])
    for item in records:
        d, spans = item['d'], item['spans']
        sn, an = item['primary']
        row = app[sn][an]
        n = len(row['differences']) + 1
        primary_spans = {tuple(c['segments'][0]['word_numbers']) for c in spans}
        primary_labels = sorted({' '.join(c['segments'][0]['words']) for c in spans})
        omission = spans[0].get('omission_boundary')
        entry = {'id': f'{sn}:{an}:{n}', 'surah_number': sn, 'ayah_number': an,
            'entry_number': n, 'location_kind': 'omitted_word_boundary' if omission else 'word_context',
            'word_numbers': [] if omission else list(next(iter(primary_spans))) if len(primary_spans) == 1 else None,
            'word_number_candidates': [] if omission else [list(w) for w in sorted(primary_spans)],
            'word_or_phrase': primary_labels[0] if len(primary_labels) == 1 else None,
            'word_or_phrase_candidates': primary_labels,
            'location_status': 'confirmed_omission_boundary' if omission else 'exact_word_span' if len(spans) == 1 and spans[0]['complete'] else
                               'multiple_word_contexts' if all(c['complete'] for c in spans) else 'partial_word_context',
            'qaloon_contexts': [{k: v for k, v in c.items() if k not in ('unaligned_source_words',)} for c in spans],
            'variants': d['variants'], 'hafs_qaloon_comparison': previous.comparison(d),
            'source': {'numbering': 'hafs_source', 'id': d['difference_id'], 'surah_number': item['sn'], 'hafs_ayah_number': item['an'],
                       'word_or_phrase': d['word_or_phrase'], 'word_location': d['word_location'],
                       'url': item['source_url']}}
        row['differences'].append(entry)
    surahs = [{'surah_number': s['surah_number'], 'surah_name': s['surah_name'],
               'ayah_count': len(app[s['surah_number']]),
               'ayahs': [a for _, a in sorted(app[s['surah_number']].items())]} for s in source['surahs']]
    stats = {'surahs': 114, 'ayahs': sum(len(s['ayahs']) for s in surahs), 'entries': len(records),
             'source_reading_rows': sum(len(r['d']['variants']) for r in records),
             'all_primary_ayah_assignments_resolved': True,
             'repeated_source_entries_disambiguated': len(repeated)}
    metadata = {'numbering': 'qaloon_app', 'created_at_utc': datetime.now(timezone.utc).isoformat(),
                'statistics': stats, 'input_sha256': before,
                'rules': ['All primary surah_number, ayah_number, id and word_numbers use the exact current app Qaloon numbering.',
                          'Each source entry occurs exactly once, under the ayah containing the first word of its context.',
                          'Cross-ayah context segments use Qaloon numbers. Hafs references exist only inside source.',
                          'Source Arabic reading descriptions and all app Quran strings are copied unchanged.',
                          'Word candidates remain explicit when a source context cannot be uniquely disambiguated.']}
    full = {'schema_version': '2.0.0', 'metadata': metadata, 'readers': source['readers'], 'surahs': surahs}
    save('qaloon_all_readers.json', full)
    focus_surahs = []
    for s in surahs:
        focus_ayahs = []
        for a in s['ayahs']:
            entries = []
            for e in a['differences']:
                if e['source']['id'] in focus_ids:
                    n = len(entries) + 1
                    entries.append({**e, 'id': f"{s['surah_number']}:{a['ayah_number']}:{n}", 'entry_number': n})
            focus_ayahs.append({**a, 'differences': entries})
        focus_surahs.append({**s, 'ayahs': focus_ayahs})
    focus_entries = [d for s in focus_surahs for a in s['ayahs'] for d in a['differences']]
    focus = {**full, 'metadata': {**metadata, 'scope': 'Hafs versus Qaloon source group differences, including optional faces.',
              'statistics': {**stats, 'entries': len(focus_entries),
                             'source_reading_rows': sum(len(d['variants']) for d in focus_entries)}}, 'surahs': focus_surahs}
    save('qaloon_hafs_differences.json', focus)
    save('example_fatiha.json', {'surah': focus_surahs[0]})
    assert before == {str(p.relative_to(ROOT)): previous.sha(p) for p in INPUTS}
    assert len(records) == 33603 and len(focus_entries) == 7826
    assert stats['source_reading_rows'] == 91393 and stats['ayahs'] == 6214
    report = {**stats, 'original_inputs_unchanged': True, 'focus_entries': len(focus_entries),
              'location_status_counts': dict(Counter(d['location_status'] for s in surahs for a in s['ayahs'] for d in a['differences'])),
              'source_entries_disambiguated_by_repetition': repeated,
              'primary_numbering': 'Qaloon', 'unresolved_primary_ayahs': 0}
    save('validation_report.json', report)
    print(json.dumps({k: v for k, v in report.items() if k != 'source_entries_disambiguated_by_repetition'},
                     ensure_ascii=False, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit-only', action='store_true')
    build(parser.parse_args().audit_only)

"""Create separate Qalun-numbered exports; never write any input file."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
from difflib import SequenceMatcher
from functools import lru_cache
import gzip
import hashlib
import json
from pathlib import Path
import re
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'output/nquran/nquran_ashr_sughra_differences.json'
MAP = ROOT / 'assets/data/narration_map.json'
APP = ROOT / 'assets/data/output.json'
HAFS = ROOT / 'hafs_uthmani.json'
OUT = ROOT / 'output/nquran_qalun'
INPUTS = [SOURCE, MAP, APP, HAFS]
TRANSLATION = str.maketrans({'ٱ': 'ا', 'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ؤ': 'و',
                           'ئ': 'ي', 'ى': 'ي', 'ے': 'ي', 'ة': 'ه', 'ء': '', 'ـ': ''})


def key(value):
    # Search/alignment only. Exported Quran quotations are never rewritten.
    return ''.join(c for c in value.translate(TRANSLATION)
                   if unicodedata.category(c).startswith('L'))


def tokens(value):
    return [t for t in value.split() if key(t)]


def load(path):
    return json.loads(path.read_text('utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, value, compress=False):
    raw = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    assert not re.search('[\u0660-\u0669\u06f0-\u06f9]', raw.decode('utf-8')), name
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_bytes(raw)
    if compress:
        (OUT / (name + '.gz')).write_bytes(gzip.compress(raw, mtime=0))


def expand_mapping(mapping, surah, ayah):
    value = mapping.get(str(surah), {}).get(str(ayah), ayah)
    return [value] if isinstance(value, int) else list(range(value[0], value[1] + 1))


def align(a, b):
    """Return conservative word correspondences and their evidence types."""
    ak, bk = [key(t) for t in a], [key(t) for t in b]
    matcher = SequenceMatcher(a=ak, b=bk, autojunk=False)
    pairs = {}
    for tag, i, j, k, l in matcher.get_opcodes():
        if tag == 'equal':
            for x, y in zip(range(i, j), range(k, l)):
                pairs[x] = (y, 'matching_normalized_word')
        elif tag == 'replace' and j - i == l - k:
            for x, y in zip(range(i, j), range(k, l)):
                similarity = SequenceMatcher(a=ak[x], b=bk[y], autojunk=False).ratio()
                if (j - i == 1) or similarity >= 0.55:
                    pairs[x] = (y, 'aligned_word_substitution')
    return pairs, matcher.ratio()


@lru_cache(maxsize=512)
def source_alignment(source_text, current):
    return align(source_text.split(), current)[0]


def prepare(source):
    mapping = load(MAP)['qalun_to_hafs']
    app = defaultdict(dict)
    for block in load(APP):
        for page in block if isinstance(block, list) else [block]:
            for a in page['ayahs']:
                sn, an = int(a['surah']), int(a['ayah'])
                assert an not in app[sn]
                app[sn][an] = {'surah_number': sn, 'ayah_number': an, 'page_number': int(page['page']),
                    'text': a['text'], 'words': tokens(a['text'])}
    baseline = {}
    basmala = [key(t) for t in tokens('بسم الله الرحمن الرحيم')]
    for s, aa in load(HAFS).items():
        sn = int(s)
        for a, txt in aa.items():
            an = int(a)
            words = tokens(txt)
            if an == 1 and sn not in (1, 9) and [key(t) for t in words[:4]] == basmala:
                words = words[4:]
            baseline[sn, an] = words
    h_to_q, ratios, changes, word_coverage = {}, [], [], []
    adapted_map = {}
    for sn in range(1, 115):
        assert sorted(app[sn]) == list(range(1, len(app[sn]) + 1))
        hw, hrefs, qw, qrefs = [], [], [], []
        for (s, an), words in baseline.items():
            if s == sn:
                hw.extend(words)
                hrefs.extend((sn, an, wi) for wi in range(1, len(words) + 1))
        for an, a in sorted(app[sn].items()):
            qw.extend(a['words'])
            qrefs.extend((sn, an, wi) for wi in range(1, len(a['words']) + 1))
        pairs, ratio = align(hw, qw)
        ratios.append({'surah_number': sn, 'exact_word_alignment_ratio': round(ratio, 6)})
        observed = defaultdict(set)
        mapped_qwords = defaultdict(set)
        for hi, (qi, method) in pairs.items():
            h_to_q[hrefs[hi]] = {'surah_number': sn, 'ayah_number': qrefs[qi][1],
                'word_number': qrefs[qi][2], 'word_text': qw[qi], 'method': method}
            observed[qrefs[qi][1]].add(hrefs[hi][1])
            mapped_qwords[qrefs[qi][1]].add(qrefs[qi][2])
        smap = {}
        for an, a in app[sn].items():
            original = expand_mapping(mapping, sn, an)
            actual = sorted(observed[an])
            covered = len(mapped_qwords[an])
            total = len(a['words'])
            complete = covered == total
            # Only change an ayah-range proposal when every app word is aligned.
            effective = actual if complete and actual else original
            a.update({'original_hafs_ayah_numbers': original, 'aligned_hafs_ayah_numbers': actual,
                      'hafs_ayah_numbers': effective, 'alignment_word_coverage': {'aligned': covered, 'total': total},
                      'difference_ids': [], 'candidate_difference_ids': []})
            if actual != original:
                changes.append({'surah_number': sn, 'qalun_ayah_number': an,
                    'original_hafs_ayah_numbers': original, 'aligned_hafs_ayah_numbers': actual,
                    'all_qalun_words_aligned': complete, 'adapted_map_uses_alignment': complete and bool(actual)})
            if not complete:
                word_coverage.append({'surah_number': sn, 'qalun_ayah_number': an,
                                      'aligned_words': covered, 'total_words': total})
            if effective != [an]:
                smap[str(an)] = effective[0] if len(effective) == 1 else [effective[0], effective[-1]]
        if smap:
            adapted_map[str(sn)] = smap
        print(f'Aligned surah {sn}/114', flush=True) if sn % 20 == 0 else None
    return app, baseline, h_to_q, adapted_map, ratios, changes, word_coverage


def phrase_candidates(phrase, sn, an, baseline, source_location, source_text):
    """Locate source contexts in the full cached Hafs baseline, including boundaries."""
    current = baseline[sn, an]
    following = (sn, an + 1) if (sn, an + 1) in baseline else (sn + 1, 1)
    after = baseline.get(following, [])
    contexts = [(current, [(sn, an, w) for w in range(1, len(current) + 1)])]
    if after:
        refs = contexts[0][1] + [(following[0], following[1], w) for w in range(1, len(after) + 1)]
        contexts.append((current + after, refs))
        if following[0] != sn and following[0] != 9:
            basmala = tokens('بسم الله الرحمن الرحيم')
            contexts.append((current + basmala + after, contexts[0][1] +
                [(following[0], None, w) for w in range(1, 5)] + refs[len(current):]))
    matches = []
    for alternative in phrase.split(' - '):
        wanted = [key(w) for w in tokens(alternative)]
        for words, refs in contexts:
            actual = [key(w) for w in words]
            for i in range(len(current)):
                if wanted and actual[i:i + len(wanted)] == wanted:
                    matches.append({'refs': refs[i:i + len(wanted)], 'method': 'source_phrase_in_full_hafs_text'})
    # Source quotation positions preserve labels whose spelling differs from the baseline.
    if not matches and source_location.get('candidate_word_number_spans') and source_text:
        pairs = source_alignment(source_text, tuple(current))
        for span in source_location['candidate_word_number_spans']:
            if all(w - 1 in pairs for w in span):
                refs = [(sn, an, pairs[w - 1][0] + 1) for w in span]
                matches.append({'refs': refs, 'method': 'source_word_positions_aligned_to_hafs'})
    # A rasm spelling can omit written alefs. This is a matching key, not rewritten text.
    if not matches:
        for alternative in phrase.split(' - '):
            wanted = [key(w).replace('ا', '') for w in tokens(alternative)]
            for words, refs in contexts:
                actual = [key(w).replace('ا', '') for w in words]
                for i in range(len(current)):
                    if wanted and all(wanted) and actual[i:i + len(wanted)] == wanted:
                        matches.append({'refs': refs[i:i + len(wanted)], 'method': 'orthographic_alef_key_match'})
    unique = {}
    for m in matches:
        unique.setdefault(tuple(m['refs']), m)
    matches = list(unique.values())
    source_span = source_location.get('word_numbers')
    if source_text and source_span:
        pairs = source_alignment(source_text, tuple(current))
        start = pairs.get(source_span[0] - 1)
        if start:
            refined = [m for m in matches if m['refs'][0] == (sn, an, start[0] + 1)]
            if refined:
                matches = refined
    return matches


def qalun_location(d, sn, an, source_text, app, baseline, h_to_q):
    matches = phrase_candidates(d['word_or_phrase'], sn, an, baseline, d['word_location'], source_text)
    candidates = []
    for m in matches:
        segments = []
        complete = True
        for ref in m['refs']:
            if ref[1] is None:
                seg = {'kind': 'inter_surah_basmala', 'surah_number': ref[0], 'ayah_number': None,
                       'word_numbers': [ref[2]], 'word_texts': [], 'alignment_methods': ['source_context']}
            elif ref not in h_to_q:
                complete = False
                continue
            else:
                q = h_to_q[ref]
                seg = {'kind': 'ayah', 'surah_number': q['surah_number'], 'ayah_number': q['ayah_number'],
                       'word_numbers': [q['word_number']], 'word_texts': [q['word_text']],
                       'alignment_methods': [q['method']]}
            if segments and all(segments[-1][k] == seg[k] for k in ['kind', 'surah_number', 'ayah_number']):
                for k in ['word_numbers', 'word_texts', 'alignment_methods']:
                    segments[-1][k].extend(seg[k])
            else:
                segments.append(seg)
        if segments and any(s['kind'] == 'ayah' for s in segments):
            candidates.append({'segments': segments, 'all_context_words_aligned': complete,
                               'source_location_method': m['method']})
    unique = {}
    for c in candidates:
        signature = tuple((s['kind'], s['surah_number'], s['ayah_number'], tuple(s['word_numbers'])) for s in c['segments'])
        unique.setdefault(signature, c)
    candidates = list(unique.values())
    refs = sorted({(s['surah_number'], s['ayah_number']) for c in candidates
                   for s in c['segments'] if s['kind'] == 'ayah'})
    # Basmala in Hafs al-Fatihah 1 is unnumbered in the app; retain it outside ayah indexing.
    if sn == 1 and an == 1:
        return {'status': 'unnumbered_basmala', 'ayah_assignment_resolved': False,
                'qalun_ayah_references': [], 'candidate_spans': []}
    if candidates:
        complete = all(c['all_context_words_aligned'] for c in candidates)
        candidate_refsets = [{(s['surah_number'], s['ayah_number']) for s in c['segments'] if s['kind'] == 'ayah'} for c in candidates]
        assignment_resolved = complete and all(r == candidate_refsets[0] for r in candidate_refsets)
        return {'status': 'word_aligned' if len(candidates) == 1 and complete else 'ambiguous_word_location' if complete else 'partial_word_alignment',
                'ayah_assignment_resolved': assignment_resolved,
                'qalun_ayah_references': [{'surah_number': s, 'ayah_number': a} for s, a in refs],
                'candidate_spans': candidates}
    fallback = [(sn, q) for q, a in app[sn].items() if an in a['hafs_ayah_numbers']]
    return {'status': 'ayah_only' if fallback else 'unmapped',
            'ayah_assignment_resolved': False,
            'qalun_ayah_references': [{'surah_number': s, 'ayah_number': a} for s, a in fallback],
            'candidate_spans': []}


def comparison(d):
    q = [v['variant_number'] for v in d['variants'] if 2 in v['narrator_ids']]
    h = [v['variant_number'] for v in d['variants'] if 21 in v['narrator_ids']]
    assert q and h, d['difference_id']
    return {'qalun_narrator_id': 2, 'qalun_name': 'قالون عن نافع', 'qalun_variant_numbers': q,
            'hafs_narrator_id': 21, 'hafs_name': 'حفص عن عاصم', 'hafs_variant_numbers': h,
            'status': 'different_source_groups' if q != h else 'same_source_group',
            'interpretation': 'Source group membership only; Arabic conditions and alternative faces remain authoritative.'}


def build(audit_only=False):
    before = {str(p.relative_to(ROOT)): sha(p) for p in INPUTS}
    source = load(SOURCE)
    app, baseline, h_to_q, adapted_map, ratios, changes, coverage = prepare(source)
    if audit_only:
        print(json.dumps({'lowest_alignment_ratios': sorted(ratios, key=lambda x: x['exact_word_alignment_ratio'])[:10],
                          'map_differences': changes, 'incomplete_word_coverage_count': len(coverage)}, ensure_ascii=False, indent=2))
        return
    differences, focus, issues = {}, {}, []
    for s in source['surahs']:
        sn = s['surah_number']
        for a in s['ayahs']:
            for original in a['differences']:
                d = dict(original)
                d['source_surah_number'] = sn
                d['source_hafs_ayah_number'] = a['ayah_number']
                d['source_url'] = a['source_url']
                d['source_word_location'] = d.pop('word_location')
                d['qalun_location'] = qalun_location(original, sn, a['ayah_number'], a['source_ayah_text'], app, baseline, h_to_q)
                d['hafs_qalun_comparison'] = comparison(original)
                did = d['difference_id']
                differences[did] = d
                if d['hafs_qalun_comparison']['status'] == 'different_source_groups':
                    focus[did] = d
                location = d['qalun_location']
                definite = location['ayah_assignment_resolved']
                for ref in location['qalun_ayah_references']:
                    row = app[ref['surah_number']][ref['ayah_number']]
                    row['difference_ids' if definite else 'candidate_difference_ids'].append(did)
                if location['status'] != 'word_aligned':
                    issues.append({'difference_id': did, 'status': location['status'],
                                   'qalun_ayah_references': location['qalun_ayah_references']})
    surahs = []
    for s in source['surahs']:
        sn = s['surah_number']
        surahs.append({'surah_number': sn, 'surah_name': s['surah_name'], 'ayah_count': len(app[sn]),
                       'ayahs': [a for _, a in sorted(app[sn].items())]})
    stats = {'surahs': len(surahs), 'app_qalun_ayahs': sum(len(s['ayahs']) for s in surahs),
             'source_hafs_ayahs': 6236, 'difference_entries': len(differences),
             'reading_variants': sum(len(d['variants']) for d in differences.values()),
             'hafs_qalun_comparison_entries': len(focus),
             'location_status_counts': dict(Counter(d['qalun_location']['status'] for d in differences.values())),
             'map_ayahs_differing_from_alignment': len(changes),
             'map_updates_with_all_qalun_words_aligned': sum(c['adapted_map_uses_alignment'] for c in changes)}
    metadata = {'created_at_utc': datetime.now(timezone.utc).isoformat(),
        'numbering': 'App Qalun numbering and text from assets/data/output.json; original Hafs references retained.',
        'source_section_ar': 'العشر الصغرى', 'statistics': stats, 'input_sha256': before,
        'schema_notes': 'differences is a catalog keyed by original source ID. surahs[].ayahs[] index that catalog. candidate_difference_ids require location review.',
        'word_numbering': '1-based Arabic-letter-bearing whitespace tokens in each exact app ayah text; not image glyph or phoneme-array offsets.',
        'map_policy': 'Original map preserved. A separate adapted map uses observed ayah ranges only where every app word has an aligned correspondence; other ranges retain the original mapping.',
        'text_policy': 'All Quran strings copied unchanged. Normalization is used only for matching. No Quran or pronunciation rules generated.',
        'comparison_policy': 'The focused file retains source entries whose Qalun and Hafs variant group IDs differ. This is not an executable text-conversion engine; keep optional faces and conditions.',
        'source_metadata': source['metadata']}
    output = {'schema_version': '1.0.0', 'metadata': metadata, 'readers': source['readers'],
              'surahs': surahs, 'differences': differences}
    save('nquran_all_readers_qalun_numbering.json', output, True)
    focused_surahs = []
    for s in surahs:
        aa = []
        for a in s['ayahs']:
            aa.append({**a, 'difference_ids': [d for d in a['difference_ids'] if d in focus],
                       'candidate_difference_ids': [d for d in a['candidate_difference_ids'] if d in focus]})
        focused_surahs.append({**s, 'ayahs': aa})
    focus_stats = {**stats, 'source_catalog_difference_entries': len(differences),
                   'difference_entries': len(focus),
                   'reading_variants': sum(len(d['variants']) for d in focus.values()),
                   'location_status_counts': dict(Counter(d['qalun_location']['status'] for d in focus.values()))}
    save('hafs_qalun_differences.json', {**output, 'metadata': {**metadata, 'statistics': focus_stats,
         'file_scope': 'Only source entries with different Hafs and Qalun variant groups; every app ayah retained in index.'},
         'surahs': focused_surahs, 'differences': focus}, True)
    save('narration_map_qalun_adapted.json', {
        '_comment': 'New companion proposal. Original assets/data/narration_map.json is unchanged. '
                    'Same sparse Qalun-to-Hafs schema; only ranges with complete app-word alignment can be updated.',
        'qalun_to_hafs': adapted_map})
    example_ids = [d for d in differences if d in ('1:4:1', '1:7:1', '1:7:2', '1:7:3', '1:7:4', '1:7:5', '1:7:6')]
    save('example_fatiha_qalun.json', {'surah': focused_surahs[0], 'differences': {d: differences[d] for d in example_ids}})
    after = {str(p.relative_to(ROOT)): sha(p) for p in INPUTS}
    assert before == after, 'An input changed during export'
    assert len(differences) == source['metadata']['statistics']['difference_entries'] == 33603
    assert stats['reading_variants'] == 91393
    assert stats['app_qalun_ayahs'] == 6214
    report = {'statistics': stats, 'original_inputs_unchanged': before == after,
        'input_sha256': before, 'surah_word_alignment': ratios, 'map_alignment_differences': changes,
        'app_ayahs_with_incomplete_word_alignment': coverage, 'location_review_entries': issues,
        'validation': {'every_source_difference_retained': True, 'every_source_reading_retained': True,
                       'all_app_ayahs_indexed': True, 'western_digits_only': True}}
    save('validation_report.json', report)
    print(json.dumps(stats, ensure_ascii=False, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit-only', action='store_true')
    build(parser.parse_args().audit_only)

"""Page-turn cues for a SERVER-ADDED reciter (tools/content_updates/reciters.json).

tools/measure_page_turn_cues.py measures only `Reciter.all` and rewrites
lib/page_turn_cues.dart. A remote reciter carries its cues in its own
reciters.json entry instead (`"pageTurnCues"`, read by
ReciterService.parseRemotePageTurnCues), so this wrapper reuses that tool's
measure() on a reciter described by an entry and prints the JSON to paste in.
It writes nothing in lib/ and leaves tools/page_turn_cues.json alone.

Run where measure_page_turn_cues.py runs (the aligner's venv), after the
reciter's audio and timings are live on R2:
    python tools/measure_remote_page_turn_cues.py ENTRY.json [--out CUES.json]
ENTRY.json = one reciters.json entry (id, name, scheme timedSurah,
audioBaseUrl, timingsBaseUrl). Prints every cue with its diagnostics, then the
"pageTurnCues" object. The listening page lands in
build/page_turn_cues/review/ like the main tool's.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    'mptc', HERE / 'measure_page_turn_cues.py')
mptc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mptc)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('entry', type=Path)
    ap.add_argument('--out', type=Path)
    a = ap.parse_args()
    e = json.loads(a.entry.read_text(encoding='utf-8'))
    if e.get('scheme') != 'timedSurah':
        raise SystemExit('remote reciters are timedSurah only')
    r = {'var': e['id'], 'id': e['id'], 'name': e['name'],
         'base': e['audioBaseUrl'], 'scheme': 'timedSurah',
         'timings': e['timingsBaseUrl'], 'covered': {}, 'missing': {},
         'breath': False, 'continuations': None}
    pages = mptc.load_pages()
    words = mptc.split_words()
    clips = mptc.Clips(r)
    cache = mptc.WORK / 'cache' / r['id']
    cache.mkdir(parents=True, exist_ok=True)
    review = mptc.WORK / 'review'
    review.mkdir(parents=True, exist_ok=True)
    per, cues = {}, {}
    for page in sorted(words):
        c = mptc.measure(r, clips, pages, page, words[page], cache, review)
        per[str(page)] = c
        cues[str(page)] = {'surah': c['surah'], 'ayah': c['ayah'],
                           'file': c['file'], 'ms': c['at_ms']}
        print('   p%d %d:%d «%s» -> %s @ %s  [%s%s]  ctc end %.2f, voice end %s'
              % (page, c['surah'], c['spanning_ayah'], c['word'], c['file'],
                 mptc.fmt_ms(c['at_ms']), c['how'],
                 ', inside %s' % c['recited'][0] if c['joined'] else '',
                 c['ctc_word'][1],
                 '-' if c['voice_end'] is None else '%.2f' % c['voice_end']),
              flush=True)
    text = json.dumps(cues, ensure_ascii=False, sort_keys=True)
    print('\n"pageTurnCues": ' + text)
    if a.out:
        a.out.write_text(json.dumps({'cues': cues, 'detail': per},
                                    ensure_ascii=False, indent=1),
                         encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())

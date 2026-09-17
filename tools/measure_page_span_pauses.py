"""Measure where each reciter actually pauses at a page break.

`build_page_spans.py` works out how far into a page-spanning ayah the break
falls by measuring the page image and counting the ayah's letters. Both are
proxies for the thing that matters — how long the head of the ayah takes to
recite — and both can be well out where the tail is heavy with مد: in 4:44 the
break is 58% of the way through by letters but every reciter reaches it at
about 49% of the recording, because «وكفى بالله وليّاً وكفى بالله نصيراً» is
drawn out far more than its letter count suggests.

So ask the recordings. Each reciter's clip for the ayah is fetched, its breath
pauses are found from the audio envelope, and those pauses are matched in order
against the ayah's marked waqf stops (plus the page break itself, which is a
place reciters stop whether or not it carries a mark). The pause that lands on
the page break is that reciter's answer. They agree closely wherever the break
carries a waqf mark, and the median of them is what the app uses.

Writes tools/page_span_audio.json, which build_page_spans.py reads. Needs
ffmpeg on PATH and network access. Run from the repo root:

    python tools/measure_page_span_pauses.py
"""

import json
import math
import os
import struct
import subprocess
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_page_spans import (  # noqa: E402
    CACHE, FOOT, LINES, PAGE_ENDS_AT_AYAH, SPLIT_WORDS, ROOT,
    bare, letters, load_pages,
)

AUDIO_OUT = os.path.join(ROOT, 'tools', 'page_span_audio.json')
CLIPS = os.path.join(ROOT, 'build', 'page_span_clips')

MIRROR = 'https://audio.mushaf-qaloon.com/'
TIMINGS = 'https://quran-content.mushaf-qaloon.com/timings/'

# The seven reciters the app ships, and how each one names the audio for a
# displayed (Qalun) ayah. 'direct' mirrors are one file per displayed ayah;
# 'mapped' ones go through assets/data/audio_ayah_map.json because their
# recitation divides a few ayat differently; 'timed' ones are one file per
# surah with a published span per ayah.
# 'breath' marks a sheikh who runs several ayat together on one breath
# (الوقف الهبطي): the ayat listed in qaniwah_continuations.json only repeat the
# previous breath, so the app never plays them on their own.
RECITERS = {
    'al-Husary': ('direct', 'alhosary/', False),
    'al-Naihi': ('mapped', 'Alnaihi/', False),
    'قنيوه': ('mapped', 'qaniwah/', True),
    'al-Hudaifi': ('direct', 'Hudaifi/', False),
    'al-Doukali': ('direct', 'doukali/', False),
    'al-Qryw': ('timed', 'alqryw/', False),
    'أبوسنينة': ('timed', 'abusenainah_timed/', False),
}

WAQF = 'ۖۗۘۙۚۛۜ'

# Under a hundredth of a second of sound: a silent placeholder file, which is
# how the per-ayah mirrors publish an ayah the sheikh reads inside a neighbour's
# breath.
SILENT_BYTES = 8000


# ── fetching ─────────────────────────────────────────────────────────────────

def _get(url):
    # The audio host refuses requests with no User-Agent.
    request = urllib.request.Request(url, headers={'User-Agent': 'curl/8'})
    with urllib.request.urlopen(request, timeout=180) as r:
        return r.read()


def _cached(name, produce):
    os.makedirs(CLIPS, exist_ok=True)
    path = os.path.join(CLIPS, name)
    if not os.path.exists(path):
        produce(path)
    return path if os.path.exists(path) else None


def _mapped_files(audio_map, continuations, surah, ayah, breath):
    """The recitation files for a displayed ayah on a 'mapped' mirror."""
    def look(n):
        return audio_map.get(str(surah), {}).get(str(n)) or [n]

    files = look(ayah)
    if ayah > 1:
        # A file already recited as part of the previous displayed ayah.
        files = [n for n in files if n > max(look(ayah - 1))]
    if breath:
        skip = set(continuations.get(str(surah), []))
        files = [n for n in files if n not in skip]
    return files


def clip_for(reciter, surah, ayah, audio_map, continuations):
    """A local mp3 of just this ayah, or None if the reciter doesn't read it
    as an ayah of its own."""
    kind, folder, breath = RECITERS[reciter]
    tag = folder.strip('/').replace('/', '_')
    if kind == 'timed':
        name = f'{surah:03d}.json'
        timings = json.loads(_get(TIMINGS + folder + name))
        span = timings['ayat'].get(str(ayah))
        if not span:
            return None
        start, end = span[0] / 1000, span[1] / 1000

        def cut(path):
            subprocess.run(
                ['ffmpeg', '-v', 'error', '-y', '-ss', f'{start:.3f}',
                 '-t', f'{end - start:.3f}', '-i',
                 f'{MIRROR}{folder}{surah:03d}.mp3', '-c', 'copy', path],
                check=False, capture_output=True)

        return _cached(f'{tag}_{surah:03d}{ayah:03d}.mp3', cut)

    numbers = ([ayah] if kind == 'direct'
               else _mapped_files(audio_map, continuations, surah, ayah, breath))
    if len(numbers) != 1:
        return None  # no audio of its own, or split over several files

    def fetch(path):
        try:
            data = _get(f'{MIRROR}{folder}{surah:03d}{numbers[0]:03d}.mp3')
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            return                        # the mirror never published it
        if len(data) > SILENT_BYTES:      # else: a silent placeholder
            with open(path, 'wb') as f:
                f.write(data)

    return _cached(f'{tag}_{surah:03d}{ayah:03d}.mp3', fetch)


# ── the audio ────────────────────────────────────────────────────────────────

def envelope(path, window=0.05, rate=8000):
    """Loudness per [window] seconds, in dBFS."""
    pcm = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', path, '-ac', '1', '-ar', str(rate),
         '-f', 's16le', '-'], capture_output=True).stdout
    count = len(pcm) // 2
    samples = struct.unpack('<%dh' % count, pcm[:count * 2])
    step = int(rate * window)
    out = []
    for i in range(0, count - step, step):
        chunk = samples[i:i + step]
        rms = math.sqrt(sum(s * s for s in chunk) / len(chunk)) or 1
        out.append((i / rate, 20 * math.log10(rms / 32768)))
    return out


def breath_pauses(env, floor=-33, shortest=0.25, join=1.0):
    """The gaps between phrases, as (start, end) seconds."""
    runs, start = [], None
    for t, db in env:
        if db < floor and start is None:
            start = t
        elif db >= floor and start is not None:
            if t - start >= shortest:
                runs.append((start, t))
            start = None
    merged = []
    for a, b in runs:
        if merged and a - merged[-1][1] < join:
            merged[-1] = (merged[-1][0], b)   # one breath, detected in pieces
        else:
            merged.append((a, b))
    return merged


def match_stops(stops, pauses):
    """Cheapest increasing match of each stop to a pause (extra breaths are
    left unmatched). Returns the pause index chosen for each stop."""
    k, n = len(stops), len(pauses)
    if k == 0 or n < k:
        return None
    inf = float('inf')
    cost = [[inf] * n for _ in range(k)]
    back = [[-1] * n for _ in range(k)]
    for j in range(n):
        cost[0][j] = (pauses[j] - stops[0]) ** 2
    for i in range(1, k):
        for j in range(i, n):
            prev = min(range(i - 1, j), key=lambda q: cost[i - 1][q])
            cost[i][j] = cost[i - 1][prev] + (pauses[j] - stops[i]) ** 2
            back[i][j] = prev
    j = min(range(n), key=lambda q: cost[k - 1][q])
    chosen = [j]
    for i in range(k - 1, 0, -1):
        j = back[i][j]
        chosen.append(j)
    return chosen[::-1]


# ── main ─────────────────────────────────────────────────────────────────────

def spanning_pages(measured):
    return [p for p, (_, last, _) in sorted(measured.items())
            if last < FOOT and p not in PAGE_ENDS_AT_AYAH]


def main():
    pages = load_pages()
    with open(CACHE, encoding='utf-8') as f:
        measured = {int(k): v for k, v in json.load(f).items()}
    with open(os.path.join(ROOT, 'assets', 'data', 'audio_ayah_map.json'),
              encoding='utf-8') as f:
        audio_map = json.load(f)['map']
    with open(os.path.join(ROOT, 'assets', 'data',
                           'qaniwah_continuations.json'), encoding='utf-8') as f:
        continuations = json.load(f)['continuations']

    result = {}
    for page in spanning_pages(measured):
        ayah = pages[page + 1][0]
        surah, number = ayah['surah'], ayah['ayah']
        words = ayah['text'].split()
        want = SPLIT_WORDS.get(page + 1)
        if want is None:
            print(f'page {page + 1}: no SPLIT_WORDS entry — skipped')
            continue
        hits = [i for i, w in enumerate(words) if bare(w) == bare(want)]
        if len(hits) != 1:
            print(f'page {page + 1}: "{want}" is not a unique word — skipped')
            continue
        split = hits[0]
        total = sum(letters(w) for w in words)
        running, upto = 0, []
        for w in words:
            running += letters(w)
            upto.append(running / total)
        # Where the reciter is expected to stop: every marked waqf, and the
        # page break itself.
        stops = sorted({i for i, w in enumerate(words[:-1])
                        if any(c in WAQF for c in w)} | {split})

        print(f'=== page {page} -> {page + 1}   {surah}:{number}   '
              f'break after word {split + 1}/{len(words)} "{want}"')
        found = {}
        for reciter in RECITERS:
            path = clip_for(reciter, surah, number, audio_map, continuations)
            if path is None:
                print(f'   {reciter:<12} reads it inside a neighbouring ayah '
                      f'— the page turns when that ayah ends')
                continue
            env = envelope(path)
            if not env:
                print(f'   {reciter:<12} no audio decoded — skipped')
                continue
            duration = env[-1][0]
            inner = [p for p in breath_pauses(env)
                     if 0.8 < (p[0] + p[1]) / 2 < duration - 0.8]
            chosen = match_stops([upto[i] for i in stops],
                                 [p[0] / duration for p in inner])
            if chosen is None:
                print(f'   {reciter:<12} {len(inner)} pauses for {len(stops)} '
                      f'stops — cannot match')
                continue
            at = {stops[i]: inner[chosen[i]][0] / duration
                  for i in range(len(stops))}
            found[reciter] = at[split]
            print(f'   {reciter:<12} {duration:5.1f}s clip, {len(inner):2d} '
                  f'pauses -> break at {at[split]:.3f} '
                  f'({at[split] * duration:.1f}s)')
        result[str(page + 1)] = found
        if found:
            values = sorted(found.values())
            mid = len(values) // 2
            median = (values[mid] if len(values) % 2
                      else (values[mid - 1] + values[mid]) / 2)
            agree = sum(1 for v in values if abs(v - median) <= 0.06)
            print(f'   -> median {median:.3f}, {agree}/{len(values)} within '
                  f'0.06 of it')

    with open(AUDIO_OUT, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=1, sort_keys=True)
    print(f'\nwrote {AUDIO_OUT}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

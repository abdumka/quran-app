"""Time the page turn inside the five ayat this mushaf prints across a page break.

Five ayat start at the foot of one page and finish on the next (2:218 p34→35,
4:44 p85→86, 14:27 p258→259, 24:36 p354→355, 24:42 p355→356 — see
tools/build_page_spans.py, which finds them). During التلاوة the page should
turn when the reciter finishes the last word printed on the earlier page: not
when the ayah starts, and not when it ends.

That moment is a property of each recording, so it is measured here for every
reciter in `Reciter.all` and written to lib/page_turn_cues.dart as an exact
position in an exact audio file:

  1. Find the clip that recites the last word on the page, the way the app
     resolves it (lib/services/audio_service.dart `_getClipsForAyah`). Usually
     that is the spanning ayah's own clip. A sheikh who reads the ayah inside
     the previous one's breath (الوقف الهبطي, or a "covered" ayah whose own file
     is a silent placeholder) recites it inside the PREVIOUS ayah's clip, which
     plays while the app is still on the earlier page — the cue then sits in
     that clip, and the app turns the page early, mid-clip.
  2. Decode that clip (all its files, in order, if the ayah is split over
     several) and force-align the text of every ayah it recites with the same
     CTC aligner the timed-reciter pipeline uses (ctc-forced-aligner, MMS).
  3. Snap the aligner's end of the page's last word to the audio: the start of
     the pause that follows it, from the loudness envelope. Where the sheikh
     reads straight on with no pause, the aligner's word junction is used.

The aligner lives in the WSL venv used by the reciter pipelines
(`/root/quran-venv`, `/root/quran/ctc_segment_progress.py`; see
D:/RajabTimed/pipeline/NEW_RECITER_INSTRUCTIONS.md). Run from WSL as root:

    cd "/mnt/d/quran app/quran-app-main"
    /root/quran-venv/bin/python tools/measure_page_turn_cues.py
    /root/quran-venv/bin/python tools/measure_page_turn_cues.py --only rajab_qaloun

Writes:
  tools/page_turn_cues.json   every measurement with its diagnostics (merged
                              with earlier runs, so --only keeps the others)
  lib/page_turn_cues.dart     the table the app reads (do not edit by hand)
  build/page_turn_cues/review/  a listening page: each cue as a short clip with
                              a tick where the page turns, for checking by ear

Re-run for a reciter whenever its audio is re-uploaded or re-cut, and for every
reciter if output.json moves a page break. test/page_turn_cues_test.dart fails
while any reciter in `Reciter.all` is missing a cue.
"""

from __future__ import annotations

import argparse
import ast
import base64
import hashlib
import io
import json
import math
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RECITER_DART = ROOT / 'lib' / 'models' / 'reciter.dart'
MODELS_DIR = ROOT / 'lib' / 'models'
OUTPUT_JSON = ROOT / 'assets' / 'data' / 'output.json'
AUDIO_MAP = ROOT / 'assets' / 'data' / 'audio_ayah_map.json'
SPANS_PY = ROOT / 'tools' / 'build_page_spans.py'
RESULT_JSON = ROOT / 'tools' / 'page_turn_cues.json'
DART_OUT = ROOT / 'lib' / 'page_turn_cues.dart'
WORK = ROOT / 'build' / 'page_turn_cues'

RATE = 16000          # what the aligner wants; also what the envelope reads
HOP = 0.010           # envelope step, seconds
WIN = 0.025           # envelope window, seconds
QUIET_DB = 30         # this far under the clip's loud speech counts as a pause
VOICE_DB = 15         # within this of loud speech is still the voice, not
                      # the room's reverb dying away after it
MIN_PAUSE = 0.15      # shorter dips are consonants, not a stop
DIP_DB = 12           # reading straight on: a dip this far under loud
DIP_SMOOTH = 0.05     # speech (over this long), within DIP_REACH of the
DIP_REACH = 0.15      # aligner's junction, is where the words meet
TURN_AFTER = 0.10     # turn this long after the voice stops (capped at
                      # the middle of the pause), so the word's last breath
                      # is heard on the page it is printed on
SILENT_BYTES = 8000   # a per-ayah mirror's silent placeholder is ~1.6 kB

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')


# ── the app's own data ───────────────────────────────────────────────────────

def load_pages():
    raw = json.loads(OUTPUT_JSON.read_text(encoding='utf-8'))
    flat = []

    def add(item):
        if isinstance(item, list):
            for sub in item:
                add(sub)
        elif isinstance(item, dict):
            flat.append(item)

    add(raw)
    return {p['page']: p['ayahs'] for p in flat}


def split_words():
    """SPLIT_WORDS from build_page_spans.py — page turned to → the last word
    printed on the page before it. Read with ast: that script imports Pillow,
    which the aligner's venv does not have."""
    tree = ast.parse(SPANS_PY.read_text(encoding='utf-8'))
    for node in tree.body:
        if (isinstance(node, ast.Assign)
                and any(getattr(t, 'id', None) == 'SPLIT_WORDS'
                        for t in node.targets)):
            return ast.literal_eval(node.value)
    raise SystemExit('SPLIT_WORDS not found in build_page_spans.py')


_MARKS = re.compile('[\u064B-\u065F\u06D6-\u06ED\u0640]')
_ALEF = re.compile('[\u0622\u0623\u0625\u0670\u0671\u0672\u0673]')


def bare(word):
    return _ALEF.sub('\u0627', _MARKS.sub('', word)).replace('\u0649', '\u064A')


def _dart_int_sets(src):
    """`{2: {218}, 11: {121}}` → {2: {218}, 11: {121}}."""
    return {int(k): {int(x) for x in re.findall(r'\d+', v)}
            for k, v in re.findall(r'(\d+)\s*:\s*\{([^}]*)\}', src)}


def dart_maps():
    """Every `Map<int, Set<int>> NAME = {…};` under lib/models, by name."""
    out = {}
    for path in MODELS_DIR.glob('*.dart'):
        text = path.read_text(encoding='utf-8')
        for m in re.finditer(
                r'Map<int,\s*Set<int>>\s+(\w+)\s*=\s*\{(.*?)\n\s*\};',
                text, re.S):
            out[m.group(1)] = _dart_int_sets(m.group(2))
    return out


def load_reciters():
    """`Reciter.all`, in order, with what this tool needs of each."""
    text = RECITER_DART.read_text(encoding='utf-8')
    maps = dart_maps()
    blocks = {}
    for m in re.finditer(r'static const Reciter (\w+) = Reciter\((.*?)\n  \);',
                         text, re.S):
        blocks[m.group(1)] = m.group(2)
    listed = re.search(r'static const List<Reciter> all = \[(.*?)\];', text,
                       re.S).group(1)
    reciters = []
    for name in re.findall(r'(\w+)\s*,', listed):
        body = blocks[name]

        def field(key, body=body):
            m = re.search(key + r":\s*\n?\s*'([^']*)'", body)
            return m.group(1) if m else None

        def int_sets(key, body=body):
            m = re.search(key + r':\s*(\w+|\{.*?\n\s*\})\s*,', body, re.S)
            if not m:
                return {}
            value = m.group(1)
            return maps[value] if value in maps else _dart_int_sets(value)

        scheme = re.search(r'scheme:\s*AudioScheme\.(\w+)', body)
        base = field('audioBaseUrl')
        reciters.append({
            'var': name,
            'id': field('id'),
            'name': field('name'),
            'base': base,
            'scheme': scheme.group(1) if scheme else 'mergedTail',
            'timings': field('timingsBaseUrlOverride') or base + 'timings/',
            'covered': int_sets('coveredAyat'),
            'missing': int_sets('missingAyat'),
            'breath': bool(re.search(r'breathCombining:\s*true', body)),
            'continuations': field('continuationsAsset'),
        })
    return reciters


# ── which clip recites an ayah (mirrors AudioService._getClipsForAyah) ───────

MERGED_TAILS = {5: 120, 6: 165, 8: 75, 9: 129, 13: 43, 14: 52, 23: 118,
                27: 93, 47: 38, 56: 96, 71: 28, 89: 30, 91: 15, 96: 19,
                106: 4}


class Clips:
    def __init__(self, reciter):
        self.r = reciter
        self._timings = {}
        self._audio_map = None
        self._continuations = None

    def timings(self, surah):
        if surah not in self._timings:
            url = '%s%03d.json' % (self.r['timings'], surah)
            self._timings[surah] = json.loads(get(url))
        return self._timings[surah]

    def _mapped(self, s, a):
        if self._audio_map is None:
            self._audio_map = json.loads(
                AUDIO_MAP.read_text(encoding='utf-8'))['map']
        return list(self._audio_map.get(str(s), {}).get(str(a)) or [a])

    def _is_continuation(self, s, n):
        if self._continuations is None:
            path = ROOT / self.r['continuations']
            self._continuations = json.loads(
                path.read_text(encoding='utf-8'))['continuations']
        return n in set(self._continuations.get(str(s), []))

    def of(self, s, a):
        """[(file, start_ms | None, end_ms | None)] for displayed ayah s:a."""
        r = self.r
        if a in r['missing'].get(s, ()):
            return []
        scheme = r['scheme']
        if scheme == 'timedSurah':
            span = self.timings(s)['ayat'].get(str(a))
            return [('%03d.mp3' % s, span[0], span[1])] if span else []
        if scheme == 'covered':
            if a in r['covered'].get(s, ()):
                return []
            return [('%03d%03d.mp3' % (s, a), None, None)]
        if scheme == 'nativeQaloun':
            mapped = self._mapped(s, a)
            if a > 1:
                prev = self._mapped(s, a - 1)
                mapped = [n for n in mapped if n > max(prev)]
            files = []
            for n in mapped:
                if n in r['missing'].get(s, ()):
                    continue
                if r['breath'] and self._is_continuation(s, n):
                    continue
                files.append(('%03d%03d.mp3' % (s, n), None, None))
            return files
        if scheme == 'mergedTail':
            if s in MERGED_TAILS and a >= MERGED_TAILS[s]:
                return [('%03d%03d.mp3' % (s, MERGED_TAILS[s]), None, None)]
            return [('%03d%03d.mp3' % (s, a), None, None)]
        raise SystemExit('unknown scheme %s for %s — teach this tool and '
                         'AudioService about it together' % (scheme, r['id']))


# ── audio ────────────────────────────────────────────────────────────────────

def get(url):
    # The audio host refuses requests with no User-Agent.
    req = urllib.request.Request(url, headers={'User-Agent': 'curl/8'})
    with urllib.request.urlopen(req, timeout=300) as response:
        return response.read()


def decode(source, start=None, end=None):
    """Mono float32 at RATE. `start`/`end` (seconds) cut a span out of a long
    file without fetching all of it — the timed mirrors are constant bitrate,
    so ffmpeg's seek lands on the exact sample."""
    cmd = ['ffmpeg', '-v', 'error', '-nostdin']
    if start is not None:
        cmd += ['-ss', '%.3f' % start]
    if end is not None:
        cmd += ['-to', '%.3f' % end]
    cmd += ['-i', str(source), '-ac', '1', '-ar', str(RATE), '-f', 's16le', '-']
    pcm = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(pcm, dtype='<i2').astype(np.float32) / 32768.0


def fetch_clip_audio(reciter, clip, cache):
    """The decoded audio of one clip, cached on disk."""
    file, start, end = clip
    key = hashlib.sha1(('%s|%s|%s|%s' % (reciter['base'], file, start, end))
                       .encode()).hexdigest()[:16]
    path = cache / ('%s_%s.npy' % (file.replace('.mp3', ''), key))
    if path.exists():
        return np.load(path)
    url = reciter['base'] + file
    if start is None:
        data = get(url)
        if len(data) <= SILENT_BYTES:
            raise SystemExit('%s%s is a silent placeholder — the clip table '
                             'disagrees with the mirror' % (reciter['base'], file))
        local = cache / file
        local.write_bytes(data)
        audio = decode(local)
        local.unlink()
    else:
        audio = decode(url, start / 1000.0, end / 1000.0)
    np.save(path, audio)
    return audio


def envelope(audio):
    hop, win = int(RATE * HOP), int(RATE * WIN)
    count = max(0, (len(audio) - win) // hop + 1)
    frames = np.lib.stride_tricks.sliding_window_view(audio, win)[::hop][:count]
    rms = np.sqrt(np.mean(frames.astype(np.float64) ** 2, axis=1)) + 1e-9
    return 20 * np.log10(rms)


def quiet_threshold(env):
    """Loudness under which the clip counts as silent."""
    # A hissy recording may never fall QUIET_DB under its speech; then silence
    # is whatever sits close to its own floor.
    return max(np.percentile(env, 95) - QUIET_DB, np.percentile(env, 3) + 6)


def quiet_runs(env):
    """(start, end) seconds of every pause in the clip."""
    quiet = env < quiet_threshold(env)
    runs, start = [], None
    for i, q in enumerate(quiet):
        if q and start is None:
            start = i
        elif not q and start is not None:
            if (i - start) * HOP >= MIN_PAUSE:
                runs.append((start * HOP, i * HOP))
            start = None
    if start is not None and (len(quiet) - start) * HOP >= MIN_PAUSE:
        runs.append((start * HOP, len(quiet) * HOP))
    return runs


# ── the aligner ──────────────────────────────────────────────────────────────

_aligner = None


def align(audio, text, cache):
    """Word timings for `text` in `audio`, cached by content."""
    key = hashlib.sha1(audio.tobytes() + text.encode()).hexdigest()[:20]
    path = cache / ('align_%s.json' % key)
    if path.exists():
        return json.loads(path.read_text(encoding='utf-8'))
    global _aligner
    sys.path.insert(0, os.environ.get('QURAN_ALIGNER_DIR', '/root/quran'))
    import ctc_segment_progress as cs  # noqa: E402
    if _aligner is None:
        _aligner = cs.Aligner(30.0)
    wav = cache / ('align_%s.wav' % key)
    write_wav(wav, audio)
    words = cs.align_surah_words(_aligner, wav, text, 0,
                                 len(audio) / RATE, batch_size=4)
    wav.unlink()
    words = [{'text': w['text'], 'start': float(w['start']),
              'end': float(w['end'])} for w in words]
    path.write_text(json.dumps(words, ensure_ascii=False), encoding='utf-8')
    return words


def norm(text):
    sys.path.insert(0, os.environ.get('QURAN_ALIGNER_DIR', '/root/quran'))
    import ctc_segment_progress as cs  # noqa: E402
    return cs.norm(text)


def write_wav(path, audio):
    pcm = (np.clip(audio, -1, 1) * 32767).astype('<i2').tobytes()
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)


# ── one cue ──────────────────────────────────────────────────────────────────

def measure(reciter, clips, pages, page, word, cache, review):
    spanning = pages[page][0]
    s, a = spanning['surah'], spanning['ayah']
    prev_page_ayat = {(x['surah'], x['ayah']) for x in pages[page - 1]}

    # The clip that recites the spanning ayah's words.
    owner = a
    while not clips.of(s, owner):
        owner -= 1
        if owner < 1 or (s, owner) not in prev_page_ayat | {(s, a)}:
            raise SystemExit('%s %d:%d: no clip recites it on page %d or %d'
                             % (reciter['id'], s, a, page - 1, page))
    unit = clips.of(s, owner)
    # Every ayah recited in that clip: the owner and the silent ones after it.
    recited = [owner]
    n = owner + 1
    while clips.of(s, n) == [] and n <= owner + 40:
        if not any(x['surah'] == s and x['ayah'] == n
                   for p in (page - 1, page, page + 1) for x in pages[p]):
            break
        recited.append(n)
        n += 1
    texts = {x['ayah']: x['text'] for p in (page - 1, page, page + 1)
             for x in pages[p] if x['surah'] == s}

    words_before = sum(len(norm(texts[x]).split()) for x in recited
                       if x < a)
    own = norm(texts[a]).split()
    hits = [i for i, w in enumerate(own) if bare(w) == bare(word)]
    if len(hits) != 1:
        raise SystemExit('page %d: «%s» is not a unique word of %d:%d'
                         % (page, word, s, a))
    target = words_before + hits[0]
    text = ' '.join(norm(texts[x]) for x in recited)

    parts = [fetch_clip_audio(reciter, c, cache) for c in unit]
    audio = np.concatenate(parts)
    offsets = np.cumsum([0] + [len(p) for p in parts]) / RATE

    words = align(audio, text, cache)
    expected = len(text.split())
    if len(words) != expected:
        raise SystemExit('%s %d:%d: aligned %d words, text has %d'
                         % (reciter['id'], s, a, len(words), expected))
    w = words[target]
    after = words[target + 1]
    env = envelope(audio)

    # Where to look for the end of the word. The aligner's word edges are not
    # to be trusted on their own: a long madd before a stop («السمَآءْ») is
    # routinely ended seconds early, and the next word started early with it,
    # so the real pause can sit inside what the aligner calls the next word.
    # Start just before the aligner's end (never inside the word's opening,
    # where a consonant's closure can look like a pause) and run to the end of
    # the next word.
    lo = max(w['start'] + 0.15, w['end'] - 0.40)
    hi = after['end'] + 0.05
    pauses = [(r0, r1) for r0, r1 in quiet_runs(env) if r1 > lo and r0 < hi]
    loud = np.percentile(env, 95)
    if pauses:
        # The first stop after the word is the end of the page's last word.
        quiet_from, pause_end = pauses[0]
        quiet_from = max(quiet_from, lo)
        # The pause is where the room falls silent; the voice stopped before
        # that, at the top of the reverb's decay.
        i = int(round(quiet_from / HOP))
        limit = max(int(round(lo / HOP)), i - int(1.0 / HOP))
        while i > limit and env[i - 1] < loud - VOICE_DB:
            i -= 1
        voice_end = i * HOP
        at = min(voice_end + TURN_AFTER, (voice_end + pause_end) / 2)
        how = 'pause %.2fs' % (pause_end - voice_end)
    else:
        # Read straight on. Without a pause the aligner's junction is the best
        # guide there is — but words in connected speech meet in a dip (the
        # closure of the next word's first consonant), so move to the dip
        # nearest it. Not the deepest dip around: a stop inside the next word
        # («تُؤْتِي»'s ؤت) is often deeper than the junction itself.
        voice_end = pause_end = None
        junction = (w['end'] + after['start']) / 2 \
            if after['start'] > w['end'] else w['end']
        # A stop too short to count as a pause is still near-silent.
        quiet = quiet_threshold(env)
        i0 = max(0, int((w['end'] - 0.25) / HOP))
        i1 = min(len(env), int((after['start'] + 0.15) / HOP))
        stop = next((i for i in range(i0, i1) if env[i] < quiet), None)
        k = max(1, int(DIP_SMOOTH / HOP))
        smooth = np.convolve(env, np.ones(k) / k, mode='same')
        i0 = max(1, int((junction - DIP_REACH) / HOP))
        i1 = min(len(smooth) - 1, int((junction + DIP_REACH) / HOP))
        dips = [i for i in range(i0, i1)
                if smooth[i] <= smooth[i - 1] and smooth[i] <= smooth[i + 1]
                and smooth[i] < loud - DIP_DB]
        if stop is not None:
            end = stop
            while end < len(env) and env[end] < quiet:
                end += 1
            at = (stop + end) / 2 * HOP
            how = 'read on, stop %.2fs' % ((end - stop) * HOP)
        elif dips:
            i = min(dips, key=lambda i: abs(i * HOP - junction))
            at = i * HOP
            how = 'read on, dip %.0f dB' % (smooth[i] - loud)
        else:
            at = junction
            how = 'read on'

    # Back to a position inside one file.
    index = int(np.searchsorted(offsets, at, side='right') - 1)
    index = min(index, len(unit) - 1)
    file, start, _ = unit[index]
    at_ms = round((at - offsets[index]) * 1000) + (start or 0)

    result = {
        'surah': s, 'ayah': owner, 'spanning_ayah': a,
        'file': file, 'at_ms': int(at_ms),
        'how': how,
        'word': word,
        'ctc_word': [round(w['start'], 3), round(w['end'], 3)],
        'ctc_next': [round(after['start'], 3), round(after['end'], 3)],
        'voice_end': None if voice_end is None else round(voice_end, 3),
        'pause_end': None if pause_end is None else round(pause_end, 3),
        'at_in_clip': round(at, 3),
        'clip_seconds': round(len(audio) / RATE, 3),
        'clips': [list(c) for c in unit],
        'recited': ['%d:%d' % (s, x) for x in recited],
        'joined': owner != a,
    }
    write_review_clip(review, reciter, page, audio, at, words, target)
    return result


# ── listening page ───────────────────────────────────────────────────────────

def write_review_clip(review, reciter, page, audio, at, words, target):
    """`at` ±, with a short tick where the page turns."""
    lead, tail = 5.0, 3.0
    a0 = max(0.0, at - lead)
    a1 = min(len(audio) / RATE, at + tail)
    piece = audio[int(a0 * RATE):int(a1 * RATE)].copy()
    t = np.arange(int(0.04 * RATE)) / RATE
    tick = 0.25 * np.sin(2 * math.pi * 1800 * t) * np.hanning(len(t))
    i = int((at - a0) * RATE)
    piece[i:i + len(tick)] += tick[:max(0, len(piece) - i)]
    stem = '%s_p%d' % (reciter['id'], page)
    wav = review / (stem + '.wav')
    write_wav(wav, piece)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-b:a',
                    '48k', str(review / (stem + '.mp3'))], check=True)
    wav.unlink()
    env = envelope(piece)
    step = 2  # 20 ms per point keeps the page small
    shown = [{'t': round(x['start'] - a0, 3), 'e': round(x['end'] - a0, 3),
              'w': x['text'], 'mark': k == target}
             for k, x in enumerate(words)
             if x['end'] > a0 and x['start'] < a1]
    (review / (stem + '.json')).write_text(json.dumps({
        'env': [round(float(v), 1) for v in env[::step]],
        'step': HOP * step, 'at': round(at - a0, 3), 'words': shown,
    }, ensure_ascii=False), encoding='utf-8')


def write_review_page(review, reciters, results, pages):
    blocks = []
    for page in sorted({int(p) for r in results.values() for p in r}):
        s, a = pages[page][0]['surah'], pages[page][0]['ayah']
        cards = []
        for r in reciters:
            cue = results.get(r['id'], {}).get(str(page))
            stem = '%s_p%d' % (r['id'], page)
            if not cue or not (review / (stem + '.mp3')).exists():
                continue
            mp3 = base64.b64encode((review / (stem + '.mp3')).read_bytes()) \
                .decode()
            data = (review / (stem + '.json')).read_text(encoding='utf-8')
            note = ('تُتلى ضمن الآية %s' % cue['recited'][0]) \
                if cue['joined'] else ''
            cards.append(
                '<div class="card"><div class="head"><b>%s</b>'
                '<span>%s · %s · %s</span><span class="j">%s</span></div>'
                '<canvas></canvas><audio controls preload="none" '
                'src="data:audio/mpeg;base64,%s"></audio>'
                '<script type="application/json">%s</script></div>'
                % (r['name'], cue['file'], fmt_ms(cue['at_ms']), cue['how'],
                   note, mp3, data))
        blocks.append('<h2>صفحة %d ← %d · الآية %d:%d · آخر كلمة «%s»</h2>%s'
                      % (page - 1, page, s, a,
                         next(iter(results.values()))[str(page)]['word'],
                         ''.join(cards)))
    html = REVIEW_TEMPLATE.replace('{{BODY}}', '\n'.join(blocks))
    (review / 'page_turn_cues_review.html').write_text(html, encoding='utf-8')


def fmt_ms(ms):
    seconds = ms / 1000.0
    return '%d:%06.3f' % (seconds // 60, seconds % 60)


REVIEW_TEMPLATE = """<!doctype html>
<html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Page Turn Cues</title>
<style>
:root{--bg:#faf8f3;--fg:#222;--muted:#666;--card:#fff;--line:#ddd;--wave:#3b6e8f;--cue:#c0392b;--word:#2e7d32}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#16181b;--fg:#eee;--muted:#aaa;--card:#202328;--line:#333;--wave:#7fb3d5;--cue:#ff6b5b;--word:#81c784}}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:16px/1.6 system-ui,"Segoe UI",Tahoma,sans-serif}
h1{font-size:1.3rem}h2{font-size:1.1rem;margin-top:2rem;border-bottom:1px solid var(--line)}
.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px;margin:10px 0}
.head{display:flex;flex-wrap:wrap;gap:12px;align-items:baseline}.head span{color:var(--muted);font-size:.9rem;direction:ltr}
.head .j{color:var(--cue);direction:rtl}
canvas{width:100%;height:110px;display:block;margin:6px 0}audio{width:100%}
p{color:var(--muted);max-width:60rem}
</style></head><body>
<h1>لحظة قلب الصفحة في الآيات الممتدة بين صفحتين</h1>
<p>كل مقطع يبدأ قبل لحظة القلب بخمس ثوانٍ وينتهي بعدها بثلاث. <b>النقرة القصيرة</b> هي اللحظة التي يقلب فيها التطبيق الصفحة؛ ينبغي أن تُسمع بعد آخر كلمة في الصفحة مباشرة. الخط الأحمر في الرسم هو نفس اللحظة، والكلمة الخضراء هي آخر كلمة في الصفحة.</p>
{{BODY}}
<script>
for (const card of document.querySelectorAll('.card')) {
  const d = JSON.parse(card.querySelector('script').textContent);
  const c = card.querySelector('canvas'), audio = card.querySelector('audio');
  const css = getComputedStyle(document.documentElement);
  function draw(now) {
    const w = c.clientWidth, h = c.clientHeight, dpr = devicePixelRatio || 1;
    c.width = w * dpr; c.height = h * dpr;
    const g = c.getContext('2d'); g.scale(dpr, dpr);
    const total = d.env.length * d.step, x = t => w - (t / total) * w;
    const lo = Math.max(...d.env) - 50, hi = Math.max(...d.env);
    g.fillStyle = css.getPropertyValue('--wave');
    d.env.forEach((v, i) => {
      const y = Math.max(0, (v - lo) / (hi - lo)) * (h - 30);
      g.fillRect(x((i + 1) * d.step), h - 22 - y, Math.max(1, w / d.env.length), y);
    });
    g.font = '13px system-ui'; g.textAlign = 'center';
    for (const word of d.words) {
      g.fillStyle = word.mark ? css.getPropertyValue('--word') : css.getPropertyValue('--muted');
      g.fillText(word.w, x((word.t + word.e) / 2), h - 6);
    }
    g.fillStyle = css.getPropertyValue('--cue'); g.fillRect(x(d.at) - 1, 0, 2, h);
    if (now != null) { g.fillStyle = css.getPropertyValue('--fg'); g.fillRect(x(now), 0, 1, h); }
  }
  draw(); addEventListener('resize', () => draw());
  audio.addEventListener('timeupdate', () => draw(audio.currentTime));
}
</script></body></html>
"""


# ── the Dart table ───────────────────────────────────────────────────────────

def write_dart(reciters, results, pages):
    lines = [
        '// Exact page-turn moments inside the ayat printed across a page break —',
        '// لحظة قلب الصفحة داخل الآيات الممتدة بين صفحتين.',
        '//',
        '// Generated by tools/measure_page_turn_cues.py — do not edit by hand.',
        '// Re-run it for a reciter whenever that reciter\'s audio changes, and for',
        '// a new reciter before it ships (test/page_turn_cues_test.dart insists).',
        '',
        "import 'page_span_data.dart';",
        '',
        '/// The moment, in one reciter\'s audio, at which the last word printed on',
        '/// the earlier page has been recited.',
        '///',
        '/// [file] is the audio file as the app names it (`SSSAAA.mp3` for the',
        '/// per-ayah mirrors, `SSS.mp3` for [AudioScheme.timedSurah]) and [atMs] a',
        '/// position inside that whole file — under the timed scheme the player',
        '/// holds the whole surah, so it is not an offset from the ayah\'s span.',
        '///',
        '/// ([surah], [ayah]) is the displayed ayah whose clip plays that file: the',
        '/// page-spanning ayah itself, or — for a sheikh who reads it inside the',
        '/// previous ayah\'s breath — that previous ayah, which is listed on the',
        '/// earlier page. The page then turns mid-way through *its* clip.',
        'class PageTurnCue {',
        '  const PageTurnCue(this.surah, this.ayah, this.file, this.atMs);',
        '',
        '  final int surah;',
        '  final int ayah;',
        '  final String file;',
        '  final int atMs;',
        '}',
        '',
        '/// Reciter id → page turned to (a key of [spannedAyahHead]) → its cue.',
        'const Map<String, Map<int, PageTurnCue>> pageTurnCues = {',
    ]
    for r in reciters:
        per = results.get(r['id'])
        if not per:
            continue
        lines.append("  '%s': {" % r['id'])
        for page in sorted(per, key=int):
            c = per[page]
            joined = (' — read inside %s' % c['recited'][0]
                      if c['joined'] else '')
            lines.append('    // %d:%d «%s», %s%s.' % (
                c['surah'], c['spanning_ayah'], c['word'], c['how'], joined))
            lines.append("    %s: PageTurnCue(%d, %d, '%s', %d)," % (
                page, c['surah'], c['ayah'], c['file'], c['at_ms']))
        lines.append('  },')
    lines.append('};')
    lines.append('')
    DART_OUT.write_text('\n'.join(lines), encoding='utf-8')


# ── main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', action='append',
                    help='reciter id to (re)measure; repeatable')
    args = ap.parse_args()

    pages = load_pages()
    words = split_words()
    reciters = load_reciters()
    known = {r['id'] for r in reciters}
    for wanted in args.only or []:
        if wanted not in known:
            raise SystemExit('no reciter %s in Reciter.all' % wanted)

    results = {}
    if RESULT_JSON.exists():
        results = json.loads(RESULT_JSON.read_text(encoding='utf-8'))
    results = {k: v for k, v in results.items() if k in known}

    review = WORK / 'review'
    review.mkdir(parents=True, exist_ok=True)
    for r in reciters:
        if args.only and r['id'] not in args.only:
            continue
        cache = WORK / 'cache' / r['id']
        cache.mkdir(parents=True, exist_ok=True)
        clips = Clips(r)
        print('== %s (%s, %s)' % (r['name'], r['id'], r['scheme']), flush=True)
        per = {}
        for page in sorted(words):
            cue = measure(r, clips, pages, page, words[page], cache, review)
            per[str(page)] = cue
            print('   p%d %d:%d «%s» → %s @ %s  [%s%s]  ctc end %.2f, voice end %s'
                  % (page, cue['surah'], cue['spanning_ayah'], cue['word'],
                     cue['file'], fmt_ms(cue['at_ms']), cue['how'],
                     ', inside %s' % cue['recited'][0] if cue['joined'] else '',
                     cue['ctc_word'][1],
                     '-' if cue['voice_end'] is None
                     else '%.2f' % cue['voice_end']), flush=True)
        results[r['id']] = per

    RESULT_JSON.write_text(json.dumps(results, ensure_ascii=False, indent=1,
                                      sort_keys=True), encoding='utf-8')
    write_dart(reciters, results, pages)
    write_review_page(review, reciters, results, pages)
    print('\nwrote %s\nwrote %s\nwrote %s' % (
        RESULT_JSON.relative_to(ROOT), DART_OUT.relative_to(ROOT),
        (review / 'page_turn_cues_review.html').relative_to(ROOT)))
    return 0


if __name__ == '__main__':
    sys.exit(main())

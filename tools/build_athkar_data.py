#!/usr/bin/env python3
"""Builds assets/data/athkar.json, the content of «الأذكار».

Sources (tools/_sources/athkar/, not in git):
  hisn_elmoslem.db   sections, athkar, repeat counts and narration sources
                     (github.com/muslimpack/HisnElmoslem_App, assets/db)
  quran_uthmani.db   Hafs text, used only to locate a verse in our own text

Qur'an verses are NOT taken from the source: each reference is located in
assets/data/output.json and the app's Qalun text is used, so rerun this after
output.json edits. The app never names the book the athkar come from (owner,
2026-11-17), and the book's introduction is left out.

    python tools/build_athkar_data.py            # writes the asset + a report
    python tools/build_athkar_data.py --check    # report only
"""
import difflib
import json
import os
import re
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'tools', '_sources', 'athkar')
OUT = os.path.join(ROOT, 'assets', 'data', 'athkar.json')

# Raise when the content changes; ContentUpdateService.bundledVersions
# ['athkar'] must match (a test keeps them in step).
VER = 7

# The themed groups of the home screen (ours: the book is one flat list).
# Numbers are the book's section order; the order inside a group is the
# book's. Every section must appear exactly once.
GROUPS = [
    ('day', 'اليوم والليلة', [3, 29, 30, 31, 32, 33, 34]),
    ('home', 'اللباس والبيت', [4, 5, 6, 7, 12, 13]),
    ('wudu', 'الطهارة والمسجد والأذان', [8, 9, 10, 11, 14, 15, 16, 17]),
    ('salah', 'الصلاة', list(range(18, 29)) + [35, 36, 45]),
    ('worry', 'الهمّ والكرب والخوف',
     [37, 38, 39, 40, 41, 42, 43, 44, 46, 47, 48, 49, 91, 95, 97, 129, 131]),
    ('sick', 'المرض والوفاة', list(range(52, 64)) + [86, 127, 128]),
    ('weather', 'الريح والمطر والهلال', list(range(64, 71))),
    ('food', 'الطعام والصيام', list(range(71, 80)) + [130]),
    ('family', 'الزواج والأولاد', [50, 51, 82, 83, 84]),
    ('travel', 'السفر والركوب', list(range(98, 109))),
    ('hajj', 'الحج والعمرة', list(range(118, 125))),
    ('manners', 'المعاملة والآداب',
     [80, 81, 85, 87, 88, 89, 90, 92, 93, 94, 96, 109, 111, 112, 113, 114,
      115, 116, 117, 125, 126, 135]),
    ('dhikr', 'فضل الذكر والتسبيح والاستغفار', [2, 110, 132, 133, 134]),
]

# The tiles on top of the home screen: (section order, short label, icon).
FEATURED = [
    (29, 'أذكار الصباح', 'sun'),
    (30, 'أذكار المساء', 'moon'),
    (27, 'بعد الصلاة', 'prayer'),
    (31, 'أذكار النوم', 'bed'),
    (3, 'الاستيقاظ', 'wake'),
]

SKIP_SECTIONS = {1}  # the book's introduction

# Verse references that are wrong in the source: content id -> right one.
REF_FIXES = {3: '(33:41:41)'}

# Verse parts printed in the source without brackets: content id -> surah.
UNMARKED_VERSES = {4: 33}

# Recited Qur'an with a few words of instruction around it (what to do
# with the hands before sleep): still played from the Qur'an reciters.
QURAN_WITH_NOTES = {137}

# Surah names that the narration sources cite with a verse number (the
# numbers are rewritten to our count).
SURAH_NUMBERS = {'البقرة': 2, 'آل عمران': 3, 'الأعراف': 7, 'المؤمنون': 23,
                 'الأحزاب': 33, 'الزخرف': 43, 'الحديد': 57}

# Words taken out of a dhikr's text: content id -> exact text removed. The
# build stops if the text is no longer there.
# 32: the greeting to the family is not part of the supplication and no
# reader says it (owner, 2026-11-23).
TEXT_CUTS = {32: '، وَالسَّلاَمُ عَلَيْكُمْ وَرَحْمَةُ اللهِ وَبَرَكَاتُهُ يا أهلي'}

# Whole surahs too long to print inside a card: the card names the surah.
WHOLE_SURAH = {32: 'سورة السجدة', 67: 'سورة الملك'}

NL = chr(10)
HARAKAT = re.compile('[ً-ٰٟۖ-ۭـ]')
EASTERN = str.maketrans('٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789')


def bare(s):
    s = HARAKAT.sub('', s)
    s = re.sub('[إأآٱ]', 'ا', s)
    s = s.replace('ى', 'ي').replace('ے', 'ي').replace('ة', 'ه')
    s = s.replace('ؤ', 'و').replace('ئ', 'ي')
    return re.sub('[^ء-ي]', '', s)


def clean(s):
    """Tidies source text: honorific glyphs of the book's font, digits,
    dashes and spacing."""
    s = s.translate(EASTERN)
    s = s.replace('×', 'ﷺ').replace('‘', 'رحمه الله')
    s = s.replace('’', 'رضي الله عنها')
    s = s.replace('—', '،').replace('–', '-')
    s = s.replace('((', '«').replace('))', '»')
    s = re.sub(r'[ \t]+', ' ', s)
    s = re.sub(r' ?\n ?', '\n', s)
    s = re.sub(r' +([،.؛:])', r'\1', s)
    return s.strip()


class Quran:
    def __init__(self):
        pages = json.load(open(os.path.join(ROOT, 'assets', 'data',
                                            'output.json'), encoding='utf-8'))
        self.ours = {}
        # the last entry of output.json is itself a list of pages
        flat = []
        for p in pages:
            flat.extend(p if isinstance(p, list) else [p])
        for p in flat:
            for a in p['ayahs']:
                self.ours.setdefault(a['surah'], []).append(
                    (a['ayah'], a['text']))
        db = sqlite3.connect(os.path.join(SRC, 'quran_uthmani.db'))
        self.hafs = {(s, a): t for s, a, t in
                     db.execute('select sura, ayah, text from arabic_text')}
        t = dict(self.ours[27])
        m = next(x for x in t.values() if 'بِسْمِ' in x and 'سُلَيْمَٰنَ' in x)
        self.basmala = re.sub('[ۖ-ۜ ]+$', '', m[m.index('بِسْمِ'):])
        self.report = []
        self.numbers = {}
        # our ayah ranges of the verses rendered for the current item
        self.ranges = []

    def locate(self, surah, first, last):
        """Our ayat covering Hafs [surah] [first]..[last] (the two counts
        differ, so the range is found by its letters)."""
        target = ''.join(bare(self.hafs[(surah, a)])
                         for a in range(first, last + 1))
        rows = self.ours[surah]
        best = (0.0, 0, 0)
        for i in range(len(rows)):
            acc = ''
            for j in range(i, len(rows)):
                acc += bare(rows[j][1])
                if len(acc) > len(target) * 1.3 + 20:
                    break
                if len(acc) < len(target) * 0.7:
                    continue
                r = difflib.SequenceMatcher(None, acc, target,
                                            autojunk=False).ratio()
                if r > best[0]:
                    best = (r, i, j)
        r, i, j = best
        self.report.append(
            f'  {surah}:{first}-{last} -> ours {rows[i][0]}-{rows[j][0]} '
            f'ratio {r:.3f}')
        if r < 0.9:
            raise SystemExit(f'verse {surah}:{first}-{last} not found '
                             f'(best {r:.3f})')
        self.ranges.append([surah, rows[i][0], rows[j][0]])
        return [t for _, t in rows[i:j + 1]]

    def our_number(self, surah, ayah):
        """Our number of Hafs [surah]:[ayah] (its last part if we split
        it)."""
        key = (surah, ayah)
        if key not in self.numbers:
            target = bare(self.hafs[key])
            rows = self.ours[surah]
            best = (0.0, 0)
            for i, (_, t) in enumerate(rows):
                for j in range(i, min(i + 3, len(rows))):
                    acc = ''.join(bare(x[1]) for x in rows[i:j + 1])
                    r = difflib.SequenceMatcher(None, acc, target,
                                                autojunk=False).ratio()
                    if r > best[0]:
                        best = (r, j)
            if best[0] < 0.9:
                raise SystemExit(f'no number for {surah}:{ayah}')
            self.numbers[key] = rows[best[1]][0]
        return self.numbers[key]

    def snippet(self, text, surah=None):
        """Our wording of a part of a verse quoted in Hafs spelling: the
        run of our words whose letters match best. Returns the words grouped
        by ayah, each group in its own brackets."""
        target = bare(re.sub('[0-9٠-٩]', '', text))
        k = len(text.split())
        best = (0.0, None)
        for s in ([surah] if surah else sorted(self.ours)):
            words = [(i, w) for i, (_, t) in enumerate(self.ours[s])
                     for w in t.split()]
            bw = [bare(w) for _, w in words]
            for size in range(max(1, k - 3), k + 4):
                for i in range(0, len(words) - size + 1):
                    if abs(sum(map(len, bw[i:i + size])) - len(target)) >                             max(3, len(target) * 0.15):
                        continue
                    acc = ''.join(bw[i:i + size])
                    if acc[:2] != target[:2] and acc[-2:] != target[-2:]:
                        continue
                    r = difflib.SequenceMatcher(None, acc, target,
                                                autojunk=False).ratio()
                    if r > best[0]:
                        best = (r, (s, words[i:i + size]))
        r, found = best
        if r < 0.88:
            raise SystemExit(f'snippet not found ({r:.3f}): {text}')
        s, words = found
        groups = {}
        for i, w in words:
            groups.setdefault(i, []).append(w)
        out = ' '.join('﴿' + ' '.join(ws) + '﴾' for ws in groups.values())
        self.report.append(f'  snippet {s}:'
                           f'{[self.ours[s][i][0] for i in groups]} '
                           f'ratio {r:.3f}: {out}')
        return out

    def render(self, refs):
        parts = []
        for surah, first, last in refs:
            if surah in WHOLE_SURAH:
                parts.append(f'قراءة {WHOLE_SURAH[surah]} كاملة')
                self.ranges.append([surah, 1, self.ours[surah][-1][0]])
                continue
            ayat = self.locate(surah, first, last)
            whole = first == 1 and (surah, last + 1) not in self.hafs
            lead = (self.basmala + '\n') if whole and surah != 9 else ''
            parts.append(lead + ' '.join(f'﴿{a.strip()}﴾' for a in ayat))
        return '\n'.join(parts)


def renumber(quran, src):
    """Verse numbers in a narration source, in our count."""
    names = '|'.join(SURAH_NUMBERS)

    def ours(surah, n):
        return str(quran.our_number(SURAH_NUMBERS[surah], int(n)))

    def after(m):
        out = m.group(1) + ours(m.group(2), m.group(3))
        if m.group(5):
            out += '-' + ours(m.group(2), m.group(5))
        return out

    new = re.sub(
        rf'(سورة ({names})[،:]? ?(?:الآية|الاية|الآيتان|رقم)?:? ?)(\d+)'
        rf'(\s*-\s*(\d+))?', after, src)
    new = re.sub(rf'(الآية رقم )(\d+)( من سورة ({names}))',
                 lambda m: m.group(1) + ours(m.group(4), m.group(2)) +
                 m.group(3), new)
    new = new.replace('الاية', 'الآية')
    if new != src:
        quran.report.append(f'  source: {src[-60:]} -> {new[-60:]}')
    return new


# The first voice is the default, and a dhikr it did not record plays in the
# next voice on this list that has it (owner, 2026-11-19: سعد الغامدي by
# default, حمد الدريهم for what he lacks). Voices not named here follow in
# the order publish_voices.py wrote them.
VOICE_ORDER = ['ghamdi', 'duraihem']


def voices():
    path = os.path.join(ROOT, 'tools', 'athkar_voices.json')
    if not os.path.exists(path):
        return []
    found = json.load(open(path, encoding='utf-8'))
    rank = {v: i for i, v in enumerate(VOICE_ORDER)}
    return sorted(found, key=lambda v: rank.get(v['id'], len(rank)))  # stable: the rest keep their order


def main():
    check_only = '--check' in sys.argv
    db = sqlite3.connect(os.path.join(SRC, 'hisn_elmoslem.db'))
    quran = Quran()

    titles = db.execute(
        'select id, "order", name from titles order by "order"').fetchall()
    by_order = {}
    sections = []
    n_items = 0
    for tid, order, name in titles:
        if order in SKIP_SECTIONS:
            continue
        plain = re.sub(r'\s+', ' ', HARAKAT.sub('', name)).strip()
        plain = plain.replace('النبي بعد', 'النبي ﷺ بعد')
        if plain.endswith('على النبي') or plain.endswith('كان النبي يسبح'):
            plain = plain.replace('النبي', 'النبي ﷺ')
        items = []
        for cid, content, count, source, audio in db.execute(
                'select id, content, count, source, audio_urls from contents '
                'where titleId=? order by "order"', (tid,)):
            if cid in REF_FIXES:
                content = f'QuranText[{REF_FIXES[cid]}]'

            def verses(m):
                refs = [tuple(int(x) for x in r.split(':'))
                        for r in re.findall(r'\(([\d:]+)\)', m.group(1))]
                return quran.render(refs)

            quran.ranges = []
            whole_quran = (content.strip().startswith('QuranText[')
                           or cid in UNMARKED_VERSES or cid in QURAN_WITH_NOTES)
            if cid in UNMARKED_VERSES:
                content = '﴿' + content.strip() + '﴾'
            # verses quoted inline: our wording (a few letters such as
            # ﴿الم﴾ stay as they are)
            content = re.sub(
                '﴿([^﴾]+)﴾',
                lambda m: quran.snippet(m.group(1), UNMARKED_VERSES.get(cid))
                if len(bare(m.group(1))) >= 6 else m.group(0), content)
            text = re.sub(r'QuranText\[(.*?)\]', verses, content)
            # tidy only what is outside the verses, keeping line breaks
            def edge(part, c):
                return '' if not c.isspace() else (
                    NL if NL in part else ' ')

            pieces = re.split('(﴿[^﴾]*﴾)', text)
            out = []
            for p in pieces:
                if p.startswith('﴿'):
                    out.append(p)
                    continue
                c = clean(p)
                if not c:
                    out.append(NL if NL in p else (' ' if p else ''))
                    continue
                lead = len(p) - len(p.lstrip())
                trail = len(p) - len(p.rstrip())
                out.append(edge(p[:lead], p[:1]) + c +
                           edge(p[len(p) - trail:], p[-1:]))
            text = re.sub(' *' + NL + ' *', NL, ''.join(out)).strip()
            b = quran.basmala
            text = text.replace('﴾ ' + b + ' ', '﴾' + NL + b + NL)
            if text.startswith(b + ' '):
                text = b + NL + text[len(b) + 1:]
            text = text.replace(NL + b + ' ', NL + b + NL)
            if cid in TEXT_CUTS:
                if TEXT_CUTS[cid] not in text:
                    raise SystemExit(f'TEXT_CUTS {cid}: text not found')
                text = text.replace(TEXT_CUTS[cid], '').strip()
            item = {'id': cid, 't': text, 'n': max(1, int(count or 1))}
            if cid in UNMARKED_VERSES:
                item['q'] = [[UNMARKED_VERSES[cid], 35, 35]]
            elif whole_quran and quran.ranges:
                # recited Qur'an: the app plays it from its Qur'an reciters
                item['q'] = quran.ranges
            src = renumber(quran, clean(source or ''))
            if src:
                item['s'] = src
            if audio:
                first = next(iter(json.loads(audio).values()))
                m = re.match(r'(\d{4})', first.rsplit('/', 1)[1])
                if m:
                    item['a'] = int(m.group(1))
            items.append(item)
        n_items += len(items)
        by_order[order] = tid
        sections.append({'id': tid, 'name': plain, 'items': items})

    seen = [o for _, _, orders in GROUPS for o in orders]
    missing = sorted(set(by_order) - set(seen))
    extra = sorted(set(seen) - set(by_order))
    dup = sorted({o for o in seen if seen.count(o) > 1})
    if missing or extra or dup:
        raise SystemExit(f'groups: missing {missing} unknown {extra} '
                         f'twice {dup}')

    data = {
        'v': 1,
        'ver': VER,
        'featured': [{'section': by_order[o], 'label': label, 'icon': icon}
                     for o, label, icon in FEATURED],
        'groups': [{'id': gid, 'name': name,
                    'sections': [by_order[o] for o in orders]}
                   for gid, name, orders in GROUPS],
        'sections': sections,
        # The app reciter the verses play in until the reader picks another
        # (owner, 2026-11-17).
        'quranReciter': 'naihi_qaloun',
        # the last line of a copied or shared dhikr (the app has the same default)
        'shareLine': 'من تطبيق المصحف الجامع',
        # The athkar voices (AthkarReciter in the app), first = default.
        # Written by C:/Down/AthkarAudio/pipeline/publish_voices.py.
        'reciters': voices(),
    }
    text = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    for pattern, what in (('[٠-٩۰-۹]', 'Eastern digits'), ('—', 'em dash'),
                          ('حصن المسلم', 'the book name'),
                          ('QuranText', 'unresolved verse')):
        hits = re.findall(pattern, text)
        if hits:
            raise SystemExit(f'{what} left in the data: {len(hits)}')
    print(f'{len(sections)} sections, {n_items} athkar, '
          f'{len(text.encode("utf-8")) // 1024} KB')
    print('verses:')
    print('\n'.join(quran.report))
    if not check_only:
        with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        print('wrote', os.path.relpath(OUT, ROOT))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()

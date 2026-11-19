"""Builds assets/data/usul.json, the «أحكام وأصول الرواية» section (side menu, under الأذكار).

The content is the reviewed mockup (owner, 2026-11-18/19): C:/Down/Books/usul_qalun/mockup_2026-11-18,
build_usul_mockup.py + chapters_more.py. Every example there is looked up in our own output.json and
the builder fails on a missing word, a wrong ياء state or a sajdah count that is not 11. This script
runs that builder with the RAW mushaf text (the app applies quranDisplayText itself), reads each
screen back from its HTML and writes plain blocks the app draws. Nothing is typed twice.

    python tools/build_usul_data.py            # writes assets/data/usul.json

Raise VER for every content change, then publish the `usul` server item
(tools/publish_content_updates.py). Western digits only.
"""
import html.parser
import json
import re
import sys
from pathlib import Path

VER = 1

ROOT = Path(__file__).resolve().parent.parent
MOCK = Path(r'C:/Down/Books/usul_qalun/mockup_2026-11-18')
OUT = ROOT / 'assets' / 'data' / 'usul.json'
sys.stdout.reconfigure(encoding='utf-8')

# ---- run the mockup builder with raw text, without writing its page ---------------------------
src = (MOCK / 'build_usul_mockup.py').read_text(encoding='utf-8')


def patch(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)


src = patch(src, "    return t.translate(DT).replace('\\u06D2\\u0655', '\\u064A\\u0654').replace('\\u06D2', '\\u064A')",
            '    return t')
src = patch(src, """f'<div class="ex"><p class="q">""",
            """f'<div class="ex" data-s="{s}" data-a="{a}" data-p="{page_of[(s, a)]}"><p class="q">""")
src = src[:src.index("\nCSS = '''")]
ns = {'__file__': str(MOCK / 'build_usul_mockup.py'), '__name__': 'usul_export'}
exec(compile(src, str(MOCK / 'build_usul_mockup.py'), 'exec'), ns)


# ---- a small HTML tree ----------------------------------------------------------------------
class Node:
    def __init__(self, tag, attrs):
        self.tag, self.attrs, self.kids = tag, dict(attrs), []

    @property
    def cls(self):
        return set((self.attrs.get('class') or '').split())

    def text(self):
        return ''.join(k if isinstance(k, str) else k.text() for k in self.kids)

    def elems(self):
        return [k for k in self.kids if isinstance(k, Node)]


VOID = {'br', 'img', 'meta', 'link'}


class Tree(html.parser.HTMLParser):
    def __init__(self, s):
        super().__init__(convert_charrefs=True)
        self.root = Node('root', {})
        self.stack = [self.root]
        self.feed(s)
        self.close()
        assert len(self.stack) == 1, [n.tag for n in self.stack]

    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs)
        self.stack[-1].kids.append(n)
        if tag not in VOID:
            self.stack.append(n)

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        # the mockup's home page closes one div too many (browsers shrug): ignore a stray end tag
        if not any(n.tag == tag for n in self.stack[1:]):
            return
        while self.stack[-1].tag != tag:
            self.stack.pop()
        self.stack.pop()

    def handle_data(self, d):
        self.stack[-1].kids.append(d)


def rich(n):
    """Inline text with <b> kept as **…**; icons dropped. Anything else is an error."""
    out = []
    for k in n.kids:
        if isinstance(k, str):
            out.append(k)
        elif k.tag == 'b':
            out.append('**' + k.text() + '**')
        elif k.tag == 'i' and 'ms' in k.cls:
            continue
        else:
            raise ValueError(f'inline <{k.tag} {k.attrs}> in {n.text()[:40]!r}')
    return re.sub(r'\s+', ' ', ''.join(out)).strip()


PAGE_RE = re.compile(r'\s*·\s*صفحة (\d+)$')


def ref_page(ref):
    m = PAGE_RE.search(ref)
    return (ref[:m.start()], int(m.group(1))) if m else (ref, None)


def word_item(w, r):
    r, p = ref_page(r)
    d = {'w': w, 'r': r}
    if p:
        d['p'] = p
    return d


def blocks_of(nodes):
    out, tags = [], []
    for n in nodes:
        c = n.cls
        if n.tag == 'h2':
            continue
        if 'tag' in c:
            tags.append({'x': n.text().strip(), **({'diff': True} if 'diff' in c else {})})
        elif n.tag == 'p' and 'lead' in c:
            out.append({'t': 'lead', 'x': rich(n)})
        elif n.tag == 'p' and 'sub' in c:
            out.append({'t': 'sub', 'x': rich(n)})
        elif n.tag == 'p' and not c:
            out.append({'t': 'para', 'x': rich(n)})
        elif 'note' in c:
            out.append({'t': 'note', 'x': rich(n), **({'mu': True} if 'mu' in c else {})})
        elif 'gh' in c:
            out.append({'t': 'head', 'x': n.text().strip()})
        elif 'rules' in c:
            items = []
            for mi in n.elems():
                assert 'mini' in mi.cls, mi.cls
                parts = {next(iter(e.cls)): e for e in mi.elems()}
                d = word_item(parts['mw'].text().strip(), parts['mr'].text().strip())
                d['x'] = rich(parts['md'])
                items.append(d)
            out.append({'t': 'minis', 'items': items})
        elif 'xl' in c:
            items = []
            for r in n.elems():
                w, f = r.elems()
                items.append(word_item(w.text().strip(), f.text().strip()))
            out.append({'t': 'words', 'items': items})
        elif 'ex' in c:
            q = next(e for e in n.elems() if 'q' in e.cls)
            parts = []
            for k in q.kids:
                if isinstance(k, str):
                    parts.append([k, 0])
                elif k.tag == 'mark':
                    parts.append([k.text(), 1])
                else:
                    assert 'an' in k.cls, k.cls
            parts[-1][0] = parts[-1][0].rstrip()
            parts = [p for p in parts if p[0]]
            foot = next(e for e in n.elems() if 'exf' in e.cls).elems()[0].text().strip()
            r, p = ref_page(foot)
            assert p == int(n.attrs['data-p']), (foot, n.attrs)
            out.append({'t': 'ayah', 's': int(n.attrs['data-s']), 'a': int(n.attrs['data-a']),
                        'p': p, 'r': r, 'parts': parts})
        elif 'two' in c:
            items = []
            for o in n.elems():
                on = next(e for e in o.elems() if 'on' in e.cls)
                name = ''.join(k for k in on.kids if isinstance(k, str)).strip()
                pref = any(isinstance(k, Node) and k.tag == 'em' for k in on.kids)
                body = next(e for e in o.elems() if e.tag == 'p')
                items.append({'n': name, **({'pref': True} if pref else {}), 'x': rich(body)})
            out.append({'t': 'options', 'items': items})
        elif n.tag == 'ol' and 'combo' in c:
            items = []
            for li in n.elems():
                name = ''.join(k for k in li.kids if isinstance(k, str)).strip()
                pref = any(isinstance(k, Node) and k.tag == 'em' for k in li.kids)
                items.append({'x': name, **({'pref': True} if pref else {})})
            out.append({'t': 'steps', 'items': items})
        elif 'card2' in c:
            kids = n.elems()
            assert 'ct' in kids[0].cls
            out.append({'t': 'card', 'h': kids[0].text().strip(), 'blocks': blocks_of(kids[1:])[0]})
        elif 'chips' in c:
            out.append({'t': 'chips', 'items': [e.text().strip() for e in n.elems()]})
        elif 'verse' in c:
            lines = [e.text().strip() for e in n.elems() if 'vl' in e.cls]
            g = next(e for e in n.elems() if 'vg' in e.cls)
            w = next(e for e in n.elems() if 'vw' in e.cls)
            out.append({'t': 'verse', 'lines': lines, 'g': rich(g), 'w': w.text().strip()})
        elif 'src' in c:
            out.append({'t': 'src', 'items': [rich(e) for e in n.elems() if 'si' in e.cls]})
        elif 'book' in c:
            body = n.elems()[1]
            parts = {next(iter(e.cls), e.tag): e for e in body.elems()}
            out.append({'t': 'book', 'h': parts['bt'].text().strip(), 'by': parts['bm'].text().strip(),
                        'x': rich(parts['p'])})
        else:
            raise ValueError(f'unknown block <{n.tag} class={sorted(c)}>: {n.text()[:50]!r}')
    return out, tags


def screen(html_text):
    t = Tree(html_text).root
    body = next(e for e in t.elems() if 'body' in e.cls)
    title = next(e for e in t.elems() if 'bar' in e.cls).elems()[-1].text().strip()
    blocks, tags = blocks_of(body.elems())
    return title, blocks, tags


# ---- the home page: hero, the three kinds, then the rows with their subtitles -----------------
home = Tree(ns['home']).root
hbody = next(e for e in home.elems() if 'body' in e.cls)
hero = next(e for e in hbody.elems() if 'hero' in e.cls)
hv = next(e for e in hero.elems() if 'hv' in e.cls)
hero_d = {
    'h': next(e for e in hero.elems() if 'ht' in e.cls).text().strip(),
    'x': rich(next(e for e in hero.elems() if e.tag == 'p')),
    'lines': [x.strip() for x in hv.kids if isinstance(x, str) and x.strip()],
    'w': next(e for e in hero.elems() if 'hw' in e.cls).text().strip(),
}
kinds = [{'h': k.elems()[0].text().strip(), 'x': k.elems()[1].text().strip()}
         for k in next(e for e in hbody.elems() if 'kinds' in e.cls).elems()]
subs, order = {}, []
for lst in (e for e in hbody.elems() + home.elems() if 'list' in e.cls):
    for r in lst.elems():
        rt = r.elems()[0].elems()[0]
        title = rich(rt)
        rs = [e for e in r.elems()[0].elems() if 'rs' in e.cls]
        subs[title] = rs[0].text().strip() if rs else ''
        order.append(title)

ICONS = {'معاني المصطلحات': 'translate', 'المصادر': 'library_books'}
groups, ids = [], set()
for gname, items in ns['GROUPS']:
    if gname == 'المدخل':
        continue
    chapters = []
    for label, body in items:
        title, blocks, tags = screen(body)
        assert title == label and label in subs, (label, title)
        cid = f'c{len(ids) + 1}'
        ids.add(cid)
        ch = {'id': cid, 'title': title, 'sub': subs[label], 'tags': tags, 'blocks': blocks}
        if label in ICONS:
            ch['icon'] = ICONS[label]
        chapters.append(ch)
    groups.append({'name': '' if gname == 'في آخر القسم' else gname, 'chapters': chapters})

assert [c['title'] for g in groups for c in g['chapters']] == order, 'home rows and chapters differ'

data = {'ver': VER, 'v': 1, 'title': 'أحكام وأصول الرواية', 'hero': hero_d, 'kinds': kinds, 'groups': groups}
text = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
bad = re.findall('[\u0660-\u0669\u06f0-\u06f9\u2014]', text)
assert not bad, bad
for w in ['nquran', 'تونس', 'dhibi']:
    assert w not in text.lower(), w
OUT.write_text(text + '\n', encoding='utf-8')
n = sum(len(g['chapters']) for g in groups)
print(f'wrote {OUT.relative_to(ROOT)}: ver {VER}, {n} chapters, {len(text) // 1024} KB')

#!/usr/bin/env python3
"""Generate assets/data/word_masks.json: for every word of every page, the set
of small rectangles that cover exactly that word's ink (its strokes and its
marks), plus the page's placement inside the hawamesh (margin-view) image.

Why not one box per word (the old word_regions.json): a word's marks reach
into the neighbouring lines, so one box either clipped the neighbour's marks
or let this word's own marks show. Here every ink component is assigned to
one word and the mask is the union of those components' boxes.

Method, per page (720x1640 image, ink = gray < 120):
  1. connected components of the ink; components inside an ayah marker or
     larger than any letter (surah frames, rules) are left out (never masked).
  2. lines = the ayah rects of ayah_regions.json (reading order). Each rect
     gets its core band (rows around the horizontal-projection peak) and its
     stroke groups: components crossing the core band, merged by x-overlap.
  3. one DP per ayah deals the groups of all its lines to its words in
     reading order: a word takes one or more consecutive groups of one line,
     scored by how well the span fits the word's predicted width (letter width
     table of generate_word_regions, scale fitted on the ayah). Groups whose
     baseline ink thins out offer "weak cuts" the DP may use at a small cost,
     so touching words can still be separated; if that is not enough the
     widest groups are cut at their thinnest column.
  4. marks (all other components) go to a line by local geometry, not a fixed
     line boundary: a mark between two lines belongs to the line above when it
     sits just under that line's ink at the same columns (kasra, dots under
     ya/ba) and the word above can carry a mark below; otherwise to the line
     below. Within a line a mark goes to the word whose columns hold its centre.
  5. a word's rects are its components' boxes, greedily merged while the merged
     rect contains no other word's ink, padded by 1 px.

Output (ints in 720x1640 px; the app divides by the image size):
  [{"page": N, "hw": [x, y, w, h] (ratio of the hawamesh image: where this
      page image sits in it, from tasmee_work/hawamesh_transform.json),
    "ayahs": [{"surah": S, "ayah": A, "words": [[[x, y, w, h], ...], ...]}]}]
Words are in the ayah's reading order (output.json). An ayah with no rects on
the page, or whose words could not be placed, has "words": [] and the app masks
it as a whole.

usage: python tools/generate_word_masks.py [--pages 1,2,3] [--preview] [--out FILE]
Diagnostics go to tasmee_work/wordmasks/ (previews) and stdout (coverage, leaks,
width residuals).
"""
import argparse
import json
import os
import re
import sys

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import generate_word_regions as G  # noqa: E402  (letter width table)

WORK = r"D:\quran app\tasmee_work"
HW_TRANSFORM = os.path.join(WORK, "hawamesh_transform.json")
PREVIEW_DIR = os.path.join(WORK, "wordmasks")

MARK = re.compile(r"[\u064b-\u065f\u0670\u06d6-\u06ed\u06e1\u08d3-\u08ff\u0610-\u061a]")
BELOW_MARKS = set("\u0650\u064d\u06ed\u0656\u0655\u06e3\u065f")  # kasra, kasratan, small marks placed under
BELOW_DOT_LETTERS = {"ب": 1, "ي": 2, "ج": 1}
PAUSE = re.compile("[ۖ-ۜ]")
PAD = 1
BRIDGE_GAP = 14      # px: a stroke may span two ink groups this close (broken join, detached letter)
BRIDGE_PEN = 0.3     # plus 0.04 per px of gap: a real word gap is bridged only when the widths insist
WEAK_PENALTY = 0.7      # cost of a word boundary at a weak cut inside a stroke group
FORCED_PENALTY = 1.5


NON_JOINING = set("\u0627\u0623\u0625\u0622\u0671\u0621\u062f\u0630\u0631\u0632\u0648\u0624\u0629\u0649\u06d2")
_STROKE_WIDTHS = None


def strokes_of_word(word):
    """Base letters of each pen stroke of the word (letters join until a
    non-joining one), e.g. the article + a joined stem + a final letter."""
    base = [c for c in MARK.sub("", word) if c != "\u06de"]
    out, cur = [], ""
    for c in base:
        cur += c
        if c in NON_JOINING:
            out.append(cur)
            cur = ""
    if cur:
        out.append(cur)
    return out


def load_stroke_widths():
    global _STROKE_WIDTHS
    if _STROKE_WIDTHS is None:
        path = os.path.join(ROOT, "tools", "stroke_widths.json")
        if os.path.exists(path):
            _STROKE_WIDTHS = json.load(open(path, encoding="utf-8"))
        else:
            # bootstrap: the hand table of generate_word_regions in px (18.3 px per unit)
            _STROKE_WIDTHS = {"letters": {c: round(u * 18.3, 2) for c, u in G.W.items()}, "const": 5.5, "default": 14.6}
            _STROKE_WIDTHS["letters"]["\u0627"] = 9.0
    return _STROKE_WIDTHS


def stroke_keys(letters):
    """Per letter of a stroke, the key of its positional form: isolated (i),
    initial (b), medial (m), final (e). The width of a letter differs a lot
    between forms (a medial kaf is a hook, an isolated one a full bowl)."""
    n = len(letters)
    if n == 1:
        return [letters + "i"]
    return [c + ("b" if k == 0 else "e" if k == n - 1 else "m") for k, c in enumerate(letters)]


def stroke_width(letters, n_strokes=1):
    t = load_stroke_widths()
    if t.get("positional"):
        return t["const"] / max(1, n_strokes) + sum(t["letters"].get(k, t["letters"].get(k[0] + "i", t["default"])) for k in stroke_keys(letters))
    return t["const"] + sum(t["letters"].get(c, t["default"]) for c in letters)


def below_marks_expected(word):
    n = sum(1 for c in word if c in BELOW_MARKS)
    n += sum(BELOW_DOT_LETTERS.get(c, 0) for c in MARK.sub("", word))
    return n


# ---------------------------------------------------------------------------
class Page:
    def __init__(self, page, regions, text, hw):
        self.page = page
        self.img = cv2.imread(os.path.join(ROOT, f"assets/images/page_{page}.webp"), cv2.IMREAD_COLOR)
        self.H, self.W = self.img.shape[:2]
        self.ink = G.ink_mask(self.img)
        self.regions, self.text, self.hw = regions, text, hw
        n, self.labels, self.stats, self.cents = cv2.connectedComponentsWithStats(self.ink, connectivity=8)
        self.ncomp = n
        self.owner = np.full(n, -1, np.int32)      # component -> word id (global on page), -2 = excluded
        self.excluded = np.zeros(n, bool)
        self.lines = []                             # per rect: dicts, page reading order
        self.words = []                             # dicts: ayah, k (index in ayah), text, line, comps, span
        self.unplaced = []                          # ayah indices whose words could not be placed
        self.residuals = []
        self.samples = []     # (stroke letters, measured px, line scale) for the width fit
        self._exclude_furniture()

    # -- 1. furniture -------------------------------------------------------
    def _exclude_furniture(self):
        H, W = self.H, self.W
        for c in range(1, self.ncomp):
            x, y, w, h, a = self.stats[c]
            if w > 0.45 * W or h > 0.09 * H or (w > 0.3 * W and h > 0.05 * H):
                self.excluded[c] = True
        for ay in self.regions["ayahs"]:
            m = ay.get("marker")
            if not m:
                continue
            mx0, my0 = m["x"] * W, m["y"] * H
            mx1, my1 = mx0 + m["width"] * W, my0 + m["height"] * H
            cx, cy = self.cents[:, 0], self.cents[:, 1]
            inside = (cx >= mx0 - 2) & (cx <= mx1 + 2) & (cy >= my0 - 2) & (cy <= my1 + 2)
            self.excluded |= inside
        self.excluded[0] = True
        self.owner[self.excluded] = -2

    # -- 2. lines and stroke groups -----------------------------------------
    def core_band(self, rect):
        x0, x1, y0, y1 = rect
        prof = self.ink[y0:y1, x0:x1].sum(axis=1).astype(float)
        if prof.max() <= 0:
            return y0 + (y1 - y0) // 3, y1 - (y1 - y0) // 3
        peak = int(np.argmax(prof))
        thr = 0.35 * prof.max()
        a = peak
        while a > 0 and prof[a - 1] >= thr:
            a -= 1
        b = peak
        while b < len(prof) - 1 and prof[b + 1] >= thr:
            b += 1
        return y0 + a, y0 + b + 1

    def build_lines(self):
        H, W = self.H, self.W
        for ai, ra in enumerate(self.regions["ayahs"]):
            rects = [(int(r["x"] * W), int((r["x"] + r["width"]) * W), int(r["y"] * H), int((r["y"] + r["height"]) * H)) for r in ra["rects"]]
            for ri, rc in enumerate(rects):
                self.lines.append(dict(ayah=ai, rect=ri, px=rc, core=self.core_band(rc), words=[], groups=[]))
        pitch = np.median([l["px"][3] - l["px"][2] for l in self.lines]) if self.lines else 100
        self.pitch = float(pitch)
        claimed = np.zeros(self.ncomp, bool)
        for line in self.lines:
            x0, x1, y0, y1 = line["px"]
            cy0, cy1 = line["core"]
            spans = []
            for c in range(1, self.ncomp):
                if self.excluded[c] or claimed[c]:
                    continue
                bx, by, bw, bh, a = self.stats[c]
                cx = self.cents[c][0]
                if not (x0 - 2 <= cx < x1 + 2):
                    continue
                inter = max(0, min(by + bh, cy1) - max(by, cy0))
                if inter >= 0.3 * (cy1 - cy0) or (inter >= 0.5 * bh and bh >= 3):
                    spans.append([int(bx), int(bx + bw), c])
                    claimed[c] = True
            line["_spans"] = spans
        # core-crossing ink outside every rect (first letter at the margin of a
        # narrow rect): nearest line on the same row, within a third of a pitch
        for c in range(1, self.ncomp):
            if self.excluded[c] or claimed[c]:
                continue
            bx, by, bw, bh, a = self.stats[c]
            cx = self.cents[c][0]
            best, bd = None, 0.34 * self.pitch
            for line in self.lines:
                cy0, cy1 = line["core"]
                inter = max(0, min(by + bh, cy1) - max(by, cy0))
                if not (inter >= 0.3 * (cy1 - cy0) or (inter >= 0.5 * bh and bh >= 3)):
                    continue
                x0, x1 = line["px"][0], line["px"][1]
                d = 0 if x0 <= cx < x1 else min(abs(cx - x0), abs(cx - x1))
                if d < bd:
                    best, bd = line, d
            if best is not None:
                best["_spans"].append([int(bx), int(bx + bw), c])
                claimed[c] = True
        for line in self.lines:
            spans = line.pop("_spans")
            spans.sort()
            groups = []
            for s in spans:
                if groups and s[0] <= groups[-1]["x1"]:
                    groups[-1]["x1"] = max(groups[-1]["x1"], s[1])
                    groups[-1]["comps"].append(s[2])
                else:
                    groups.append(dict(x0=s[0], x1=s[1], comps=[s[2]]))
            line["groups"] = groups[::-1]  # reading order: right to left

    def word_samples(self):
        """(word text, measured px width) for every ayah whose stroke groups are
        exactly as many as its words: then each group is one whole word, with no
        model involved. The width fit trains on these only."""
        tmap = {(a["surah"], a["ayah"]): [w for w in a["text"].split() if w] for a in self.text["ayahs"]}
        out = []
        for ai, ra in enumerate(self.regions["ayahs"]):
            words = tmap.get((ra["surah"], ra["ayah"]), [])
            lines = [l for l in self.lines if l["ayah"] == ai]
            groups = [g for l in lines for g in l["groups"]]
            if words and len(groups) == len(words):
                for w, g in zip(words, groups):
                    out.append((w, g["x1"] - g["x0"]))
        return out

    # -- 3. groups -> words (one DP per ayah) --------------------------------
    def weak_cuts(self, line, g):
        """Candidate cut columns inside a stroke group: the thinnest columns of the
        core band (local minima of the column ink), each with a penalty that grows
        with the ink there. Returns [(x, penalty)] sorted by x descending."""
        cy0, cy1 = line["core"]
        gw = g["x1"] - g["x0"]
        if gw < 14:
            return []
        col = self.ink[cy0:cy1, g["x0"]:g["x1"]].sum(axis=0).astype(float)
        sm = np.convolve(col, np.ones(3) / 3, mode="same")
        nz = sm[sm > 0]
        med = float(np.median(nz)) if len(nz) else 1.0
        cands = []
        for i in range(6, gw - 6):
            if sm[i] <= sm[i - 1] and sm[i] <= sm[i + 1] and sm[i] <= 0.8 * med:
                cands.append((sm[i], i))
        cands.sort()
        chosen = []
        for v, i in cands:
            if all(abs(i - j) >= 8 for _, j in chosen):
                chosen.append((v, i))
            if len(chosen) >= 8:
                break
        out = [(g["x0"] + i, 0.15 + 0.8 * (v / max(med, 1e-6))) for v, i in chosen]
        return sorted(out, key=lambda t: -t[0])

    def segments_for_ayah(self, line_ids):
        """Sub-segments: every stroke group split at its candidate cuts. A cut is
        optional: the DP may span several consecutive sub-segments of one group."""
        segs = []
        gid = 0
        for li in line_ids:
            line = self.lines[li]
            for g in line["groups"]:
                cuts = self.weak_cuts(line, g)
                edges = [(g["x1"], 0.0)] + cuts + [(g["x0"], 0.0)]
                for k in range(len(edges) - 1):
                    segs.append(dict(x0=edges[k + 1][0], x1=edges[k][0], line=li, group=gid, comps=g["comps"],
                                     cut_pen=edges[k][1], group_start=(k == 0), group_end=(k == len(edges) - 2)))
                gid += 1
        return segs

    def split_ayah(self, ai, words):
        """Stroke-level alignment: every word is a known sequence of pen strokes
        (letters up to the next non-joining letter); runs of strokes are dealt
        to runs of sub-segments (within one ink group) in reading order, scored
        by width. A word boundary can only sit at a group edge or at a
        candidate cut (paid), and a word never crosses a line."""
        line_ids = [li for li, l in enumerate(self.lines) if l["ayah"] == ai]
        n = len(words)
        if not line_ids or n == 0:
            self.unplaced.append(ai)
            return
        segs = self.segments_for_ayah(line_ids)
        if not segs:
            self.unplaced.append(ai)
            return
        strokes = []   # (word index, first-of-word, predicted px width, letters)
        for k, w in enumerate(words):
            parts = strokes_of_word(w) or [""]
            for si, letters in enumerate(parts):
                strokes.append((k, si == 0, stroke_width(letters, len(parts)), letters))
        line_scale = {li: 1.0 for li in line_ids}
        runs = None
        for _round in range(2):
            runs = self._stroke_dp(segs, strokes, line_scale)
            if runs is None:
                self.unplaced.append(ai)
                return
            tot_meas, tot_pred = {}, {}
            for (m0, m1, k0, k1) in runs:
                if k1 <= k0:
                    continue
                li = segs[m0]["line"]
                tot_meas[li] = tot_meas.get(li, 0.0) + (segs[m0]["x1"] - segs[m1 - 1]["x0"])
                tot_pred[li] = tot_pred.get(li, 0.0) + sum(strokes[k][2] for k in range(k0, k1))
            for li in line_ids:
                if tot_pred.get(li, 0) > 0:
                    line_scale[li] = min(1.5, max(0.75, tot_meas[li] / tot_pred[li]))
        # training samples for the width fit: every run (the strokes of one word
        # inside one group range) with its measured width, line stretch undone
        for (m0, m1, k0, k1) in runs:
            if k1 > k0:
                keys = [key for k in range(k0, k1) for key in stroke_keys(strokes[k][3])]
                self.samples.append((keys, (segs[m0]["x1"] - segs[m1 - 1]["x0"]) / line_scale[segs[m0]["line"]]))
        # words -> spans (union of their runs), groups -> words using them
        word_runs = {}
        group_words = {}
        for (m0, m1, k0, k1) in runs:
            if k1 <= k0:
                continue
            k = strokes[k0][0]
            word_runs.setdefault(k, []).append((m0, m1))
            group_words.setdefault(segs[m0]["group"], set()).add(k)
        wid_of = {}
        for k, wtext in enumerate(words):
            rs = word_runs.get(k)
            if not rs:
                self.unplaced.append(ai)
                return
            wid = len(self.words)
            wid_of[k] = wid
            li = segs[rs[0][0]]["line"]
            span = (min(segs[m1 - 1]["x0"] for m0, m1 in rs), max(segs[m0]["x1"] for m0, m1 in rs))
            w = dict(id=wid, ayah=ai, k=k, text=wtext, line=li, comps=[], clips=[], span=span)
            self.words.append(w)
            self.lines[li]["words"].append(wid)
            pred = sum(st[2] for st in strokes if st[0] == k) * line_scale[li]
            self.residuals.append(abs((span[1] - span[0]) - pred) / max(pred, 8.0))
        # component ownership per group
        seen_groups = set()
        for sg in segs:
            g = sg["group"]
            if g in seen_groups:
                continue
            seen_groups.add(g)
            ks = group_words.get(g, set())
            if len(ks) == 1:
                wid = wid_of[next(iter(ks))]
                for c in sg["comps"]:
                    if self.owner[c] == -1:
                        self.words[wid]["comps"].append(c)
                        self.owner[c] = wid
            elif len(ks) > 1:
                # the group is cut between words: each word gets the part of every
                # component's box inside the word's span (clipped rects)
                for k in ks:
                    w = self.words[wid_of[k]]
                    s0, s1 = w["span"]
                    for c in sg["comps"]:
                        bx, by, bw, bh, _a = self.stats[c]
                        x0c, x1c = max(int(bx), s0), min(int(bx + bw), s1)
                        if x1c - x0c >= 2:
                            w["clips"].append([x0c, int(by), x1c, int(by + bh)])
                            self.owner[c] = -3
            else:
                # stray ink the DP skipped: nearest word on the line
                for c in sg["comps"]:
                    if self.owner[c] == -1:
                        wid = self.word_at(self.lines[sg["line"]], self.cents[c][0], any_distance=True)
                        if wid is not None:
                            self.words[wid]["comps"].append(c)
                            self.owner[c] = wid
        for li in line_ids:
            wids = self.lines[li]["words"]
            for a, b in zip(wids, wids[1:]):
                wa, wb = self.words[a], self.words[b]
                mid = (wa["span"][0] + wb["span"][1]) / 2
                wa["span"] = (int(mid), wa["span"][1])
                wb["span"] = (wb["span"][0], int(mid))

    def _stroke_dp(self, segs, strokes, line_scale):
        """dp[m][k]: the first m sub-segments hold the first k strokes. A run is
        sub-segments m0..m-1 of one group holding strokes k0..k-1 of one word
        (a word boundary only at the run start). Returns runs [(m0, m1, k0, k1)]
        or None when infeasible."""
        M, K = len(segs), len(strokes)
        INF = 1e18
        dp = [[INF] * (K + 1) for _ in range(M + 1)]
        bk = [[None] * (K + 1) for _ in range(M + 1)]
        dp[0][0] = 0.0
        MAX_STROKES = 8
        for m in range(1, M + 1):
            last = segs[m - 1]
            li = last["line"]
            sc = line_scale[li]
            # candidate run starts m0: back within the same group, or across a
            # small gap into the previous group (a stroke whose ink is broken
            # at a thin join), at a cost per bridged gap
            m0 = m - 1
            bridge_pen = 0.0
            bridges = 0
            while True:
                first_seg = segs[m0]
                width = first_seg["x1"] - last["x0"]
                prev_line = segs[m0 - 1]["line"] if m0 >= 1 else None
                boundary_pen = first_seg["cut_pen"] + bridge_pen   # 0 at a group edge
                whole_group = first_seg["group_start"] and last["group_end"] and bridge_pen == 0
                for k in range(0, K + 1):
                    if dp[m0][k] < INF and whole_group and width <= 10:   # stray ink, no stroke
                        c = dp[m0][k] + 3.0
                        if c < dp[m][k]:
                            dp[m][k] = c
                            bk[m][k] = (m0, k)
                    pred = 0.0
                    for k0 in range(k - 1, max(-1, k - MAX_STROKES - 1), -1):
                        pred += strokes[k0][2] * sc
                        if k0 < k - 1 and strokes[k0 + 1][1]:
                            break                                   # a word boundary needs a run edge
                        if dp[m0][k0] >= INF:
                            continue
                        first = strokes[k0][1]
                        if not first and (prev_line is None or prev_line != li):
                            continue                                # a word never crosses a line
                        if not first and first_seg["group_start"] and m0 >= 1 and segs[m0 - 1]["group"] != first_seg["group"]:
                            pass                                    # detached stroke of the same word: fine
                        cost = dp[m0][k0] + ((width - pred) / max(pred, 6.0)) ** 2 + bridge_pen
                        if first and not first_seg["group_start"]:
                            cost += first_seg["cut_pen"]            # word boundary at a cut
                        if cost < dp[m][k]:
                            dp[m][k] = cost
                            bk[m][k] = (m0, k0)
                if m0 == 0:
                    break
                if first_seg["group_start"]:
                    prev = segs[m0 - 1]
                    gap = prev["x0"] - first_seg["x1"]
                    if prev["line"] != first_seg["line"] or gap > BRIDGE_GAP or bridges >= 2:
                        break
                    bridge_pen += BRIDGE_PEN + 0.04 * max(0, gap)
                    bridges += 1
                m0 -= 1
        if dp[M][K] >= INF:
            return None
        runs = []
        m, k = M, K
        while m > 0:
            m0, k0 = bk[m][k]
            runs.append((m0, m, k0, k))
            m, k = m0, k0
        return runs[::-1]

    # -- 4. marks -> lines -> words ------------------------------------------
    def local_ink_edge(self, line, x0, x1, want="bottom"):
        comps = [c for g in line["groups"] for c in g["comps"]]
        if not comps:
            return None
        cy0, cy1 = line["core"]
        y_from, y_to = max(0, cy0 - int(self.pitch)), min(self.H, cy1 + int(self.pitch))
        sub = self.labels[y_from:y_to, max(0, x0):min(self.W, x1)]
        if sub.size == 0:
            return None
        hit = np.isin(sub, comps).any(axis=1)
        ys = np.where(hit)[0]
        if len(ys) == 0:
            return None
        return y_from + (ys.max() if want == "bottom" else ys.min())

    def assign_marks(self):
        order = sorted(range(len(self.lines)), key=lambda i: self.lines[i]["core"][0])
        for c in range(1, self.ncomp):
            if self.owner[c] != -1:
                continue
            bx, by, bw, bh, a = self.stats[c]
            # marks are small: letters of a basmala or header near an ayah line
            # must not be taken for marks of that line
            if bh > 0.32 * self.pitch or bw > 0.45 * self.pitch:
                continue
            cx = self.cents[c][0]
            top, bot = by, by + bh
            above = below = None
            for li in order:
                line = self.lines[li]
                if not line["words"]:
                    continue
                x0, x1, y0, y1 = line["px"]
                if not (x0 - 4 <= cx < x1 + 4):
                    continue
                cy0, cy1 = line["core"]
                if top < cy1 and bot > cy0:
                    above = below = line
                    break
                if cy1 <= top and (top - cy1) < 0.45 * self.pitch:
                    if above is None or line["core"][1] > above["core"][1]:
                        above = line
                if cy0 >= bot and (cy0 - bot) < 0.6 * self.pitch:
                    if below is None or line["core"][0] < below["core"][0]:
                        below = line
            if above is None and below is None:
                continue
            if above is not None and below is not None and above is not below:
                w_above = self.word_at(above, cx)
                exp_below = below_marks_expected(self.words[w_above]["text"]) if w_above is not None else 0
                edge_up = self.local_ink_edge(above, bx - 3, bx + bw + 3, "bottom")
                edge_dn = self.local_ink_edge(below, bx - 3, bx + bw + 3, "top")
                d_up = (top - edge_up) if edge_up is not None else (top - above["core"][1])
                d_dn = (edge_dn - bot) if edge_dn is not None else (below["core"][0] - bot)
                # only kasra- or dot-sized ink can hang under a word; anything
                # bigger between two lines (pause marks, small alef stacks) is
                # an above-mark of the line below
                if exp_below == 0 or bh > 7 or bw > 14:
                    chosen = below
                elif d_up <= max(4, 0.16 * self.pitch) and d_up <= d_dn * 1.5:
                    chosen = above
                elif d_dn <= d_up:
                    chosen = below
                else:
                    chosen = above if d_up <= max(6, 0.25 * self.pitch) else below
            else:
                chosen = above if above is not None else below
            wid = self.word_at(chosen, cx)
            if wid is None:
                continue
            # A pause mark (ۖ ۗ ۚ ۛ ۜ ۘ ۙ) is printed above the gap AFTER its
            # word, i.e. over the start of the next word: a small component
            # above the core band near the boundary goes to the previous word
            # when that word's text carries a pause mark and this one's does not.
            if bot <= chosen["core"][0] + 2:
                wids = chosen["words"]
                i = wids.index(wid)
                if i > 0 and PAUSE.search(self.words[wids[i - 1]]["text"]) and not PAUSE.search(self.words[wid]["text"]):
                    s_this = self.words[wid]["span"]
                    if bx + bw >= s_this[1] - 0.35 * self.pitch:
                        wid = wids[i - 1]
            self.words[wid]["comps"].append(c)
            self.owner[c] = wid

    def sweep_leftovers(self):
        """Ink that is neither a stroke nor a mark-sized component (a detached
        bowl of a final nun, a tall mark stack) but lies within a line's reach
        goes to the nearest word of that line, so nothing shows through."""
        for c in range(1, self.ncomp):
            if self.owner[c] != -1:
                continue
            bx, by, bw, bh, a = self.stats[c]
            if a < 4 or bw > 0.6 * self.pitch or bh > 0.9 * self.pitch:
                continue
            cx, cy = self.cents[c]
            best, bd = None, 1e9
            for line in self.lines:
                if not line["words"]:
                    continue
                cy0, cy1 = line["core"]
                if cy < cy0 - 0.5 * self.pitch or cy > cy1 + 0.5 * self.pitch:
                    continue
                x0, x1 = line["px"][0], line["px"][1]
                dx = 0 if x0 - 30 <= cx < x1 + 30 else 1e9
                dy = 0 if cy0 <= cy <= cy1 else min(abs(cy - cy0), abs(cy - cy1))
                if dx + dy < bd:
                    best, bd = line, dx + dy
            if best is None:
                continue
            wid = self.word_at(best, cx, any_distance=True)
            if wid is not None:
                self.words[wid]["comps"].append(c)
                self.owner[c] = wid

    def word_at(self, line, cx, any_distance=False):
        best, bd = None, 1e9
        for wid in line["words"]:
            s = self.words[wid]["span"]
            if s is None:
                continue
            if s[0] <= cx < s[1]:
                return wid
            d = min(abs(cx - s[0]), abs(cx - s[1]))
            if d < bd:
                best, bd = wid, d
        return best if (any_distance or bd < 0.4 * self.pitch) else None

    # -- 5. rects per word ---------------------------------------------------
    def word_rects(self, w):
        comps = w["comps"]
        rects = [[int(self.stats[c][0]), int(self.stats[c][1]), int(self.stats[c][0] + self.stats[c][2]), int(self.stats[c][1] + self.stats[c][3])] for c in comps]
        clips = [list(r) for r in w.get("clips", [])]
        if not rects and not clips:
            # no ink component landed on this word (should be rare): cover its
            # column span over the line's core band so nothing leaks
            span = w.get("span")
            if span is None or span[1] - span[0] < 2:
                return []
            cy0, cy1 = self.lines[w["line"]]["core"]
            h = cy1 - cy0
            return [[int(span[0]), max(0, int(cy0 - 0.6 * h)), int(span[1] - span[0]), int(2.2 * h)]]
        own_arr = np.zeros(self.ncomp, bool)
        own_arr[comps] = True
        own_arr[0] = True

        def clean(r):
            sub = self.labels[r[1]:r[3], r[0]:r[2]]
            return own_arr[np.unique(sub)].all()

        merged = True
        while merged and len(rects) > 1:
            merged = False
            rects.sort()
            for i in range(len(rects)):
                for j in range(i + 1, len(rects)):
                    a, b = rects[i], rects[j]
                    u = [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]
                    if clean(u):
                        rects[i] = u
                        del rects[j]
                        merged = True
                        break
                if merged:
                    break
        out = []
        for r in rects + clips:
            x0, y0 = max(0, r[0] - PAD), max(0, r[1] - PAD)
            x1, y1 = min(self.W, r[2] + PAD), min(self.H, r[3] + PAD)
            out.append([x0, y0, x1 - x0, y1 - y0])
        return out

    # -- driver ----------------------------------------------------------------
    def run(self):
        self.build_lines()
        tmap = {(a["surah"], a["ayah"]): [w for w in a["text"].split() if w] for a in self.text["ayahs"]}
        for ai, ra in enumerate(self.regions["ayahs"]):
            self.split_ayah(ai, tmap.get((ra["surah"], ra["ayah"]), []))
        self.assign_marks()
        self.sweep_leftovers()
        ayahs_out = []
        by_ayah = {}
        for w in self.words:
            by_ayah.setdefault(w["ayah"], []).append(w)
        for ai, ra in enumerate(self.regions["ayahs"]):
            ws = sorted(by_ayah.get(ai, []), key=lambda w: w["k"])
            n_words = len(tmap.get((ra["surah"], ra["ayah"]), []))
            if ws and len(ws) == n_words and ai not in self.unplaced:
                ayahs_out.append({"surah": ra["surah"], "ayah": ra["ayah"], "words": [self.word_rects(w) for w in ws]})
            else:
                ayahs_out.append({"surah": ra["surah"], "ayah": ra["ayah"], "words": []})
        hw = None
        if self.hw:
            hw = [round(self.hw["x"] / self.hw["W"], 5), round(self.hw["y"] / self.hw["H"], 5), round(self.hw["w"] / self.hw["W"], 5), round(self.hw["h"] / self.hw["H"], 5)]
        return {"page": self.page, "hw": hw, "ayahs": ayahs_out}

    def report(self):
        area = self.stats[:, 4].astype(float)
        area[0] = 0
        total = area[~self.excluded].sum()
        assigned = area[(self.owner >= 0) | (self.owner == -3)].sum()
        leaks = [(int(c), int(area[c])) for c in range(1, self.ncomp) if self.owner[c] == -1 and area[c] >= 6]
        res = np.array(self.residuals) if self.residuals else np.zeros(1)
        return dict(page=self.page, ink_covered=round(assigned / max(1, total), 4), leak_comps=len(leaks), leak_area=int(sum(a for _, a in leaks)),
                    lines=len(self.lines), unplaced_ayahs=len(self.unplaced), words=len(self.words),
                    resid_med=round(float(np.median(res)), 3), resid_bad=int((res > 0.5).sum()))

    def preview(self, out_path, debug_boxes=True):
        img = self.img.copy()
        palette = [(255, 128, 0), (0, 160, 255), (0, 200, 0), (200, 0, 200), (0, 0, 220), (180, 120, 0)]
        over = img.copy()
        for w in self.words:
            col = palette[w["id"] % len(palette)]
            for x, y, ww, hh in self.word_rects(w):
                cv2.rectangle(over, (x, y), (x + ww, y + hh), col, -1)
        img = cv2.addWeighted(over, 0.35, img, 0.65, 0)
        for w in self.words:
            if w["span"] is None:
                continue
            cy0, cy1 = self.lines[w["line"]]["core"]
            for x in w["span"]:
                cv2.line(img, (int(x), cy0 - 3), (int(x), cy1 + 3), (0, 0, 0), 1)
        if debug_boxes:
            for c in range(1, self.ncomp):
                if self.owner[c] == -1 and self.stats[c][4] >= 6:
                    x, y, ww, hh, a = self.stats[c]
                    cv2.rectangle(img, (x - 1, y - 1), (x + ww + 1, y + hh + 1), (0, 0, 255), 1)
        cv2.imwrite(out_path, img)
        hidden = self.img.copy()
        for w in self.words:
            for x, y, ww, hh in self.word_rects(w):
                cv2.rectangle(hidden, (x, y), (x + ww, y + hh), (0xD8, 0xFC, 0xFC), -1)
        cv2.imwrite(out_path.replace(".png", "_hidden.png"), hidden)


RUN_CONST = 4.0      # px a stroke run adds beyond its letters (pen lead-in/out); fixed, not fitted
RIDGE = 4.0          # shrinkage of every positional form toward its prior, in sample-equivalents


def fit_widths(samples):
    """Huber ridge fit of per-letter positional px widths from the DP's runs
    (strokes of one word in one ink group range, with the measured width). Each
    form is shrunk toward its prior (the hand table in px) so rare forms stay
    sane, and the per-run constant is fixed so the fit cannot degenerate."""
    prior_tab = {c: u * 18.3 for c, u in G.W.items()}
    alphabet = {}
    rows, ys = [], []
    for keys, meas in samples:
        if not keys or meas <= 0:
            continue
        for c in keys:
            alphabet.setdefault(c, len(alphabet))
        rows.append(keys)
        ys.append(meas - RUN_CONST)
    n, k = len(rows), len(alphabet)
    A = np.zeros((n + k, k))
    for i, ls in enumerate(rows):
        for c in ls:
            A[i, alphabet[c]] += 1
    y = np.zeros(n + k)
    y[:n] = ys
    sq = np.sqrt(RIDGE)
    for c, i in alphabet.items():
        A[n + i, i] = sq
        y[n + i] = sq * prior_tab.get(c[0], 14.6)
    w = np.ones(n + k)
    sol = None
    for _ in range(15):
        sol, *_ = np.linalg.lstsq(A * w[:, None], y * w, rcond=None)
        r = (y - A @ sol)[:n]
        sd = 1.4826 * np.median(np.abs(r)) + 1e-6
        w[:n] = np.minimum(1.0, 2.0 * sd / np.maximum(np.abs(r), 1e-6))
    r = (y - A @ sol)[:n]
    inv = {v: kk for kk, v in alphabet.items()}
    letters = {inv[i]: round(float(max(1.0, sol[i])), 2) for i in range(k)}
    sol = np.append(sol, RUN_CONST)
    # forms seen fewer than 5 times are unreliable: fall back to the letter's mean over forms
    counts = {c: int(A[:, i].sum()) for c, i in alphabet.items()}
    by_letter = {}
    for key, v in letters.items():
        by_letter.setdefault(key[0], []).append((v, counts[key]))
    for key in list(letters):
        if counts[key] < 5:
            vals = [(v, c) for v, c in by_letter[key[0]] if c >= 5]
            if vals:
                letters[key] = round(sum(v * c for v, c in vals) / sum(c for _, c in vals), 2)
    table = {"positional": True, "letters": letters, "const": round(float(sol[k]), 2), "default": round(float(np.median(list(letters.values()))), 2),
             "n": n, "resid_med": round(float(np.median(np.abs(r))), 2)}
    path = os.path.join(ROOT, "tools", "stroke_widths.json")
    json.dump(table, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"fitted {k} letter forms from {n} runs, const {table['const']}, |resid| median {table['resid_med']} px -> {path}")
    shown = sorted(letters.items(), key=lambda kv: -kv[1])
    print("   " + "  ".join(f"{c}:{v:.1f}({counts[c]})" for c, v in shown[:60]))


def load_pages_text():
    """output.json: 602 page dicts, the last list element being a nested list
    holding pages 551-602 (flattened here)."""
    raw = json.load(open(os.path.join(ROOT, "assets/data/output.json"), encoding="utf-8"))
    out = []
    for x in raw:
        if isinstance(x, list):
            out.extend(y for y in x if isinstance(y, dict) and "page" in y)
        elif isinstance(x, dict) and "page" in x:
            out.append(x)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pages", default=None)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--out", default=os.path.join(ROOT, "assets/data/word_masks.json"))
    ap.add_argument("--no-write", action="store_true")
    ap.add_argument("--site-previews", default=None, help="write tinted previews as webp for the review site into this dir")
    ap.add_argument("--fit-widths", action="store_true", help="fit tools/stroke_widths.json from one-group words of the given pages (no masks written)")
    args = ap.parse_args()
    regions = {p["page"]: p for p in json.load(open(os.path.join(ROOT, "assets/data/ayah_regions.json"), encoding="utf-8"))}
    text = {p["page"]: p for p in load_pages_text()}
    hw = {int(k): v for k, v in json.load(open(HW_TRANSFORM)).items()} if os.path.exists(HW_TRANSFORM) else {}
    pages = [int(x) for x in args.pages.split(",")] if args.pages else sorted(regions)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    out, reports, samples = [], [], []
    for page in pages:
        if page not in regions or page not in text:
            print("page", page, "missing regions/text", file=sys.stderr)
            continue
        P = Page(page, regions[page], text[page], hw.get(page))
        out.append(P.run())
        r = P.report()
        reports.append(r)
        samples.extend(P.samples)
        if args.site_previews:
            os.makedirs(args.site_previews, exist_ok=True)
            P.preview(os.path.join(args.site_previews, f"page_{page}.png"), debug_boxes=False)
            im = cv2.imread(os.path.join(args.site_previews, f"page_{page}.png"))
            cv2.imwrite(os.path.join(args.site_previews, f"page_{page}.webp"), im, [cv2.IMWRITE_WEBP_QUALITY, 82])
            os.remove(os.path.join(args.site_previews, f"page_{page}.png"))
            os.remove(os.path.join(args.site_previews, f"page_{page}_hidden.png"))
        if args.preview:
            P.preview(os.path.join(PREVIEW_DIR, f"preview_{page}.png"))
            worst = sorted(zip(P.residuals, P.words), key=lambda t: -t[0])[:12]
            for res, w in worst:
                if res > 0.4:
                    print(f"   p{page} residual {res:.2f} word {w['k']} ayah {w['ayah']} line {w['line']} width {w['span'][1]-w['span'][0]}: {w['text']}")
        if r["ink_covered"] < 0.97 or r["unplaced_ayahs"] or r["leak_comps"] > 3 or r["resid_bad"] > 3:
            print(r, flush=True)
    if not args.no_write and not args.pages:
        json.dump(out, open(args.out, "w", encoding="utf-8"), separators=(",", ":"))
        print("wrote", args.out, os.path.getsize(args.out) // 1024, "KB")
    elif not args.no_write and args.pages:
        p = args.out.replace(".json", "_partial.json")
        json.dump(out, open(p, "w", encoding="utf-8"), separators=(",", ":"))
        print("wrote", p)
    if args.fit_widths:
        fit_widths(samples)
        return
    cov = np.array([r["ink_covered"] for r in reports])
    print(f"pages {len(reports)}: ink covered mean {cov.mean():.4f} min {cov.min():.4f}; unplaced ayahs {sum(r['unplaced_ayahs'] for r in reports)}; "
          f"leak comps {sum(r['leak_comps'] for r in reports)}; words {sum(r['words'] for r in reports)}; "
          f"width residual median {np.median([r['resid_med'] for r in reports]):.3f}, words >50% off {sum(r['resid_bad'] for r in reports)}")


if __name__ == "__main__":
    main()

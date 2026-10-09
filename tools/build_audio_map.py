"""Build assets/data/audio_ayah_map.json: output.json ayah (O) -> recitation
audio file (A), so each displayed ayah plays its own audio. Both shipped reciters
(al-Husary, al-Naihi) use the same audio ayah division.

Two-step compose, keeping the exact half exact:
  1. O -> Q  : exact word alignment of output.json to the Qalun text (quran-meta
               QalounData, same orthography). Captures output.json's own quirks.
  2. Q -> A  : the audio uses a Qalun عدّ very close to QalounData but differing at
               a few compensating fawasil (e.g. it keeps Ayat al-Kursi whole while
               QalounData splits it). Located per-surah by aligning QalounData
               letter-counts to the audio file DURATIONS (differences are large,
               isolated, and stand out).
  O -> A = compose(O->Q, Q->A).

Output JSON: { "<surah>": { "<O_ayah>": [<A_file>, ...] } } (non-identity only).

WARNING (2026-10-08): this script no longer reproduces the shipped map. Run
today it emits 27 surahs; the shipped file has 16, pruned by hand after it was
generated on 2026-07-14. Do not regenerate over it. Edit the JSON directly, and
verify any change against the audio first: file durations across mirrors,
and forced alignment of the file against the displayed text.

Later on 2026-10-08 every surah the shipped map remapped was checked against
قنيوه's files (the only reader of the map now) and found to follow output.json
one for one, so the shipped map is down to the single entry in
PLACEHOLDER_OVERRIDES. The text alignment below is kept for reference only.
"""
import json, re, unicodedata
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "assets" / "data"
TOOLS = Path(__file__).resolve().parent
PEN = 0.003
GATE = 0.05


def normalize(text):
    text = unicodedata.normalize("NFC", text)
    t = "".join(c for c in text if unicodedata.category(c) != "Mn")
    t = t.replace("ـ", "")
    t = re.sub("[آأإٱٰ]", "ا", t)
    t = t.replace("ى", "ي").replace("ة", "ه")
    t = re.sub("[ؤئء]", "", t)
    t = re.sub(r"[^ء-ي\s]", "", t)
    return re.sub(r"\s+", " ", t).strip()


def words_of(t):
    return [w for w in normalize(t).split(" ") if w]


def letters(t):
    return len(re.findall(r"[ء-ي]", normalize(t)))


def load_output():
    raw = json.loads((DATA / "output.json").read_text(encoding="utf-8"))
    pages = []
    for p in raw:
        pages.extend(p if isinstance(p, list) else [p])
    s = {}
    for p in pages:
        for a in p["ayahs"]:
            s.setdefault(int(a["surah"]), {})[int(a["ayah"])] = a["text"]
    return s


def load_qalun():
    d = json.loads((TOOLS / "_qaloun_data.json").read_text(encoding="utf-8"))
    s = {}
    for a in d:
        s.setdefault(int(a["sura_no"]), {})[int(a["aya_no"])] = a["aya_text"]
    return s


def text_align(od, nd):
    """O ayah -> list of N ayahs covering the same words (exact)."""
    no, nn = max(od), max(nd)
    ow, ob = [], {}
    for k in range(1, no + 1):
        st = len(ow); ow.extend(words_of(od.get(k, ""))); ob[k] = (st, len(ow))
    nw, nown = [], []
    for k in range(1, nn + 1):
        ws = words_of(nd.get(k, "")); nw.extend(ws); nown.extend([k] * len(ws))
    blocks = SequenceMatcher(a=ow, b=nw, autojunk=False).get_matching_blocks()

    def owner(pos):
        for a, b, sz in blocks:
            if sz and a <= pos < a + sz:
                return nown[b + (pos - a)]
        for a, b, sz in blocks:
            if sz and a >= pos:
                return nown[b]
        return nown[-1] if nown else None
    out = {}
    for k in range(1, no + 1):
        st, en = ob[k]
        if en <= st:
            out[k] = [k]; continue
        f, l = owner(st), owner(en - 1)
        if f is None or l is None:
            out[k] = [k]; continue
        out[k] = list(range(min(f, l), max(f, l) + 1))
    return out


def dur_align(nd, dur):
    """Q ayah (letters) -> list of audio file(s) (durations). Q and audio are
    nearly identical; only a few isolated fawasil differ."""
    nn = max(nd)
    nkeys = sorted(int(a) for a in dur if a != "0" and dur[a] is not None)
    if not nkeys:
        return {k: [k] for k in range(1, nn + 1)}
    m = max(nkeys)
    Lv = [letters(nd.get(k, "")) for k in range(1, nn + 1)]
    Dv = [dur.get(str(a)) or 0.0 for a in range(1, m + 1)]
    tL, tD = sum(Lv) or 1, sum(Dv) or 1
    A = [x / tL for x in Lv]
    B = [x / tD for x in Dv]
    n = len(A)
    INF = float("inf")
    dp = [[INF] * (m + 1) for _ in range(n + 1)]
    bk = [[None] * (m + 1) for _ in range(n + 1)]
    dp[0][0] = 0.0
    MAXK = 4
    for i in range(n + 1):
        for j in range(m + 1):
            if dp[i][j] == INF:
                continue
            if i < n and j < m:
                c = dp[i][j] + abs(A[i] - B[j])
                if c < dp[i + 1][j + 1]:
                    dp[i + 1][j + 1] = c; bk[i + 1][j + 1] = (i, j, ("m", 1))
            for k in range(2, MAXK + 1):
                if i + k <= n and j < m:
                    c = dp[i][j] + abs(sum(A[i:i + k]) - B[j]) + PEN * (k - 1)
                    if c < dp[i + k][j + 1]:
                        dp[i + k][j + 1] = c; bk[i + k][j + 1] = (i, j, ("m", k))
                if i < n and j + k <= m:
                    c = dp[i][j] + abs(A[i] - sum(B[j:j + k])) + PEN * (k - 1)
                    if c < dp[i + 1][j + k]:
                        dp[i + 1][j + k] = c; bk[i + 1][j + k] = (i, j, ("s", k))
    # Gate: when Qalun and audio have the SAME count, a non-identity alignment is
    # only trusted if it fits the durations SUBSTANTIALLY better than plain 1:1
    # (a real compensating fawasil like Ayat al-Kursi), not marginally (proxy noise).
    if n == m:
        ident_cost = sum(abs(A[k] - B[k]) for k in range(n))
        if ident_cost - dp[n][m] < GATE:
            return {k: [k] for k in range(1, n + 1)}
    out = {}
    i, j = n, m
    while not (i == 0 and j == 0):
        if bk[i][j] is None:  # safety: should not happen
            break
        pi, pj, (kind, k) = bk[i][j]
        if kind == "m":
            for t in range(k):
                out[pi + t + 1] = [pj + 1]
        else:
            out[pi + 1] = [pj + 1 + t for t in range(k)]
        i, j = pi, pj
    return out


# Hand-verified Qalun(QalounData) -> audio overrides for the few same-count
# surahs where the recitation uses a NON-STANDARD division that no dataset
# documents and that letter/duration alignment can't recover reliably.
# Confirmed from the audio durations (al-Husary AND al-Naihi agree):
#   S2: the audio keeps Ayat al-Kursi as ONE file (253) while QalunData splits it
#   (253+254), and instead splits 2:256 (الله ولي) into two files (255+256).
Q2A_OVERRIDES = {
    2: {253: [253], 254: [253], 255: [254], 256: [255, 256]},
}

# Surahs where the recitation files follow output.json's own division even
# though QalounData divides them differently, so O -> A is plain identity.
#   S14: QalounData divides 14:22-27 differently from output.json, but every
#   mirror's file 023 is the 5-word «وما ذلك على الله بعزيز» (قنيوه 5.9 s,
#   al-Naihi 4.7 s, al-Husary 8.5 s) and 024-027 match the displayed ayat in
#   length and in forced alignment. The text remap played 14:23-27 one ayah
#   behind for قنيوه (removed 2026-10-08).
#   The rest were checked the same day by greedy CTC decode of each قنيوه file
#   around every remapped ayah (file N decodes as displayed ayah N, or as the
#   breath group starting at N). What the remaps did instead:
#   S2   196-199 one behind (2:218 and 2:255-256 merges were no-ops / blurred).
#   S3   91-97 one behind.             S11  122 (last ayah) never played.
#   S18  33-35 one behind; 22-24 and 83-84 merged into one highlight.
#   S20  87-88 one behind.
#   S30  55-60 one behind, 60 (last ayah) never played.
#   S39  16-19 one behind.             S40  53-58 one behind; 71-72 no-op.
#   S44  41-43 no-op.                  S56  20-29, 53 one behind.
#   S65  2-10 one behind.              S71  24-25 one behind.
#   S73  2-20 one behind, 19-20 (the last two) never played.
#   S80  24-42 one behind.             S91  15-16, 16 (last) never played.
#   S103 2-3 no-op.
AUDIO_FOLLOWS_OUTPUT = {2, 3, 11, 14, 18, 20, 30, 39, 40, 44, 56, 65, 71, 73,
                        80, 91, 103}

# Entries that come from the audio, not from any text division. قنيوه's
# 020024.mp3 is a silent 1.6 kB placeholder upstream (nquran); he recites 20:24
# at the start of 020025.mp3, the 24-29 breath (25-29 are byte-identical
# continuations). Mapping 24 -> 25 plays that breath on 24 and highlights 24-29.
PLACEHOLDER_OVERRIDES = {20: {24: [25]}}


def main():
    O, Q = load_output(), load_qalun()
    result = {}
    for s in range(1, 115):
        od, nd = O.get(s), Q.get(s)
        if not nd or s in AUDIO_FOLLOWS_OUTPUT:
            continue
        o2q = text_align(od, nd) if od else None
        q2a = Q2A_OVERRIDES.get(s, {})  # exact text for O->Q; only the verified Q->A overrides
        no = max(od) if od else max(nd)
        sm = {}
        for o in range(1, no + 1):
            qs = o2q[o] if o2q else [o]
            files = []
            for q in qs:
                for a in q2a.get(q, [q]):
                    if a not in files:
                        files.append(a)
            if not files:
                files = [o]
            if not (len(files) == 1 and files[0] == o):
                sm[str(o)] = files
        if sm:
            result[str(s)] = sm
    for s, entries in PLACEHOLDER_OVERRIDES.items():
        result.setdefault(str(s), {}).update(
            {str(a): files for a, files in entries.items()})

    out = {
        "_comment": "output.json ayah -> recitation audio file(s). Built by "
                    "tools/build_audio_map.py: exact text align output.json->Qalun "
                    "(quran-meta QalounData) composed with duration-located Qalun->audio "
                    "fawasil. All shipped reciters use this audio division. Non-identity only.",
        "map": result,
    }
    (DATA / "audio_ayah_map.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print("surahs remapped:", len(result))


if __name__ == "__main__":
    main()

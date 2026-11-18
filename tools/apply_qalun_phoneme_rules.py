"""Qalun pronunciation rules for the Tasmee sounds in assets/data/page_phonemes.json.

The sounds were generated from the Hafs phonetic lexicon and converted to Qalun; wherever
the conversion borrowed a Hafs word whole, Hafs rules came with it, and a Qalun reader was
stopped for reading correctly (owner, 2026-11-10: «قُلُ ادعوا» on p175, «يَصّالحا» on p99).
This script states the Qalun rules once, from the mushaf's OWN marks, and fixes every word
that breaks one. Run it after any regeneration of the asset; `--check` lists what still
breaks a rule (test/tasmee_qalun_rules_asset_test.dart enforces the same rules).

Rules (each applies only where the stored sound breaks it):
  final_vowel   A word whose last letter carries a vowel in the mushaf («قُلُ», «أَنُ»,
                «طَعَامِ», «اَ۬للَّهُ») ends with that vowel. Covers the two-sakins rule:
                Qalun moves the first sakin with a damma before a verb whose third letter
                has a lazim damma («قُلُ ادْعُوا», «أَنُ اعْبُدُوا») where Hafs uses a kasra.
  joining_vowel A tanween before hamzat al-wasl joins with the vowel the mushaf writes on that
                alif («بِرَحْمَةٍ اُ۟دْخُلُوا» -> «بِرَحْمَتِنُ دْخُلُوا»).
  silah         The ha of the pronoun is long only where the mushaf writes the small waw/ya
                («نُؤْتِهِ مِنْهَا», «فِيهِ مُهَاناً» are short in Qalun; Hafs lengthens them).
  tanween_tail  A tanween before ي/و merges into it (يي / وو), before an ikhfa letter it is
                hidden (ںںں); judged against the Qalun next word («سُجَّداً تُغْفَرْ», not the
                Hafs «نَّغْفِرْ»).
  no_tanween    A word the mushaf writes without tanween has none («مِن كُلِّ زَوْجَيْنِ»; Hafs «كُلٍّ»).
  maqsura       An alif maqsura before hamzat al-wasl is dropped; it is never a «ي» sound
                («وَعَلَي اَ۬للَّهِ» -> «وَعَلَللَااهِ»). At an ayah end it is a long «ا».
  FARSH         Words whose whole reading differs (table below), from the mushaf text and the
                two sheikh recordings.

The old sound of a changed word is kept as an accepted form when it is a Hafs reading the
model cannot reliably tell apart (vowel only), or becomes the word's Hafs check when the
difference is clear and the sheikhs were heard reading the Qalun form (FARSH mode "hafs").
Generator slips that nobody reads are dropped.

usage: python tools/apply_qalun_phoneme_rules.py [--write] [--check]
"""
import io
import json
import os
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET = os.path.join(REPO, "assets", "data", "page_phonemes.json")

F, D, K = "َ", "ُ", "ِ"
SHORT = (F, D, K)
NAME = {F: "fatha", D: "damma", K: "kasra"}
TANWEEN = set("ًࣰٌࣱٍࣲٖٗٞ")
SILAH_WAW, SILAH_YA = "ۥ", "ۦ"
MADDA = "ٓ"
LETTERS = set("ءآأؤإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىيٱے")
# pause signs and RLMs after the last letter (the small meem of iqlab, the silah waw / ya stay)
TRAILING = re.compile("[ۖ-ۜ۞۩؀-؅‏ ]+$")
IQLAB_MEEM = set("ۭۢ")
PAUSE = re.compile("[ۖ-ۜ]")  # waqf signs written after a word  # tanween written as one vowel + small meem (iqlab / sequential)
WASL_ALIF = re.compile("^ا([َُِ])[۪۟۬]")
IKHFA = "ں" * 3
IKHFA_LETTERS = set("تثجدذزسشصضطظفقك")

# (ayah key, word index, stored sound it was written against, Qalun sound, mode, extra accepted forms)
# mode: "hafs" = old sound becomes the Hafs check; "accept" = old sound stays accepted;
#       "drop" = old sound is a generator slip.
FARSH = [
    ("4:127", 12, "يُصلِحَاا", "يَصصَاالَحَاا", "hafs", []),          # أن يَصّالحا (Hafs يُصلحا); both sheikhs
    ("2:183", 18, "مِسكِۦۦنِںںں", "مَسَااكِۦۦنَ", "hafs", []),        # طعامِ مساكينَ (Hafs طعامُ مسكينٍ)
    ("2:206", 5, "سسِلمِ", "سسَلمِ", "accept", []),                     # في السَّلم (Hafs السِّلم)
    ("24:7", 1, "ءَننننَ", "ءَ", "accept", []),                          # أنْ لَّعنتُ (Hafs أنَّ لعنتَ)
    ("24:9", 1, "ءَننننَ", "ءَن", "hafs", []),                           # أنْ غَضِبَ (Hafs أنَّ غضبَ); sheikh heard ءَن
    ("53:49", 2, "عَاادَنِ", "عَاادَ", "accept", []),                     # عاداً لُّولى (naql + idgham)
    ("61:14", 4, "ءَںںںصَاارَن", "ءَںںںصَاارَ", "accept", []),          # أنصاراً لِّلّه (Hafs أنصارَ الله)
    ("61:14", 5, "للَااهِ", "للِللَااهِ", "accept", []),
    ("76:16", 0, "قَوَاارِۦۦرَن", "قَوَاارِۦۦرَ", "accept", []),        # قواريراً مِّن (tanween merges into م)
    ("76:16", 1, "مِںںں", "ممممِںںں", "accept", []),
    ("65:2", 44, "ءَمرِهِۦۦ", "ءَمرَهُۥۥ", "accept", []),               # بالغٌ أمرَه (Hafs بالغُ أمرِه)
    ("32:27", 5, "لَي", "ءِلَ", "drop", []),                              # الماءَ إِلَى (eased hamza kept as ء like elsewhere)
    ("58:10", 13, "وعَلَي", "وَعَلَ", "drop", []),                        # وعلى اللهِ
    ("10:66", 17, "ن", "ءِيي", "drop", ["ي", "يِيي"]),                    # شركاءَ إِن يَتَّبعون: eased hamza; sheikhs heard «ي»
    ("11:40", 10, "كُللِںںں", "كُللِ", "hafs", []),                       # مِن كُلِّ زوجين (Hafs كُلٍّ); sheikhs heard كُللِ
    ("23:27", 15, "كُللِںںں", "كُللِ", "hafs", []),
]


def last_letter(text):
    """(last letter, its marks) of a mushaf word, pause signs ignored."""
    t = TRAILING.sub("", text)
    i = len(t) - 1
    marks = []
    while i >= 0 and t[i] not in LETTERS:
        marks.append(t[i])
        i -= 1
    return (t[i] if i >= 0 else ""), marks


def first_letter(text):
    return next((c for c in text if c in LETTERS), "")


def tail_vowel(ph):
    """The stored sound's final short vowel, '' when it ends in a consonant, None after a long vowel."""
    if not ph:
        return ""
    if ph[-1] in SHORT:
        return ph[-1]
    if ph[-1] in "اۥۦ":
        return None
    return ""


def is_muqattaat(text, marks):
    """Opening letters (حمٓ، طسٓ، نٓ): spelled out, the madda sits on the last letter."""
    return MADDA in marks or text.count(MADDA) >= 2


def ensure(w):
    while len(w) < 8:
        w.append([] if len(w) in (6, 7) else ("" if len(w) == 4 else 0))
    if not isinstance(w[7], list):
        w[7] = []
    return w


def keep_old(w, old, new, mode):
    if mode == "hafs":
        ensure(w)
        w[4] = old
        w[7] = [f for f in w[7] if f not in (old, new)]
    elif mode == "accept":
        ensure(w)
        if old not in w[7] and old != new:
            w[7].append(old)
    if len(w) > 7:
        w[7] = [f for f in w[7] if f != new]


def rule_violations(flat):
    """[(index, rule, new sound, mode)] for every word that breaks a generic rule."""
    out = []
    for k, it in enumerate(flat):
        w, key, wi, n = it["w"], it["key"], it["wi"], it["n"]
        text, ph = w[0], w[1]
        nxt = flat[k + 1] if k + 1 < len(flat) and flat[k + 1]["key"] == key else None
        at_end = wi == n - 1
        letter, marks = last_letter(text)
        vowel = next((m for m in marks if m in SHORT), "")
        tanween = any(m in TANWEEN or m in IQLAB_MEEM for m in marks) or (
            letter in "اى" and any(c in TANWEEN for c in TRAILING.sub("", text)[-3:]))
        # maqsura: a «ي» sound after a fatha at the end, where the mushaf has an alif maqsura
        if ph.endswith(F + "ي") and letter in "يى" and not vowel and "ّ" not in marks:
            new = ph[:-1] + ("اا" if at_end else "")
            out.append((k, "maqsura", new, "drop"))
            continue
        if at_end or is_muqattaat(text, marks):
            continue
        tv = tail_vowel(ph)
        # no_tanween: the mushaf writes a plain vowel, the stored sound carries a tanween tail
        if vowel and not tanween and tv == "":
            for tail in (IKHFA, "۾۾۾"):
                if ph.endswith(vowel + tail):
                    out.append((k, "no_tanween", ph[:-len(tail)], "accept"))
                    break
            if out and out[-1][0] == k:
                continue
        # final_vowel: the vowel the mushaf writes on the last letter
        if vowel and not tanween and not (set(marks) & {SILAH_WAW, SILAH_YA}) and tv is not None and tv != vowel:
            new = ph[:-1] + vowel if tv else ph + vowel
            out.append((k, "final_vowel", new, "accept" if tv else "drop"))
            continue
        # joining_vowel: tanween before hamzat al-wasl. At a pause sign readers often stop
        # (the sheikhs did at «بِرَحْمَةٍۖ», «ثَلَٰثَةٌۖ»), so there the neutral «…ن» is kept and
        # only a Hafs connector is taken off.
        if tanween and nxt:
            m = WASL_ALIF.match(nxt["w"][0])
            if m and m.group(1) != F:
                want = m.group(1)
                wrong = "ن" + (K if want == D else D)
                if PAUSE.search(text):
                    if ph.endswith(wrong):
                        out.append((k, "joining_vowel", ph[:-1], "accept"))
                        continue
                elif ph.endswith("ن"):
                    out.append((k, "joining_vowel", ph + want, "accept"))
                    continue
                elif ph.endswith(wrong):
                    out.append((k, "joining_vowel", ph[:-1] + want, "accept"))
                    continue
        # silah: long ha only where the mushaf writes the small waw / ya
        if letter == "ه" and vowel in (D, K) and not (set(marks) & {SILAH_WAW, SILAH_YA}):
            if ph.endswith(("هُۥۥ", "هِۦۦ")):
                out.append((k, "silah", ph[:-2], "accept"))
                continue
        # tanween_tail: judged against the Qalun next word
        if tanween and nxt and ph and ph[-1] in SHORT:
            f = first_letter(nxt["w"][0])
            nph = nxt["w"][1]
            if f in "يو" and not nph.startswith(f + f):
                out.append((k, "tanween_tail", ph + f + f, "accept"))
            elif f in IKHFA_LETTERS:
                out.append((k, "tanween_tail", ph + IKHFA, "accept"))
    return out


def flatten(pages):
    flat = []
    for p in pages:
        for a in p["ayahs"]:
            for wi, w in enumerate(a["w"]):
                flat.append(dict(page=p["page"], key=a["key"], wi=wi, n=len(a["w"]), w=w))
    return flat


def main():
    write = "--write" in sys.argv
    check = "--check" in sys.argv
    raw = open(ASSET, "rb").read()
    pages = json.loads(raw.decode("utf-8"))
    flat = flatten(pages)
    by_key = {(it["key"], it["wi"]): it for it in flat}
    changed = 0
    if not check:
        for key, wi, old, new, mode, extra in FARSH:
            it = by_key[(key, wi)]
            w = it["w"]
            if w[1] == new:
                continue
            if w[1] != old:
                print(f"SKIP farsh {key}:{wi} {w[0]} stored {w[1]!r}, table expects {old!r}")
                continue
            w[1] = new
            keep_old(w, old, new, mode)
            for e in extra:
                ensure(w)
                if e not in w[7]:
                    w[7].append(e)
            changed += 1
            print(f"p{it['page']} {key}:{wi} {w[0]}  farsh  {old} -> {new}  ({mode})")
    # generic rules, after the table (the table may settle a word a rule would misread)
    farsh_keys = {(k, i) for k, i, *_ in FARSH}
    for k, rule, new, mode in rule_violations(flat):
        it = flat[k]
        if (it["key"], it["wi"]) in farsh_keys:
            continue
        w = it["w"]
        old = w[1]
        if check:
            print(f"p{it['page']} {it['key']}:{it['wi']} {w[0]}  breaks {rule}: {old} (should be {new})")
            changed += 1
            continue
        w[1] = new
        keep_old(w, old, new, mode)
        changed += 1
        print(f"p{it['page']} {it['key']}:{it['wi']} {w[0]}  {rule}  {old} -> {new}  ({mode})")
    print(("still breaking a rule: " if check else "changed: ") + str(changed))
    if write and changed and not check:
        out = json.dumps(pages, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        open(ASSET, "wb").write(out + (b"\n" if raw.endswith(b"\n") else b""))
        print("written", ASSET)
    return 1 if (check and changed) else 0


if __name__ == "__main__":
    sys.exit(main())

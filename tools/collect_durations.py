"""ffprobe every al-Naihi audio file (over HTTP) and save per-ayah durations.
Used to align the audio's ayah division (N) to output.json's numbering (O)."""
import json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

BASE = "https://raw.githubusercontent.com/abdumka/alnaihiaudio/main/"
# N (nquran/Madani) ayah counts per surah — same list baked into Reciter.naihiMadaniAyahCounts
NMAX = [7,285,200,175,122,167,206,76,130,109,122,111,44,54,99,128,110,105,98,134,
        111,76,119,62,77,227,95,88,69,60,33,30,73,54,45,82,181,86,72,84,53,50,89,
        56,36,34,39,29,18,45,60,47,61,55,77,99,28,22,24,13,14,11,11,18,12,12,30,52,
        52,44,30,28,20,56,39,31,50,40,45,41,28,19,36,25,22,16,19,26,32,20,16,21,11,
        8,8,20,5,8,8,11,10,8,3,9,5,5,6,3,6,3,5,4,5,6]

def dur(args):
    s, a = args
    url = "%s%03d%03d.mp3" % (BASE, s, a)
    try:
        o = subprocess.run(["ffprobe","-v","error","-show_entries","format=duration",
                            "-of","csv=p=0", url], capture_output=True, text=True, timeout=60)
        return (s, a, float(o.stdout.strip()))
    except Exception:
        return (s, a, None)

def main():
    jobs = []
    for s in range(1, 115):
        if s != 9:
            jobs.append((s, 0))  # basmala
        for a in range(1, NMAX[s-1] + 1):
            jobs.append((s, a))
    print("files to probe:", len(jobs))
    res = {}
    done = 0
    with ThreadPoolExecutor(max_workers=12) as ex:
        for s, a, d in ex.map(dur, jobs):
            res.setdefault(str(s), {})[str(a)] = d
            done += 1
            if done % 500 == 0:
                print("  probed", done, flush=True)
    out = os.path.join(os.path.dirname(__file__), "naihi_durations.json")
    json.dump(res, open(out, "w"), separators=(",", ":"))
    miss = sum(1 for s in res for a in res[s] if res[s][a] is None)
    print("done. saved", out, "missing:", miss)

if __name__ == "__main__":
    main()

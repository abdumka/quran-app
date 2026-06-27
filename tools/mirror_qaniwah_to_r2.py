"""Mirror الأمين محمد قنيوه (qareeid 39, Qaloun) from nquran.com into Cloudflare R2,
AND detect his الوقف الهبطي breath-combining (consecutive ayat whose audio is
byte-identical = one breath). Outputs assets/data/qaniwah_continuations.json:
{ "<surah>": [ayat that merely repeat the previous breath and must be skipped] }.

Streams each file (download -> hash -> upload), parallel, resumable. Reads R2
creds from tools/.r2_secret. Hashes persisted to tools/_qaniwah_hashes.json so a
resumed run doesn't need to re-download already-mirrored files.
"""
import base64, hashlib, io, json, os, sys, urllib.request, urllib.error
import truststore
truststore.inject_into_ssl()
import boto3
from botocore.config import Config
from concurrent.futures import ThreadPoolExecutor

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

cfg = {}
for line in open("tools/.r2_secret"):
    if "=" in line:
        k, v = line.strip().split("=", 1)
        cfg[k] = v
BUCKET, PREFIX = cfg["R2_BUCKET"], cfg["R2_PREFIX"]

s3 = boto3.client(
    "s3", endpoint_url=cfg["R2_ENDPOINT"],
    aws_access_key_id=cfg["R2_ACCESS_KEY_ID"], aws_secret_access_key=cfg["R2_SECRET_ACCESS_KEY"],
    config=Config(region_name="auto", max_pool_connections=40,
                  request_checksum_calculation="when_required",
                  response_checksum_validation="when_required"),
)

NMAX = [7,285,200,175,122,167,206,76,130,109,122,111,44,54,99,128,110,105,98,134,
        111,76,119,62,77,227,95,88,69,60,33,30,73,54,45,82,181,86,72,84,53,50,89,
        56,36,34,39,29,18,45,60,47,61,55,77,99,28,22,24,13,14,11,11,18,12,12,30,52,
        52,44,30,28,20,56,39,31,50,40,45,41,28,19,36,25,22,16,19,26,32,20,16,21,11,
        8,8,20,5,8,8,11,10,8,3,9,5,5,6,3,6,3,5,4,5,6]
SRC = "moshaf/qaloon/alameen_kanyouh/%03d/%03d.mp3"
READ = "https://www.nquran.com/globals/readaudio.php?mp3="
HDRS = {"User-Agent": "Mozilla/5.0",
        "Referer": "https://www.nquran.com/ar/quranplayer/?rewayano=3&sorano=1&ayano=1"}
HASHFILE = "tools/_qaniwah_hashes.json"


def token(p):
    return base64.b64encode(('s:%d:"%s";|_*7H_' % (len(p.encode()), p)).encode()).decode()


existing = set()
for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=PREFIX + "/"):
    for o in page.get("Contents", []):
        existing.add(o["Key"])
hashes = {}
if os.path.exists(HASHFILE):
    hashes = {k: v for k, v in json.load(open(HASHFILE)).items()}
print("in R2: %d | known hashes: %d" % (len(existing), len(hashes)), flush=True)

jobs = []
for s in range(1, 115):
    if s != 9:
        jobs.append((s, 0))
    for a in range(1, NMAX[s - 1] + 1):
        jobs.append((s, a))
print("files:", len(jobs), flush=True)


def work(job):
    s, a = job
    kid = "%03d%03d" % (s, a)
    key = "%s/%s.mp3" % (PREFIX, kid)
    have_obj, have_hash = key in existing, kid in hashes
    if have_obj and have_hash:
        return ("skip", kid, hashes[kid])
    for _ in range(4):
        try:
            data = urllib.request.urlopen(urllib.request.Request(READ + token(SRC % (s, a)), headers=HDRS), timeout=60).read()
            if len(data) < 200:
                return ("small", kid, None)
            h = hashlib.md5(data).hexdigest()
            if not have_obj:
                s3.put_object(Bucket=BUCKET, Key=key, Body=data, ContentType="audio/mpeg")
            return ("up", kid, h)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return ("404", kid, None)
        except Exception:
            pass
    return ("err", kid, None)


up = skip = bad = done = 0
with ThreadPoolExecutor(max_workers=16) as ex:
    for status, kid, h in ex.map(work, jobs):
        done += 1
        if h:
            hashes[kid] = h
        if status == "up":
            up += 1
        elif status == "skip":
            skip += 1
        else:
            bad += 1
            if bad <= 30:
                print("  ", status, kid, flush=True)
        if done % 300 == 0:
            json.dump(hashes, open(HASHFILE, "w"))
            print("progress %d/%d up=%d skip=%d bad=%d" % (done, len(jobs), up, skip, bad), flush=True)
json.dump(hashes, open(HASHFILE, "w"))

# Build continuation set: ayah a (>=2) whose audio equals ayah a-1 (same breath).
cont = {}
for s in range(1, 115):
    lst = []
    for a in range(2, NMAX[s - 1] + 1):
        cur, prev = hashes.get("%03d%03d" % (s, a)), hashes.get("%03d%03d" % (s, a - 1))
        if cur and prev and cur == prev:
            lst.append(a)
    if lst:
        cont[str(s)] = lst
out = {"_comment": "قنيوه (الوقف الهبطي): ayat whose audio is byte-identical to the "
                   "previous ayah (recited together in one breath). The app plays the "
                   "breath once on the first ayah and skips these.",
       "continuations": cont}
json.dump(out, open(os.path.join(ROOT, "assets", "data", "qaniwah_continuations.json"), "w"),
          ensure_ascii=False, indent=1)
combined_total = sum(len(v) for v in cont.values())
print("\nDONE up=%d skip=%d bad=%d | surahs with combining=%d, continuation ayat=%d"
      % (up, skip, bad, len(cont), combined_total))

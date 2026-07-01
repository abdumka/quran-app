"""Mirror the al-Husary (الحصري) Qaloun recitation from its GitHub raw repo
into Cloudflare R2, so the app can serve it from R2 like al-Naihi / قنيوه.

Source : https://raw.githubusercontent.com/quran-by-verses/alhosary-qaloon-32/main/verses/<SSSAAA>.mp3
Dest   : R2  <BUCKET>/<PREFIX>/<SSSAAA>.mp3   (PREFIX = alhosary)

The file set is the exact set the app requests (Hafs ayah counts, with a few
end-of-surah ayat merged into one file) — verified 1:1 against the GitHub repo
(6236 files). Streams each file (download -> upload), parallel, resumable
(skips objects already in R2). Reads R2 creds from tools/.r2_secret (gitignored).
"""
import io, os, sys, urllib.request, urllib.error
import truststore
truststore.inject_into_ssl()
import boto3
from botocore.config import Config
from concurrent.futures import ThreadPoolExecutor

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

cfg = {}
for line in open("tools/.r2_secret"):
    if "=" in line and not line.lstrip().startswith("#"):
        k, v = line.strip().split("=", 1)
        cfg[k] = v
BUCKET = cfg["R2_BUCKET"]
PREFIX = cfg.get("R2_PREFIX", "alhosary").strip("/")

s3 = boto3.client(
    "s3", endpoint_url=cfg["R2_ENDPOINT"],
    aws_access_key_id=cfg["R2_ACCESS_KEY_ID"], aws_secret_access_key=cfg["R2_SECRET_ACCESS_KEY"],
    config=Config(region_name="auto", max_pool_connections=40,
                  request_checksum_calculation="when_required",
                  response_checksum_validation="when_required"),
)

SRC = "https://raw.githubusercontent.com/quran-by-verses/alhosary-qaloon-32/main/verses/%s.mp3"
HDRS = {"User-Agent": "Mozilla/5.0"}

# Hafs ayah counts + merged end-of-surah thresholds — mirrors the app's
# AudioDownloadService.getAllFilenames() so we copy exactly what the app requests.
COUNTS = [7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,
          112,78,118,64,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,54,53,89,
          59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,30,52,
          52,44,28,28,20,56,40,31,50,40,46,42,29,19,36,25,22,17,19,26,30,20,15,21,11,
          8,8,19,5,8,8,11,11,8,3,9,5,4,7,3,6,3,5,4,5,6]
MERGED = {5:120, 6:165, 8:75, 9:129, 13:43, 14:52, 23:118, 27:93, 47:38, 56:96,
          71:28, 89:30, 91:15, 96:19, 106:4}

names = set()
for s in range(1, 115):
    ss = "%03d" % s
    for a in range(1, COUNTS[s - 1] + 1):
        n = MERGED[s] if (s in MERGED and a >= MERGED[s]) else a
        names.add("%s%03d" % (ss, n))
names = sorted(names)
print("files to mirror:", len(names), flush=True)

existing = set()
for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=PREFIX + "/"):
    for o in page.get("Contents", []):
        existing.add(o["Key"])
print("already in R2 (%s/): %d" % (PREFIX, len(existing)), flush=True)


def work(name):
    key = "%s/%s.mp3" % (PREFIX, name)
    if key in existing:
        return ("skip", name)
    for _ in range(4):
        try:
            data = urllib.request.urlopen(urllib.request.Request(SRC % name, headers=HDRS), timeout=60).read()
            if len(data) < 200:
                return ("small", name)
            s3.put_object(Bucket=BUCKET, Key=key, Body=data, ContentType="audio/mpeg")
            return ("up", name)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return ("404", name)
        except Exception:
            pass
    return ("err", name)


up = skip = bad = done = 0
with ThreadPoolExecutor(max_workers=16) as ex:
    for status, name in ex.map(work, names):
        done += 1
        if status == "up":
            up += 1
        elif status == "skip":
            skip += 1
        else:
            bad += 1
            if bad <= 40:
                print("  ", status, name, flush=True)
        if done % 400 == 0:
            print("progress %d/%d up=%d skip=%d bad=%d" % (done, len(names), up, skip, bad), flush=True)

print("\nDONE up=%d skip=%d bad=%d (of %d)" % (up, skip, bad, len(names)))
if bad == 0:
    print("All al-Husary files mirrored to R2 %s/%s/" % (BUCKET, PREFIX))

"""
Publishes a Tasmee recognizer file to the public `quran-content` R2 bucket under
`asr/`, where `AsrModelManager.baseUrl` downloads it from
(https://pub-5025f0d14b9046309795201770f30da1.r2.dev/asr/).

Credentials come from tools/.r2_secret (same as upload_tv_apk_to_r2.py). The
bucket is pinned to quran-content because R2_BUCKET in that file tracks whatever
was mirrored last.

Usage:
    python tools/upload_asr_model_to_r2.py asr_model_upload/zipformer_p_arabic_v3.1_c16.int8.onnx
    python tools/upload_asr_model_to_r2.py <file> --key asr/other-name.onnx
    python tools/upload_asr_model_to_r2.py --check asr/zipformer_p_arabic_v3.1_c16.int8.onnx
"""
import io
import os
import sys
import urllib.request

import truststore
truststore.inject_into_ssl()
import boto3
from botocore.config import Config

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBLIC = "https://pub-5025f0d14b9046309795201770f30da1.r2.dev/"
BUCKET = "quran-content"
args = sys.argv[1:]

if "--check" in args:
    key = args[args.index("--check") + 1]
    req = urllib.request.Request(PUBLIC + key, method="HEAD")
    with urllib.request.urlopen(req, timeout=60) as r:
        print(key, r.status, r.headers.get("Content-Length"), "bytes")
    raise SystemExit(0)

path = next(a for a in args if not a.startswith("--"))
key = args[args.index("--key") + 1] if "--key" in args else "asr/" + os.path.basename(path)
if "--bucket" in args:
    BUCKET = args[args.index("--bucket") + 1]

cfg = {}
with open(os.path.join(ROOT, "tools", ".r2_secret"), encoding="utf-8") as fh:
    for line in fh:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            cfg[k] = v

s3 = boto3.client(
    "s3", endpoint_url=cfg["R2_ENDPOINT"],
    aws_access_key_id=cfg["R2_ACCESS_KEY_ID"],
    aws_secret_access_key=cfg["R2_SECRET_ACCESS_KEY"],
    config=Config(region_name="auto",
                  request_checksum_calculation="when_required",
                  response_checksum_validation="when_required"),
)
size = os.path.getsize(path)
print(f"uploading {size / (1024 * 1024):.1f} MB -> {BUCKET}/{key}", flush=True)
s3.upload_file(path, BUCKET, key, ExtraArgs={"ContentType": "application/octet-stream"})
req = urllib.request.Request(PUBLIC + key, method="HEAD")
with urllib.request.urlopen(req, timeout=60) as r:
    got = int(r.headers.get("Content-Length") or 0)
print(f"done: {PUBLIC}{key} -> HTTP {r.status}, {got} bytes ({'OK' if got == size else 'SIZE MISMATCH'})")

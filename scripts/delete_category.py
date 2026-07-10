#!/usr/bin/env python3
"""Butun kategoriyani O'CHIRADI: R2 (`<cat>/` prefiks) + lokal raw/out papkalar.

    python delete_category.py --category amoled
    python delete_category.py --category amoled --dry-run   # faqat ro'yxat

So'ng: python generate_catalog.py && python upload_r2.py  (katalog yangilanadi).
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
RAW = SCRIPT_DIR / "raw"
OUT = SCRIPT_DIR / "out"


def make_client():
    from dotenv import load_dotenv
    load_dotenv(SCRIPT_DIR / ".env")
    import boto3
    from botocore.config import Config
    acc = os.getenv("R2_ACCOUNT_ID")
    client = boto3.client(
        "s3", endpoint_url=f"https://{acc}.r2.cloudflarestorage.com",
        aws_access_key_id=os.getenv("R2_ACCESS_KEY_ID"),
        aws_secret_access_key=os.getenv("R2_SECRET_ACCESS_KEY"),
        region_name="auto", config=Config(signature_version="s3v4"),
    )
    return client, os.getenv("R2_BUCKET")


def add_to_blocklist(keys) -> None:
    bl = SCRIPT_DIR / "blocklist.json"
    try:
        existing = set(json.loads(bl.read_text(encoding="utf-8"))) if bl.exists() else set()
    except Exception:
        existing = set()
    existing.update(keys)
    bl.write_text(json.dumps(sorted(existing), ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"  blocklist: +{len(keys)} (jami {len(existing)})")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--category", required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    cat = args.category.strip("/")
    prefix = f"{cat}/"

    client, bucket = make_client()

    keys: list[str] = []
    token = None
    while True:
        kw = {"Bucket": bucket, "Prefix": prefix}
        if token:
            kw["ContinuationToken"] = token
        resp = client.list_objects_v2(**kw)
        keys += [o["Key"] for o in resp.get("Contents", [])]
        if resp.get("IsTruncated"):
            token = resp["NextContinuationToken"]
        else:
            break

    print(f"R2 '{prefix}' ostida {len(keys)} obyekt:")
    for k in keys:
        print("  -", k)
    raw_here = "bor" if (RAW / cat).exists() else "yoq"
    out_here = "bor" if (OUT / cat).exists() else "yoq"
    print(f"Lokal: raw/{cat} [{raw_here}], out/{cat} [{out_here}]")

    if args.dry_run:
        print("(dry-run — hech narsa o'chirilmadi)")
        return

    for i in range(0, len(keys), 1000):
        batch = [{"Key": k} for k in keys[i:i + 1000]]
        if batch:
            client.delete_objects(Bucket=bucket, Delete={"Objects": batch})
    print(f"✓ R2: {len(keys)} obyekt o'chirildi.")

    def _base(rk: str) -> str:
        for suf in ("_full.webp", "_thumb.webp"):
            if rk.endswith(suf):
                return rk[: -len(suf)]
        return rk
    add_to_blocklist(sorted({_base(k) for k in keys}))

    for d in (RAW / cat, OUT / cat):
        if d.exists():
            shutil.rmtree(d)
            print(f"✓ lokal o'chirildi: {d.relative_to(SCRIPT_DIR)}")

    print("Endi: python generate_catalog.py && python upload_r2.py")


if __name__ == "__main__":
    main()

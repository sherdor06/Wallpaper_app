#!/usr/bin/env python3
"""Favourites'da belgilangan wallpaper key'larni O'CHIRADI: R2 (full+thumb) +
lokal (raw manba, out webp). Ishlatuvchi app'da "sifatsiz"larni favourite qilib
belgilaydi → bu skript ularni tozalaydi. So'ng favorites.json bo'shatiladi.

    python delete_favorites.py --from-favorites "<.../favorites.json>"
    python delete_favorites.py --from-favorites "<...>" --dry-run   # faqat ro'yxat
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
OUT = SCRIPT_DIR / "out"
RAW = SCRIPT_DIR / "raw"


def make_client():
    from dotenv import load_dotenv
    load_dotenv(SCRIPT_DIR / ".env")
    import boto3
    from botocore.config import Config
    account = os.getenv("R2_ACCOUNT_ID")
    client = boto3.client(
        "s3",
        endpoint_url=f"https://{account}.r2.cloudflarestorage.com",
        aws_access_key_id=os.getenv("R2_ACCESS_KEY_ID"),
        aws_secret_access_key=os.getenv("R2_SECRET_ACCESS_KEY"),
        region_name="auto",
        config=Config(signature_version="s3v4"),
    )
    return client, os.getenv("R2_BUCKET")


def add_to_blocklist(keys) -> None:
    """O'chirilgan kalitlarni blocklist.json ga qo'shadi (qayta yuklanmasin)."""
    bl = SCRIPT_DIR / "blocklist.json"
    try:
        existing = set(json.loads(bl.read_text(encoding="utf-8"))) if bl.exists() else set()
    except Exception:
        existing = set()
    existing.update(keys)
    bl.write_text(json.dumps(sorted(existing), ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"  blocklist: +{len(keys)} (jami {len(existing)})")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--from-favorites", required=True, help="favorites.json yo'li")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    fav_path = Path(args.from_favorites)
    keys = sorted(set(json.loads(fav_path.read_text(encoding="utf-8"))))
    if not keys:
        sys.exit("favorites bo'sh — o'chiradigan narsa yo'q.")

    print(f"{len(keys)} ta wallpaper o'chiriladi:")
    for k in keys:
        print("  -", k)
    if args.dry_run:
        return

    client, bucket = make_client()
    for k in keys:
        # R2 obyektlari + lokal out webp
        for suf in ("_full.webp", "_thumb.webp"):
            r2key = f"{k}{suf}"
            try:
                client.delete_object(Bucket=bucket, Key=r2key)
                print(f"  ✗R2  {r2key}")
            except Exception as e:
                print(f"  ! R2 {r2key}: {e}")
            (OUT / f"{k}{suf}").unlink(missing_ok=True)
        # lokal raw manba (har xil kengaytma)
        sub = RAW / Path(k).parent
        if sub.exists():
            for f in sub.glob(Path(k).name + ".*"):
                f.unlink(missing_ok=True)

    add_to_blocklist(keys)  # doimiy: fetch qayta yuklamaydi
    # favorites.json ni bo'shatamiz (o'chirilganlar qayta belgilanmasin)
    fav_path.write_text("[]", encoding="utf-8")
    print(f"\nTayyor. {len(keys)} ta o'chirildi (R2 + lokal). favorites.json bo'shatildi.")
    print("Endi: python generate_catalog.py && python upload_r2.py")


if __name__ == "__main__":
    main()

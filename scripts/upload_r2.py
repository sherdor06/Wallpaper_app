#!/usr/bin/env python3
"""`out/` papkadagi hamma narsani (rasm + catalog.json) Cloudflare R2'ga yuklaydi.

Ishlatish:
    python upload_r2.py            # haqiqiy yuklash (.env kerak)
    python upload_r2.py --dry-run  # faqat ro'yxatni ko'rsatadi (kredensialsiz)

Kredensiallar .env dan o'qiladi (.env.example dan nusxa oling). Kalit nomlari
out/ ichidagi nisbiy yo'l bilan bir xil bo'ladi (masalan nature/sunset_full.webp),
shuning uchun ilova yasagan URL'lar mos tushadi.
"""
from __future__ import annotations

import argparse
import mimetypes
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
OUT_DIR = SCRIPT_DIR / "out"

# Rasmlar deyarli o'zgarmaydi -> uzoq kesh. Katalog tez yangilanishi kerak -> qisqa kesh.
LONG_CACHE = "public, max-age=31536000, immutable"
SHORT_CACHE = "public, max-age=300"

CONTENT_TYPES = {
    ".webp": "image/webp",
    ".json": "application/json",
    ".mp4": "video/mp4",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
}


def iter_files() -> list[tuple[Path, str]]:
    """(local_path, r2_key) ro'yxati."""
    files = []
    for p in sorted(OUT_DIR.rglob("*")):
        if p.is_file():
            files.append((p, p.relative_to(OUT_DIR).as_posix()))
    return files


def content_type(path: Path) -> str:
    return CONTENT_TYPES.get(path.suffix.lower()) or (
        mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    )


def make_client():
    from dotenv import load_dotenv

    load_dotenv(SCRIPT_DIR / ".env")
    account = os.getenv("R2_ACCOUNT_ID")
    key_id = os.getenv("R2_ACCESS_KEY_ID")
    secret = os.getenv("R2_SECRET_ACCESS_KEY")
    bucket = os.getenv("R2_BUCKET")

    missing = [
        n
        for n, v in {
            "R2_ACCOUNT_ID": account,
            "R2_ACCESS_KEY_ID": key_id,
            "R2_SECRET_ACCESS_KEY": secret,
            "R2_BUCKET": bucket,
        }.items()
        if not v
    ]
    if missing:
        sys.exit(
            "❌ .env to'liq emas. Yetishmayotgan: "
            + ", ".join(missing)
            + "\n   .env.example dan nusxa oling va to'ldiring (README A-qism)."
        )

    import boto3
    from botocore.config import Config

    client = boto3.client(
        "s3",
        endpoint_url=f"https://{account}.r2.cloudflarestorage.com",
        aws_access_key_id=key_id,
        aws_secret_access_key=secret,
        region_name="auto",
        config=Config(signature_version="s3v4"),
    )
    return client, bucket


def remote_size(client, bucket: str, key: str) -> int | None:
    from botocore.exceptions import ClientError

    try:
        head = client.head_object(Bucket=bucket, Key=key)
        return head["ContentLength"]
    except ClientError:
        return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dry-run", action="store_true", help="Faqat ro'yxat, yuklamaydi"
    )
    args = parser.parse_args()

    if not OUT_DIR.exists():
        sys.exit(f"❌ '{OUT_DIR}' topilmadi. Avval process + generate skriptlarini ishga tushiring.")

    files = iter_files()
    if not files:
        sys.exit("❌ out/ bo'sh. Yuklash uchun hech narsa yo'q.")

    if args.dry_run:
        print(f"DRY-RUN — {len(files)} fayl yuklanardi:")
        for _, key in files:
            print(f"  {key}")
        return

    client, bucket = make_client()

    uploaded = skipped = 0
    for path, key in files:
        size = path.stat().st_size
        if key != "catalog.json" and remote_size(client, bucket, key) == size:
            skipped += 1
            continue  # o'lcham bir xil -> qayta yuklamaymiz
        cache = SHORT_CACHE if key == "catalog.json" else LONG_CACHE
        client.upload_file(
            str(path),
            bucket,
            key,
            ExtraArgs={"ContentType": content_type(path), "CacheControl": cache},
        )
        uploaded += 1
        print(f"↑ {key}")

    print(f"\nTayyor. Yuklandi: {uploaded}, o'tkazib yuborilgan: {skipped}")
    print("Eslatma: catalog.json doim qayta yuklanadi (yangi kontent ko'rinishi uchun).")


if __name__ == "__main__":
    main()

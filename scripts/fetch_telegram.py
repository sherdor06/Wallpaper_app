#!/usr/bin/env python3
"""@iphonefotohd kanalidan hashtag bo'yicha TO'LIQ rasmlarni yuklaydi.

Kanal naqshi (aniqlangan): har wallpaper = 2 xabar —
  1) `#hashtag`li siqilgan PHOTO (preview),
  2) darrov ketidan captionsiz DOC (image/*) — HAQIQIY to'liq fayl.
Biz PHOTO#tag ni ko'rib, ketidan kelgan to'liq DOC'ni yuklaymiz (preview'ni emas).

Hashtag'lar ruscha → toza lotin kategoriyaga TAG_MAP orqali map qilinadi (whitelist:
faqat map'dagi tag'lar olinadi; #девушки, #реклама, #разное va h.k. — tashlanadi).

Avval bir marta login_telegram.py bilan kiring (wallpaper.session).

Ishlatish:
    python fetch_telegram.py                      # har kategoriyaga 50
    python fetch_telegram.py --per 50 --scan 3000
    python fetch_telegram.py --only cars animals  # faqat shu kategoriyalar
"""
from __future__ import annotations

import argparse
import asyncio
import json
import mimetypes
import os
import re
from pathlib import Path

from dotenv import load_dotenv
from telethon import TelegramClient

from face_filter import has_prominent_face

SCRIPT_DIR = Path(__file__).resolve().parent
RAW = SCRIPT_DIR / "raw"
load_dotenv(SCRIPT_DIR / ".env")

TAG_RE = re.compile(r"#(\w+)", re.UNICODE)
CHANNEL = "@iphonefotohd"

# O'chirilgan (foydalanuvchi rad etgan) wallpaperlar — hech qachon qayta yuklanmaydi.
try:
    BLOCKLIST = set(json.loads((SCRIPT_DIR / "blocklist.json").read_text(encoding="utf-8")))
except Exception:
    BLOCKLIST = set()

# Ruscha hashtag -> toza lotin kategoriya (whitelist). Bu yerда yo'q tag'lar
# (#девушки, #реклама, #разное, #парные, #пасха ...) UMUMAN olinmaydi.
TAG_MAP = {
    "cars": "cars", "машины": "cars",
    "животные": "animals", "животное": "animals",
    "природа": "nature",
    "море": "ocean",
    "абстракция": "abstract", "абстрация": "abstract", "текстуры": "abstract",
    "космос": "space",
    "цветы": "flowers",
    "спорт": "sport",
    "градиент": "gradient",
    "город": "city",
    "архитектура": "architecture",
    "игры": "games",
    "комиксы": "comics", "мультфильмы": "comics", "мультики": "comics",
    "технологии": "tech", "apple": "tech", "android": "tech",
    "кино": "movies",
    # art / anime (нейро, самурай, аниме) — qiz-ko'p, ataylab OLIB TASHLANGAN.
}


def category_for(caption: str) -> str | None:
    for t in TAG_RE.findall(caption or ""):
        cat = TAG_MAP.get(t.lower())
        if cat:
            return cat
    return None


async def run(per: int, scan: int, only: set[str]) -> None:
    api_id = os.getenv("TELEGRAM_API_ID")
    api_hash = os.getenv("TELEGRAM_API_HASH")
    phone = os.getenv("TELEGRAM_PHONE")
    if not api_id or not api_hash:
        raise SystemExit("❌ .env da TELEGRAM_API_ID/API_HASH yo'q.")

    client = TelegramClient(
        str(SCRIPT_DIR / "wallpaper"), int(api_id), api_hash,
        connection_retries=10, retry_delay=3, request_retries=10,
        timeout=30, flood_sleep_threshold=60,
    )
    await client.start(phone=phone or (lambda: input("Telefon raqam (+998...): ")))

    counts: dict[str, int] = {}
    pending: str | None = None  # to'liq faylini kutayotgan kategoriya
    scanned = 0

    async for m in client.iter_messages(CHANNEL, limit=scan):
        scanned += 1
        cap = m.message or ""
        if TAG_RE.search(cap):
            # Hashtagli xabar (odatda PHOTO preview) — kategoriyani belgilaymiz.
            cat = category_for(cap)
            if only and cat not in only:
                cat = None
            pending = cat if m.photo else None
            continue
        # Captionsiz xabar — pending kategoriyaning to'liq DOC'i bo'lishi mumkin.
        doc = getattr(m, "document", None)
        mime = getattr(doc, "mime_type", None) if doc else None
        if pending and mime and mime.startswith("image/"):
            if f"{pending}/tg_{m.id}" in BLOCKLIST:
                pending = None  # foydalanuvchi o'chirgan — qayta yuklamaymiz
                continue
            if counts.get(pending, 0) < per:
                ext = mimetypes.guess_extension(mime) or ".jpg"
                dest = RAW / pending / f"tg_{m.id}{ext}"
                if dest.exists():
                    counts[pending] = counts.get(pending, 0) + 1
                else:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    ok = False
                    for attempt in range(4):
                        try:
                            await m.download_media(file=str(dest))
                            ok = True
                            break
                        except Exception as e:
                            print(f"   ⚠️ {pending}/{m.id}: {e} — qayta ({attempt + 1})")
                            await asyncio.sleep(3 * (attempt + 1))
                    if ok and has_prominent_face(dest):
                        dest.unlink(missing_ok=True)  # yirik yuz (odam/qiz) — o'tkazamiz
                        print(f"  ⊘ {pending}/{m.id} — yuz aniqlandi, o'tkazildi")
                        ok = False
                    if ok:
                        counts[pending] = counts.get(pending, 0) + 1
                        print(f"  ✓ {pending}/{dest.name}")
                        await asyncio.sleep(0.25)
                    elif dest.exists():
                        dest.unlink()  # yarim yuklangan faylni tozalash
            pending = None

    await client.disconnect()
    total = sum(counts.values())
    print(f"\nTayyor. Skaner: {scanned} xabar, yuklangan: {total}")
    for c, n in sorted(counts.items(), key=lambda x: -x[1]):
        print(f"  {c}: {n}")
    print("Keyingi: process_images.py → generate_catalog.py → upload_r2.py")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--per", type=int, default=50, help="Har kategoriyaga nechta (default 50)")
    p.add_argument("--scan", type=int, default=3000, help="Ko'pi bilan nechta xabar skaner")
    p.add_argument("--only", nargs="*", help="Faqat shu kategoriyalar (lotin nomi)")
    args = p.parse_args()
    asyncio.run(run(args.per, args.scan, set(args.only or [])))


if __name__ == "__main__":
    main()

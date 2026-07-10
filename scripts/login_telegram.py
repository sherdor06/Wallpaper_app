#!/usr/bin/env python3
"""Bir martalik Telegram login — `wallpaper.session` faylini yaratadi.

Terminalда o'zingiz ishga tushiring (interaktiv):
    cd scripts && source venv/bin/activate
    python login_telegram.py

Telefon raqamingiz .env dan olinadi; Telegram yuborgan **kodni** kiritasiz
(agar 2FA parol bo'lsa, uni ham). Muvaffaqiyatdan keyin fetch_telegram.py
qayta login so'ramaydi.
"""
import os
from pathlib import Path

from dotenv import load_dotenv
from telethon.sync import TelegramClient

SCRIPT_DIR = Path(__file__).resolve().parent
load_dotenv(SCRIPT_DIR / ".env")

api_id = os.getenv("TELEGRAM_API_ID")
api_hash = os.getenv("TELEGRAM_API_HASH")
phone = os.getenv("TELEGRAM_PHONE")

missing = [n for n, v in {
    "TELEGRAM_API_ID": api_id,
    "TELEGRAM_API_HASH": api_hash,
}.items() if not v]
if missing:
    raise SystemExit(
        "❌ .env to'liq emas. Yetishmayapti: " + ", ".join(missing)
        + "\n   my.telegram.org > API development tools dan oling (README/plan)."
    )

with TelegramClient(str(SCRIPT_DIR / "wallpaper"), int(api_id), api_hash) as client:
    # Telefon .env da bo'lmasa, terminalда so'raladi.
    client.start(phone=phone or (lambda: input("Telefon raqam (+998...): ")))
    me = client.get_me()
    print(f"\n✓ Kirildi: {me.first_name} (@{me.username}). "
          f"wallpaper.session tayyor — endi menga 'login tayyor' deng.")

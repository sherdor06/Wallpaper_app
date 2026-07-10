#!/usr/bin/env python3
"""Kategoriya bo'yicha CC0 / Public-Domain foto yig'uvchi (Openverse API).

Faqat FOTO-provayderlardan (StockSnap, Flickr) va faqat `license=cc0,pdm`
(CC0 / Public Domain Mark) rasmlar olinadi — bular standalone wallpaper
qayta-tarqatishga ruxsat beradi, shuning uchun release'ga qonuniy mos.
Manba filtri muzey/Wikimedia eski rasm-kartinalarini chetlaydi.

Eslatma: Openverse StockSnap uchun ~960px (kichraytirilgan) versiya beradi —
to'liq 4K originalni bermaydi. Shuning uchun MIN_LONG_SIDE original metadata
bo'yicha sifat-pol'i (juda past manbalarni chetlaydi), yuklangan fayl ~960px.

Oqim: bu skript rasmlarni `raw/<category>/` ga yuklaydi → so'ng
    python process_images.py && python generate_catalog.py && python upload_r2.py

Shipdagi ilova hech qanday API'ga tegmaydi — u faqat R2'dagi catalog.json'ni o'qiydi.

Idempotent: mavjud fayl qayta yuklanmaydi. Qayta ishga tushirsa yangilarini qo'shadi.

Ishlatish:
    python fetch_stock.py                          # hamma kategoriya
    python fetch_stock.py --categories nature space
    python fetch_stock.py --max 40 --min-side 3840
    python fetch_stock.py --sources stocksnap      # faqat StockSnap
    python fetch_stock.py --dry-run                # yuklamaydi, faqat ro'yxat

Bulk uchun (anonim limit 200/kun → 401) .env ga bepul token qo'ying:
    OPENVERSE_CLIENT_ID=...  OPENVERSE_CLIENT_SECRET=...
    (https://api.openverse.org/v1/auth_tokens/register/)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
RAW = SCRIPT_DIR / "raw"
ENV_PATH = SCRIPT_DIR / ".env"

API = "https://api.openverse.org/v1/images/"
TOKEN_URL = "https://api.openverse.org/v1/auth_tokens/token/"
UA = "wallpaper-content-pipeline/1.0 (+personal wallpaper app)"

# Faqat foto-provayderlar (muzey/Wikimedia EMAS). StockSnap = zamonaviy 4K stock
# foto; Flickr = qo'shimcha (NASA fotolari ham shu yerda). --sources bilan o'zgartiring.
SOURCES = "stocksnap,flickr"

MIN_LONG_SIDE = 1600   # manba fotoning original uzun tomoni (sifat pol'i, 4K emas)
MAX_PER_CATEGORY = 30  # har kategoriyaga nechta rasm yig'ish
PAGE_SIZE = 20         # anonim uchun xavfsiz sahifa hajmi
MAX_PAGES = 20         # bir kategoriyada ko'pi bilan shuncha sahifa ko'riladi
OK_TYPES = {"jpg", "jpeg", "png", "webp"}

# category -> [qidiruv kalitlari]. Foto-mos kategoriyalar (AI-mos emas).
QUERIES: dict[str, list[str]] = {
    "nature":       ["landscape", "forest", "waterfall", "autumn nature", "jungle", "meadow", "lake"],
    "mountains":    ["mountain landscape", "snowy mountains", "alps", "mountain peak", "hills"],
    "ocean":        ["ocean wave", "beach sunset", "sea coast", "tropical beach", "underwater"],
    "space":        ["milky way night sky", "starry sky", "aurora", "night sky stars", "moon night"],
    "city":         ["city skyline night", "street at night", "cityscape", "city lights", "skyscraper"],
    "architecture": ["modern architecture", "building facade", "cathedral", "bridge", "interior design"],
    "animals":      ["wildlife", "lion", "wolf", "bird", "tiger", "elephant", "deer", "fox", "horse", "owl"],
    "flowers":      ["flower macro", "cherry blossom", "rose", "tulip", "sunflower", "orchid", "lavender"],
    "cars":         ["sports car", "car road", "classic car", "luxury car", "supercar", "car night"],
}


# --- Slug / fayl nomi ------------------------------------------------------

def slugify(s: str) -> str:
    """URL-xavfsiz kalit: kichik harf, faqat a-z0-9_ (process_images bilan mos)."""
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "_", s).strip("_").lower()
    return s or "photo"


# --- Auth (ixtiyoriy token) ------------------------------------------------

def load_env() -> None:
    """`.env` ni o'qiydi (python-dotenv bo'lsa; bo'lmasa oddiy parser)."""
    try:
        from dotenv import load_dotenv
        load_dotenv(ENV_PATH)
        return
    except Exception:
        pass
    if ENV_PATH.exists():
        for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())


def get_token() -> str | None:
    """.env da client kredensiallari bo'lsa OAuth access_token oladi, bo'lmasa None."""
    cid = os.getenv("OPENVERSE_CLIENT_ID")
    secret = os.getenv("OPENVERSE_CLIENT_SECRET")
    if not cid or not secret:
        print("ℹ️  Token yo'q — anonim (limit 200/kun). Bulk uchun .env ga "
              "OPENVERSE_CLIENT_ID/SECRET qo'shing.")
        return None
    data = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "client_id": cid,
        "client_secret": secret,
    }).encode()
    req = urllib.request.Request(TOKEN_URL, data=data, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            tok = json.load(r).get("access_token")
            if tok:
                print("✓ Openverse token olindi (yuqori limit).")
            return tok
    except Exception as e:
        print(f"⚠️  Token olinmadi ({e}) — anonim davom etadi.")
        return None


# --- Qidiruv + yuklab olish ------------------------------------------------

def search(query: str, page: int, token: str | None, sources: str) -> dict:
    """Openverse qidiruvi. 401/403/429 (limit) da backoff bilan qayta urinadi,
    baribir bo'lmasa bo'sh natija qaytaradi (crash yo'q)."""
    params = {
        "q": query,
        "license": "cc0,pdm",
        "aspect_ratio": "tall",
        "mature": "false",
        "page": page,
        "page_size": PAGE_SIZE,
    }
    if sources:
        params["source"] = sources
    req = urllib.request.Request(
        f"{API}?{urllib.parse.urlencode(params)}", headers={"User-Agent": UA}
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")

    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (429, 401, 403):  # burst-throttle — sabr bilan qayta urinamiz
                wait = min(15 * (attempt + 1), 45)
                print(f"   … Openverse throttle ({e.code}), {wait}s kutilyapti")
                time.sleep(wait)
                continue
            print(f"   ⚠️  Openverse xatosi {e.code} — sahifa o'tkazildi")
            return {"results": []}
        except Exception as e:
            print(f"   … tarmoq xatosi ({e}), qayta urinish")
            time.sleep(5)

    print("   ⚠️  Bu sahifa throttle tufayli o'tkazildi (keyingisi davom etadi).")
    return {"results": []}


def download(url: str, dest: Path) -> bool:
    """Rasmni yuklaydi. 429/timeout da backoff bilan qayta urinadi, bo'lmasa skip."""
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            if len(data) < 10_000:  # juda kichik -> yaroqsiz/placeholder
                return False
            dest.write_bytes(data)
            return True
        except urllib.error.HTTPError as e:
            if e.code in (429, 503) and attempt < 2:
                time.sleep(15 * (attempt + 1))
                continue
            print(f"   ✗ yuklab bo'lmadi: {e}")
            return False
        except Exception as e:
            if attempt < 2:
                time.sleep(3)
                continue
            print(f"   ✗ yuklab bo'lmadi: {e}")
            return False
    return False


def fetch_category(cat: str, queries: list[str], token: str | None, sources: str,
                   max_per: int, min_side: int, dry_run: bool) -> int:
    d = RAW / cat
    credits_path = d / "_credits.json"
    credits: dict = {}
    if credits_path.exists():
        try:
            credits = json.loads(credits_path.read_text(encoding="utf-8"))
        except Exception:
            credits = {}

    seen = set(credits.keys())
    # Mavjud fayllarni ham hisobga olamiz (idempotent).
    if d.exists():
        for f in d.glob("*"):
            if f.is_file() and f.suffix.lower().lstrip(".") in OK_TYPES:
                seen.add(f.stem)

    made = 0
    for query in queries:
        if made >= max_per:
            break
        for page in range(1, MAX_PAGES + 1):
            if made >= max_per:
                break
            res = search(query, page, token, sources)
            results = res.get("results") or []
            if not results:
                break
            for item in results:
                if made >= max_per:
                    break
                url = item.get("url")
                w, h = item.get("width") or 0, item.get("height") or 0
                ftype = (item.get("filetype") or "").lower()
                if not url or max(w, h) < min_side:
                    continue
                if ftype and ftype not in OK_TYPES:
                    continue
                slug = slugify(item.get("title") or "")
                if slug in seen:  # nom to'qnashuvi -> id bo'lakchasini qo'shamiz
                    slug = f"{slug}_{str(item.get('id'))[:6]}"
                if slug in seen:
                    continue
                ext = ftype if ftype in OK_TYPES else "jpg"
                dest = d / f"{slug}.{ext}"

                if dry_run:
                    print(f"  [dry] {cat}/{slug}.{ext}  "
                          f"({w}x{h}, {item.get('license')}, {item.get('source')})")
                    seen.add(slug)
                    made += 1
                    continue

                d.mkdir(parents=True, exist_ok=True)
                if download(url, dest):
                    seen.add(slug)
                    credits[slug] = {
                        "creator": item.get("creator"),
                        "license": item.get("license"),
                        "source_url": item.get("foreign_landing_url"),
                    }
                    made += 1
                    print(f"  ✓ {cat}/{slug}.{ext}  "
                          f"({w}x{h}, {item.get('license')}, {item.get('source')})")
                    time.sleep(0.5)  # yuklab olishlar orasida xushmuomala pauza
            time.sleep(2.5)  # sahifalar orasida (burst-throttle'ga kamroq urilish)

    if not dry_run and credits:
        d.mkdir(parents=True, exist_ok=True)
        credits_path.write_text(
            json.dumps(credits, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    return made


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--categories", nargs="*", help="Faqat shu kategoriyalar")
    parser.add_argument("--max", type=int, default=MAX_PER_CATEGORY,
                        help=f"Har kategoriyaga nechta (default {MAX_PER_CATEGORY})")
    parser.add_argument("--min-side", type=int, default=MIN_LONG_SIDE,
                        help=f"Minimal original uzun tomon px (default {MIN_LONG_SIDE})")
    parser.add_argument("--sources", default=SOURCES,
                        help=f"Openverse provayderlar (default '{SOURCES}')")
    parser.add_argument("--dry-run", action="store_true", help="Yuklamaydi, ro'yxat")
    args = parser.parse_args()

    load_env()
    token = None if args.dry_run else get_token()

    cats = args.categories or list(QUERIES.keys())
    total = 0
    for cat in cats:
        queries = QUERIES.get(cat)
        if not queries:
            print(f"⚠️  '{cat}' uchun QUERIES yo'q — o'tkazib yuborildi.")
            continue
        print(f"\n=== {cat} ===")
        total += fetch_category(
            cat, queries, token, args.sources, args.max, args.min_side, args.dry_run
        )

    print(f"\nTayyor. Yangi rasmlar: {total}")
    if not args.dry_run:
        print("Keyingi: python process_images.py && python generate_catalog.py && python upload_r2.py")


if __name__ == "__main__":
    main()

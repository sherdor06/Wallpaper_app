#!/usr/bin/env python3
"""`out/` papkadan `catalog.json` yasaydi (ilova o'qiydigan sxema).

Ishlatish:
    python generate_catalog.py

`out/<kategoriya>/<nom>_full.webp` har biri uchun bitta wallpaper yozuvi yaratadi.
URL'lar ilovada `key` dan yasaladi (kalit+qoida), shuning uchun bu yerda faqat `key`
saqlanadi. Live wallpaper: agar yonida `<nom>.mp4` bo'lsa, turi `live` bo'ladi.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image

_ID_RE = re.compile(r"^[0-9a-f]{4,}$", re.IGNORECASE)


def meaningful_words(name: str) -> list[str]:
    """Fayl nomidan ma'noli so'zlar (tg_, raqam, hex-id tokenlarni tashlaydi)."""
    out: list[str] = []
    for w in re.split(r"[_\-\s]+", name):
        wl = w.lower()
        if not wl or wl == "tg" or wl.isdigit() or _ID_RE.match(wl):
            continue
        out.append(wl)
    return out

SCRIPT_DIR = Path(__file__).resolve().parent
OUT_DIR = SCRIPT_DIR / "out"
RAW_DIR = SCRIPT_DIR / "raw"
CONFIG_PATH = SCRIPT_DIR / "config.json"
CATALOG_PATH = OUT_DIR / "catalog.json"

FULL_SUFFIX = "_full.webp"

# fetch_stock.py yozgan attribution (raw/<category>/_credits.json) — kesh.
_credits_cache: dict[str, dict] = {}


def load_config() -> dict:
    if CONFIG_PATH.exists():
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    return {"premium_if_4k": True, "categories": {}}


def credit_for(category: str, name: str) -> str | None:
    """`_credits.json` bo'lsa rasmning muallif belgisini qaytaradi (CC0 attribution)."""
    if category not in _credits_cache:
        path = RAW_DIR / category / "_credits.json"
        try:
            _credits_cache[category] = (
                json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
            )
        except Exception:
            _credits_cache[category] = {}
    info = _credits_cache[category].get(name) or {}
    creator = info.get("creator")
    return f"© {creator}" if creator else None


def title_case(name: str) -> str:
    return name.replace("_", " ").replace("-", " ").strip().title()


def resolution_label(path: Path) -> str:
    try:
        with Image.open(path) as im:
            longest = max(im.size)
    except Exception:
        return "HD"
    if longest >= 3000:
        return "4K"
    if longest >= 1600:
        return "FHD"
    return "HD"


def main() -> None:
    if not OUT_DIR.exists():
        print(f"❌ '{OUT_DIR}' topilmadi. Avval process_images.py ni ishga tushiring.")
        return

    config = load_config()
    cat_config: dict = config.get("categories", {})
    premium_if_4k: bool = config.get("premium_if_4k", True)

    wallpapers: list[dict] = []
    used_categories: set[str] = set()
    cat_counter: dict[str, int] = {}  # mazmunsiz nomlar uchun "Cars 1, Cars 2..."

    for full in sorted(OUT_DIR.rglob(f"*{FULL_SUFFIX}")):
        name = full.name[: -len(FULL_SUFFIX)]
        category = full.parent.relative_to(OUT_DIR).as_posix()
        key = f"{category}/{name}"

        is_live = (full.parent / f"{name}.mp4").exists()
        resolution = resolution_label(full)

        cat_meta = cat_config.get(category, {})
        premium = bool(cat_meta.get("premium", False))
        if premium_if_4k and resolution == "4K":
            premium = True
        if is_live:
            premium = bool(cat_meta.get("premium", True))  # live odatda premium

        # Nom: ma'noli so'zlar bo'lsa — o'shalar ("Misty Forest"); bo'lmasa
        # (tg_31772 kabi) — kategoriya + raqam ("Cars 1"). Search shu title/tag'lardan
        # topadi.
        words = meaningful_words(name)
        if words:
            title = " ".join(words).title()
        else:
            cat_counter[category] = cat_counter.get(category, 0) + 1
            title = f"{title_case(category)} {cat_counter[category]}"

        tags = sorted({category, *words})  # kategoriya + kalit so'zlar (searchable)
        credit = credit_for(category, name)
        if credit:
            tags.append(credit)

        wallpapers.append(
            {
                "key": key,
                "title": title,
                "category": category,
                "type": "live" if is_live else "image",
                "resolution": resolution,
                "premium": premium,
                "tags": tags,
            }
        )
        used_categories.add(category)

    categories = [
        {"id": cid, "name": cat_config.get(cid, {}).get("name", title_case(cid))}
        for cid in sorted(used_categories)
    ]

    catalog = {"version": 1, "categories": categories, "wallpapers": wallpapers}
    CATALOG_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(f"✓ {CATALOG_PATH}")
    print(f"  Kategoriyalar: {len(categories)}, wallpaperlar: {len(wallpapers)}")
    premium_count = sum(1 for w in wallpapers if w["premium"])
    live_count = sum(1 for w in wallpapers if w["type"] == "live")
    print(f"  Premium: {premium_count}, live: {live_count}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""`out/` papkadan `catalog.json` yasaydi (ilova o'qiydigan sxema).

Ishlatish:
    python generate_catalog.py

`out/<kategoriya>/<nom>_full.webp` har biri uchun bitta wallpaper yozuvi yaratadi.
URL'lar ilovada `key` dan yasaladi (kalit+qoida), shuning uchun bu yerda faqat `key`
saqlanadi. Live wallpaper: agar yonida `<nom>.mp4` bo'lsa, turi `live` bo'ladi.
"""
from __future__ import annotations

import colorsys
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


def moods_for(thumb: Path) -> list[str]:
    """Tone tags read off the image's colours — what the app's collection page
    filters by ("Light", "Dark", "Vivid", "Mono"). Nothing semantic: the
    Telegram sources carry no usable tags, and tone is what people actually
    pick a wallpaper by. A picture may carry several (neon at night is dark
    *and* vivid) or none. Keep the ids in step with `kMoodOrder` in
    lib/models/wallpaper.dart.

    Cheap on purpose: the thumbnail shrunk to 32px, HLS per pixel.
    """
    try:
        with Image.open(thumb) as im:
            im = im.convert("RGB")
            im.thumbnail((32, 32))
            px = list(im.getdata())
    except Exception:
        return []
    if not px:
        return []
    ls: list[float] = []
    ss: list[float] = []
    for r, g, b in px:
        _h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        ls.append(l)
        # Saturation is noise on near-black and near-white pixels; weight it
        # by how mid-toned the pixel is so a black frame does not read "mono".
        ss.append(s * (1 - abs(2 * l - 1)))
    n = len(px)
    light = sum(ls) / n
    sat = sum(ss) / n
    dark_share = sum(1 for v in ls if v < 0.2) / n
    # Share of the frame that carries real colour. Mean saturation alone
    # called a blue Earth on black "mono" — the planet is 15% of the frame.
    colour_share = sum(1 for v in ss if v > 0.12) / n
    out: list[str] = []
    if colour_share < 0.06:
        out.append("mono")
    if light < 0.3 or dark_share > 0.6:
        out.append("dark")
    if light > 0.55 and sat < 0.22 and "mono" not in out:
        out.append("light")
    if sat >= 0.22 and light > 0.25:
        out.append("vivid")
    return out


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
        moods = moods_for(full.parent / f"{name}_thumb.webp")

        wallpapers.append(
            {
                "key": key,
                "title": title,
                "category": category,
                "type": "live" if is_live else "image",
                "resolution": resolution,
                "premium": premium,
                "tags": tags,
                "moods": moods,
            }
        )
        used_categories.add(category)

    categories = []
    for cid in sorted(used_categories):
        meta = cat_config.get(cid, {})
        entry = {"id": cid, "name": meta.get("name", title_case(cid))}
        # One line about the collection, shown under its name in the app's
        # carousel. Optional: the app falls back to the wallpaper count.
        if meta.get("tagline"):
            entry["tagline"] = meta["tagline"]
        categories.append(entry)

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

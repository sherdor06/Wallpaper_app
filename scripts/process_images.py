#!/usr/bin/env python3
"""Rasmlarni wallpaper uchun tayyorlaydi: WebP + thumbnail.

Ishlatish:
    python process_images.py

`raw/<kategoriya>/*.{jpg,jpeg,png,webp}` -> `out/<kategoriya>/`:
    <nom>_full.webp   (uzun tomon <= FULL_MAX px, sifat FULL_Q)
    <nom>_thumb.webp  (uzun tomon <= THUMB_MAX px, sifat THUMB_Q)

Idempotent: chiqish fayli manbadan yangiroq bo'lsa, qayta ishlanmaydi.
Video (.mp4) fayllari teginilmaydi — ular jonli (live) wallpaper uchun
generate_catalog.py tomonidan aniqlanadi (raw'dan out'ga qo'lda nusxalang).
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageOps

SCRIPT_DIR = Path(__file__).resolve().parent
RAW_DIR = SCRIPT_DIR / "raw"
OUT_DIR = SCRIPT_DIR / "out"

FULL_MAX = 3840   # 4K uzun tomon
FULL_Q = 85
THUMB_MAX = 640   # galereya katakchasi uchun
THUMB_Q = 80

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def slugify(s: str) -> str:
    """Fayl nomini URL-xavfsiz kalitga aylantiradi: kichik harf, faqat a-z0-9_.

    Masalan "Misty Forest (4K).jpg" -> "misty_forest_4k".
    """
    import re
    import unicodedata

    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "_", s).strip("_").lower()
    return s or "wall"


def _resize_longest(img: Image.Image, max_side: int) -> Image.Image:
    """Uzun tomonni max_side gacha kichraytiradi (kattalashtirmaydi)."""
    w, h = img.size
    longest = max(w, h)
    if longest <= max_side:
        return img.copy()
    scale = max_side / longest
    return img.resize((round(w * scale), round(h * scale)), Image.LANCZOS)


def _is_fresh(src: Path, *outs: Path) -> bool:
    """Barcha chiqish fayllari mavjud va manbadan yangi bo'lsa True."""
    if not all(o.exists() for o in outs):
        return False
    src_mtime = src.stat().st_mtime
    return all(o.stat().st_mtime >= src_mtime for o in outs)


def process_one(src: Path, out_dir: Path) -> bool:
    """Bitta rasmni ishlaydi. Qayta ishlangan bo'lsa False qaytaradi."""
    # Fayl nomi URL-xavfsiz slug'ga aylantiriladi (bo'shliq/katta harf/unicode -> toza).
    name = slugify(src.stem)
    full_out = out_dir / f"{name}_full.webp"
    thumb_out = out_dir / f"{name}_thumb.webp"

    if _is_fresh(src, full_out, thumb_out):
        return False

    out_dir.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as im:
        im = ImageOps.exif_transpose(im)  # telefon rasmlaridagi burilishni to'g'rilaydi
        im = im.convert("RGB")

        full = _resize_longest(im, FULL_MAX)
        full.save(full_out, "WEBP", quality=FULL_Q, method=6)

        thumb = _resize_longest(im, THUMB_MAX)
        thumb.save(thumb_out, "WEBP", quality=THUMB_Q, method=6)
    return True


def main() -> None:
    if not RAW_DIR.exists():
        print(f"❌ '{RAW_DIR}' topilmadi. Rasmlarni raw/<kategoriya>/ ichiga joylang.")
        return

    processed = skipped = uncategorized = failed = 0
    for src in sorted(RAW_DIR.rglob("*")):
        if not src.is_file() or src.suffix.lower() not in IMAGE_EXTS:
            continue
        if src.suffix.lower() == ".webp" and src.stem.endswith(("_full", "_thumb")):
            continue  # avval ishlangan chiqishni qayta yutmaslik
        rel_category = src.parent.relative_to(RAW_DIR)
        if rel_category == Path("."):
            # To'g'ridan-to'g'ri raw/ ichida — kategoriya papkasi yo'q, o'tkazib yuboriladi.
            uncategorized += 1
            continue
        out_dir = OUT_DIR / rel_category
        try:
            done = process_one(src, out_dir)
        except Exception as e:
            # Buzuq / yarim yuklangan rasm — o'tkazamiz (butun run to'xtamasin).
            failed += 1
            print(f"✗ {src.relative_to(RAW_DIR)}: {e}")
            continue
        if done:
            processed += 1
            print(f"✓ {src.relative_to(RAW_DIR)}")
        else:
            skipped += 1

    print(f"\nTayyor. Ishlangan: {processed}, o'tkazib yuborilgan: {skipped}, buzuq: {failed}")
    if uncategorized:
        print(f"⚠️  {uncategorized} ta rasm to'g'ridan-to'g'ri raw/ ichida (kategoriyasiz) — "
              f"ular o'tkazib yuborildi. Ularni raw/<kategoriya>/ papkasiga ko'chiring.")
    print(f"Chiqish: {OUT_DIR}")


if __name__ == "__main__":
    main()

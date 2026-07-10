#!/usr/bin/env python3
"""Kategoriya bo'yicha AI wallpaper generatori (pollinations.ai — bepul, kalitsiz).

Har kategoriya uchun promptlarni generatsiya qiladi, ~1440x2560 ga kattalaytirib
`raw/<category>/` ga yozadi. So'ng: process_images.py + generate_catalog.py + upload_r2.py.

Idempotent: mavjud fayl qayta generatsiya qilinmaydi. Qayta ishga tushirsa yangilarini qo'shadi.
Ko'proq rasm: PROMPTS ga yangi qatorlar qo'shing yoki SEEDS_PER_PROMPT ni oshiring.
"""
from __future__ import annotations

import io
import time
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
RAW = SCRIPT_DIR / "raw"
TARGET = (1440, 2560)  # upscale target (9:16), pollinations 576x1024 dan
SUFFIX = ", vertical phone wallpaper, ultra detailed, cinematic lighting, high quality, no text, no watermark"
SEEDS_PER_PROMPT = 1   # har promptdan nechta variant

# category -> [(fayl_nomi_label, prompt)]
PROMPTS: dict[str, list[tuple[str, str]]] = {
    "nature": [
        ("misty_forest", "misty pine forest at dawn, fog between dark trees, soft god rays"),
        ("alpine_lake", "crystal clear alpine lake reflecting snowy mountains at golden hour"),
        ("autumn_path", "autumn forest path covered in orange leaves, warm sunlight"),
        ("ocean_wave", "powerful ocean wave curling at sunset, backlit spray, deep blue"),
        ("waterfall", "tropical waterfall in lush green jungle, mist, sunbeams"),
        ("desert_dunes", "golden desert sand dunes at sunset, smooth curves, minimal"),
    ],
    "space": [
        ("purple_nebula", "purple and pink nebula with bright star cluster, deep space"),
        ("earth_orbit", "earth horizon from orbit at night, glowing city lights, stars"),
        ("spiral_galaxy", "spiral galaxy from above, violet core, scattered stars"),
        ("moon_craters", "full moon extreme close up, detailed craters, black sky"),
        ("aurora_sky", "green and purple aurora borealis over snowy mountains, starry sky"),
    ],
    "city": [
        ("tokyo_rain", "tokyo street at night in rain, neon signs reflecting on wet asphalt, cyberpunk"),
        ("city_aerial", "aerial view of city grid at night, glowing streets, dark blue tones"),
        ("foggy_skyline", "foggy skyline at blue hour, skyscraper silhouettes, minimal"),
        ("cyberpunk_alley", "futuristic cyberpunk alley, purple and cyan neon, rain, cinematic"),
    ],
    "cars": [
        ("supercar_night", "sleek black supercar on wet city street at night, neon reflections"),
        ("classic_sunset", "classic vintage car on coastal road at sunset, warm tones"),
        ("sports_rain", "red sports car in the rain, dramatic lighting, close up"),
    ],
    "animals": [
        ("lion_portrait", "majestic lion portrait, golden light, dramatic, detailed fur"),
        ("wolf_snow", "lone wolf in snowy forest, misty, cinematic, moody"),
        ("eagle_flight", "bald eagle soaring against dramatic sky, wings spread"),
        ("tiger_close", "bengal tiger close up portrait, intense eyes, dark background"),
    ],
    "flowers": [
        ("cherry_blossom", "cherry blossom branches in full bloom, soft pink, dreamy bokeh"),
        ("rose_macro", "single red rose with water drops, dark background, studio macro"),
        ("lavender_field", "endless lavender field at sunset, purple hues, soft focus"),
    ],
}


def generate(prompt: str, seed: int) -> bytes:
    q = urllib.parse.quote(prompt + SUFFIX)
    url = (f"https://image.pollinations.ai/prompt/{q}"
           f"?width=1080&height=1920&nologo=true&model=flux&seed={seed}")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=150) as r:
        return r.read()


def main() -> None:
    made = skipped = failed = 0
    for category, items in PROMPTS.items():
        d = RAW / category
        d.mkdir(parents=True, exist_ok=True)
        for label, prompt in items:
            for s in range(SEEDS_PER_PROMPT):
                name = label if SEEDS_PER_PROMPT == 1 else f"{label}_{s + 1}"
                out = d / f"{name}.png"
                if out.exists():
                    skipped += 1
                    continue
                seed = abs(hash((label, s))) % 1_000_000
                ok = False
                for attempt in range(2):  # 1 retry
                    try:
                        data = generate(prompt, seed + attempt * 13)
                        img = Image.open(io.BytesIO(data)).convert("RGB")
                        img = img.resize(TARGET, Image.LANCZOS)
                        img.save(out)
                        made += 1
                        ok = True
                        print(f"✓ {category}/{name}")
                        break
                    except Exception as e:
                        if attempt == 1:
                            print(f"✗ {category}/{name}: {e}")
                    time.sleep(2)
                if not ok:
                    failed += 1
                time.sleep(1)  # xushmuomala pauza

    print(f"\nTayyor. Yangi: {made}, mavjud: {skipped}, xato: {failed}")
    print("Keyingi: python process_images.py && python generate_catalog.py && python upload_r2.py")


if __name__ == "__main__":
    main()

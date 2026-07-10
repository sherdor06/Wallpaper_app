#!/usr/bin/env python3
"""Protsedural (kod bilan) chiroyli wallpaperlar generatori — PIL only.

Gradient / AMOLED / abstract / minimal turlarini 4K vertikal (2160x3840) PNG qilib
`raw/<category>/` ga yozadi. Keyin process_images.py + generate_catalog.py + upload_r2.py.
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SCRIPT_DIR = Path(__file__).resolve().parent
RAW = SCRIPT_DIR / "raw"
W, H = 2160, 3840


def hx(c: str) -> tuple[int, int, int]:
    c = c.lstrip("#")
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16))


def save(img: Image.Image, category: str, name: str) -> None:
    d = RAW / category
    d.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(d / f"{name}.png")
    print(f"  {category}/{name}")


def mesh_gradient(palette: list[str], grid=(3, 5), seed=0) -> Image.Image:
    """Random color grid -> smooth upscale = trendy mesh gradient."""
    random.seed(seed)
    cols, rows = grid
    colors = [hx(c) for c in palette]
    small = Image.new("RGB", (cols, rows))
    px = small.load()
    for y in range(rows):
        for x in range(cols):
            px[x, y] = random.choice(colors)
    # Smooth blend at a medium size, then crisp upscale to 4K.
    mid = small.resize((720, 1280), Image.BICUBIC).filter(ImageFilter.GaussianBlur(40))
    return mid.resize((W, H), Image.LANCZOS)


def radial_glow(color: str, cx=0.5, cy=0.36, radius=0.55, bg="#05050A") -> Image.Image:
    """Pure-dark canvas with one soft glowing orb — AMOLED style."""
    base = Image.new("RGB", (W, H), hx(bg))
    # Build the glow small (fast) then upscale.
    s = 360
    glow = Image.new("L", (s, s), 0)
    gd = ImageDraw.Draw(glow)
    r = int(s * 0.5)
    for i in range(r, 0, -1):
        a = int(255 * (i / r) ** 0.4)  # bright center, soft falloff
        gd.ellipse([s / 2 - i, s / 2 - i, s / 2 + i, s / 2 + i], fill=255 - a)
    glow = glow.filter(ImageFilter.GaussianBlur(24))
    gw = int(W * radius * 2)
    glow_big = glow.resize((gw, gw), Image.LANCZOS)
    col = Image.new("RGB", (gw, gw), hx(color))
    base.paste(col, (int(W * cx - gw / 2), int(H * cy - gw / 2)), glow_big)
    return base


def diagonal_waves(palette: list[str], seed=0) -> Image.Image:
    """Soft overlapping color blobs -> abstract gradient art."""
    random.seed(seed)
    colors = [hx(c) for c in palette]
    base = Image.new("RGB", (W, H), colors[-1])
    layer = Image.new("RGB", (W, H), colors[-1])
    ld = ImageDraw.Draw(layer)
    for i in range(5):
        col = colors[i % (len(colors) - 1)]
        cx = random.randint(0, W)
        cy = random.randint(0, H)
        rr = random.randint(W // 2, W)
        ld.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(320))
    return Image.blend(base, layer, 0.9)


def duotone(top: str, bottom: str) -> Image.Image:
    """Clean vertical two-color gradient — minimal."""
    t, b = hx(top), hx(bottom)
    small = Image.new("RGB", (2, 256))
    px = small.load()
    for y in range(256):
        f = y / 255
        px[0, y] = px[1, y] = (
            round(t[0] + (b[0] - t[0]) * f),
            round(t[1] + (b[1] - t[1]) * f),
            round(t[2] + (b[2] - t[2]) * f),
        )
    return small.resize((W, H), Image.LANCZOS)


def main() -> None:
    print("Generatsiya:")

    # --- gradient/ (mesh) ---
    meshes = {
        "violet_dream": ["#6C5CE7", "#4834D4", "#0E0E12", "#8E7CF0"],
        "aurora": ["#22D3EE", "#A78BFA", "#34D399", "#0E1630"],
        "sunset": ["#FF6B6B", "#FFD93D", "#6C5CE7", "#2D1B4E"],
        "ocean": ["#0EA5E9", "#2563EB", "#38BDF8", "#0E1A2B"],
        "rose": ["#F472B6", "#FB7185", "#FDA4AF", "#2A0E1E"],
        "cyber": ["#EC4899", "#8B5CF6", "#06B6D4", "#0E0E12"],
    }
    for i, (name, pal) in enumerate(meshes.items()):
        save(mesh_gradient(pal, seed=i * 7 + 1), "gradient", name)

    # --- amoled/ (glow on black) ---
    glows = {
        "violet_glow": "#6C5CE7",
        "cyan_glow": "#22D3EE",
        "magenta_glow": "#EC4899",
        "amber_glow": "#F59E0B",
        "emerald_glow": "#10B981",
    }
    for name, col in glows.items():
        save(radial_glow(col), "amoled", name)

    # --- abstract/ (blobs) ---
    absts = {
        "nebula": ["#8B5CF6", "#EC4899", "#22D3EE", "#0E0E12"],
        "lava": ["#FF6B6B", "#F59E0B", "#B45309", "#1A0A06"],
        "mint": ["#34D399", "#22D3EE", "#A78BFA", "#0A1512"],
        "dusk": ["#6C5CE7", "#F472B6", "#2563EB", "#0E0E12"],
    }
    for i, (name, pal) in enumerate(absts.items()):
        save(diagonal_waves(pal, seed=i * 11 + 3), "abstract", name)

    # --- minimal/ (duotone) ---
    duos = {
        "violet_fade": ("#8E7CF0", "#0E0E12"),
        "peach_fade": ("#FDA4AF", "#2A0E1E"),
        "sky_fade": ("#38BDF8", "#0E1A2B"),
        "sand_fade": ("#FCD34D", "#1A1206"),
    }
    for name, (top, bot) in duos.items():
        save(duotone(top, bot), "minimal", name)

    print("Tayyor.")


if __name__ == "__main__":
    main()

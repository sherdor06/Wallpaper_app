"""Bake seamless, lit fractal cloud density once, never on animation frames.

Requires Pillow. Run from the project root; no source photos or network used.
Both Flutter and the native Android wallpaper consume the same small texture.
"""
from pathlib import Path
import math
import random

from PIL import Image

WIDTH, HEIGHT = 768, 384
rng = random.Random(38401)
grids = []
for octave in range(6):
    nx, ny = 4 * 2**octave, 3 * 2**octave
    grids.append((nx, ny, [[rng.random() for _ in range(nx)] for _ in range(ny + 1)]))


def smooth(v):
    return v * v * (3 - 2 * v)


def noise(x, y):
    total, weight = 0.0, 0.0
    for level, (nx, ny, grid) in enumerate(grids):
        gx, gy = x * nx, y * ny
        ix, iy = math.floor(gx), min(ny - 1, math.floor(gy))
        fx, fy = smooth(gx - ix), smooth(gy - iy)
        a, b = grid[iy][ix % nx], grid[iy][(ix + 1) % nx]
        c, d = grid[iy + 1][ix % nx], grid[iy + 1][(ix + 1) % nx]
        amplitude = .52**level
        total += ((a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy) * amplitude
        weight += amplitude
    return total / weight


def generate():
    density = []
    for y in range(HEIGHT):
        v = (y + .5) / HEIGHT
        envelope = math.sin(math.pi * v)**.8
        row = []
        for x in range(WIDTH):
            n = noise(x / WIDTH, v)
            value = max(0, min(1, (n * .85 + envelope * .45 - .49) * 3.7))
            row.append(smooth(value) * smooth(min(1, envelope * 2.2)))
        density.append(row)
    pixels = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            d = density[y][x]
            # Upper-left illumination and denser, cooler cloud bellies.
            edge = d - density[max(0, y - 6)][(x - 5) % WIDTH]
            light = max(155, min(251, 235 - d * 48 + edge * 115))
            pixels.append((int(light * .95), int(light * .98), int(light), round(d * 255)))
    image = Image.new('RGBA', (WIDTH, HEIGHT))
    image.putdata(pixels)
    path = Path(__file__).resolve().parents[1] / 'assets/worlds/weather_clouds.png'
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    print(f'{path}: {path.stat().st_size:,} bytes')


if __name__ == '__main__':
    generate()

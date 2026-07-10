# Wallpaper generatsiya promptlari — "Wallpapers 4K"

> Birinchi katalogni to'ldirish uchun tayyor AI promptlar. Har promptdan 3–5 variant
> generatsiya qiling — eng yaxshilarini tanlaysiz. Maqsad: boshlash uchun **50–100 rasm**.

## Qayerda generatsiya qilish (bepul boshlash)

| Vosita | Izoh |
|---|---|
| **Bing Image Creator** (bing.com/create) | Bepul, DALL-E asosida, tez |
| **Ideogram.ai** | Bepul tarif bor, sifat yuqori |
| **Leonardo.ai** | Bepul kunlik limit, "Leonardo Diffusion XL" yaxshi |
| **Claude design / boshqa** | Qo'lingizda bori |

⚙️ **Sozlama:** aspect ratio **9:16 (vertikal / portrait)** tanlang — telefon ekrani.
Iloji boricha eng katta o'lchamni tanlang (pipeline o'zi 4K'gacha saqlaydi, kichraytiradi).

## Fayl nomlash va joylash

Yuklab olgan rasmlarni shunday joylang (nom oddiy lotincha, bo'shliqsiz):

```
scripts/raw/nature/misty_forest.png
scripts/raw/nature/alpine_lake.png
scripts/raw/abstract/neon_waves.png
scripts/raw/amoled/minimal_moon.png
scripts/raw/space/nebula_purple.png
scripts/raw/city/tokyo_night.png
scripts/raw/minimal/dune_lines.png
```

Keyin menga "tayyor" deysiz — men pipeline'ni ishga tushiraman
(`process → generate → upload`) va hammasi R2/ilovada paydo bo'ladi.

---

## PROMPTLAR (har biri oxiriga qo'shing: `vertical wallpaper, 9:16, ultra detailed, high resolution, no text, no watermark`)

### 🌲 nature/
1. `Misty pine forest at dawn, layers of fog between dark green trees, soft god rays, moody atmosphere`
2. `Crystal clear alpine lake reflecting snowcapped mountains at golden hour, dramatic sky`
3. `Tropical beach from above, turquoise water meeting white sand, aerial drone view`
4. `Autumn forest path covered in orange leaves, warm sunlight filtering through trees`
5. `Powerful ocean wave curling at sunset, backlit spray, deep blue and amber tones`

### 🎨 abstract/
1. `Flowing liquid gradient waves, deep violet and indigo silk fabric texture, elegant, dark background`
2. `Abstract 3D glass shapes with iridescent refraction, floating on dark gradient, studio lighting`
3. `Smooth neon light trails curving through darkness, purple and cyan, long exposure style`
4. `Marble ink swirls, gold veins on deep navy, luxury texture, macro`
5. `Geometric low-poly mountains, dark purple gradient palette, clean modern illustration`

### ⚫ amoled/ (asosan qora — OLED uchun)
1. `Single thin crescent moon line art, glowing white on pure black background, ultra minimal`
2. `Tiny glowing purple orb in vast pure black space, extreme minimalism, OLED wallpaper`
3. `Faint constellation lines and dots, pure black background, subtle white glow, minimal`
4. `One neon purple lightning bolt on pure black, sharp, high contrast, minimal`
5. `Silhouette of mountain ridge bottom edge only, pure black sky with single star`

### 🌌 space/
1. `Purple and pink nebula with bright star cluster, deep space, hubble photography style`
2. `Earth horizon from orbit at night, city lights glowing, stars above, cinematic`
3. `Spiral galaxy viewed from above, violet core, scattered stars, deep black space`
4. `Astronaut silhouette floating toward glowing purple portal in space, surreal, cinematic`
5. `Full moon extreme close-up, detailed craters, on deep black sky`

### 🏙 city/
1. `Tokyo street at night in rain, neon signs reflecting on wet asphalt, cyberpunk mood, cinematic`
2. `Aerial view of city grid at night, glowing streets like circuits, dark blue tones`
3. `Foggy skyline at blue hour, skyscraper silhouettes, minimal color palette`
4. `Old European narrow street at dusk, warm lanterns, cobblestones, atmospheric`
5. `Futuristic city with flying vehicles at sunset, purple orange sky, sci-fi concept art`

### ▫️ minimal/
1. `Sand dune curves, soft beige gradient, extreme minimalism, zen, negative space`
2. `Single green leaf with water drops on pastel background, studio macro, clean`
3. `Smooth gradient from deep violet to soft peach, grain texture, nothing else`
4. `Paper layers cut art, monochrome purple shades, abstract landscape, flat design`
5. `Lone small boat on vast calm water, fog, japanese minimalism, muted tones`

### 🎬 live/ (video — ixtiyoriy, keyinroq ham bo'ladi)
Video generatsiya (Runway/Pika/Kling — bepul limitlar) yoki litsenziyali stock
(pexels.com/videos — bepul, litsenziya toza). Vertikal, 5–15s, loop'ga mos:
1. `Slow ocean waves rolling at sunset, seamless loop, vertical`
2. `Purple ink drop spreading in water, slow motion, dark background, loop`
3. `Rain drops sliding down glass at night, bokeh city lights behind, loop`
Fayl: `scripts/raw/live/<nom>.png` (poster kadri) + video `scripts/out/live/<nom>.mp4`.

---

## Litsenziya eslatmasi
- **AI generatsiya** — o'zingiz yaratdingiz, muammo yo'q (vositaning shartlarini bir ko'ring).
- **Unsplash/Pexels** — bepul va tijoriy foydalanish mumkin, lekin "urniga sotish"
  taqiqlariga e'tibor bering; AI generatsiya xavfsizroq va noyob.
- Boshqa saytlardan (Pinterest, Google Images) **olmang** — mualliflik huquqi buzilishi
  Play Store'dan uchirilishga olib keladi.

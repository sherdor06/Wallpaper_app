# Design prompts — "Wallpapers 4K"

> Claude design'ga ko'chirib qo'yish uchun tayyor promptlar. Har birini alohida
> suhbatda yuboring. Natijalarni `design/` papkaga saqlang — integratsiyani men qilaman.

---

## PROMPT 1 — App icon

```
Design a professional mobile app icon for "Wallpapers 4K" — a wallpaper app for
Android and iOS with a premium dark aesthetic and liquid-glass UI.

BRAND
- Primary accent: #6C5CE7 (violet)
- Deep accent: #4834D4
- App background (dark): #0E0E12
- Personality: modern, minimal, premium — think high-end photography / OLED wallpapers.

CONCEPT
An abstract, instantly readable symbol of "beautiful imagery / wallpaper":
a minimal landscape mark (mountain + sun), a stylized stack of photo cards, or an
abstract "4K frame" — pick the strongest single idea. No text, no letters, no
photo-realism. One clear silhouette that stays readable at 48×48 px.

STYLE
- Flat with a subtle vertical or diagonal gradient (violet range #6C5CE7 → #4834D4).
- Optional soft inner glow / subtle depth, but no heavy shadows, no skeuomorphism.
- Full-bleed square design (the OS applies the mask: circle on Android, squircle on iOS)
  — keep the key silhouette inside the central ~66% safe zone.
- High contrast between glyph and background so it pops on any home screen.

DELIVERABLES (PNG, exact sizes)
1. icon.png — 1024×1024, full-bleed background + glyph (used for iOS and legacy Android).
2. icon_foreground.png — 1024×1024, TRANSPARENT background, glyph only, centered,
   glyph fits within the central 66% (Android adaptive icon foreground).
3. splash.png — 1024×1024, TRANSPARENT background, a single-color (white or very light)
   version of the glyph, centered at ~55% size (used on a #0E0E12 splash screen).

Show me 3 concept directions first as a grid, then produce the final 3 files for the
strongest one.
```

---

## PROMPT 2 — Lottie animation set (loading / splash / empty)

```
Create a cohesive set of 3 Lottie animations for "Wallpapers 4K" — a premium dark-themed
wallpaper app (Flutter). All three must share one visual system.

BRAND
- Primary accent: #6C5CE7 (violet), deep accent #4834D4, highlight white #FFFFFF.
- Shown on a very dark background (#0E0E12) — use colors that read clearly on dark.
- Personality: smooth, calm, premium. Easing: gentle ease-in-out, no bouncy cartoon physics.

THE SET
1. loading.json — a looping loader shown while the wallpaper catalog loads.
   - Concept: three rounded "photo cards" gently cycling/shuffling, or a soft violet
     orb morphing — subtle and hypnotic, not busy.
   - Duration: 1.5–2 s seamless loop. Canvas 200×200.
2. splash_logo.json — a one-shot logo reveal played once at app start.
   - Concept: the app's mountain/sun glyph drawing itself in / assembling from soft
     shapes, ending in the final still logo pose.
   - Duration: 2–2.5 s, ends on a hold frame. Canvas 400×400.
3. empty.json — a gentle ambient loop for empty states ("No favorites yet",
   "Nothing found").
   - Concept: an empty picture frame or photo stack with a slowly drifting
     sparkle/star, friendly but restrained.
   - Duration: 2–3 s seamless loop. Canvas 300×300.

TECHNICAL CONSTRAINTS (hard requirements — target the Flutter `lottie` package)
- Export as Lottie JSON (bodymovin schema).
- VECTOR SHAPES ONLY: no raster images, no embedded PNGs, no effects (blur/glow filters),
  no expressions, no masks-heavy tricks — plain shape layers, trims, and transforms.
- Transparent background in all three.
- Keep each file lightweight: under ~100 KB, 60 fps timeline.
- Name the files exactly: loading.json, splash_logo.json, empty.json.

Deliver each animation as a downloadable .json file, plus a short preview description.
```

---

## Integratsiya (dizayn tayyor bo'lgach)

1. **Ikonka:** 3 PNG'ni `assets/icon/` dagi shu nomli fayllar ustiga qo'ying, so'ng menga
   ayting — men `dart run flutter_launcher_icons` + `dart run flutter_native_splash:create`
   ni ishga tushirib, ikkala platformada tekshiraman.
2. **Lottie:** 3 JSON'ni `assets/anim/` papkaga qo'ying — men `lottie` paketini ulab,
   loading/empty/splash joylariga integratsiya qilaman.

# Kontent pipeline — Cloudflare R2 + rasm tayyorlash

Bu papka ilovaga rasm yetkazib berish uchun. Oqim:

```
raw/ (xom rasm)  →  process_images.py  →  out/ (WebP + thumbnail)
                 →  generate_catalog.py →  out/catalog.json
                 →  upload_r2.py        →  Cloudflare R2 → CDN → Ilova
```

---

## A QISM — Cloudflare R2 ni noldan sozlash (BIR MARTALIK)

> Bu qismni **siz** qilasiz (shaxsiy akkaunt kerak). Karta so'raydi, lekin bepul
> tarif (10 GB) boshlanish uchun yetadi — pul yechilmaydi.

### 1. Akkaunt ochish
- https://dash.cloudflare.com → **Sign Up** (email + parol).

### 2. R2 ni yoqish
- Chap menyuda **R2 Object Storage** → **Enable / Purchase R2**.
- Karta qo'shishni so'raydi (bepul tarif uchun ham majburiy). Qo'shing — bepul
  limit ichida pul yechilmaydi.

### 3. Bucket yaratish
- **R2 → Create bucket**.
- Nom: **`wallpapers`** (yoki xohlagan nom — keyin `.env` da shu nomni yozasiz).
- Location: **Automatic** → **Create bucket**.

### 4. API token (skript uchun kalit)
- **R2 → Manage R2 API Tokens → Create API Token**.
- Permission: **Object Read & Write**.
- Bucket: faqat `wallpapers` (xavfsizroq) yoki barchasi.
- **Create** → ekranda chiqadi (FAQAT BIR MARTA ko'rsatiladi, ko'chirib oling):
  - **Access Key ID**
  - **Secret Access Key**
  - **Account ID** (endpoint URL ichida: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`)

### 5. Public URL yoqish (dev/test uchun — r2.dev)
- `wallpapers` bucket → **Settings → Public access → R2.dev subdomain → Allow**.
- Sizga manzil beradi: **`https://pub-XXXXXXXX.r2.dev`** ← bu **CDN_BASE_URL**.
- ⚠️ r2.dev faqat test uchun (Cloudflare uni rate-limit qiladi). Production'da 6-qadam.

### 6. Custom domen (production — KEYINROQ)
- Domen Cloudflare'da bo'lishi kerak (~$10/yil).
- bucket → **Settings → Custom Domains → Connect Domain** → `cdn.sizningapp.com`.
- Shunda CDN + kesh avtomatik. `CDN_BASE_URL` = `https://cdn.sizningapp.com`.

---

## B QISM — Pipeline'ni ishlatish (HAR SAFAR yangi rasm qo'shganda)

### 1. Bir martalik tayyorgarlik
```bash
cd scripts
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env              # .env ni A-qism 4-qadamdagi kalitlar bilan to'ldiring
```

### 2. Rasmlarni joylash
Xom rasmlarni kategoriya papkalariga qo'ying:
```
scripts/raw/nature/sunset.jpg
scripts/raw/nature/forest.png
scripts/raw/abstract/neon.jpg
```
- Telefon uchun **vertikal** rasm tavsiya etiladi (9:16 yoki balandroq).
- Manba: AI generatsiya (Flux / SDXL / Midjourney) **yoki** litsenziyali (Unsplash/Pexels —
  litsenziyaga rioya qiling). Skript har qanday `.jpg/.png/.webp` bilan ishlaydi.

### 3. Ishga tushirish (ketma-ket)
```bash
python process_images.py     # raw/ → out/ (WebP _full + _thumb)
python generate_catalog.py   # out/ → out/catalog.json
python upload_r2.py --dry-run # nima yuklanishini ko'rish (ixtiyoriy)
python upload_r2.py          # R2'ga yuklash
```

### 4. Ilovani R2'ga ulab ishga tushirish
```bash
cd ..
flutter run --dart-define=CDN_BASE_URL=https://pub-XXXXXXXX.r2.dev
```
Endi galereya R2'dagi haqiqiy rasmlardan to'ladi. 🎉

---

## Jonli (live) wallpaper qo'shish
1. Poster (muqova) rasmni `raw/live/<nom>.png` ga qo'ying → `process_images.py`.
2. Video faylni qo'lda `out/live/<nom>.mp4` ga nusxalang (skript videoni teginmaydi).
3. `generate_catalog.py` uni avtomatik `type: "live"` deb belgilaydi.
> Eslatma: ilovada jonli fonni **o'rnatish** native qism hali tayyor emas (keyingi
> bosqich). Hozir live wallpaperlar katalogда ko'rinadi va premium sifatida belgilanadi.

## Premium (pullik) belgilash
`config.json` da boshqariladi:
- `premium_if_4k: true` → 4K rasmlar avtomatik premium.
- har kategoriya uchun `"premium": true/false` default.

## Muhim
- `.env`, `raw/`, `out/`, `venv/` git'ga tushmaydi (`.gitignore` da).
- `catalog.json` har upload'da yangilanadi (qisqa kesh) — yangi rasm tez ko'rinadi.
- Rasmlar uzoq keshlanadi (tez va arzon).

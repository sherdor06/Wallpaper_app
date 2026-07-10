# Wallpaper App — Rivojlantirish Rejasi

> MVP'dan to'liq monetizatsiya qilingan ilovaga o'tish rejasi.
> Bu fayl repo ildizida turadi va Claude Code uchun kontekst bo'lib xizmat qiladi.

---

## 1. Asosiy yondashuv

| Element | Yechim | Sabab |
|---|---|---|
| Rasmlar | AI bilan generatsiya | Litsenziya muammosi yo'q, noyob kontent, differensiatsiya |
| Saqlash | Cloudflare R2 | Egress bepul, $0.015/GB, S3-mos |
| Yetkazib berish | Cloudflare CDN (custom domen) | Edge kesh, tez, arzon |
| Katalog | JSON (R2'da) → keyin Supabase | Boshlash oson, keyin dinamik |
| Reklama | AdMob (`google_mobile_ads`) | Asosiy daromad |
| Obuna | RevenueCat (`purchases_flutter`) | Barqaror daromad |
| Maqsad | Foydalanuvchi yig'ish + Tier-1 trafik | eCPM 5-10x oshadi |

**Boshlang'ich kapital:** ~$25 (Google Play, bir martalik) + ~$10/yil domen + AI generatsiya uchun bir necha dollar. R2 bepul tarifi boshlanish bosqichini qoplaydi.

---

## 2. Texnik arxitektura (oqim)

```
AI generatsiya  →  Processing skript  →  R2 bucket  →  Cloudflare CDN  →  Flutter App
(Flux/SDXL)        (WebP, thumbnail,     (rasmlar)     (cdn.myapp.com)    (katalog JSON
                    4K upscale)                                            orqali o'qiydi)
```

- **Rasmlar** R2'da saqlanadi, CDN orqali uzatiladi.
- **Metadata** (ro'yxat, kategoriya, premium belgisi) JSON kataloglda.
- **Flutter** katalog JSON'ni o'qiydi → thumbnail ko'rsatadi → to'liq rasmni CDN'dan yuklaydi.

---

## 3. Tech stack

**Flutter paketlar:**
- `cached_network_image` — rasmlarni qurilmada keshlash (qayta yuklanmaydi)
- `dio` — HTTP / katalogni yuklash
- `get` (GetX) — state management *(sen allaqachon ishlatasan)*
- `google_mobile_ads` — AdMob reklama
- `purchases_flutter` — RevenueCat obuna/IAP
- `flutter_staggered_grid_view` — wallpaper grid (chiroyli)
- `hive` yoki `shared_preferences` — sevimlilar (lokal)
- `async_wallpaper` — wallpaper o'rnatish (faqat Android, pastga qara)

**Servislar:**
- Cloudflare R2 + CDN — storage + yetkazib berish
- Supabase (keyinroq) — dinamik katalog / foydalanuvchi ma'lumotlari
- Firebase Analytics — metrikalar (DAU, retention, yuklab olishlar)
- AdMob + RevenueCat — monetizatsiya

**Skriptlar (Python — Claude Code yozadi):**
- Rasm processing (Pillow): resize, WebP, thumbnail
- 4K upscale (Real-ESRGAN)
- R2 upload (boto3 yoki rclone)
- Katalog JSON generator

---

## 4. Bosqichlar

### Bosqich 0 — Poydevor (1-hafta)
- [ ] Cloudflare account ochish, R2 bucket yaratish
- [ ] Domen olish (~$10/yil) yoki mavjudini ishlatish
- [ ] Custom domenni bucket'ga ulash (`cdn.myapp.com`), public access yoqish
- [ ] R2 API token yaratish (skript uchun)
- [ ] Rasm spetsifikatsiyasini belgilash: format (WebP q~85), o'lchamlar (to'liq 4K, thumbnail ~400px)
- [ ] Kategoriyalar ro'yxatini belgilash (Nature, Abstract, Minimal, Dark/AMOLED, Anime, Gradient, Space...)
- [ ] Katalog JSON sxemasini belgilash (pastdagi namuna)

### Bosqich 1 — Kontent pipeline (1-2 hafta)
- [ ] AI generatsiya tanlash: **Flux.1** (Replicate/fal.ai API orqali, ~bir necha sent/rasm) yoki **SDXL** (lokal, bepul) yoki **Midjourney** (obuna, sifat yuqori)
- [ ] Aspekt nisbati: telefon uchun vertikal (9:19.5 yoki 9:16). Yuqori sifatda generatsiya → 4K'gacha upscale
- [ ] Har kategoriya uchun batch generatsiya (izchil promptlar bilan)
- [ ] **Claude Code:** processing skript — har rasmni `name_full.webp` + `name_thumb.webp` ga aylantiradi
- [ ] **Claude Code:** R2 upload skript (boto3) yoki rclone buyrug'i
- [ ] **Claude Code:** katalog JSON generator (rasmlar papkasidan avtomatik JSON yasaydi)
- [ ] **Maqsad:** birinchi 100-200 sifatli wallpaper R2'da, CDN orqali ochiladi

### Bosqich 2 — Ilovani qayta qurish (2-3 hafta)
- [ ] MVP'ni R2 katalogidan o'qishga o'tkazish (avvalgi manba o'rniga)
- [ ] Data layer: katalog repository (JSON yuklash + keshlash)
- [ ] Kategoriya ekrani + staggered grid (thumbnail'lar)
- [ ] Detail ekran: to'liq ko'rish, yuklab olish, set wallpaper, sevimliga qo'shish
- [ ] Sevimlilar (lokal saqlash)
- [ ] Qidiruv / filtr
- [ ] **Wallpaper o'rnatish — muhim cheklov:**
  - **Android:** `async_wallpaper` yoki platform channel orqali to'g'ridan-to'g'ri o'rnatiladi
  - **iOS:** Apple ilovaga programma orqali wallpaper o'rnatishga RUXSAT BERMAYDI. iOS'da faqat rasmni Photos'ga saqlaysan, foydalanuvchi o'zi qo'lda o'rnatadi. Buni UI'da hisobga ol.
- [ ] **Claude Code:** bu refaktor multi-file — Claude Code'ning kuchli tomoni

### Bosqich 3 — Monetizatsiya (3-4 hafta)
- [ ] AdMob hisob ochish, app qo'shish
- [ ] **Rewarded reklama:** premium rasmni ochish / vaqtincha reklamasiz rejim
- [ ] **Interstitial:** har N yuklab olishdan keyin (counter + remote config bilan boshqar)
- [ ] RevenueCat sozlash
- [ ] **Obuna:** haftalik/oylik/yillik — reklamasiz + barcha premium + 4K. Lifetime variant ham qo'sh
- [ ] Firebase Remote Config — reklama chastotasini redeploy'siz sozlash
- [ ] (Keyinroq) AppLovin MAX mediation — eCPM oshirish uchun
- [ ] **Claude Code:** ad/IAP integratsiya boilerplate'i

### Bosqich 4 — Sayqal va launch oldi (4-5 hafta)
- [ ] App icon, splash screen, onboarding
- [ ] **Privacy policy** (MAJBURIY — reklama data yig'adi, store'lar talab qiladi)
- [ ] Firebase Analytics eventlar: `wallpaper_view`, `wallpaper_download`, `wallpaper_set`, `ad_shown`, `subscription_started`
- [ ] **ASO (App Store Optimization):**
  - Sarlavhada kalit so'zlar ("HD Wallpapers 4K", "AMOLED Wallpapers"...)
  - Eng yaxshi wallpaper'lar bilan screenshot'lar
  - Tavsifda kalit so'zlar
  - **Tier-1 (AQSh/Yevropa) kalit so'zlar va lokalizatsiya** → eCPM bir necha barobar yuqori
- [ ] Store listing tayyorlash (Google Play, kerak bo'lsa App Store)

### Bosqich 5 — Launch va iteratsiya
- [ ] Soft launch (bitta mamlakat yoki kichik auditoriya)
- [ ] Metrikalarni kuzatish (pastga qara)
- [ ] Reklama chastotasini A/B test qilish
- [ ] Muntazam yangi kontent qo'shish (retention uchun muhim)
- [ ] O'sish: ASO takomillashtirish, ijtimoiy tarmoq, organik

---

## 5. Katalog JSON sxemasi (namuna)

```json
{
  "version": 3,
  "categories": [
    { "id": "nature", "name": "Nature", "icon": "..." },
    { "id": "amoled", "name": "AMOLED", "icon": "..." }
  ],
  "wallpapers": [
    {
      "id": "nature_001",
      "title": "Misty Mountains",
      "category": "nature",
      "thumb": "https://cdn.myapp.com/nature/001_thumb.webp",
      "full":  "https://cdn.myapp.com/nature/001_full.webp",
      "premium": false,
      "tags": ["mountain", "fog", "blue"]
    }
  ]
}
```

> Boshlanishda bu JSON R2'da turadi, ilova uni `dio` bilan yuklab oladi va keshlaydi.
> Keyinroq (dinamik like soni, foydalanuvchi sevimlilarini sinxron qilish, redeploy'siz kontent qo'shish kerak bo'lganda) — Supabase (Postgres) ga o'tasan.

---

## 6. Claude Code bilan qanday ishlash

**Bu faylni repo ildizida saqla** — Claude Code uni o'qib, butun loyiha kontekstini tushunadi.

**Claude Code uchun ideal vazifalar:**
- Python rasm pipeline skriptlari (processing, upscale, upload) — mukammal mos
- Katalog JSON generator
- Flutter multi-file refaktorlar (data layer, ekranlar)
- Ad / IAP integratsiya boilerplate
- Platform channel (Android wallpaper o'rnatish)

**Maslahatlar:**
- Har vazifani boshlashda Claude Code'ga katalog JSON sxemasini va R2 URL strukturasini ber.
- Mayda, aniq vazifalarga bo'l ("processing skript yoz" → "katalog generator yoz" → "detail ekranni R2'dan o'qishga o'tkaz"), bittada hammasini emas.
- **Muhim:** har bo'lakni o'zing ham tushunib bor — shunchaki kod qabul qilma. Bu loyiha sening portfolio'ng uchun kuchli signal: production ilova, object storage, CDN, IAP, reklama integratsiyasi — bularning hammasi to'liq-stavka Flutter ish qidiruvingda katta plus.

---

## 7. Kuzatiladigan metrikalar

| Metrika | Nima uchun muhim |
|---|---|
| DAU / MAU | Faol auditoriya hajmi (daromad shunga bog'liq) |
| Retention (D1/D7/D30) | Foydalanuvchilar qaytadimi? Kontent yangilanishi shunga ta'sir qiladi |
| Yuklab olish / foydalanuvchi | Engagement darajasi |
| eCPM (geo bo'yicha) | Reklama daromadi. Tier-1 = yuqori |
| Ad fill rate | Reklama to'ldirilishi |
| Obuna konversiyasi (%) | Premium daromad. 1-2% yaxshi natija |
| ARPU | O'rtacha foydalanuvchidan daromad |

---

## 8. Eslatma: eng katta xavf — pul emas, foydalanuvchi yig'ish

Infratuzilma xarajati to'g'ri qilinsa deyarli yo'q. Wallpaper ilovalari xarajatdan emas, foydalanuvchi yetishmasligidan "o'ladi". Shuning uchun Bosqich 4-5 (ASO, Tier-1 trafik, retention) — kod yozishdan kam emas, balki ko'proq e'tibor talab qiladi.

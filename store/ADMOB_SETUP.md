# AdMob sozlash — real reklama (Wallpapers 4K)

> Hozir ilova Google'ning TEST reklama ID'lari bilan ishlayapti. Bu qo'llanma bo'yicha
> o'z AdMob akkauntingizni ochib, real ID'larni olasiz — men ularni kodga qo'yaman.
> App ID va ad-unit ID'lar **maxfiy emas**, bemalol menga yuborasiz.

---

## A. Akkaunt ochish

1. **https://admob.google.com** → **Sign in** (Gmail bilan) → **Get started**.
2. Country/region: **Uzbekistan**, vaqt mintaqasi, valyuta — tanlang.
3. Shartlarga rozilik → akkaunt yaratildi.
   - To'lov/soliq ma'lumotlari keyin so'raladi (payout chegarasidan oldin) — hozir shart emas.

## B. Ilovani qo'shish (Android va iOS — ikkalasi alohida)

1. Chap menyu → **Apps** → **Add app**.
2. "Is your app listed on a supported app store?" → **No** (hali chiqarilmagan).
3. Platform: **Android** → App name: **Wallpapers 4K** → **Add app**.
4. Xuddi shu tarzda yana bir marta **iOS** uchun qo'shing (Add app → iOS → Wallpapers 4K).
5. Har biri sizga **App ID** beradi (tilda belgisi `~`):
   `ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY`
   → **Android App ID** va **iOS App ID** ni ko'chirib oling.

## C. Reklama birliklari (har ilova uchun 2 tadan)

Har bir ilova (Android, iOS) ichida **Ad units** → **Add ad unit**:

1. **Banner**:
   - Format: **Banner** → Name: `Home banner` → **Create ad unit**
   - Sizga **ad unit ID** beradi (belgisi `/`):
     `ca-app-pub-XXXXXXXXXXXXXXXX/BBBBBBBBBB`
2. **Interstitial**:
   - Format: **Interstitial** → Name: `Apply interstitial` → **Create ad unit**
   - Yana **ad unit ID** beradi.

Demak jami menga kerak bo'ladigan **6 ta qiymat**:

| # | Nima | Ko'rinishi |
|---|------|-----------|
| 1 | Android **App ID** | `...~...` |
| 2 | Android **Banner** unit | `.../...` |
| 3 | Android **Interstitial** unit | `.../...` |
| 4 | iOS **App ID** | `...~...` |
| 5 | iOS **Banner** unit | `.../...` |
| 6 | iOS **Interstitial** unit | `.../...` |

## D. Menga yuboring → men kodga qo'yaman

Bu 6 ta ID ni chatga yozing. Men:
- App ID'larni `AndroidManifest.xml` + `Info.plist` ga;
- Banner/Interstitial ID'larni `AdService` ga qo'yaman;
- **Debug rejimda TEST reklama, faqat release'da REAL reklama** ishlashini sozlayman —
  bu sizning akkauntingizni "invalid clicks" dan himoya qiladi (o'zingizning reklamangizni
  bosish taqiqlanadi, akkaunt bloklanishi mumkin).

## E. Muhim qoidalar (akkaunt bloklanmasligi uchun)
- **O'z reklamangizni bosmang** va boshqalarga ham aytmang. Google buni aniqlaydi.
- Test qilishda faqat TEST reklama ishlatiladi (biz shunday sozlaymiz).
- Reklamani ekranga sun'iy ravishda ko'p tiqmang (biz chastotani allaqachon chekladik).
- Play Store'ga chiqqach, AdMob ilovani do'kon bilan bog'lang ("app-ads.txt" so'ralishi mumkin).

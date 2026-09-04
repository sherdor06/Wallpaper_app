# Reklama sozlash — Wavely

Ilova reklamani **Yandex Mobile Ads** orqali to'g'ridan-to'g'ri ko'rsatadi
(mediation yo'q). AppLovin MAX rejasi publisher akkaunti ochilmagani uchun
to'xtatildi — pastda "Keyinga qoldirilgan" bo'limida.

---

## Holat

| Qism | Holat |
|------|-------|
| Yandex akkaunti + ilova (ID 19979404) | ✅ |
| Android ad unit'lar (banner / interstitial / rewarded) | ✅ |
| `yandex_mobileads: ^8.4.0` paketi | ✅ |
| `AdService` — init, consent, banner, interstitial, rewarded, chastota | ✅ |
| Banner widget (`AdWidget` + sticky banner) | ✅ |
| iOS ad unit'lar | ⏳ App Store'ga chiqqach |
| Play Console: privacy policy manzili | ✅ `wallpapers-cdn.pages.dev/privacy` |
| app-ads.txt | ✅ portfolio domenida jonli |
| GDPR consent oynasi | ✅ kodda — Firebase shartini qo'shish kerak |

## Ad unit ID'lar (Android)

| Format | Nom | ID |
|--------|-----|-----|
| Banner | Wavely Android Banner | `R-M-19979404-1` |
| Interstitial | Wavely Android Interstitial | `R-M-19979404-2` |
| Rewarded | Wavely Android Rewarded | `R-M-19979404-3` |

Kodda: `lib/services/ad_service.dart`. Yandex'da SDK key tushunchasi yo'q —
har so'rovda unit ID o'zi akkauntni aniqlaydi.

**Ilova ma'lumotlari:** `Wavely` · package `com.sherdor.wallpapers` ·
Yandex App ID `19979404` · privacy `https://wallpapers-cdn.pages.dev/privacy`

---

## Qolgan ishlar

### 1. ✅ app-ads.txt — joylandi

Jonli: `https://sherdor-portfolio.vercel.app/app-ads.txt`
(Yandex publisher ID `330661293`; `yandex.com` va `yango-ads.com` DIRECT
qatorlari + Yandex ruxsat bergan reseller'lar.)

**Nega aynan portfolio domeni:** crawler faylni Play Store listingidagi
*developer website* domenidan qidiradi, ilova CDN'idan emas. Listingda
`https://sherdor-portfolio.vercel.app/` turibdi, shuning uchun fayl o'sha
saytda bo'lishi shart.

Manba: `sherdor06/sherdor-portfolio` repo, `public/app-ads.txt` (Next.js
`public/` ni domen ildizida xizmat qiladi). Yangilash = faylni almashtirib,
`main` ga push — Vercel o'zi deploy qiladi.

`wallpapers-cdn.pages.dev/app-ads.txt` da ham nusxa bor. U ishlatilmaydi,
lekin zarar ham qilmaydi — Play listingidagi domen o'zgarsa asqotishi mumkin.

### 2. 🟠 Moderatsiya

Yandex'da ilova dastlab **Test mode** da bo'ladi: reklama ko'rinadi, lekin pul
hisoblanmaydi. Haqiqiy daromad moderatsiya va ilovaga egalik tasdiqlangandan
keyin boshlanadi. Partner interfeysida ilova statusini kuzatib boring.

### 3. 🟠 Firebase'da `consent_required` shartini yoqish

Consent oynasi kodda tayyor (`lib/services/consent_service.dart` +
`lib/ui/widgets/consent_dialog.dart`). Ishlashi:

| Foydalanuvchi | Nima bo'ladi |
|---|---|
| EEA/Britaniyadan tashqarida | Hech narsa so'ralmaydi, consent `true` → **personalizatsiyalangan reklama** |
| EEA/Britaniyada | Splash tugagach bir marta oyna chiqadi; javob berilmaguncha reklama SDK'si ishga tushmaydi |

Hudud ikki manbadan aniqlanadi:

1. **Firebase Remote Config** — `consent_required` (asosiy, aniq)
2. **Qurilma tili/regioni** — RC kelmasa ishlaydigan zaxira

**Sizdan talab qilinadigan qadam:** Firebase Console → Remote Config →
`consent_required` parametrini qo'shing (Boolean, default `false`), so'ng unga
**Condition** biriktiring:

- Condition nomi: `EEA and UK`
- Applies if: **Country/Region** → EEA 30 davlati + United Kingdom
- Value in this condition: `true`

Firebase mamlakatni server tomonda so'rovdan aniqlaydi — bu ilova ichidan
mavjud bo'lgan yagona ishonchli signal.

Shartsiz ham ilova ishlaydi: O'zbekistonda hech kim so'ralmaydi va reklama
personalizatsiyalanadi (ya'ni eCPM ko'tariladi), lekin EEA foydalanuvchisi
faqat qurilma tili orqali aniqlanadi.

> **Eslatma:** bu IAB TCF sertifikatlangan CMP emas. Yandex SDK'si bitta
> boolean qabul qiladi va shu to'ldiriladi. Bitta tarmoq uchun yetarli;
> mediation qo'shilsa yoki EEA trafigi jiddiy ulushga aylansa, haqiqiy CMP
> kerak bo'ladi.

Foydalanuvchi fikrini istalgan vaqtda o'zgartira oladi: Settings → **Ad
personalisation** (GDPR talabi — rad etish berish kabi oson bo'lishi shart).

### 4. ⏳ iOS

App Store'ga chiqqach: Yandex'da **alohida ilova** sifatida qo'shiladi (iOS
platformasi) va 3 ta yangi unit yaratiladi. ID'lar
`ad_service.dart` dagi `_bannerIos` / `_interstitialIos` / `_rewardedIos` ga
tushadi.

Hozir ular `YOUR_...` placeholder. `_credentialsMissing` **platformaga qarab**
ishlaydi, shuning uchun iOS build'i reklama so'ramaydi — bo'sh banner ham
ko'rinmaydi. iOS chiqishidan oldin `Info.plist` dagi SKAdNetwork ro'yxatiga
Yandex ID'lari qo'shilishi kerak (hozirgi ro'yxat AdMob davridan qolgan).

---

## Chastota sozlamalari (Firebase Remote Config)

Reklama zichligini kodni qayta chiqarmasdan o'zgartirasiz:

| Kalit | Default | Ma'nosi |
|-------|---------|---------|
| `ads_enabled` | true | Butun reklamani o'chiruvchi kill switch |
| `ad_show_every` | 3 | Har nechta apply/save'dan keyin interstitial |
| `ad_browse_every` | 8 | Har nechta shuffle'dan keyin interstitial |
| `ad_min_gap_seconds` | 45 | Ikki full-screen reklama orasidagi eng kam vaqt |
| `rewarded_required_for_4k` | true | 4K uchun rewarded majburiymi |
| `rewarded_required_for_fhd` | true | FHD uchun rewarded majburiymi |

---

## Test qilish

**O'z reklamangizni bosmang** — bu akkaunt yopilishining birinchi sababi.

- Reklamasiz build (do'kon skrinshotlari uchun):
  ```bash
  flutter build apk --release --dart-define=HIDE_ADS=true
  ```
- **Debug build har doim Yandex demo unit'larini ishlatadi**
  (`demo-banner-yandex`, `demo-interstitial-yandex`, `demo-rewarded-yandex`):
  ular moderatsiyasiz har doim to'ladi va haqiqiy statistikaga tegmaydi.
  Haqiqiy `R-M-...` ID'lar faqat release build'da ishlaydi.
- Integratsiyani tekshirish: `YandexAds.showDebugPanel()`. Kerak bo'lsa
  vaqtincha Settings sahifasiga chiqarib beraman.
- Debug build'da SDK logi yoqilgan (`YandexAds.setLogging(!kReleaseMode)`).

---

## Keyinga qoldirilgan: AppLovin MAX

Sabab: `dash.applovin.com` (publisher tomoni) da akkaunt ochilmadi — advertiser
kabineti `ads.applovin.com` bilan aralashib ketdi, ular alohida tizim.

Qaytarish qiyin emas: `AdService` ning tashqi interfeysi tarmoqqa bog'liq emas
(`adsAllowed`, `bannerUnitId`, `maybeShowInterstitial`,
`maybeShowInterstitialOnBrowse`, `showRewardedToUnlock`, `rewardedAvailable`),
shuning uchun mediation qaytarilsa faqat shu bitta fayl va banner widget
o'zgaradi — UI'ga tegilmaydi. Yandex esa MAX ichida bidder sifatida
ishlatiladi va yuqoridagi `R-M-...` ID'lar o'sha yerga kiritiladi.

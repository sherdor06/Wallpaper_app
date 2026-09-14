# Wavely — loyiha qoidalari

Bu fayl har sessiya boshida o'qiladi. Qoida — qaror, izoh emas. Yangi qaror
chiqsa shu yerga qo'shiladi; eskirgani o'chiriladi.

## Til

- Chat — o'zbek. Kod, Dart izohlari, UI matnlari, commit xabarlari — ingliz.

## Platformaga moslashuv

- Uch tomonlama bo'linish, hamma joyda bir xil:
  - **iOS 26+** → `cupertino_native_better` (`CN*`) — tizimning o'z kontroli.
  - **iOS < 26** → oddiy Cupertino (`CupertinoSwitch`, `CupertinoListTile`…).
  - **Android** → Material yoki solid pill (`_solidDecoration`).
- Istisno: tepadagi floating qator (`TitlePill`, `ChromeIconButton`,
  `SegmentedPill`) iOS'ning **hamma** versiyasida `liquid_glass_widgets`.
  `CN*` faqat tab bar va Settings kontrollari uchun.
- Sahifa kodi platformani tekshirmaydi. Moslashuv primitivlarda:
  `lib/ui/widgets/adaptive_settings.dart`, `lib/ui/widgets/floating_chrome.dart`.
  Sahifada `Platform.isIOS` ko'rinsa — bu xato.
- Tizim kontrollari tizim rangida qoladi (iOS switch — yashil). Ilova aksenti
  (`#6C5CE7 → #8E7BF5`) faqat ilova o'zi chizgan elementlarda.
- Yangi qayta ishlatiladigan chrome widget → `floating_chrome.dart` ga.
- `SegmentedPill` — istalgan joyi bosilsa keyingisiga o'tadi; segmentlar
  alohida nishon emas. 2–3 element uchun; forma kontroli sifatida ishlatilmaydi.

## Bosh ekran va kontent

- Ikki layout: Editorial (hero + qatorlar + grid) va Collections (kategoriya
  kartalari). Tanlov `HomeLayoutService` da saqlanadi. Chip qatori yo'q.
- Hero va muqova avto-nomli rasmlarni chetlab o'tadi (`Wallpaper.isAutoTitled`:
  "Cars 41", "Img" kabi) — ular ko'pincha noto'g'ri kategoriyada.
- 12 tadan kam rasmi bor kategoriya to'plam kartasi olmaydi.
- `addedAt` hozircha yo'q → "New" bo'limi qilinmaydi. Kelajakda kerak bo'lsa
  `generate_catalog.py` avvalgi katalogdan sanani saqlab qolishi shart.
- Kategoriya nomi auditoriyani emas, estetikani bildiradi ("Aesthetic",
  "Girls" emas).

## Reklama

- Yandex Mobile Ads to'g'ridan-to'g'ri, mediation yo'q. `AdService` interfeysi
  tarmoqdan mustaqil — tarmoq almashsa faqat shu fayl o'zgaradi.
- Debug → `demo-*-yandex` unit'lar. Release → `R-M-19979404-1/2/3`.
- **Release build'da reklamani hech qachon bosmaslik.**
- Banner navbar ustida, 50dp, inline. Qo'lda refresh qo'shilmaydi — SDK o'zi
  60s da yangilaydi.
- **Debug build simulyator/emulyatorda banner yashirin** (`AdService.
  bannerSuppressed`, native `isEmulator` orqali). `kDebugMode` bilan
  qo'riqlangan — release'da bu kod umuman yo'q. Interstitial va rewarded
  ta'sirlanmaydi. Bannerni simulyatorda ko'rish kerak bo'lsa — release APK.
- Consent faqat EEA/UK da so'raladi; boshqa joyda `true`.
- Chastota Remote Config'da: `ad_show_every`, `ad_browse_every`,
  `ad_min_gap_seconds`. Kamida bir haftalik ma'lumotsiz o'zgartirilmaydi.

## Git

- Commit erkin, mantiqiy o'zgarish boyicha bittadan.
- **Push faqat foydalanuvchi aytganda.** Hech qachon o'z-o'zidan emas.
- Commit xabari: qisqa sarlavha + *nima uchun* (sabab, kontekst), ingliz tilida.
  "Fixed bug" emas — qanday bug, nega shunday tuzatildi.

## Tekshirish

- `flutter analyze` toza bo'lmaguncha commit yo'q.
- UI o'zgarishi → ikkala platformada ko'rish: iOS simulyator (iPhone 17 Pro,
  iOS 26) va Android emulator (`emulator-5554`). Faqat bittasida ko'rib
  "tayyor" deyilmaydi.
- iOS < 26 ko'rinishi simulyatorda yo'q — kod yo'li oddiy bo'lsa, analyze
  bilan cheklanadi va shu aytiladi.
- Testlar hozircha yozilmaydi.
- `AndroidManifest.xml` izohlarida `--` ishlatilmaydi — XML buni taqiqlaydi va
  Android build butunlay yiqiladi (iOS sezmaydi).

## Loyiha faktlari

- Play Store'da jonli: `1.0.1+4`. Keyingi release: `1.0.2+5` (share, App Links,
  push, yangi bosh ekran, Settings).
- Bundle/package: `com.sherdor.wallpapers` (ikkala platformada).
- CDN: `wallpapers-cdn.pages.dev`, `scripts/out` dan `wrangler pages deploy`.
  `scripts/site/` (w.html, _redirects, assetlinks) deploy'dan oldin `out/` ga
  nusxalanadi — `out/` gitignore'da.
- `app-ads.txt` bu repoda emas: `sherdor06/sherdor-portfolio` → `public/`.
- Privacy: `https://wallpapers-cdn.pages.dev/privacy`.
- Yandex: app ID `19979404`, publisher `330661293`. Moderatsiya o'tgan.

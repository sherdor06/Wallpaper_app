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
  `ChromeSearchField`) iOS'ning **hamma** versiyasida `liquid_glass_widgets`.
  `CN*` faqat tab bar va Settings kontrollari uchun. `SegmentedPill` bundan
  mustasno — ikkala platformada bir xil solid pill (pastda).
- Sahifa kodi platformani tekshirmaydi. Moslashuv primitivlarda:
  `lib/ui/widgets/adaptive_settings.dart`, `lib/ui/widgets/floating_chrome.dart`.
  Sahifada `Platform.isIOS` ko'rinsa — bu xato.
- Tizim kontrollari tizim rangida qoladi (iOS switch — yashil). Ilova aksenti
  (`#6C5CE7 → #8E7BF5`) faqat ilova o'zi chizgan elementlarda.
- Yangi qayta ishlatiladigan chrome widget → `floating_chrome.dart` ga.
- `SegmentedPill` — 2–3 element uchun; forma kontroli sifatida ishlatilmaydi.
  Ikkala platformada bir xil, glass yo'q: istalgan joyi bosilsa keyingisiga
  o'tadi; aksent disk siljimaydi, *cho'ziladi* (oldingi chet avval ketadi,
  orqa chet keyin yetib keladi — bir zum ikki o'rinni qoplagan kapsula),
  kelgan glyph kichik burilish bilan "pop" qiladi, ketgani xiralashadi.

## Bosh ekran va kontent

- Ikki layout: Editorial (hero + qatorlar + grid) va Collections (kategoriya
  kartalari). Tanlov `HomeLayoutService` da saqlanadi. Chip qatori yo'q.
- Hero va muqova avto-nomli rasmlarni chetlab o'tadi (`Wallpaper.isAutoTitled`:
  "Cars 41", "Img" kabi) — ular ko'pincha noto'g'ri kategoriyada. Avto-nomli
  hero sarlavhasi kategoriya nomi ("Sport"), pastida "Wallpaper of the day".
- 12 tadan kam rasmi bor kategoriya to'plam kartasi ham, spotlight ham olmaydi
  (`kMinCollectionSize`, `Collection.isDestination`).
- To'plam bitta model: `models/collection.dart` `Collection` (id, name,
  tagline, items, `cover`). Katalogdan `Catalog.collection(id)` yoki
  `Catalog.destinations()` bilan olinadi — sahifada `wallpapers.where(...)`
  yozilmaydi (guruhlash katalogda bir marta hisoblanadi). To'plam sahifasi
  `openCollection(context, c)` bilan ochiladi, rasm — `openWallpaper`.
- Thumbnail har joyda `WallpaperThumb` (`widgets/wallpaper_thumb.dart`):
  `CachedNetworkImage` + `AppCache.thumbs` boilerplate qayta yozilmaydi.
- Ilova aksenti `ui/accent.dart` (`kAccent`, `kAccentLight`,
  `kAccentGradient`); fayl ichida `const _accent = Color(0xFF6C5CE7)`
  ko'rinsa — xato.
- Spotlight ("New collection" kartasi, hero ostida) Remote Config
  `featured_category` dan. Bo'sh → karta yo'q. Yangi to'plam chiqqanda konsolda
  id yoziladi, eskirgach tozalanadi — release kerak emas.
- Hero ostida `CategoryCarousel`: 8 ta to'plam, o'rtadagisi fokusda (164×92,
  qo'shnilar 0.86, halqasiz), har 4 s o'zi suriladi (teginilsa 6 s to'xtaydi),
  cheksiz aylanadi. Sig'magan tagline fokusdagi kartada ticker bo'lib aylanadi
  (keskin kesim, fade yo'q); bir aylanib boshiga kelmaguncha karusel kutadi.
  Ro'yxat va tartib Remote Config `home_strip` (vergul bilan id'lar); 12 tadan
  kam rasmli id tashlab ketiladi, 2 tadan kam qolsa karusel chiqmaydi.
- Rasm soni hech qayerda ko'rsatilmaydi. Nom ostida tagline — `config.json`
  `categories.<id>.tagline`, katalog bilan keladi; yo'q bo'lsa qator tushib
  qoladi.
- Har kategoriya `CollectionPage` ochadi (muqova + nom + tagline + kayfiyat
  chiplari). `CategoryPage` yo'q. Chiplar katalogdagi `moods` dan
  (`light/dark/vivid/mono`, `generate_catalog.py` rangdan hisoblaydi);
  kamida 2 ta kayfiyat 6+ rasm bilan bo'lmasa chip qatori chiqmaydi.
- To'plam aksenti `collection_accent.dart` da, ro'yxat qisqa qoladi: `girly`
  (pushti) va `aesthetic` (lavanda). Aksent to'plam sahifasi, uning bo'lim
  sarlavhasi va spotlight chipida — boshqa joyda ilova binafshasi.
- Editorial qatorlar tartibi: Girly, Aesthetic, Popular, Nature, Space. Bo'sh
  kategoriya qatori ko'rinmaydi — kontentdan oldin qo'shib qo'yish mumkin.
- Qatorda: sarlavha, "See all ›" pill va oxirgi "See all" kartasi to'plamni
  ochadi; rasm o'zining detail sahifasini ochadi.
- Pastki bar hamma platformada Home / Favorites / Settings; **Archive —
  tepadagi chrome tugmasi** (iOS'da ham). Archive tab emas.
- Qidiruv platformaga qarab joylashadi: **iOS 26+** — `CNTabBar` `split: true,
  rightCount: 1`: Search o'ngda alohida glass pill (4-tab, `SearchPage(asTab:
  true)`: maydon tepada, orqaga tugma yo'q); **Android va iOS < 26** —
  chrome'dagi lupa tugma → `SearchPage` (orqaga + `ChromeSearchField`).
  Ikkala yo'l bitta `SearchBody` va `SearchService.search`. Paketning
  `CNTabBar.searchItem` (native search roli) ishlatilmaydi: iOS 27 da maydon
  chiqmadi va aktivlik xabari kelmadi.
- Simulyatorda native tab bar'ga `tap` yetib bormaydi — `touch_path` bilan
  ~100 ms bosish kerak.
- Qidiruv — tez filtr, matn indeksi emas: so'zlar to'plam nomi/tagline'i,
  kayfiyat, va tag'lardagi so'zlarga tegadi; har so'z rasmga mos kelishi
  shart (AND). Natija tepasida faqat natijani shakllantirgan filtrlar teg
  bo'lib ko'rinadi. Oxirgi 8 qidiruv `search_recent.json` da.
- `addedAt` hozircha yo'q → "New" bo'limi qilinmaydi. Kelajakda kerak bo'lsa
  `generate_catalog.py` avvalgi katalogdan sanani saqlab qolishi shart.
- Kategoriya nomi auditoriyani emas, estetikani bildiradi: "Girly" (qizlarcha
  uslub) — "Girls" emas. `girly` = pushti/kawaii/bantik; `aesthetic` = umumiy
  estetik fotolar (mushuk, qahva, sokin manzara).

## Wavely Worlds

- Worlds = foydalanuvchi rasmi (yoki `assets/worlds/` sahnasi) + ob-havo /
  palitra / harakat sozlamalari (`WorldSettings`). Chizish bitta joyda —
  `WorldPainter` (`ui/worlds/world_scene.dart`): jonli sahna, muqova, still
  eksport va video kadrlar hammasi shundan; `time` bo'yicha deterministik.
  Android `WorldWallpaperService.kt` shu chizishning native nusxasi — rang
  koeffitsientlari va zarrachalar ikkalasida bir xil tutiladi.
- "Jonli" ikki xil, platformaga qarab:
  - **Android** — dunyo *o'zi* wallpaper: `setWorldWallpaper` → tizim
    preview → foydalanuvchi tasdiqlaydi (`supportsLiveWallpaper`).
  - **iOS** — hech qanday ilova wallpaper o'rnata olmaydi; dunyo Photos'ga
    **Live Photo** bo'lib saqlanadi (`supportsLivePhoto`,
    `WorldsService.saveLivePhoto` → `LivePhotoWriter.swift`), foydalanuvchi
    Photos'da Lock Screen qilib tanlaydi. Lock Screen harakati har bir iOS
    versiyasida kafolatlanmaydi — haqiqiy telefonda alohida tekshiriladi.
    Klip 2 s, 30 fps, balandligi 2304 px, H.264 MOV; still — klipning
    **o'rta** kadri, video bilan bir xil o'lchamda. Kadrlar Dart'da render
    qilinib raw RGBA holida bittalab
    kanal orqali yuboriladi (`livePhotoBegin/Frame/Finish/Cancel`), native
    tomonda BGRA'ga o'girilib encoder'ga beriladi. JPEG'dagi Apple maker
    note `17` va MOV'dagi `content.identifier` + `still-image-time` treki —
    Photos juftlashtirishi uchun shart; bularsiz oddiy rasm + video bo'ladi.
  - Ikkalasida ham "Save image" (still) va "Share image" qoladi.
- Animatsiya widget daraxtini qayta qurmaydi: faqat canvas, 30 fps;
  sahifa ko'rinmaganda, fonda yoki harakat o'chirilganda ticker to'xtaydi.
  Live Photo progressi alohida notifier'da; butun editor har kadrda rebuild
  bo'lmaydi. Bir paytda faqat bitta eksport; encoder kutishi chegaralangan,
  xato/ruxsat rad etilganda vaqtinchalik fayllar tozalanadi.
- Kutubxona fonda yuklanadi; uni ochgan sahifa tayyor bo'lishini kutadi.
  Saqlangan ro'yxat o'zgarmas snapshot: faqat yozilganda yangilanadi,
  grid katagini chizish uchun har safar butun ro'yxat nusxalanmaydi.
- Yangi Swift fayl Xcode target'ga `xcodeproj` gem bilan qo'shiladi
  (CocoaPods bilan keladi), pbxproj qo'lda tahrirlanmaydi.

## Kontent manbalari

- Faqat Telegram. Hashtag'li (odatiy rejim): `@iphonefotohd`, `@phone_wallps`.
  Hashtag'siz (`--channel ... --as <cat>`): `@Prinssec_Walpaper` → aesthetic
  (CLIP taklif bilan), `@Cute_Girly_Walpaper` → girly (`--no-suggest`: kanal
  o'zi kategoriya, 90 ta rasm — tugagan). Openverse/stock (`fetch_stock.py`) va generatsiya
  (`gen_wallpapers.py`) katalogga kirmaydi — ularning 173 ta rasmi
  `scripts/review/.retired/` ga chiqarilgan (o'chirilmagan), kategoriya
  papkalari (`minimal`, `mountains`, …) bo'sh bo'lsa ham `raw/` da qoladi.
- Har rasm foydalanuvchi tomonidan tasdiqlanadi: `review_serve.py`. Kategoriya
  taklifi CLIP dan (`suggest_category.py`, torch + open_clip venv'da), reviewer
  o'zgartirishi mumkin — Keep tanlangan kategoriyaga yozadi.
- 👤 belgi = odam surati (CLIP + yuz detektori). Boshqa odamning shaxsiy
  fotosi wallpaper emas — mualliflik va shaxs huquqi; ular odatda Skip.
- Telegram "photo" (hujjat emas) ≤1280px keladi → katalogda "HD" belgisi.
  Bu manba 4K bermaydi; sifat cheklovi ma'lum va qabul qilingan.

## Reklama

- Yandex Mobile Ads to'g'ridan-to'g'ri, mediation yo'q. `AdService` interfeysi
  tarmoqdan mustaqil — tarmoq almashsa faqat shu fayl o'zgaradi.
- Debug → `demo-*-yandex` unit'lar. Release → `R-M-19979404-1/2/3`.
- **Release build'da reklamani hech qachon bosmaslik.**
- Banner navbar ustida, 50dp, inline. Qo'lda refresh qo'shilmaydi — SDK o'zi
  60s da yangilaydi.
- **Debug build simulyator/emulyatorda reklama umuman so'ralmaydi** — SDK
  ishga tushmaydi, demo unit ham yo'q. Banner yashirin; interstitial/rewarded
  o'rnida `AdStandIn` sahifasi: qaysi reklama, nima uchun (trigger, hisob),
  qaysi unit, cooldown. Bosilsa yopiladi, rewarded'da unlock beriladi.
  Sanagichlar va cooldown haqiqiy — sahifa aynan reklama chiqadigan paytda
  chiqadi. `kDebugMode` bilan qo'riqlangan — release'da bu kod umuman yo'q;
  haqiqiy reklamani ko'rish kerak bo'lsa — release APK (va unga bosilmaydi).
- Consent faqat EEA/UK da so'raladi; boshqa joyda `true`.
- Chastota Remote Config'da: `ad_show_every`, `ad_browse_every`,
  `ad_min_gap_seconds`. Kamida bir haftalik ma'lumotsiz o'zgartirilmaydi.

## Git

- **Commit faqat foydalanuvchi "commit" deganda** — ish tugagach, saralab:
  mantiqiy o'zgarish bo'yicha bittadan, mayda tuzatishlar o'z asosiy
  o'zgarishiga qo'shiladi. Har qadamda commit qilinmaydi.
- **Push faqat foydalanuvchi aytganda.** Hech qachon o'z-o'zidan emas.
- Commit xabari: qisqa sarlavha + *nima uchun* (sabab, kontekst), ingliz tilida.
  "Fixed bug" emas — qanday bug, nega shunday tuzatildi.
- Commit xabarida Telegram username'lar yozilmaydi ("the girly channel",
  "a second tagged channel" — kanal nomi emas).

## Tekshirish

- `flutter analyze` toza bo'lmaguncha commit yo'q.
- UI o'zgarishi → ikkala platformada ko'rish: iOS simulyator (iPhone 17 Pro,
  iOS 26) va Android emulator (`emulator-5554`). Faqat bittasida ko'rib
  "tayyor" deyilmaydi.
- iOS < 26 ko'rinishi simulyatorda yo'q — kod yo'li oddiy bo'lsa, analyze
  bilan cheklanadi va shu aytiladi.
- Yangi katalog maydonini deploy'dan oldin ko'rish: `scripts/out` ni
  `python3 -m http.server 8788 --bind 0.0.0.0` bilan tarqatib, Android'da
  `--dart-define=CDN_BASE_URL=http://10.0.2.2:8788`, iOS'da
  `http://localhost:8788`. Debug manifest cleartext'ga ruxsat beradi,
  release — yo'q.
- Testlar hozircha yozilmaydi.
- Android'da edge-to-edge `main()` da yoqiladi (`SystemUiMode.edgeToEdge`),
  faqat Android 15 majburlagan joyda emas — eski Android ham bir xil
  ko'rinsin. Tizim barlari rangi bitta joyda: `main.dart` `_systemBars`
  (ildiz `AnnotatedRegion`, tema bo'yicha shaffof barlar). Sahifalar
  `SystemChrome` bilan rang o'rnatmaydi; `styles.xml` da `statusBarColor` /
  `navigationBarColor` yozilmaydi — Play Console ularni eskirgan deb
  belgilaydi, engine esa 35 dan pastda o'zi qo'llaydi.
- Android build: AGP `9.0.1` + Gradle `9.1.0` (Flutter 3.44 shabloni bilan
  bir xil), `android.r8.optimizedResourceShrinking=true`. `builtInKotlin` va
  `newDsl` hozircha `false` — plaginlar KGP qo'llaydi.
- `AndroidManifest.xml` izohlarida `--` ishlatilmaydi — XML buni taqiqlaydi va
  Android build butunlay yiqiladi (iOS sezmaydi).

## Build muammolari

- `flutter run` ilova ochilishidan oldin yiqilsa (simulyator, emulator yoki
  qurilma) — avval `python3 scripts/doctor.py`. U shu loyihada haqiqatan
  bo'lgan har bir nosozlikni tekshiradi: mahalliy holatni o'zi tiklaydi
  (Flutter engine keshi, `pub get`, `pod install`, binary'siz qolgan
  `Flutter.framework`), git'dagi faylni o'zgartiradiganini faqat aytadi.
  Yangi turdagi nosozlik tuzatilsa — shu skriptga tekshiruv qo'shiladi.
- iOS plaginlari faqat CocoaPods orqali: `pubspec.yaml` →
  `flutter: config: enable-swift-package-manager: false`. `yandex_mobileads`
  SPM'ni bilmaydi; SPM yoqilsa KSCrash ikki marta linklanadi (2183
  duplicate symbol). Global Flutter sozlamasiga tegilmaydi.
- Firebase oktabr 2026 dan keyin CocoaPods'ga yangi versiya chiqarmaydi.
  Keyingi Firebase yangilanishidan oldin SPM masalasi hal qilinadi:
  `yandex_mobileads` `Package.swift` chiqargan bo'lsa SPM qayta yoqiladi,
  bo'lmasa `appmetrica_plugin` dan voz kechish ko'riladi.
- Firebase plaginlari faqat birga yangilanadi (buyruq `pubspec.yaml` da).
- `pod install` qo'lda — `LANG=en_US.UTF-8` bilan, aks holda CocoaPods'ning
  xato hisobotchisi yiqilib, asl xatoni yashiradi.
- Android Studio yoki terminaldan run qilganda Xcode yopiq turadi: bitta
  workspace'da ikki build servis "Could not compute dependency graph"
  beradi va paketlarni ikki marta resolve qiladi.
- 2026-09-29 da Flutter SDK keshidan uchala rejimning simulator `Flutter`
  binary'lari birdaniga yo'qolgan (sababi aniqlanmadi). Belgisi: "Binary …
  does not exist, cannot thin". Doctor buni `flutter precache --ios
  --force` bilan tiklaydi.

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

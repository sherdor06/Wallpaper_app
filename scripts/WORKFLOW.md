# Content workflow — fetch → curate → publish

Portable runbook for adding/removing wallpapers. Lives in git, so it works from
any machine / any Claude account. Run everything from `scripts/` with the venv.

```bash
cd scripts && source venv/bin/activate     # or prefix commands with venv/bin/
```

## Where things live (not in git)
- `scripts/.env` — R2 + Telegram (`TELEGRAM_API_ID/HASH`) keys. Copy from `.env.example`.
- `scripts/wallpaper.session` — Telegram login (`python login_telegram.py` once).
- `scripts/raw/` (originals), `scripts/out/` (webp), `scripts/review/` (curation staging).
- Cloudflare auth — `npx wrangler login` (browser). Account: sherdor0605@gmail.com.

## The app reads from Cloudflare Pages (NOT r2.dev)
CDN = `https://wallpapers-cdn.pages.dev`, set as the default `CDN_BASE_URL` in
`lib/config/app_config.dart`. Publishing = **deploying `out/` to Pages** (free,
unlimited bandwidth, no rate limit). `upload_r2.py` no longer feeds the app.

## A. Add wallpapers from Telegram (@iphonefotohd) — with manual review
Each wallpaper in the channel = a `#hashtag` PHOTO preview, then the caption-less
full-size DOC right after it. A DOC's category = the hashtag post **one id below**
it. `review_fetch.py` handles this correctly (buffers the DOC).

```bash
# 1. Stage candidates for review (dedups against raw/ + blocklist).
python review_fetch.py --before 2026-01-01 --per 15      # older than a date
python review_fetch.py --offset-id 22849 --per 8         # CONTINUE below an id
#    (to continue: min id of the current review/queue.json)

# 2. Curate in the browser.
python review_serve.py                                    # http://127.0.0.1:8765
#    /         one-by-one:  →/Y = Keep · ←/N = Skip · U = Undo
#    /gallery  grid overview: hover a thumb, click ✓/✗ to flip a decision
#    Keep → raw/ · Skip → blocklist (never re-fetched). Resumable.

# 3. Publish the kept images.
python process_images.py        # raw/ → out/ (webp full + thumb)
python generate_catalog.py      # out/catalog.json
cp -R site/. out/   # w.html, _redirects, .well-known -- site/ manba, out/ ignore'da
npx wrangler pages deploy out --project-name=wallpapers-cdn --branch=main --commit-dirty=true
```
Deploy takes a few minutes and sometimes fails with an empty "Failed to upload"
error — just re-run the same command. Verify: `curl -A Mozilla https://wallpapers-cdn.pages.dev/catalog.json`.

## A2. Add wallpapers from a single-topic channel (@Prinssec_Walpaper)
No hashtags there — albums of plain photos. Everything is staged into one
category and the reviewer files each image where it belongs:

```bash
python review_fetch.py --channel @Prinssec_Walpaper --as aesthetic --per 80
#    stages review/aesthetic/tg_<id>.jpg, then runs suggest_category.py (CLIP)
#    so every candidate carries a suggested category + a 👤 flag for people.
python review_fetch.py --channel @Cute_Girly_Walpaper --as girly --no-suggest
#    --no-suggest: the channel IS the category — the picker stays on it and
#    only the 👤 flag is added. Use it for any single-topic channel.
python review_fetch.py --channel @phone_wallps --per 20    # tagged, like @iphonefotohd
#    To continue older: --offset-id <min id of the current review/queue.json>
python review_serve.py                                    # http://127.0.0.1:8765
#    header picker = suggested category (↑/↓ cycles it); Keep files the image
#    under the picker's category, e.g. a cat → raw/animals/. Skip → blocklist.
```
Then step 3 of section A (process → catalog → cp site → deploy).

`suggest_category.py` needs `pip install torch open_clip_torch` in the venv
(~1 GB once). Without it the fetch still works; the picker just defaults to
the staging category. Re-score pending items: `python suggest_category.py --all`.

Telegram photos (not documents) arrive at ≤1280px → labelled "HD" in the
catalog. Reposted personal photos (👤) are normally skipped.

## B. Delete wallpapers favorited in the simulator
Mark bad wallpapers as favourites in the running app, then:
```bash
FAV=$(find ~/Library/Developer/CoreSimulator/Devices -name favorites.json -path '*Application Support*')
python delete_favorites.py --from-favorites "$FAV"        # R2 + local + blocklist
python generate_catalog.py
cp -R site/. out/   # w.html, _redirects, .well-known -- site/ manba, out/ ignore'da
npx wrangler pages deploy out --project-name=wallpapers-cdn --branch=main --commit-dirty=true
```
Gotcha: a running app re-writes old favourites from memory — close & reopen it
before favouriting so already-deleted keys don't reappear.

## Notes
- Whitelist in `review_fetch.py`/`fetch_telegram.py` (`TAG_MAP`) excludes girl-heavy
  tags: #девушки #нейро #аниме #art.
- `generate_catalog.py` writes `moods` per wallpaper (light/dark/vivid/mono,
  from the thumb's colours) — the app's collection-page chips read them.
- Retired placeholder content (generated PNGs + Openverse stock, 173 files)
  lives in `review/.retired/<category>/`, not deleted. `fetch_stock.py` and
  `gen_wallpapers.py` are no longer part of the pipeline.
- The older ~839 raw/ images were fetched with a category-shift bug → some are
  mis-tagged (future re-tag cleanup).
- Cloudflare Pages limits: 20,000 files/deploy (currently ~2000), 25 MB/file.

## D. Share havolalari (App Links)

`out/` ichida uchta fayl shu ish uchun turadi va kontent bilan birga deploy
bo'ladi:

Manbasi `scripts/site/` da turadi (kuzatiladi); `out/` gitignore'da, shuning
uchun deploy'dan oldin `cp -R site/. out/` bilan nusxalanadi.

| Fayl | Vazifasi |
|------|----------|
| `w.html` | Ilova o'rnatilmagan odam ko'radigan sahifa — rasm + Play tugmasi |
| `_redirects` | `/w/*` ni `w.html` ga qayta yozadi (200), URL o'zgarmaydi |
| `.well-known/assetlinks.json` | Android'ga "bu domen shu ilovaga ishonadi" deydi |

**assetlinks.json to'ldirilmaguncha App Links ishlamaydi** — havola bosilganda
Android to'g'ridan-to'g'ri ilovani ochish o'rniga tanlov oynasini ko'rsatadi.
Kerakli barmoq izi:

> Play Console -> Test and release -> Setup -> **App integrity** ->
> *App signing key certificate* -> **SHA-256 certificate fingerprint**

Bu Google qayta imzolaydigan kalit; upload kaliti emas. Sideload qilingan
release APK ham to'g'ridan-to'g'ri ochilishi kerak bo'lsa, ro'yxatga upload
kalitining SHA-256 ini ham qo'shing (ikkalasi bir massivda tura oladi).

Tekshirish (deploy'dan keyin):
```bash
curl -s https://wallpapers-cdn.pages.dev/.well-known/assetlinks.json
adb shell pm get-app-links com.sherdor.wallpapers   # "verified" ko'rinishi kerak
```

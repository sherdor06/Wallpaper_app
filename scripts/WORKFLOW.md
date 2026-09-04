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
npx wrangler pages deploy out --project-name=wallpapers-cdn --branch=main --commit-dirty=true
```
Deploy takes a few minutes and sometimes fails with an empty "Failed to upload"
error — just re-run the same command. Verify: `curl -A Mozilla https://wallpapers-cdn.pages.dev/catalog.json`.

## B. Delete wallpapers favorited in the simulator
Mark bad wallpapers as favourites in the running app, then:
```bash
FAV=$(find ~/Library/Developer/CoreSimulator/Devices -name favorites.json -path '*Application Support*')
python delete_favorites.py --from-favorites "$FAV"        # R2 + local + blocklist
python generate_catalog.py
npx wrangler pages deploy out --project-name=wallpapers-cdn --branch=main --commit-dirty=true
```
Gotcha: a running app re-writes old favourites from memory — close & reopen it
before favouriting so already-deleted keys don't reappear.

## Notes
- Whitelist in `review_fetch.py`/`fetch_telegram.py` (`TAG_MAP`) excludes girl-heavy
  tags: #девушки #нейро #аниме #art.
- The older ~839 raw/ images were fetched with a category-shift bug → some are
  mis-tagged (future re-tag cleanup).
- Cloudflare Pages limits: 20,000 files/deploy (currently ~2000), 25 MB/file.

#!/usr/bin/env python3
"""Stages candidate wallpapers from @iphonefotohd into `review/` for manual
yes/no curation (see review_serve.py). Unlike fetch_telegram.py it does NOT put
files into raw/ directly — it downloads to review/<category>/tg_<id>.<ext> and
appends them to review/queue.json. The web reviewer then approves (→ raw/) or
rejects (→ blocklist.json) each one.

Skips anything already in raw/ (kept), already staged in review/, or in the
blocklist (deleted/rejected earlier). Channel pattern: a #hashtag PHOTO preview
followed immediately by the caption-less full-size image DOC.

    python review_fetch.py                       # 20 new candidates per category
    python review_fetch.py --per 40 --scan 4000
    python review_fetch.py --only cars nature    # only these categories
    python review_fetch.py --before 2026-01-01   # start OLDER than this date
    python review_fetch.py --face-filter         # pre-drop prominent-face photos
    python review_fetch.py --channel @Prinssec_Walpaper --as aesthetic --per 60

--channel/--as: single-topic channel mode. Every image in the channel (photo or
image document, no hashtag needed) is staged into the one category given by
--as. Dedup is scoped to that category, so message ids from different channels
cannot collide in raw/. The queue, blocklist and review_serve.py are shared.

--before <YYYY-MM-DD>: begin the (newest->oldest) scan just before this date, so
already-fetched newer posts aren't re-scanned. E.g. `--before 2026-01-01` starts
at the end of Dec 2025 and walks backward into older history.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import mimetypes
import os
import re
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv
from telethon import TelegramClient

SCRIPT_DIR = Path(__file__).resolve().parent
RAW = SCRIPT_DIR / "raw"
REVIEW = SCRIPT_DIR / "review"
QUEUE = REVIEW / "queue.json"
BLOCKLIST_FILE = SCRIPT_DIR / "blocklist.json"
load_dotenv(SCRIPT_DIR / ".env")

TAG_RE = re.compile(r"#(\w+)", re.UNICODE)
CHANNEL = "@iphonefotohd"

# Russian hashtag -> clean latin category (whitelist). Tags absent here
# (#реклама, #разное ...) are never staged. Shared by @iphonefotohd and
# @phone_wallps, which post the same way (tagged PHOTO, then the DOC).
#
# #девушки is in since the Aesthetic collection exists: those go to the
# reviewer under 'aesthetic', flagged 👤 when they are a person, and the
# reviewer decides. It was excluded before there was anywhere to put them.
TAG_MAP = {
    "cars": "cars", "машины": "cars",
    "животные": "animals", "животное": "animals", "котики": "animals",
    "природа": "nature",
    "горы": "mountains",
    "море": "ocean",
    "абстракция": "abstract", "абстрация": "abstract", "текстуры": "abstract",
    "космос": "space",
    "цветы": "flowers",
    "спорт": "sport",
    "градиент": "gradient",
    "город": "city",
    "архитектура": "architecture", "мосты": "architecture",
    "игры": "games",
    "комиксы": "comics", "мультфильмы": "comics", "мультики": "comics",
    "технологии": "tech", "apple": "tech", "android": "tech",
    "кино": "movies", "фильмы": "movies",
    "девушки": "aesthetic", "сладости": "aesthetic",
}


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def save_queue(new_items: list[dict]) -> None:
    """Persists the queue, merging with whatever is on disk right now.

    review_serve.py writes the same file while the user reviews, so a blind
    overwrite would revert their keep/skip decisions. Re-read first, keep the
    on-disk status for items that already exist, and only append the new ones.
    """
    on_disk = load_json(QUEUE, {})
    existing = on_disk.get("items") or [
        {**it, "status": "pending"} for it in on_disk.get("pending", [])
    ]
    have = {_item_key(it) for it in existing}
    merged = list(existing)
    for it in new_items:
        if _item_key(it) not in have:
            merged.append(it)
    QUEUE.parent.mkdir(parents=True, exist_ok=True)
    QUEUE.write_text(json.dumps({"items": merged}, ensure_ascii=False, indent=2),
                     encoding="utf-8")


def _channel_key(channel: str) -> str:
    """'@Foo' and 'foo' are the same channel."""
    return channel.lstrip("@").lower()


def _item_key(it: dict) -> tuple[str, int]:
    """(channel, message id) — items staged before channels were recorded
    belong to the default channel."""
    return (it.get("ch") or _channel_key(CHANNEL), it["mid"])


def category_for(caption: str) -> str | None:
    for t in TAG_RE.findall(caption or ""):
        cat = TAG_MAP.get(t.lower())
        if cat:
            return cat
    return None


def _already_have(key: tuple[str, int], staged: set[tuple[str, int]],
                  cat: str | None = None) -> bool:
    """True if this (channel, message id) is already in the queue, or the id is
    downloaded into raw/. Default (@iphonefotohd): any category, since one file
    can be re-posted under several tags. Channel mode passes its category so
    ids from a second channel are only matched against their own folder.

    Message ids are per channel, so the queue is keyed by channel too: the
    channels' id ranges will overlap eventually, and a candidate must not be
    dropped because another channel once posted the same number."""
    if key in staged:
        return True
    return any(RAW.glob(f"{cat or '*'}/tg_{key[1]}.*"))


async def run(per: int, scan: int, only: set[str], face_filter: bool,
              before: datetime | None, offset_id: int = 0,
              channel: str = CHANNEL, as_cat: str | None = None,
              suggest: bool = True) -> None:
    api_id = os.getenv("TELEGRAM_API_ID")
    api_hash = os.getenv("TELEGRAM_API_HASH")
    phone = os.getenv("TELEGRAM_PHONE")
    if not api_id or not api_hash:
        raise SystemExit("❌ .env da TELEGRAM_API_ID/API_HASH yo'q.")

    blocklist = set(load_json(BLOCKLIST_FILE, []))
    queue = load_json(QUEUE, {})
    items: list[dict] = queue.get("items") or [
        {**it, "status": "pending"} for it in queue.get("pending", [])
    ]
    ch = _channel_key(channel)
    staged_ids = {_item_key(it) for it in items}  # dedup across runs

    hide_faces = None
    if face_filter:
        from face_filter import has_prominent_face
        hide_faces = has_prominent_face

    client = TelegramClient(
        str(SCRIPT_DIR / "wallpaper"), int(api_id), api_hash,
        connection_retries=10, retry_delay=3, request_retries=10,
        timeout=30, flood_sleep_threshold=60,
    )
    await client.start(phone=phone or (lambda: input("Telefon raqam (+998...): ")))

    staged: dict[str, int] = {}   # new candidates staged this run, per category
    dmin: datetime | None = None
    dmax: datetime | None = None

    async def stage(doc_msg, cat: str) -> None:
        nonlocal dmin, dmax
        mid = doc_msg.id
        key = f"{cat}/tg_{mid}"
        if key in blocklist or _already_have((ch, mid), staged_ids, as_cat):
            return
        if staged.get(cat, 0) >= per:
            return
        # Telegram "photos" (compressed, no document) download as JPEG.
        doc = getattr(doc_msg, "document", None)
        mime = doc.mime_type if doc else "image/jpeg"
        ext = mimetypes.guess_extension(mime) or ".jpg"
        rel = f"{cat}/tg_{mid}{ext}"
        dest = REVIEW / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        ok = False
        for attempt in range(4):
            try:
                await doc_msg.download_media(file=str(dest))
                ok = True
                break
            except Exception as e:
                print(f"   ⚠️ {key}: {e} — qayta ({attempt + 1})")
                await asyncio.sleep(3 * (attempt + 1))
        if not ok:
            dest.unlink(missing_ok=True)
            return
        if hide_faces and hide_faces(dest):
            dest.unlink(missing_ok=True)
            print(f"  ⊘ {key} — yuz aniqlandi (--face-filter), o'tkazildi")
            return
        items.append({"cat": cat, "mid": mid, "file": rel, "status": "pending",
                      "ch": ch})
        staged_ids.add((ch, mid))
        staged[cat] = staged.get(cat, 0) + 1
        # Persist after every download so a dropped connection never loses the
        # queue (Telegram disconnects mid-scan happen; files stay + are recorded).
        # Merges with disk so a concurrent review session isn't reverted.
        save_queue(items)
        if doc_msg.date:
            dmin = doc_msg.date if dmin is None or doc_msg.date < dmin else dmin
            dmax = doc_msg.date if dmax is None or doc_msg.date > dmax else dmax
        print(f"  + {rel}  ({doc_msg.date:%Y-%m-%d})" if doc_msg.date else f"  + {rel}")
        await asyncio.sleep(0.2)

    scanned = 0
    pending_doc = None  # the caption-less image DOC awaiting its category photo

    # Channel layout (chronological): #hashtag PHOTO preview, then immediately the
    # caption-less full-size DOC. So a DOC's category = the hashtag post one id
    # BELOW it. We scan newest->oldest, so the DOC is seen first and its category
    # photo comes on the very next (older) step — buffer the DOC, assign then.
    # offset_date starts the scan just before `before` (older posts only).
    async for m in client.iter_messages(channel, limit=scan, offset_date=before,
                                        offset_id=offset_id):
        scanned += 1
        if as_cat:
            # Single-topic channel: no tags, albums of plain photos. Stage every
            # image straight into the given category; the reviewer decides.
            doc = getattr(m, "document", None)
            is_image_doc = bool(doc and (doc.mime_type or "").startswith("image/"))
            if getattr(m, "photo", None) or is_image_doc:
                await stage(m, as_cat)
                if staged.get(as_cat, 0) >= per:
                    break
            continue
        cap = m.message or ""
        if TAG_RE.search(cap):
            if pending_doc is not None:
                cat = category_for(cap)
                if only and cat not in only:
                    cat = None
                if cat:
                    await stage(pending_doc, cat)
            pending_doc = None
            continue
        doc = getattr(m, "document", None)
        mime = getattr(doc, "mime_type", None) if doc else None
        pending_doc = m if (mime and mime.startswith("image/")) else None

    await client.disconnect()

    REVIEW.mkdir(parents=True, exist_ok=True)
    save_queue(items)

    if staged:
        # Channel mode has no hashtags to lean on, so the image proposes its
        # own category — unless --no-suggest says the channel *is* the
        # category (a "girly" channel is girly whatever CLIP sees in a frame).
        # Hashtag mode keeps the tag — it is the better signal. Both of those
        # only take the 👤 flag, so reposted personal photos stand out.
        # Optional: needs torch + open_clip; without them the reviewer just
        # sees the staging category pre-selected.
        try:
            from suggest_category import annotate, write_suggestions
            want = bool(as_cat) and suggest
            print("\nKategoriya takliflari (CLIP)…" if want else "\n👤 belgilar (CLIP)…")
            if annotate(items, suggest=want):
                write_suggestions(items)
        except ImportError:
            print("\nℹ️  Taklif yo'q: `pip install torch open_clip_torch` qilib "
                  "`python suggest_category.py` ni ishga tushiring.")
    new_total = sum(staged.values())
    rng = f"  Sanalar: {dmin:%Y-%m-%d} … {dmax:%Y-%m-%d}" if dmin and dmax else ""
    print(f"\nSkaner: {scanned} xabar. Yangi nomzod: {new_total}. "
          f"Ko'rib chiqishга kutayotgan jami: {len(items)}.{rng}")
    for c, n in sorted(staged.items(), key=lambda x: -x[1]):
        print(f"  {c}: +{n}")
    print("Keyingi: python review_serve.py  → brauzerда ✓/✗ bosing.")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--per", type=int, default=20, help="Har kategoriyaga nechta YANGI nomzod (default 20)")
    p.add_argument("--scan", type=int, default=3000, help="Ko'pi bilan nechta xabar skaner")
    p.add_argument("--only", nargs="*", help="Faqat shu kategoriyalar")
    p.add_argument("--face-filter", action="store_true", help="Yirik yuzli rasmlarni oldindan tashlash")
    p.add_argument("--before", metavar="YYYY-MM-DD",
                   help="Shu sanadan oldingi (eskiroq) postlardan boshlaydi")
    p.add_argument("--offset-id", type=int, default=0,
                   help="Shu xabar id'sidan pastroq (eskiroq) davom etadi")
    p.add_argument("--channel", default=CHANNEL,
                   help=f"Telegram kanal (default {CHANNEL})")
    p.add_argument("--as", dest="as_cat", metavar="CATEGORY",
                   help="Kanaldagi HAMMA rasmni shu kategoriyaga qo'yadi (hashtag'siz kanal uchun)")
    p.add_argument("--no-suggest", action="store_true",
                   help="--as bilan: kategoriya taklifi yo'q, faqat 👤 belgi — kanal bir mavzuli bo'lsa")
    args = p.parse_args()
    before = None
    if args.before:
        try:
            before = datetime.strptime(args.before, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        except ValueError:
            raise SystemExit("❌ --before format: YYYY-MM-DD (masalan 2026-01-01)")
    asyncio.run(run(args.per, args.scan, set(args.only or []), args.face_filter,
                    before, args.offset_id, args.channel, args.as_cat,
                    suggest=not args.no_suggest))


if __name__ == "__main__":
    main()

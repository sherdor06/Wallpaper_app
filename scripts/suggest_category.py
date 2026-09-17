#!/usr/bin/env python3
"""Suggests a catalog category for staged candidates by looking at the image.

CLIP zero-shot (open_clip, runs locally — Apple GPU via MPS when available).
For every pending item in review/queue.json without a suggestion it writes:

    "suggest": "animals",   # best-matching category
    "suggest_p": 0.83,      # its share of the probability mass
    "person": true          # only when the image is mostly a person / selfie

review_serve.py pre-selects `suggest` in its category picker; the reviewer
confirms or changes it before keeping. The channel mode of review_fetch.py
runs this automatically after staging.

    python suggest_category.py                 # annotate pending items lacking one
    python suggest_category.py --all           # redo every pending item
    python suggest_category.py --file x.jpg    # print scores for one image (debug)

Needs `pip install torch open_clip_torch` (~1 GB once; the ViT-B-32 weights,
~600 MB, download on first run into ~/.cache).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REVIEW = SCRIPT_DIR / "review"
QUEUE = REVIEW / "queue.json"
CONFIG = SCRIPT_DIR / "config.json"

MODEL = "ViT-B-32"
PRETRAINED = "laion2b_s34b_b79k"

# Category -> several plain descriptions. Each prompt is scored on its own and
# a category's score is the sum over its prompts — averaging the embeddings
# instead blurred "a pattern of hearts" and "hello kitty" into something that
# matched nothing. Written for what actually shows up in the feeds, not for
# dictionary definitions — "animals" leans on pets because that is what gets
# posted.
PROMPTS: dict[str, list[str]] = {
    "nature":       ["a landscape photo of nature", "a forest", "a lake surrounded by trees",
                     "a sunset over fields", "autumn leaves", "a waterfall"],
    "mountains":    ["a photo of mountains", "snowy mountain peaks", "a mountain valley"],
    "ocean":        ["the sea", "a beach with waves", "ocean water", "a tropical coast"],
    "space":        ["the night sky full of stars", "the moon in the sky", "a galaxy in outer space",
                     "planets", "the northern lights"],
    "city":         ["a city skyline", "a city street at night", "city lights and traffic"],
    "architecture": ["the architecture of a building", "the interior of a building", "a bridge",
                     "a cathedral"],
    "animals":      ["a photo of an animal", "a cat", "a kitten", "a dog", "a puppy", "a bird",
                     "a horse", "a wild animal", "a deer"],
    "flowers":      ["flowers", "a bouquet of roses", "a close-up of a flower", "tulips",
                     "cherry blossoms"],
    "cars":         ["a car", "a sports car", "a luxury car parked", "a motorcycle"],
    "abstract":     ["an abstract pattern", "abstract shapes and colours", "a texture close-up",
                     "a repeating pattern"],
    "gradient":     ["a smooth colour gradient background", "a blurred gradient of colours"],
    "minimal":      ["a minimalist background with one small object", "a plain solid colour background",
                     "a simple minimal wallpaper"],
    "anime":        ["an anime illustration", "an anime character", "a manga drawing"],
    "comics":       ["a comic book superhero", "a cartoon character", "a cartoon illustration",
                     "a mascot character"],
    "games":        ["a video game screenshot", "a video game character", "gaming artwork"],
    "movies":       ["a movie poster", "a scene from a film", "a film character"],
    "sport":        ["a football player", "a sports match", "a basketball game", "a sports car race"],
    "tech":         ["a smartphone or gadget", "a computer circuit board", "a technology logo",
                     "headphones"],
    "art":          ["a painting", "a drawing or sketch", "digital art illustration", "a sculpture"],
    "aesthetic":    ["a cute pink aesthetic wallpaper", "a pastel aesthetic photo",
                     "a pattern of hearts and bows", "a girly aesthetic collage",
                     "a cosy aesthetic photo of a room", "hello kitty",
                     "an aesthetic photo of a bouquet of pink roses", "a moody dark aesthetic photo",
                     "a phone wallpaper with a short quote"],
    "girly":        ["a pink girly wallpaper", "a cute kawaii wallpaper with hearts and bows",
                     "a pink princess aesthetic", "a sparkly pink glitter background",
                     "a cute cartoon character in pastel pink", "a coquette bow aesthetic"],
    # Not a category: flagged so the reviewer notices reposted personal photos.
    "_person":      ["a selfie", "a photo of a woman", "a photo of a man", "a portrait of a girl",
                     "a group of people posing", "a person's face"],
}


def _load(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


class Classifier:
    """Lazy CLIP wrapper; construction downloads the weights on first use."""

    def __init__(self) -> None:
        import open_clip
        import torch
        self.torch = torch
        self.device = "mps" if torch.backends.mps.is_available() else "cpu"
        self.model, _, self.preprocess = open_clip.create_model_and_transforms(
            MODEL, pretrained=PRETRAINED, device=self.device)
        self.model.eval()
        tok = open_clip.get_tokenizer(MODEL)
        self.labels = list(PROMPTS.keys())
        # One row per prompt; `owner[i]` is the category row i belongs to.
        self.owner: list[str] = []
        prompts: list[str] = []
        for cat in self.labels:
            for p in PROMPTS[cat]:
                self.owner.append(cat)
                prompts.append(p if p.startswith(("a ", "an ", "the ")) else f"a photo of {p}")
        with torch.no_grad():
            e = self.model.encode_text(tok(prompts).to(self.device))
            self.text = e / e.norm(dim=-1, keepdim=True)

    def scores(self, paths: list[Path]) -> list[dict[str, float]]:
        from PIL import Image
        torch = self.torch
        out: list[dict[str, float]] = []
        for i in range(0, len(paths), 16):
            batch = paths[i:i + 16]
            ims = []
            for p in batch:
                try:
                    ims.append(self.preprocess(Image.open(p).convert("RGB")))
                except Exception:
                    ims.append(None)
            ok = [im for im in ims if im is not None]
            probs = None
            if ok:
                with torch.no_grad():
                    x = torch.stack(ok).to(self.device)
                    e = self.model.encode_image(x)
                    e = e / e.norm(dim=-1, keepdim=True)
                    probs = (100.0 * e @ self.text.T).softmax(dim=-1).cpu().tolist()
            j = 0
            for im in ims:
                if im is None or probs is None:
                    out.append({})
                else:
                    agg = {cat: 0.0 for cat in self.labels}
                    for cat, pr in zip(self.owner, probs[j]):
                        agg[cat] += pr
                    out.append(agg)
                    j += 1
        return out


def suggestion(score: dict[str, float], path: Path | None = None) -> dict:
    """Turns raw scores into the fields stored on a queue item."""
    if not score:
        return {}
    person = score.get("_person", 0.0)
    ranked = sorted(((v, k) for k, v in score.items() if not k.startswith("_")), reverse=True)
    p, cat = ranked[0]
    out = {"suggest": cat, "suggest_p": round(p, 2)}
    # The flag tells the reviewer it is a reposted personal photo. CLIP alone
    # misses a fair share of selfies (it sees the outfit, the car, the horse),
    # so the frontal-face detector gets a vote too.
    if person >= 0.25 or person > p or (path is not None and _has_face(path)):
        out["person"] = True
    return out


def _has_face(path: Path) -> bool:
    try:
        from face_filter import has_prominent_face
        return has_prominent_face(path, min_ratio=0.03)
    except Exception:
        return False


def annotate(items: list[dict], redo: bool = False, quiet: bool = False,
             suggest: bool = True) -> int:
    """Fills suggestions for pending items in place; returns how many changed.

    With `suggest=False` only the 👤 flag is written — for channels whose
    hashtag already names the category better than the image could."""
    done_key = "suggest" if suggest else "person_checked"
    todo = [it for it in items
            if it.get("status", "pending") == "pending" and (redo or done_key not in it)]
    if not todo:
        return 0
    clf = Classifier()
    paths = [REVIEW / it["file"] for it in todo]
    n = 0
    for it, sc, path in zip(todo, clf.scores(paths), paths):
        s = suggestion(sc, path)
        if not s:
            continue
        if suggest:
            it.update(s)
        else:
            it["person_checked"] = True
            if s.get("person"):
                it["person"] = True
        n += 1
        if not quiet:
            flag = "  👤" if s.get("person") else ""
            shown = f"→ {s['suggest']:12} {s['suggest_p']:.0%}" if suggest else f"({it['cat']})"
            print(f"  {it['file']:34} {shown}{flag}")
    return n


def write_suggestions(annotated: list[dict]) -> None:
    """Merges suggestions into the queue on disk by file key rather than
    overwriting it: review_serve.py may be saving decisions at the same time."""
    by_file = {it["file"]: it for it in annotated
               if "suggest" in it or "person_checked" in it}
    items = (_load(QUEUE, {}) or {}).get("items") or annotated
    for it in items:
        src = by_file.get(it["file"])
        if src:
            for k in ("suggest", "suggest_p", "person", "person_checked"):
                if k in src:
                    it[k] = src[k]
    QUEUE.write_text(json.dumps({"items": items}, ensure_ascii=False, indent=2),
                     encoding="utf-8")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--all", action="store_true", help="Pending'larning hammasini qayta baholash")
    p.add_argument("--file", help="Bitta rasm uchun ballarni chiqarish (debug)")
    args = p.parse_args()

    if args.file:
        sc = Classifier().scores([Path(args.file)])[0]
        for k, v in sorted(sc.items(), key=lambda kv: -kv[1])[:8]:
            print(f"  {k:12} {v:.1%}")
        print(" ", suggestion(sc, Path(args.file)))
        return

    items = (_load(QUEUE, {}) or {}).get("items") or []
    n = annotate(items, redo=args.all)
    if n:
        write_suggestions(items)
    print(f"\n{n} ta nomzodga taklif yozildi. Keyingi: python review_serve.py")


if __name__ == "__main__":
    main()

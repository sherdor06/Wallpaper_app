#!/usr/bin/env python3
"""Local web reviewer for candidates staged by review_fetch.py.

Two views (open http://127.0.0.1:8765):
  •  /          one-at-a-time: Keep (✓/→/Y) · Skip (✗/←/N) · Undo (↩/U)
  •  /gallery   overview grid of everything decided so far — Approved and
                Rejected side by side; hover a thumbnail to flip its decision
                (an approved one that slipped through → reject, and vice versa).

State lives in review/queue.json as items with a status:
  pending → file in review/<file>   kept → raw/<file>   skipped → review/.trash/<file>
Keeping is resumable; skipping also blocklists the key so it is never re-fetched.

    python review_serve.py                # port 8765
    python review_serve.py --port 9000

After reviewing, publish the kept images:
    python process_images.py && python generate_catalog.py
    npx wrangler pages deploy out --project-name=wallpapers-cdn --branch=main --commit-dirty=true
"""
from __future__ import annotations

import argparse
import io
import json
import mimetypes
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

SCRIPT_DIR = Path(__file__).resolve().parent
RAW = SCRIPT_DIR / "raw"
REVIEW = SCRIPT_DIR / "review"
TRASH = REVIEW / ".trash"
THUMBS = REVIEW / ".thumbs"
STATE = REVIEW / "queue.json"
BLOCKLIST_FILE = SCRIPT_DIR / "blocklist.json"

_BASE = {"pending": REVIEW, "kept": RAW, "skipped": TRASH}
_LOCK = threading.Lock()
_HISTORY: list[dict] = []  # in-session undo stack for the one-by-one view


def _load(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def _load_items() -> list[dict]:
    data = _load(STATE, None)
    if not isinstance(data, dict):
        return []
    if isinstance(data.get("items"), list):
        return data["items"]
    # migrate the older {"pending": [...]} schema
    return [{**it, "status": "pending"} for it in data.get("pending", [])]


def _save_items(items: list[dict]) -> None:
    REVIEW.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps({"items": items}, ensure_ascii=False, indent=2),
                     encoding="utf-8")


def _blocklist(key: str, add: bool) -> None:
    bl = set(_load(BLOCKLIST_FILE, []))
    bl.add(key) if add else bl.discard(key)
    BLOCKLIST_FILE.write_text(json.dumps(sorted(bl), ensure_ascii=False, indent=2),
                              encoding="utf-8")


def _safe(base: Path, rel: str) -> Path | None:
    try:
        p = (base / rel).resolve()
        p.relative_to(base.resolve())
        return p
    except Exception:
        return None


def _locate(rel: str) -> Path | None:
    """The file may live in review/, raw/ or .trash/ depending on its status."""
    for base in (REVIEW, RAW, TRASH):
        p = _safe(base, rel)
        if p and p.is_file():
            return p
    return None


def _apply(item: dict, to_status: str) -> None:
    """Move the file to match `to_status` and update the blocklist."""
    frm = item.get("status", "pending")
    if frm == to_status:
        return
    src = _safe(_BASE[frm], item["file"])
    dst = _safe(_BASE[to_status], item["file"])
    if dst is not None:
        dst.parent.mkdir(parents=True, exist_ok=True)
        if src and src.exists():
            src.replace(dst)
    key = f"{item['cat']}/tg_{item['mid']}"
    if to_status == "skipped":
        _blocklist(key, add=True)
    elif frm == "skipped":
        _blocklist(key, add=False)
    item["status"] = to_status


def _thumb(rel: str) -> bytes | None:
    """A small cached WEBP thumbnail so the gallery loads fast."""
    src = _locate(rel)
    if not src:
        return None
    cache = _safe(THUMBS, rel + ".webp")
    if cache and cache.exists() and cache.stat().st_mtime >= src.stat().st_mtime:
        return cache.read_bytes()
    try:
        from PIL import Image
        im = Image.open(src)
        im.thumbnail((360, 360))
        if im.mode not in ("RGB", "RGBA"):
            im = im.convert("RGB")
        buf = io.BytesIO()
        im.save(buf, "WEBP", quality=72)
        data = buf.getvalue()
        if cache:
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_bytes(data)
        return data
    except Exception:
        return src.read_bytes()


REVIEW_PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Wallpaper review</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}
body{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#0e0e12;color:#eee;
 height:100vh;display:flex;flex-direction:column;overflow:hidden}
header{display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid #24242e}
.badge{background:#6C5CE7;color:#fff;padding:3px 12px;border-radius:20px;font-size:13px;font-weight:600}
.count{color:#9a9aa5;font-size:14px;margin-left:auto}
a.tab{color:#8E7BF5;text-decoration:none;font-size:14px;font-weight:600;border:1px solid #33334a;
 padding:5px 12px;border-radius:10px}
.bar{height:4px;background:#24242e}.bar>div{height:100%;background:#6C5CE7;width:0;transition:width .2s}
main{flex:1;display:flex;align-items:center;justify-content:center;padding:16px;min-height:0}
img{max-width:100%;max-height:100%;border-radius:14px;box-shadow:0 8px 40px #0008;object-fit:contain}
footer{display:flex;gap:14px;justify-content:center;padding:16px}
button{border:0;border-radius:14px;padding:16px 30px;font-size:17px;font-weight:700;cursor:pointer;transition:transform .05s}
button:active{transform:scale(.96)}
.skip{background:#2a2a33;color:#ff6b6b}.keep{background:#00b894;color:#fff}
.undo{background:#2a2a33;color:#aaa;font-size:14px;padding:16px 18px}
.hint{color:#666;font-size:12px;text-align:center;padding:0 0 12px}
.done{text-align:center;color:#9a9aa5;font-size:18px;line-height:1.6}.done b{color:#00b894}
</style></head><body>
<header><span class="badge" id="cat">—</span><span id="key" style="color:#777;font-size:13px"></span>
 <span class="count" id="count"></span><a class="tab" href="/gallery">▦ Gallery</a></header>
<div class="bar"><div id="prog"></div></div>
<main id="main"><div class="done">Yuklanmoqda…</div></main>
<footer id="ctrl" style="display:none">
 <button class="skip" onclick="decide('skip')">✗ Skip <small style="opacity:.6">(←)</small></button>
 <button class="undo" onclick="undo()">↩ Undo</button>
 <button class="keep" onclick="decide('keep')">✓ Keep <small style="opacity:.6">(→)</small></button>
</footer>
<div class="hint">→ / Y = Keep · ← / N = Skip · U = Undo · ▦ Gallery = hammasini ko'rish</div>
<script>
let cur=null,busy=false;
async function load(){
 const s=await (await fetch('/api/state')).json();
 document.getElementById('count').textContent=s.remaining+' qoldi · '+s.kept+' ✓ · '+s.skipped+' ✗';
 document.getElementById('prog').style.width=s.total?((s.kept+s.skipped)/s.total*100)+'%':'0';
 cur=s.current; const main=document.getElementById('main'),ctrl=document.getElementById('ctrl');
 if(!cur){ctrl.style.display='none';
  main.innerHTML='<div class="done">🎉 <b>Hammasi ko\\'rildi!</b><br>▦ Gallery da tekshiring, '
   +'so\\'ng <code>process_images → generate_catalog → Pages deploy</code>.</div>';return;}
 document.getElementById('cat').textContent=cur.cat;
 document.getElementById('key').textContent='tg_'+cur.mid;ctrl.style.display='flex';
 const im=new Image();im.onload=()=>{main.innerHTML='';main.appendChild(im);};
 im.src='/img?f='+encodeURIComponent(cur.file)+'&t='+Date.now();
 if(s.next)new Image().src='/img?f='+encodeURIComponent(s.next)+'&t='+Date.now();
}
async function decide(d){if(busy||!cur)return;busy=true;
 await fetch('/api/decide',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({file:cur.file,decision:d})});busy=false;load();}
async function undo(){if(busy)return;busy=true;await fetch('/api/undo',{method:'POST'});busy=false;load();}
document.addEventListener('keydown',e=>{const k=e.key.toLowerCase();
 if(e.key==='ArrowRight'||k==='y')decide('keep');
 else if(e.key==='ArrowLeft'||k==='n')decide('skip');
 else if(k==='u'||k==='z')undo();});
load();
</script></body></html>"""

GALLERY_PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Wallpaper gallery</title><style>
:root{color-scheme:dark}*{box-sizing:border-box}
body{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#0e0e12;color:#eee}
header{position:sticky;top:0;z-index:5;background:#0e0e12ee;backdrop-filter:blur(6px);
 display:flex;align-items:center;gap:12px;padding:12px 18px;border-bottom:1px solid #24242e}
a.tab{color:#8E7BF5;text-decoration:none;font-weight:600;border:1px solid #33334a;padding:5px 12px;border-radius:10px}
h2{font-size:15px;margin:22px 18px 10px;color:#cfcfe0;display:flex;gap:8px;align-items:center}
h2 .n{color:#777;font-weight:500}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px;padding:0 18px}
.cell{position:relative;aspect-ratio:3/4;border-radius:12px;overflow:hidden;background:#1a1a22;
 border:2px solid transparent}
.cell.kept{border-color:#00b89455}.cell.skipped{border-color:#ff6b6b55;opacity:.6}
.cell img{width:100%;height:100%;object-fit:cover;display:block}
.cell .tag{position:absolute;left:6px;top:6px;background:#000a;color:#fff;font-size:11px;padding:2px 7px;border-radius:8px}
.cell .act{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;
 background:#000c;opacity:0;transition:opacity .12s;cursor:pointer;font-size:15px;font-weight:700;flex-direction:column;gap:4px}
.cell:hover .act{opacity:1}
.cell.kept .act{color:#ff6b6b}.cell.skipped .act{color:#00b894}
.empty{color:#666;padding:0 18px 10px;font-size:13px}
footer{padding:26px 18px;color:#777;font-size:13px}
</style></head><body>
<header><a class="tab" href="/">‹ Review</a><b>▦ Gallery</b>
 <span id="sum" style="margin-left:auto;color:#9a9aa5;font-size:14px"></span></header>
<h2>✓ Approved <span class="n" id="nk"></span></h2>
<div class="grid" id="kept"></div><div class="empty" id="ke"></div>
<h2>✗ Rejected <span class="n" id="ns"></span></h2>
<div class="grid" id="skipped"></div><div class="empty" id="se"></div>
<footer>Thumbnailга kursor oborib, ✓/✗ bosib holatni almashtiring.<br>
 Tugagach: <code>process_images → generate_catalog → Pages deploy</code>.</footer>
<script>
async function load(){
 const g=await (await fetch('/api/gallery')).json();
 document.getElementById('sum').textContent=g.kept.length+' ✓ · '+g.skipped.length+' ✗';
 render('kept',g.kept,'skipped','✗ Reject');
 render('skipped',g.skipped,'kept','✓ Approve');
 document.getElementById('nk').textContent=g.kept.length;
 document.getElementById('ns').textContent=g.skipped.length;
 document.getElementById('ke').textContent=g.kept.length?'':'— bo\\'sh —';
 document.getElementById('se').textContent=g.skipped.length?'':'— bo\\'sh —';
}
function render(id,list,to,label){
 const el=document.getElementById(id);el.innerHTML='';
 for(const it of list){
  const c=document.createElement('div');c.className='cell '+(to==='skipped'?'kept':'skipped');
  c.innerHTML='<img loading="lazy" src="/thumb?f='+encodeURIComponent(it.file)+'">'
   +'<span class="tag">'+it.cat+'</span>'
   +'<div class="act">'+label+'<small style="opacity:.7">tg_'+it.mid+'</small></div>';
  c.querySelector('.act').onclick=()=>flip(it.file,to);
  el.appendChild(c);
 }
}
async function flip(file,to){
 await fetch('/api/reclassify',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({file:file,to:to})});load();
}
load();
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, body: bytes, ctype: str, cache=False):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if not cache:
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj):
        self._send(json.dumps(obj).encode("utf-8"), "application/json")

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length", 0) or 0)
        try:
            return json.loads(self.rfile.read(n).decode("utf-8")) if n else {}
        except Exception:
            return {}

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/":
            self._send(REVIEW_PAGE.encode("utf-8"), "text/html; charset=utf-8")
        elif u.path == "/gallery":
            self._send(GALLERY_PAGE.encode("utf-8"), "text/html; charset=utf-8")
        elif u.path == "/api/state":
            with _LOCK:
                items = _load_items()
            pend = [it for it in items if it.get("status") == "pending"]
            self._json({
                "total": len(items),
                "kept": sum(1 for it in items if it.get("status") == "kept"),
                "skipped": sum(1 for it in items if it.get("status") == "skipped"),
                "remaining": len(pend),
                "current": pend[0] if pend else None,
                "next": pend[1]["file"] if len(pend) > 1 else None,
            })
        elif u.path == "/api/gallery":
            with _LOCK:
                items = _load_items()
            self._json({
                "kept": [it for it in items if it.get("status") == "kept"],
                "skipped": [it for it in items if it.get("status") == "skipped"],
            })
        elif u.path == "/img":
            self._serve(_locate(parse_qs(u.query).get("f", [""])[0]), full=True)
        elif u.path == "/thumb":
            data = _thumb(parse_qs(u.query).get("f", [""])[0])
            if data is None:
                self.send_error(404)
            else:
                self._send(data, "image/webp", cache=True)
        else:
            self.send_error(404)

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/api/decide":
            d = self._body()
            to = "kept" if d.get("decision") == "keep" else "skipped"
            with _LOCK:
                items = _load_items()
                it = next((x for x in items
                           if x["file"] == d.get("file") and x.get("status") == "pending"), None)
                if it:
                    _apply(it, to)
                    _HISTORY.append({"file": it["file"], "from": "pending", "to": to})
                    _save_items(items)
            self._json({"ok": bool(it)})
        elif u.path == "/api/reclassify":
            d = self._body()
            to = d.get("to")
            with _LOCK:
                items = _load_items()
                it = next((x for x in items if x["file"] == d.get("file")), None)
                if it and to in ("kept", "skipped"):
                    _apply(it, to)
                    _save_items(items)
            self._json({"ok": bool(it)})
        elif u.path == "/api/undo":
            with _LOCK:
                if _HISTORY:
                    h = _HISTORY.pop()
                    items = _load_items()
                    it = next((x for x in items if x["file"] == h["file"]), None)
                    if it:
                        _apply(it, h["from"])
                        _save_items(items)
            self._json({"ok": True})
        else:
            self.send_error(404)

    def _serve(self, path: Path | None, full=False):
        if not path or not path.is_file():
            self.send_error(404)
            return
        ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self._send(path.read_bytes(), ctype)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=8765)
    args = p.parse_args()
    items = _load_items()
    pend = sum(1 for it in items if it.get("status") == "pending")
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"\n  🖼  Review:   http://127.0.0.1:{args.port}")
    print(f"  ▦  Gallery:  http://127.0.0.1:{args.port}/gallery")
    print(f"  {len(items)} ta rasm ({pend} ko'rilmagan).  Ctrl+C = to'xtatish.\n")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nTo'xtatildi. Holat review/queue.json da saqlanadi.")


if __name__ == "__main__":
    main()

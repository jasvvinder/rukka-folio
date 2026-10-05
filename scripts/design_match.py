#!/usr/bin/env python3
"""design_match.py — the canvas side of the design-match step (ADR 2026-10-05 §2, §4).

  python3 scripts/design_match.py index              # write design/match/canvas-index.json
  python3 scripts/design_match.py render S1 S2.1 A1  # canvas frames → build/design_match/canvas/
  python3 scripts/design_match.py render --all       # every frame (~2–3 min)
  python3 scripts/design_match.py pair S1            # canvas frames beside app captures → build/design_match/pairs/S1.png
  python3 scripts/design_match.py stamp S1           # fill design/match/S1.json's hashes

`render` and `pair` take doc S-ids (S1, S11.6) or design ids (A1, R2.1b, E3). Doc ids pick up every
frame whose design id 13 §3.3 translates to them. Entity, role and state variants (A1–D8, R1, E1–E7)
keep their design id, so name them when the screen has a variant drawn.

Needs the git-ignored mirror (design/canvas-mirror/, pulled by /design-pull) and a local Google Chrome
for render/pair. `index` and `stamp` need only the mirror. CI never runs this: it reads the committed
index and records (scripts/check_design_match.dart).

Frames come from partials/canvas*-screens.json and partials/new-screens-*.json, in the English light
variant. Canvas 0 (master map) and Canvas 17 (reports, which has no partials) are not indexed.
⚠️ The pa/hi and dark renders are not wired yet: the canvases translate through the i18n dictionaries
in build-canvas.js, which this script does not replay.
"""
import glob, hashlib, html, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIRROR = os.path.join(ROOT, "design", "canvas-mirror")
PARTIALS = os.path.join(MIRROR, "partials")
MATCH = os.path.join(ROOT, "design", "match")
INDEX = os.path.join(MATCH, "canvas-index.json")
OUT = os.path.join(ROOT, "build", "design_match")
APP_CAPTURES = os.path.join(ROOT, "app", "build", "design_match", "app")
FONTS = os.path.join(ROOT, "app", "assets", "fonts")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 390, 844  # 13 §10 decision 9: the design canvas


def die(msg):
    sys.exit(f"design_match: {msg}")


def need_mirror():
    if not os.path.isdir(PARTIALS):
        die("design/canvas-mirror/partials is missing — run /design-pull first (the mirror is git-ignored)")


# ---- 13 §3.3: design id → doc id ------------------------------------------------------------------

def _expand(token):
    """'O2a/O2b' → [O2a, O2b]; 'O6a–c' → [O6a, O6b, O6c]; 'R2.2(+b)' → [R2.2, R2.2b]."""
    out = []
    for part in token.split("/"):
        part = part.strip()
        if re.fullmatch(r"[a-z]", part) and out:  # 'O7a/b' → O7a, O7b
            part = re.sub(r"[a-z]$", part, out[-1])
        m = re.match(r"^(.*?)\(\+(\w)\)$", part)
        if m:
            out += [m.group(1), m.group(1) + m.group(2)]
            continue
        m = re.match(r"^(.*?)([a-z])–([a-z])$", part)
        if m:
            out += [m.group(1) + chr(c) for c in range(ord(m.group(2)), ord(m.group(3)) + 1)]
            continue
        out.append(part)
    return [o for o in out if o]


def design_aliases():
    """Read the 13 §3.3 table. Rows whose two columns hold the same count of '·' items zip one-to-one;
    a row with one doc id takes every design id on it (S2-B / S2-C → S2.1)."""
    text = open(os.path.join(ROOT, "docs", "13-ux-architecture.md"), encoding="utf-8").read()
    sec = re.search(r"### 3\.3 Design ↔ doc id map.*?\n(\|.*?)(?:\n\n|\n#)", text, re.S)
    if not sec:
        die("13 §3.3 (Design ↔ doc id map) not found — the alias table moved")
    alias = {}
    for line in sec.group(1).splitlines()[2:]:
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2 or cells[1] in ("—", ""):
            continue
        designs = [d.strip() for d in cells[0].split("·")]
        docs = [d.strip() for d in cells[1].split("·")]
        if len(docs) == 1:
            for d in designs:
                for e in _expand(d):
                    alias[e] = docs[0]
        elif len(designs) == len(docs):
            for d, s in zip(designs, docs):
                for e in _expand(d):
                    alias[e] = s
    return alias


def doc_id(design_id, alias):
    first = design_id.strip().split(" ")[0]
    if first in alias:
        return alias[first]
    if re.fullmatch(r".*\d[b-z]", first) and first[:-1] in alias:  # 'R2.1b' is a second frame of R2.1
        return alias[first[:-1]]
    m = re.match(r"^(S\d+(?:\.\d+[a-z0-9]*)?)", first)
    return m.group(1) if m else None


# ---- frames ---------------------------------------------------------------------------------------

def frames():
    """[(key, canvas, design_id, caption, html)] — key is stable across pulls while the frame stays put."""
    need_mirror()
    found = []

    def walk(x, canvas):
        if isinstance(x, list) and len(x) >= 3 and isinstance(x[0], str) and isinstance(x[1], str):
            h = x[2].get("en") if isinstance(x[2], dict) else x[2]
            if isinstance(h, str) and h.lstrip().startswith("<div"):
                found.append((canvas, x[0], x[1], h))
                return
        if isinstance(x, list):
            for y in x:
                walk(y, canvas)
        elif isinstance(x, dict):
            for y in x.values():
                walk(y, canvas)

    for f in sorted(glob.glob(os.path.join(PARTIALS, "canvas*-screens.json"))):
        walk(json.load(open(f, encoding="utf-8")), "c" + re.search(r"canvas(\d+)", f).group(1))
    for f in sorted(glob.glob(os.path.join(PARTIALS, "new-screens-*.json"))):
        tag = "n" + re.search(r"new-screens-(\w)", f).group(1)
        for k, h in json.load(open(f, encoding="utf-8")).items():
            if isinstance(h, str) and h.lstrip().startswith("<div"):
                found.append((tag, k, k, h))
    out, seen = [], {}
    for canvas, did, cap, h in found:
        base = f"{canvas}/{did}/{cap}"
        seen[base] = seen.get(base, 0) + 1
        key = base if seen[base] == 1 else f"{base}#{seen[base]}"
        out.append((key, canvas, did, cap, h))
    return out


def file_slug(key):
    return re.sub(r"[^A-Za-z0-9.-]+", "_", key.replace("#", "-dup")).strip("_")


def sha(b):
    return hashlib.sha256(b if isinstance(b, bytes) else b.encode("utf-8")).hexdigest()


# ---- index ----------------------------------------------------------------------------------------

def cmd_index(_):
    alias = design_aliases()
    by_sid, variants = {}, {}
    for key, canvas, did, cap, h in frames():
        entry = {"frame": key, "design_id": did, "caption": cap, "sha256": sha(h)}
        sid = doc_id(did, alias)
        (by_sid.setdefault(sid, []) if sid else variants.setdefault(did.split(" ")[0], [])).append(entry)
    os.makedirs(MATCH, exist_ok=True)
    index = {
        "_": "Written by scripts/design_match.py index (ADR 2026-10-05 §4). Ids, captions and hashes "
             "only — frame content stays in the git-ignored mirror. Regenerate after every /design-pull.",
        "screens": dict(sorted(by_sid.items(), key=lambda kv: _sid_key(kv[0]))),
        "variants": dict(sorted(variants.items())),
    }
    with open(INDEX, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1)
        f.write("\n")
    n = sum(len(v) for v in by_sid.values())
    print(f"canvas-index.json: {len(by_sid)} S-ids ({n} frames) · {len(variants)} variant ids "
          f"({sum(len(v) for v in variants.values())} frames)")


def _sid_key(sid):
    return [int(p) if p.isdigit() else p for p in re.findall(r"\d+|[a-z]+", sid)]


def load_index():
    if not os.path.exists(INDEX):
        die("design/match/canvas-index.json missing — run `design_match.py index`")
    return json.load(open(INDEX, encoding="utf-8"))


def frames_for(ids):
    """Frames for doc ids (via the index) or design ids (direct), from the live mirror."""
    alias = design_aliases()
    want = set(ids)
    picked = []
    for key, canvas, did, cap, h in frames():
        first = did.split(" ")[0]
        if first in want or doc_id(did, alias) in want:
            picked.append((key, h))
    return picked


# ---- render ---------------------------------------------------------------------------------------

def _tokens():
    """The en-light band's custom properties, as build-canvas.js `bandShell` sets them: LIGHT_TOKENS
    plus `--ff`, the band's face. 131 of 301 frames set `font-family:var(--ff)` on their root, so
    without it they fall to Chrome's default serif."""
    js = open(os.path.join(PARTIALS, "build-canvas.js"), encoding="utf-8").read()
    m = re.search(r"const LIGHT_TOKENS = `([^`]*)`", js)
    if not m:
        die("LIGHT_TOKENS not found in partials/build-canvas.js")
    ff = re.search(r"key:\s*'en-light'[^}]*?ff:\s*\"([^\"]+)\"", js)
    if not ff:
        die("the en-light band's ff (font family) not found in partials/build-canvas.js BANDS")
    return m.group(1).rstrip().rstrip(";") + ";--ff:" + ff.group(1)


def _fontfaces():
    faces = []
    for fam, prefix in (("Mukta", "Mukta"), ("Mukta Mahee", "MuktaMahee")):
        for weight, name in ((400, "Regular"), (500, "Medium"), (600, "SemiBold")):
            path = os.path.join(FONTS, f"{prefix}-{name}.ttf")
            w = "600 700" if weight == 600 else str(weight)
            faces.append(f"@font-face{{font-family:'{fam}';src:url('file://{path}');font-weight:{w}}}")
    return "".join(faces)


def _chrome(html_path, png_path, w, h, scale):
    if not os.path.exists(CHROME):
        die(f"Google Chrome not found at {CHROME}")
    subprocess.run(
        [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
         f"--force-device-scale-factor={scale}", f"--screenshot={png_path}", f"--window-size={w},{h}",
         "file://" + html_path],
        capture_output=True, timeout=90, check=False)
    if not os.path.exists(png_path):
        die(f"Chrome wrote no screenshot for {html_path}")


def render(picked, scale=2):
    os.makedirs(os.path.join(OUT, "canvas"), exist_ok=True)
    tok, faces = _tokens(), _fontfaces()
    paths = []
    for key, h in picked:
        slug = file_slug(key)
        doc = (f"<!doctype html><meta charset=utf-8><style>{faces}:root{{{tok}}}"
               f"body{{margin:0;background:#fff}}</style>{h}")
        hp = os.path.join(OUT, "canvas", slug + ".html")
        pp = os.path.join(OUT, "canvas", slug + ".png")
        open(hp, "w", encoding="utf-8").write(doc)
        _chrome(hp, pp, W + 2, H + 2, scale)  # +2: the frame's 1px border
        paths.append((key, pp))
    return paths


def cmd_render(args):
    if args == ["--all"]:
        picked = [(k, h) for k, _, _, _, h in frames()]
    else:
        if not args:
            die("render needs S-ids or design ids (or --all)")
        picked = frames_for(args)
        if not picked:
            die(f"no canvas frame for {' '.join(args)} — check 13 §3.3 or design/match/canvas-index.json")
    for key, p in render(picked):
        print(f"{key}  →  {os.path.relpath(p, ROOT)}")


# ---- pair -----------------------------------------------------------------------------------------

def cmd_pair(args):
    if not args:
        die("pair needs one S-id (and optionally extra design ids for its variants)")
    sid = args[0]
    canvas = render(frames_for(args))
    # `S1__*` only: the S-id is followed by the state separator, so S1 never picks up S1.1's captures,
    # and the harness's own captures (HARNESS__*) are never anyone's.
    caps = sorted(glob.glob(os.path.join(APP_CAPTURES, f"{glob.escape(sid)}__*.png")))
    if not canvas and not caps:
        die(f"nothing to pair for {sid}: no canvas frame and no app capture")
    if not caps:
        print(f"⚠ no app capture for {sid} in {os.path.relpath(APP_CAPTURES, ROOT)} — run its design test first")

    def col(title, items):
        cells = "".join(
            f"<figure><figcaption>{html.escape(label)}</figcaption><img src='file://{p}'></figure>"
            for label, p in items) or "<p class=none>none</p>"
        return f"<section><h2>{html.escape(title)}</h2>{cells}</section>"

    left = [(k, p) for k, p in canvas]
    right = [(os.path.basename(p)[:-4], p) for p in caps]
    rows = max(len(left), len(right), 1)
    page = (
        "<!doctype html><meta charset=utf-8><style>"
        "body{margin:0;padding:16px;background:#fff;font:14px -apple-system,sans-serif;display:flex;gap:32px}"
        "section{width:392px}h2{font-size:16px;margin:0 0 8px}figure{margin:0 0 16px}"
        "figcaption{height:22px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;color:#555}"
        f"img{{width:392px;height:846px;object-fit:contain;object-position:top;border:1px solid #ccc;display:block}}"
        ".none{color:#a33}</style>"
        + col("Canvas", left) + col("App", right))
    os.makedirs(os.path.join(OUT, "pairs"), exist_ok=True)
    hp = os.path.join(OUT, "pairs", file_slug(sid) + ".html")
    pp = os.path.join(OUT, "pairs", file_slug(sid) + ".png")
    open(hp, "w", encoding="utf-8").write(page)
    _chrome(hp, pp, 16 * 2 + 392 * 2 + 32 + 4, 16 * 2 + rows * (846 + 42), 1)
    print(os.path.relpath(pp, ROOT))


# ---- stamp ----------------------------------------------------------------------------------------

def screens_hash(paths):
    """Must equal scripts/check_design_match.dart `screensHash`: sha256 over
    '<path>\\n<sha256(file)>\\n' for each path, in sorted order."""
    acc = ""
    for p in sorted(paths):
        full = os.path.join(ROOT, p)
        if not os.path.exists(full):
            die(f"screen file {p} does not exist")
        acc += f"{p}\n{sha(open(full, 'rb').read())}\n"
    return sha(acc)


def frames_hash(sha_list):
    """Must equal check_design_match.dart `framesHash`: sha256 over the sorted frame hashes, '\\n'-joined."""
    return sha("\n".join(sorted(sha_list)))


def cmd_stamp(args):
    if len(args) != 1:
        die("stamp takes exactly one S-id")
    sid = args[0]
    path = os.path.join(MATCH, f"{sid}.json")
    if not os.path.exists(path):
        die(f"{os.path.relpath(path, ROOT)} does not exist — write the record first (ADR 2026-10-05 §2 step 4)")
    rec = json.load(open(path, encoding="utf-8"))
    index = load_index()
    keys = set(rec.get("frames", []))  # a key named twice is one frame; the gate hashes the same set
    pool = [f for fs in index["screens"].values() for f in fs] + [f for fs in index["variants"].values() for f in fs]
    shas = [f["sha256"] for f in pool if f["frame"] in keys]
    missing = keys - {f["frame"] for f in pool}
    if missing:
        die(f"record names frames the index does not hold: {sorted(missing)} — re-run `index`?")
    if not rec.get("screen_files"):
        die("record has no screen_files")
    # The gate's rules (check_design_match.dart, ADR 2026-10-05 §2, §4), said here before it says them.
    own = [f["frame"] for f in index["screens"].get(sid, [])]
    owner = {f["frame"]: s for s, fs in index["screens"].items() for f in fs}
    if rec.get("verdict") == "no-canvas":
        if own:
            die(f"'no-canvas' but the canvas has {len(own)} frame(s) for {sid}: {own}")
        if not str(rec.get("nearest", "")).strip():
            die("'no-canvas' needs \"nearest\": the drawn pattern this screen followed")
    else:
        foreign = sorted(k for k in keys if owner.get(k) not in (None, sid))
        if foreign:
            die(f"record names another screen's frame(s): {foreign}")
        unnamed = [k for k in own if k not in keys]
        if unnamed:
            print(f"⚠ frame(s) of {sid} not in the record — the gate reports them stale: {unnamed}")
    rec["hashes"] = {"screens": screens_hash(rec["screen_files"]), "frames": frames_hash(shas)}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(rec, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"stamped {os.path.relpath(path, ROOT)}")


COMMANDS = {"index": cmd_index, "render": cmd_render, "pair": cmd_pair, "stamp": cmd_stamp}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    COMMANDS[sys.argv[1]](sys.argv[2:])

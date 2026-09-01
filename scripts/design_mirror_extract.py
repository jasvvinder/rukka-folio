#!/usr/bin/env python3
"""design_mirror_extract.py — write DesignSync get_file results into design/canvas-mirror/.

Used by /design-pull (.claude/commands/design-pull.md). After the main session has
fetched the mirror-set files with DesignSync get_file, this script recovers every
result byte-exact — inline results from the session transcript, large results from
the persisted tool-results directory — and writes each to the mirror by its
project-relative path. Later occurrences of a path win. Truncated results
(content > 256 KiB) are reported, never written.

Usage: python3 scripts/design_mirror_extract.py <session-id>
       (session id = the Claude Code session UUID; its transcript lives at
        ~/.claude/projects/-Users-office-Github-rukka-folio/<session-id>.jsonl)
"""
import json, os, sys, glob, base64

if len(sys.argv) != 2:
    sys.exit(__doc__)
SESSION_ID = sys.argv[1]
SESSION_DIR = os.path.expanduser("~/.claude/projects/-Users-office-Github-rukka-folio")
TRANSCRIPT = os.path.join(SESSION_DIR, SESSION_ID + ".jsonl")
RESULTS_DIR = os.path.join(SESSION_DIR, SESSION_ID, "tool-results")
MIRROR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "design", "canvas-mirror")

def in_mirror_set(p):
    if p in ("DUPLICATES.md", "TRANSLATION-PENDING.md", "FLOW-RESTRUCTURE-REPORT.md"):
        return True
    return p.startswith("partials/") or (p.startswith("i18n-") and p.endswith(".json"))

envelopes, truncated = {}, set()

def consider(env):
    if not isinstance(env, dict) or env.get("method") != "get_file" or "content" not in env:
        return
    p = env.get("path", "")
    if not in_mirror_set(p):
        return
    if env.get("truncated"):
        truncated.add(p)
        return
    envelopes[p] = env
    truncated.discard(p)

def walk(x):
    if isinstance(x, str):
        s = x.strip()
        if s.startswith('{"method":"get_file"'):
            try:
                consider(json.loads(s))
            except json.JSONDecodeError:
                pass
    elif isinstance(x, dict):
        for v in x.values():
            walk(v)
    elif isinstance(x, list):
        for v in x:
            walk(v)

with open(TRANSCRIPT, "r", encoding="utf-8") as f:
    for line in f:
        if '"method":"get_file"' not in line:
            continue
        try:
            walk(json.loads(line))
        except json.JSONDecodeError:
            continue

for path in sorted(glob.glob(os.path.join(RESULTS_DIR, "*.txt"))):
    try:
        with open(path, "r", encoding="utf-8") as f:
            consider(json.load(f))
    except (json.JSONDecodeError, UnicodeDecodeError):
        continue

wrote, bad = [], []
for p, env in sorted(envelopes.items()):
    target = os.path.join(MIRROR, p)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if env.get("isBase64"):
        with open(target, "wb") as f:
            f.write(base64.b64decode(env["content"]))
    else:
        with open(target, "w", encoding="utf-8") as f:
            f.write(env["content"])
    if target.endswith(".json"):
        try:
            with open(target, "r", encoding="utf-8") as f:
                json.load(f)
        except json.JSONDecodeError as e:
            bad.append(f"{p}: {e}")
            continue
    wrote.append(f"{p} ({os.path.getsize(target)} bytes)")

print(f"WROTE {len(wrote)} files:")
for line in wrote:
    print("  " + line)
if truncated:
    print("TRUNCATED (over the 256 KiB API cap, not written):")
    for p in sorted(truncated):
        print("  " + p)
if bad:
    print("INVALID JSON:")
    for line in bad:
        print("  " + line)
sys.exit(1 if bad else 0)

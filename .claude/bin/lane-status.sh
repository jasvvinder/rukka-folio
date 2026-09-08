#!/usr/bin/env bash
# Rukka Folio — which lanes have landed, and which are only part-way.
# Run at the start of /lane: `complete=True` lanes are done and get dropped from the run;
# `complete=False` lanes hit their turn cap or were killed and must be re-run with their notes.
set -uo pipefail
cd "$(dirname "$0")/../.."
python3 - "${1:-}" <<'PY'
import json, glob, os, sys

want = sys.argv[1] if len(sys.argv) > 1 else ""
files = sorted(glob.glob(".claude/lane-reports/*.json"))
if want:
    files = [f for f in files if want in os.path.basename(f)]

if not files:
    print("No lane reports. Nothing has landed yet — every requested lane runs.")
    raise SystemExit(0)

print(f"{'report':<28}{'complete':<10}{'tests':<7}open  notes")
print("-" * 92)
todo = []
for f in files:
    try:
        d = json.load(open(f))
    except Exception as e:
        print(f"{os.path.basename(f):<28}{'UNREADABLE':<10}{'-':<7}-     {e}")
        todo.append(os.path.basename(f).removesuffix(".json"))
        continue
    done = d.get("complete")
    if done is not True:
        todo.append(os.path.basename(f).removesuffix(".json"))
    print(f"{os.path.basename(f):<28}{str(done):<10}{len(d.get('tests', [])):<7}"
          f"{len(d.get('open', [])):<6}{(d.get('notes') or '')[:44]}")
print("-" * 92)
if todo:
    print("RE-RUN (incomplete): " + ", ".join(todo))
    print("  Feed each lane its own `notes` so it does not redo finished work.")
else:
    print("All reported lanes complete — safe to /gate.")
PY

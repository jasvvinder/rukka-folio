#!/usr/bin/env bash
# Rukka Folio — where the build stands, and what to start next.
# Regenerates .claude/state.json, then renders it.
#   .claude/bin/board.sh           full board
#   .claude/bin/board.sh --line    one line (for the statusline)
set -uo pipefail
cd "$(dirname "$0")/../.."
.claude/bin/rf-state.py >/dev/null 2>&1
python3 - "${1:-}" <<'PY'
import json, sys

mode = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    s = json.load(open(".claude/state.json"))
except Exception as e:
    print(f"board: no state ({e}) — run .claude/bin/rf-state.py"); raise SystemExit(0)

B, D, DIM, R, Y, G = "\033[1m", "\033[0m", "\033[2m", "\033[31m", "\033[33m", "\033[32m"
sp, bu = s["spend"], s["budget"]
M = lambda n: f"{n/1_000_000:.2f}M"
desk_open = [d for d in s["desk"] if not d["done"]]

def bar(used, cap, w=18):
    if not cap: return "░" * w + "  no ceiling set"
    f = min(1.0, used / cap)
    col = G if f < .6 else (Y if f < .9 else R)
    return f"{col}{'█' * round(f*w)}{D}{DIM}{'░' * (w - round(f*w))}{D} {M(used)}/{M(cap)} ({round(f*100)}%)"

if mode == "--line":
    day = f"{round(100*sp['today']/bu['daily_tokens'])}%" if bu.get("daily_tokens") else M(sp["today"])
    wk  = f"{round(100*sp['week']/bu['weekly_tokens'])}%" if bu.get("weekly_tokens") else M(sp["week"])
    wip = sum(1 for l in s["layers"] if l["state"] != "done")
    print(f"RF {s['branch']} · {wip} layer(s) open · desk {len(desk_open)} · "
          f"day {day} · week {wk} · {s['dirty_paths']} dirty")
    raise SystemExit(0)

W = 74
line = lambda ch="─": print(f"├{ch*W}┤")
def row(t, pad=0):
    raw = "".join(c for c in t if ord(c) < 0x2500 or c in "✅\U0001f7e1⬜⛔─")
    print(f"│ {t}{' ' * max(0, W - 1 - _w(t) - pad)}│")
def _w(t):
    import unicodedata, re
    t = re.sub(r"\033\[[0-9;]*m", "", t)
    return sum(2 if unicodedata.east_asian_width(c) in "WF" or ord(c) > 0x1F000 else 1 for c in t)

print(f"┌{'─'*W}┐")
row(f"{B}RUKKA FOLIO{D}   {s['branch']}   plan as of {s['asof'] or '?'}")
row(f"{DIM}{s['head'][:66]}{D}")
line()
row(f"{B}LAYERS{D}")
for l in s["layers"]:
    ms = ", ".join(l["milestones"][:3])
    mixed = f"{DIM}(part){D}" if l.get("mixed") else ""
    row(f"  {l['mark']} {l['name']:<26} {ms:<14} {mixed}")
line()
row(f"{B}YOUR DESK{D}  {len(desk_open)} open   {DIM}(nothing below moves until these do){D}")
if not desk_open:
    row(f"  {G}clear{D}")
for d in desk_open:
    row(f"  ⛔ {d['id']:<8} {d['title'][:52]}")
    if d["blocks"]:
        row(f"    {DIM}↳ holds: {', '.join(d['blocks'])}{D}")
if not any(d["blocks"] for d in desk_open):
    row(f"  {DIM}tip: add ⟦blocks: KEY, KEY⟧ to a PLAN.md desk line to link it to lanes{D}")
line()
row(f"{B}LANES{D}  {s['lanes_total']} report(s) · {len(s['lanes_partial'])} part-way · "
    f"{s['open_blockers']} verified blocker(s) unrouted")
for k in s["lanes_partial"][:6]:
    row(f"  {Y}◐{D} {k}")
line()
row(f"{B}BUDGET{D}   {DIM}measured spend; quota is owner-set (no script can read it){D}")
row(f"  today  {bar(sp['today'], bu.get('daily_tokens'))}" + (f"  {Y}override{D}" if bu.get("daily_override") else ""))
row(f"  week   {bar(sp['week'], bu.get('weekly_tokens'))}   {DIM}since {sp['week_start']}{D}")
if not bu.get("weekly_tokens"):
    row(f"  {Y}set budget.weekly_tokens in .claude/rf.config.json ( /usage shows it ){D}")
line()
row(f"{B}NEXT{D}")
if desk_open:
    row(f"  1. clear desk item {desk_open[0]['id']}")
if s["lanes_partial"]:
    row(f"  2. /cycle {s['lanes_partial'][0].split('-',1)[-1]}   {DIM}(re-runs part-way lanes with their notes){D}")
else:
    row(f"  2. /cycle <keys>")
row(f"  {DIM}{s['dirty_paths']} uncommitted path(s) in the tree{D}")
print(f"└{'─'*W}┘")
PY

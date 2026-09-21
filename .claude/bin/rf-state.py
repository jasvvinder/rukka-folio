#!/usr/bin/env python3
"""Rukka Folio — the machine-readable state of the build.

Writes .claude/state.json from sources that ALREADY exist. This adds no new
source of truth: every field carries `source`, so a stale field is visible as
stale rather than believed.

  PLAN.md               -> phase, layer table, the owner desk (the "Owner now" list)
  .claude/lane-reports/ -> lanes landed / part-way, and their open items
  ~/.claude/projects/.../workflows/*.json -> token spend (same data wf-spend.sh reads)
  git                   -> dirty tree
  .claude/rf.config.json-> budget ceilings (owner-set; no script can read the quota)

Usage:
  .claude/bin/rf-state.py            # write .claude/state.json
  .claude/bin/rf-state.py --print    # write it and dump it
"""
import json, glob, os, re, subprocess, sys
from datetime import datetime, timedelta

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
os.chdir(ROOT)

DESK_BLOCKS_RE = re.compile(r"⟦blocks:\s*([^⟧]+)⟧")   # ⟦blocks: CER2, CER3⟧
NUM_ITEM_RE = re.compile(r"^(\d+)\.\s+(.*)$")


def sh(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout.strip()
    except Exception:
        return ""


def strip_md(s):
    s = re.sub(r"\*\*|__|`", "", s)
    s = DESK_BLOCKS_RE.sub("", s)
    return re.sub(r"\s+", " ", s).strip()


def load_config():
    try:
        with open(".claude/rf.config.json") as f:
            return json.load(f)
    except Exception:
        return {}


# ---------------------------------------------------------------- PLAN.md
def parse_plan():
    out = {"phase": None, "asof": None, "layers": [], "desk": [], "source": "PLAN.md"}
    try:
        lines = open("PLAN.md", encoding="utf-8").read().splitlines()
    except Exception as e:
        out["error"] = str(e)
        return out

    for ln in lines:
        m = re.match(r"^##\s*0\.\s*Where we are\s*[—-]\s*(.+)$", ln.strip())
        if m:
            out["asof"] = m.group(1).strip()
            break

    # layer table: | `core_ledger` (02) | ✅ M1 | evidence |
    for ln in lines:
        if not ln.startswith("|"):
            continue
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        name, state = strip_md(cells[0]), cells[1]
        if not name or name.lower() in ("layer", "traceability") or set(name) <= set("-: "):
            continue
        # worst mark wins: a row reading "✅ M2 · 🟡 M8/M9" is NOT done.
        order = ["⛔", "⬜", "🟡", "✅"]
        found = [g for g in order if g in state]
        if not found:
            continue
        mark = found[0]
        out["layers"].append({
            "name": name,
            "mark": mark,
            "marks": found,
            "mixed": len(found) > 1,
            "state": {"✅": "done", "🟡": "wip", "⬜": "todo", "⛔": "blocked"}[mark],
            "milestones": re.findall(r"M\d+", state),
        })

    # owner desk: the numbered list under the "Owner now" heading
    in_desk, buf = False, []
    for ln in lines:
        if "Owner now" in ln:
            in_desk = True
            continue
        if in_desk:
            if ln.strip().startswith("---") or ln.startswith("## "):
                break
            buf.append(ln)
    text = "\n".join(buf)
    for raw in text.split("\n"):
        m = NUM_ITEM_RE.match(raw.strip())
        if not m:
            continue
        num, body = m.group(1), m.group(2)
        done = "✅" in body
        blocks = []
        bm = DESK_BLOCKS_RE.search(body)
        if bm:
            blocks = [b.strip() for b in bm.group(1).split(",") if b.strip()]
        title = strip_md(body)
        title = re.sub(r"^(✅|⛔)\s*", "", title)
        out["desk"].append({
            "id": f"PLAN-{num}",
            "done": done,
            "title": (title[:110] + "…") if len(title) > 110 else title,
            "blocks": blocks,
        })
    return out


# ------------------------------------------------------- lane reports
def parse_lanes():
    lanes, open_items = [], []
    for f in sorted(glob.glob(".claude/lane-reports/*.json")):
        key = os.path.basename(f)[:-5]
        try:
            d = json.load(open(f))
        except Exception as e:
            lanes.append({"report": key, "complete": None, "error": str(e)})
            continue
        complete = d.get("complete") is True
        lanes.append({
            "report": key,
            "key": d.get("key", key),
            "complete": complete,
            "tests": len(d.get("tests") or []),
            "files": len(d.get("files") or []),
            "open": len(d.get("open") or []),
            "notes": (d.get("notes") or "")[:160],
        })
        for o in (d.get("open") or []):
            open_items.append({
                "report": key,
                "blocker": "BLOCKER" in o.upper(),
                "lock": "\U0001f512" in o,
                "text": o[:300],
            })
    return lanes, open_items


# ------------------------------------------------------------- spend
def parse_spend():
    now = datetime.now().astimezone()
    week_start = (now - timedelta(days=(now.weekday() + 1) % 7)).replace(
        hour=0, minute=0, second=0, microsecond=0)
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    pat = os.path.expanduser(
        "~/.claude/projects/-Users-office-Github-rukka-folio*/*/workflows/*.json")
    today = week = alltime = 0
    runs_today = runs_week = 0
    for f in glob.glob(pat):
        try:
            d = json.load(open(f))
        except Exception:
            continue
        ts = d.get("timestamp") or ""
        try:
            when = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
        except Exception:
            when = datetime.fromtimestamp(os.path.getmtime(f)).astimezone()
        tok = d.get("totalTokens") or 0
        alltime += tok
        if when >= week_start:
            week += tok
            runs_week += 1
        if when >= day_start:
            today += tok
            runs_today += 1
    return {
        "today": today, "week": week, "alltime": alltime,
        "runs_today": runs_today, "runs_week": runs_week,
        "week_start": week_start.strftime("%a %d %b"),
        "source": "workflow run history (same data as wf-spend.sh)",
        "quota_note": "measured spend only — no script can read the plan quota (ADR 2026-09-13e)",
    }


def main():
    cfg = load_config()
    plan = parse_plan()
    lanes, open_items = parse_lanes()
    spend = parse_spend()

    dirty = [l for l in sh("git", "status", "--porcelain").splitlines() if l.strip()]
    partial = [l for l in lanes if l.get("complete") is False]
    desk_open = [d for d in plan["desk"] if not d["done"]]
    held = sorted({k for d in desk_open for k in d["blocks"]})

    budget = cfg.get("budget", {})
    state = {
        "generated_by": ".claude/bin/rf-state.py",
        "asof": plan.get("asof"),
        "branch": sh("git", "rev-parse", "--abbrev-ref", "HEAD"),
        "head": sh("git", "log", "-1", "--format=%h %s")[:100],
        "dirty_paths": len(dirty),
        "layers": plan["layers"],
        "desk": plan["desk"],
        "desk_open": len(desk_open),
        "lanes_total": len(lanes),
        "lanes_partial": [l["report"] for l in partial],
        "open_items": open_items,
        "open_blockers": sum(1 for o in open_items if o["blocker"]),
        "held_lanes": held,
        "spend": spend,
        "budget": {
            "daily_tokens": budget.get("daily_tokens"),
            "weekly_tokens": budget.get("weekly_tokens"),
            "day_used_pct": (round(100 * spend["today"] / budget["daily_tokens"])
                             if budget.get("daily_tokens") else None),
            "week_used_pct": (round(100 * spend["week"] / budget["weekly_tokens"])
                              if budget.get("weekly_tokens") else None),
        },
        "cycle": cfg.get("cycle", {}),
    }

    with open(".claude/state.json", "w") as f:
        json.dump(state, f, indent=2)
    if "--print" in sys.argv:
        print(json.dumps(state, indent=2))
    else:
        print(f".claude/state.json written · {len(plan['layers'])} layers · "
              f"{len(desk_open)} desk item(s) open · {len(partial)} lane(s) part-way")


if __name__ == "__main__":
    main()

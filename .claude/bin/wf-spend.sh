#!/usr/bin/env bash
# Rukka Folio — what the parallel build has cost, this week and per run.
# Run at the START of a session, before spending more (PLAN.md §3).
# Fable 5.1 resets weekly on Sunday; that reset is the budget this guards.
#   .claude/bin/wf-spend.sh          → since last Sunday
#   .claude/bin/wf-spend.sh --all    → every run on record
set -uo pipefail
ALL="${1:-}"
python3 - "$ALL" <<'PY'
import json, glob, sys, os
from datetime import datetime, timedelta, timezone

show_all = sys.argv[1] == "--all"
now = datetime.now().astimezone()
# last Sunday 00:00 local (weekday(): Mon=0 … Sun=6)
week_start = (now - timedelta(days=(now.weekday() + 1) % 7)).replace(hour=0, minute=0, second=0, microsecond=0)

rows = []
for f in glob.glob(os.path.expanduser("~/.claude/projects/-Users-office-Github-rukka-folio*/*/workflows/*.json")):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    ts = d.get("timestamp") or ""
    try:
        when = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
    except Exception:
        when = datetime.fromtimestamp(os.path.getmtime(f)).astimezone()
    models = sorted({p.get("model") for p in (d.get("workflowProgress") or []) if p.get("model")}) or \
             ([d["defaultModel"]] if d.get("defaultModel") else [])
    rows.append({
        "when": when, "run": d.get("runId", "?"), "wf": d.get("workflowName", "?"),
        "status": d.get("status", "?"), "agents": d.get("agentCount") or 0,
        "tokens": d.get("totalTokens") or 0,
        "min": round((d.get("durationMs") or 0) / 60000, 1),
        "models": ", ".join(m.replace("claude-", "") for m in models),
    })
rows.sort(key=lambda r: r["when"])
shown = rows if show_all else [r for r in rows if r["when"] >= week_start]

if not shown:
    print(f"No workflow runs since {week_start:%a %d %b}. Full budget available.")
    raise SystemExit(0)

print(f"{'when':<14}{'run':<18}{'wf':<17}{'status':<11}{'ag':>3}{'tokens':>11}{'min':>6}  models")
print("-" * 96)
for r in shown:
    print(f"{r['when']:%d %b %H:%M}  {r['run']:<18}{r['wf']:<17}{r['status']:<11}"
          f"{r['agents']:>3}{r['tokens']:>11,}{r['min']:>6}  {r['models']}")
print("-" * 96)

tot = sum(r["tokens"] for r in shown)
fable = sum(r["tokens"] for r in shown if "fable" in r["models"])
label = "all time" if show_all else f"since {week_start:%a %d %b}"
print(f"{len(shown)} run(s) {label}: {tot:,} tokens total · {fable:,} on fable")
n_fable = sum(1 for r in shown if "fable" in r["models"])
if not show_all:
    print(f"fable runs this week: {n_fable} / 2 budgeted  "
          + ("⚠️ OVER BUDGET — escalate only with the owner's say-so" if n_fable > 2 else "(escalation tier)"))
killed = [r["run"] for r in shown if r["status"] != "completed"]
if killed:
    print(f"did not complete: {', '.join(killed)} — check .claude/lane-reports/ before re-running those lanes")
PY

---
name: lane
description: Run one to three Rukka Folio build lanes as tiered subagents (disjoint directories, tests-first against named spec sections), write durable reports, then stop without gating. This is the default way to build M4 onward — one lane per session wherever possible.
---

# /lane $ARGUMENTS

`$ARGUMENTS` = the lane keys to run — normally **one** (`U2`), at most **three** (`S Y`). One
`/lane` per session. You are the orchestrator: you hold PLAN rows and lane reports, **nothing else**.
You do not implement, and you do not gate.

## 0. Budget check (always, first)
```bash
.claude/bin/wf-spend.sh
```
Fable 5.1 resets weekly on **Sunday** — that reset is the budget. If the week already shows a
`fable` run, no lane goes to `lane-core` without the owner saying so. If a past run shows
`killed`, check `.claude/lane-reports/` before re-running its lanes.

## 1. Prepare (≈ 5 minutes, no code)
1. Read **`PLAN.md` §0 and only the rows for the requested lanes.** Not CHANGELOG, not whole specs.
2. **Skip what already landed:**
   ```bash
   .claude/bin/lane-status.sh          # or: lane-status.sh M4   to filter
   ```
   `complete=True` → that lane is done: drop it from the run and use its report.
   `complete=False` → it hit its turn cap or was killed part-way: **re-run it**, and put its
   `notes` in the new prompt so it does not redo finished work.
   This is what makes a session-limit kill cheap — the work survives on disk even when the run
   does not. Lanes carry a `maxTurns` cap, so a partial report is a normal outcome, not a fault.
3. **Confirm the directories are disjoint.** If two lanes need the same file, either give it to one
   lane and let the other consume an interface with a fake, or run it first, alone.
4. **Pick the tier** — this is the whole point, so pick deliberately:

   | Agent | Model · effort · turns | For |
   |---|---|---|
   | `lane-mech` | haiku · low · 15 turns | ARB drafts, l10n parts, fixtures, codegen and token regen, file moves |
   | `lane-ui` | sonnet · medium · 40 | **repeat** screens by S-id (13 §3.2) on a settled pattern, F1 widget tests |
   | `lane-ui-hard` | opus · medium · 40 | new design-system components, foundation (theme/shell/nav), 200% · 360×800 layout defects, state-machine screens (S10, S15, S7) |
   | `lane-server` | opus · medium · 40 | migrations + RLS, edge functions, hostile-query tests |
   | `lane-sync` | opus · medium · 50 | `sync_engine`, ordering/cursor/conflict/trust logic, projector |
   | `lane-core` | fable · high · 60 | ⚠️ **escalation only** — see §4 |

   Each tier preloads its own skill (`ui-screen`, `server`, `sync-slice`) and is denied
   `WebSearch`/`WebFetch` — the specs are local. If a lane's work genuinely will not fit its turn
   cap, **split the work**, do not raise the cap.

   The four build lanes run `permissionMode: acceptEdits`, so they will not stall on edit prompts
   mid-run — which also means **nothing enforces the directory split but the prompt you write.**
   Step 3 is therefore load-bearing: name each lane's directories exactly, and never give two
   concurrent lanes a path in common.

   Model and effort live in `.claude/agents/*.md`, **not** in your args. Do not pass `model` or
   `effort` unless you are deliberately overriding a tier, and say why when you do.
   **Opus at the ends, never haiku on tests** (ADR 2026-09-08b). A settled-pattern screen goes to
   `lane-ui`; a new component, foundation work, a 200%/360×800 layout defect or a state-machine
   screen goes to `lane-ui-hard`. `lane-mech` never authors a test — test authoring belongs to the
   lane that owns the behaviour. **Tier up, never cap up:** if the work will not fit 40 turns,
   split it (§1.3).

   **No lane starts on `lane-core`.**
5. For each lane write a prompt with, in this order:
   - the **spec sections by number** (`03 §2.3, §2.5; ADR 2026-09-05b §5`) — sections, not docs
   - the **test ids to write first** (09 §2 and the `⟦tests: …⟧` markers) and the id it must mint
     for new tests (`<Suite>-<source>-<n>`; `dart run scripts/check_coverage.dart` gives the next free number)
   - the work itself
   The repo rules, the skill to follow, the report path and the return shape all come from the
   agent definition — **do not restate them in the prompt.**

## 2. Run
```
Workflow({ name: 'lanes', args: { milestone: 'M4', lanes: [
  { key: 'U2', agent: 'lane-ui', dirs: ['app/lib/features/entry', 'app/test/features/entry'], prompt: '…' }
] } })
```
If the name does not resolve, `Workflow({ scriptPath: '.claude/workflows/lanes.js', args })`.
The script caps the run at 3 lanes and refuses more.

**While it runs, do nothing.** Do not poll, do not pre-read lane files, do not start the next thing.

## 3. Integrate — only what a lane cannot do alone
- Wire feature `routes` into `app/lib/shared/router.dart`.
- Merge ARB parts: `dart run scripts/gen_l10n_arb.dart`.
- `dart pub get` if a lane added a dependency.

If the result has **`ok: false`**, `incomplete` names the lanes that either died (usually the
session limit) or hit their turn cap. Re-run `/lane <those keys>` in a fresh session, feeding each
one its own report's `notes`. **Do not gate on a partial phase.**

## 4. Escalation (the only route to Fable)
`escalate` in the result lists lanes whose `open` items mention 🔒, an ADR, a golden, or a STOP.
Escalation is **the owner's call, never automatic**:
- a 🔒 line needs changing → `/adr`, owner ratifies; no lane changes a 🔒 line
- a suite-A golden disagrees with the engine → **stop and ask** (CLAUDE.md § Accounting authority)
- `core_ledger`/`core_crypto` behaviour must change, or a lower tier genuinely could not resolve
  the logic → one `lane-core` run, scoped to that blocker alone

## 5. Stop here
**Do not run the gate.** The gate is a separate invocation (`/gate`) so that a limit hit costs one
lane, not a phase. Report to the owner:
- lanes run, with tier and test ids
- `incomplete` and `escalate`, if any
- what you integrated
- the next single step (`/gate`, or `/lane <key>`)

Then say plainly: **run `/clear` before the next lane.** A fresh session is the cheapest session.

## Economy rules (PLAN.md §3)
Lanes never run `ci.sh`, never read whole docs, never re-read files after editing; one gate per
phase, one fix pass; reports are JSON. Never spawn a lane for what a `grep` answers, or for work
under ~30 minutes — do that inline.

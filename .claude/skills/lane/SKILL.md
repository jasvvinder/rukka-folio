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
   ls .claude/lane-reports/ 2>/dev/null
   ```
   A lane with a report there is done — drop it from the run and use the report. This is what
   makes a session-limit kill cheap: the work survives on disk even though the run did not.
3. **Confirm the directories are disjoint.** If two lanes need the same file, either give it to one
   lane and let the other consume an interface with a fake, or run it first, alone.
4. **Pick the tier** — this is the whole point, so pick deliberately:

   | Agent | Model · effort | For |
   |---|---|---|
   | `lane-mech` | haiku · low | ARB drafts, l10n parts, fixtures, codegen and token regen, file moves |
   | `lane-ui` | sonnet · medium | screens by S-id (13 §3.2), feature folders, F1 widget tests |
   | `lane-server` | sonnet · medium | migrations + RLS, edge functions, hostile-query tests |
   | `lane-sync` | opus · medium | `sync_engine`, ordering/cursor/conflict/trust logic, projector |
   | `lane-core` | fable · high | ⚠️ **escalation only** — see §4 |

   Model and effort live in `.claude/agents/*.md`, **not** in your args. Do not pass `model` or
   `effort` unless you are deliberately overriding a tier, and say why when you do.
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

If the result has **`ok: false`**, some lane died (usually the session limit). Its files may be on
disk but its report is not: re-run `/lane <those keys>` in a fresh session. **Do not gate on a
partial phase.**

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

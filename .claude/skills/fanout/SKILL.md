---
name: fanout
description: Run one phase of PLAN.md as parallel lanes — subagents owning disjoint directories, tests-first against named spec sections — then a single gate + fix pass. Use for any milestone work larger than one module; this is the default way to build M4 onward.
---

# /fanout $ARGUMENTS

`$ARGUMENTS` = the phase or lane set (`A`, `M4`, `U2 U3`). One `/fanout` per session; the
orchestrator (you) reads PLAN rows and lane reports and nothing else.

## 1. Prepare lanes (≈ 5 minutes, no code)
1. Read `PLAN.md` §0 and the rows for the requested lanes. Each ⬜ module becomes work for exactly
   one lane. **Confirm the lanes' directories are disjoint**; if two lanes need the same file,
   move that file into P0 (done first, alone) or give it to one lane and have the other consume an
   interface with a fake.
2. For each lane write a prompt with, in this order:
   - the directories it owns (and that it must not touch anything else)
   - the spec sections by number (`03 §2.3, §2.5; ADR 2026-09-05b §5`) — **sections, not docs**
   - the test ids to write first (from 09 §2 and the `⟦tests: …⟧` markers) and the id it must
     mint for new tests (`<Suite>-<source>-<n>`; check `dart run scripts/check_coverage.dart`
     output for the next free number)
   - the skill it should follow: `ui-screen`, `server`, `sync-slice`, or `slice`
   - what to return: the `LANE_SCHEMA` object (files, tests, open, notes) — no prose
3. Pick `effort`/`model` per lane: mechanical (ARB drafts, fixtures, codegen) → `low` + `haiku`;
   logic → default; `core_*` or security-sensitive verification → `high`.

## 2. Run
Use the saved workflow: `Workflow({ name: 'milestone-lanes', args: {...} })`; if the name is not
found, `Workflow({ scriptPath: '.claude/workflows/milestone-lanes.js', args })`. Args shape:
```json
{ "milestone": "M4", "lane": "push",
  "lanes": [ { "key": "S", "dirs": ["server/supabase"], "prompt": "…", "effort": "medium" } ] }
```
The workflow runs all lanes in parallel, then one gate agent (`LANE=push ./scripts/ci.sh`) that fixes
only mechanical failures (format, generated files, analyzer infos) and reports the rest. While it
runs, do nothing — do not poll, do not pre-read lane files.

## 3. Integrate (only what lanes cannot do alone)
- Wire feature `routes` into `app/lib/shared/router.dart`; merge ARB parts (`dart run
  scripts/gen_l10n_arb.dart`); run `dart pub get` if a lane added a dependency.
- If the gate is red on logic: one fix agent per failing suite, with the failing test names and
  assertion messages verbatim. One round. Still red → report to the owner, do not loop.
- A failing suite-A golden is never patched (CLAUDE.md § Accounting authority) — stop and ask.

## 4. Close
`/plan` (mark ✅ only for ids green in the gate) → `/changelog` → report: lanes, tests by id,
⚠️ items, suggested commit `M<n>: <what>`. The owner commits.

## Economy rules (PLAN.md §3 apply)
Lanes never run `ci.sh`, never read whole docs, never re-read files after editing; one gate, one
fix pass; return JSON. Never fan out for work under ~30 minutes — do it inline.

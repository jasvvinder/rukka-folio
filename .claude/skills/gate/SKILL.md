---
name: gate
description: Run the CI gate (scripts/ci.sh) once for a lane as a separate cheap subagent, then report failures grouped by step and suite with the fix for each. Use after /lane reports ok:true, before handing files to the owner, or when asked "does CI pass".
---

# /gate $ARGUMENTS

`$ARGUMENTS` is the lane: `push` (default), `nightly`, `rc`, `release` (ADR 2026-09-05i §2).
`ci.sh` honours `LANE` since M2: nightly re-enables `flaky` tests; steps a lane does not own yet
print *scheduled — lands at M<n>* — report those as **scheduled**, not as passed.

## Run it as its own agent
```
Workflow({ name: 'gate-run', args: { lane: 'push', landed: [ { key, files, tests } ] } })
```
Fallback: `Workflow({ scriptPath: '.claude/workflows/gate-run.js', args })`.

The `gate` agent (`.claude/agents/gate.md`, sonnet · low) pipes `ci.sh` to a file and greps it, so
the full CI log never enters your context. **Do not run `ci.sh` in this session yourself** — that
is the single most expensive thing the orchestrator can do.

First, refuse to gate a partial phase: if the last `/lane` returned `ok: false`, or
`ls .claude/lane-reports/` is missing a lane the phase needs, re-run that lane instead.

## Report
Lead with **green** or **red**. If red, one bullet per failing step in `ci.sh` order:
- **generated files** — which of `tokens.css`/`tokens.dart`/identifier ARBs drifted; fix is
  `dart run scripts/gen_tokens.dart` or `dart run scripts/gen_l10n_arb.dart`.
- **format** — files; fix is `dart format <paths>`.
- **purity** — the `PURITY:` lines verbatim; these are CLAUDE.md rules 3 and 7 and the hex-literal rule.
- **strings** — missing EN/PA/HI keys, placeholder drift, forbidden jargon (01 §1.3).
- **analyze** — per package, error count and the first three diagnostics.
- **tests** — per package: failed test names (they start with their suite id, so group by suite
  A/B/C/D/E/F1/G) and the assertion message verbatim.

The gate agent has already fixed what is mechanical and re-run once. What comes back is
behavioural. Route it:
- a failure inside one lane's directories → **one fix agent for that lane's tier**, with the
  failing test names and assertion messages verbatim. **One round.** Still red → report to the
  owner, do not loop.
- a failing **suite-A golden** → the engine and the worked examples disagree: **stop and ask**.
  Never patch the fixture (CLAUDE.md § Accounting authority).
- a 🔒 line in the way → `/adr`, owner ratifies. Never `git commit`.

Then, per ADR 2026-09-12b §6, **keep filling the session**: green gate → next `/lane` round →
`/gate` again. `/close` is for when the budget is genuinely low or the phase is done, not after
every gate.

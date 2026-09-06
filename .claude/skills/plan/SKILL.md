---
name: plan
description: Refresh PLAN.md — mark modules ✅ from test ids that are green, update the "Where we are" table and phase status, add newly discovered ⬜/⛔ items. Use at the end of every session, before /changelog.
---

# /plan $ARGUMENTS

`$ARGUMENTS` = optional milestone/lane hint (`M4 S Y`).

## Gather (cheap)
```bash
dart run scripts/check_coverage.dart 2>&1 | head -5     # tests · ids · orphans line
git status --porcelain --untracked-files=all | head -40
```
Plus the lane reports / gate result from this session. Do **not** run the test suites here — the gate did.

## Update PLAN.md
1. **§0 table** — one line per layer: state (✅/🟡/⬜) and the evidence (suite, test count). Date in the heading.
2. **§2 modules** — flip ⬜ → ✅ **only** for modules whose ids passed in this session's push-lane gate; ⬜ → 🟡 for started-but-red; add ⬜ rows for work discovered; ⛔ for anything waiting on the owner or an external party (and add it to §4 if it has a lead time).
3. **§1 phase row** — mark the phase exit met/unmet in one word; never move dates silently — propose a new date in the changelog Open list instead.
4. Keep the file under ~200 lines; a module line is one line. History belongs in `CHANGELOG.md`, specs in `docs/`.

## Never
- Mark ✅ from a lane's self-report alone — the gate must have been green on that id.
- Record decisions here — a 🔒 change needs `/adr`.
- Put financial data, keys or secrets in the file.

Then run `/changelog`.

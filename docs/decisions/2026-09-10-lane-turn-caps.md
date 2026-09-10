# ADR 2026-09-10 — Lane turn caps roughly double; "tier up, never cap up" is narrowed

**Status:** accepted (owner-directed, 10 Sep 2026)
**Supersedes:** the "**Tier up, never cap up**" clause of ADR 2026-09-08b §Tiers, and the
matching 🔒 line in `CLAUDE.md` § Session economy. Every other ruling of 2026-09-08b —
model per tier, Opus at the ends, **never haiku on a test** — stands unchanged.

## Context

ADR 2026-09-08b set per-tier `maxTurns` (mech 15 · ui/ui-hard/server 40 · sync 50 · core 60) and
forbade raising them: *"every lane death this week was over-scoping against `maxTurns`, not model
quality — split the work."* On the evidence available on 8 Sep that was right.

Lane **M5-U2a** then died at its cap twice (9 Sep, 10 Sep) on work that was not over-scoped: the
second run had two screens to write and two tests to land. Its transcript
(`wf_33b04890-cfe`, 64 tool calls, 19.6 min) shows where the budget actually went:

1. **Calls 1–20 were orientation** — re-reading `home_data.dart`, all 652 lines of
   `home_cards.dart`, the ARB, `test_app.dart`, `local_ledger.dart` and nine spec greps, all of
   which the orchestrator's prompt had already summarised as done. The first `Write` was call 21.
   This is not waste the lane could have avoided: **CLAUDE.md rule 11 requires a lane to verify
   before it asserts**, so a file inventory in a prompt is a reading list, not a shortcut. Rule 11
   and a 40-turn cap are in direct tension, and rule 11 is the one worth keeping.
2. **Calls 31–63 were one slow test** — a widget test whose failure mode is a ten-minute
   timeout. Each iteration cost a turn *and* ten minutes, so the lane paid full price per attempt
   on the very defect the attempts were meant to fix.

Neither cause is over-scoping, and neither is fixed by splitting: half of a task still pays the
orientation toll, and a slow test is slow in either half.

## Decision

1. **Caps roughly double.** `lane-mech` 15 → **30** · `lane-ui`, `lane-ui-hard`, `lane-server`
   40 → **90** · `lane-sync` 50 → **110** · `lane-core` 60 → **120**. The values live in
   `.claude/agents/*.md` frontmatter, as before; a lane is still chosen by naming an agent.
2. **"Tier up, never cap up" is narrowed, not deleted.** It remains the right answer to its
   original case — *a lane that genuinely has too many screens in it*. It is no longer a reason to
   refuse a cap that a verification toll or a slow suite has made too small. Splitting stays the
   first instinct for scope; the cap is no longer a hard ceiling to design around.
3. **A cap is a backstop, not a budget.** Doubling the ceiling does not license doubling the work
   per lane; §M5's ~2–3 screens per lane is unchanged. The cap exists so that a lane which hits an
   unforeseen cost finishes instead of dying with a partial report.
4. **The orchestrator stops shipping file inventories.** A lane prompt states the *rule*
   ("everything outside `screens/` and `test/` is settled; the feature compiles") rather than
   listing the files that are done, which under rule 11 only commissions the reads it meant to save.

## Consequences

- A killed lane still writes a durable report; that machinery is unchanged.
- Cost per lane death rises with the cap. The mitigation is (4) plus the standing rule that lanes
  never run `ci.sh` and never re-read files after editing — not a lower ceiling.
- If a lane now dies at 90 turns, the cap is not the diagnosis. Read the transcript before
  raising it again.

⟦tests: n/a — process rule, not behaviour⟧

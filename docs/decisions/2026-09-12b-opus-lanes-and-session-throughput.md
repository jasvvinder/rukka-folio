# ADR 2026-09-12b — Every build lane is Opus; caps double again; a session is filled, not ended

**Status:** accepted (owner-directed, 12 Sep 2026)
**Supersedes:** the **model** column of ADR 2026-09-08b (`lane-ui` on sonnet) and the **caps** of
ADR 2026-09-10; the *one lane per session* and *never chain the next lane* clauses of `CLAUDE.md`
§ Session economy. Everything else in 2026-09-08b stands — tiers are structural, chosen by naming
an agent, and **`lane-mech` never authors a test**.

## Context

Two things were true at the end of the 12 Sep (e) session:

1. **The budget was barely touched.** Two lanes (U1e trust branch, U3d FY switcher), a gate and a
   close finished the session at **29 %** of the limit. The session economy was written on 7–8 Sep
   when a session died mid-phase; its answer — one lane, then `/clear` — solved that by spending
   less. It now leaves roughly two-thirds of every session unused, which is the same waste in the
   other direction: milestones arrive slower than the budget allows.
2. **Lane deaths this week were never model quality.** M5-U2a died twice at its cap, U2d took
   three runs, U3c was finished inline after a kill. ADR 2026-09-10 diagnosed the first correctly
   (a rule-11 verification toll and a slow widget test) and doubled the caps. The deaths stopped,
   but the tier ladder still put a sonnet lane on repeat screens and medium effort on the two
   adversarial tiers — `lane-server` (RLS, hostile queries) and `lane-sync` (ordering and trust,
   where a subtle error is a green test over a wrong ledger).

The owner's direction, 12 Sep: raise the lanes, raise the caps, do not let a lane fail or be
interrupted, and take as many milestones per session as the budget allows.

## Decision

1. **Every build lane is Opus.** `lane-ui` **sonnet → opus**, effort medium. `lane-ui-hard`,
   `lane-server` and `lane-sync` move to **high** effort. `lane-mech` stays **haiku · low** —
   transcription from a source of truth is the one job a small model does safely, and it still
   never touches a test. `lane-core` is unchanged (**fable · high**), still escalation-only, still
   **2 runs per week**.
2. **The UI split survives the model merge as an effort split.** With `lane-ui` on Opus the two UI
   tiers share a model, so the distinction is now **medium vs high effort** plus the prompt: settled
   repeat screens on `lane-ui`, new components, foundation work, 200 % / 360×800 defects and
   state-machine screens on `lane-ui-hard`. ⚠️ The owner named three tiers explicitly; raising
   `lane-ui-hard` to high is the orchestrator's inference, so that the hard tier does not become
   indistinguishable from the easy one. Say so if the intent was for both to sit at medium.
3. **Caps roughly double again**, so that a cap is never the reason a slice comes back partial:
   `lane-mech` 30 → **60** · `lane-ui`, `lane-ui-hard`, `lane-server` 90 → **180** · `lane-sync`
   110 → **220** · `lane-core` 120 → **240**. The `gate` agent goes 20 → **40**.
4. **The gate gains `permissionMode: acceptEdits`.** It is allowed to fix mechanical failures
   (`dart format`, generated files) but had no edit permission mode, so it could stall on a prompt
   with the whole CI run already paid for. Every build lane already had it.
5. **`MAX_LANES` 3 → 5** per `/lane` run.
6. **Fill the session.** A session now runs **round after round** — `/lane` → `/gate` → `/lane` → …
   — until the remaining budget is genuinely low or the phase is done, and then `/close` **once**.
   `/clear` at the end of a session, not after every lane.

## What does not change

- **Disjoint directories are per *run*, not per session.** Lanes inside one round must own disjoint
  directories; the next round may take the directories the last one released. This is the rule that
  the lane prompt alone enforces (edits are auto-accepted), so it stays load-bearing — more lanes
  per run makes it *more* so, not less.
- `/gate` is still its own invocation, never inside a lane run.
- Lanes still never run `ci.sh`, never read whole docs, never re-read a file after editing.
- Reports are still durable and `complete: false` until the work is wholly done — a bigger cap
  makes a partial report rarer, it does not make it impossible.
- **No lane starts on `lane-core`**, and the weekly fable budget is untouched at 2.

## Consequences

- **Cost per session rises on both axes** — a more expensive model on every build lane, and more
  rounds per session. That is the intended trade: the constraint being optimised is now
  milestones per session, not tokens per lane.
- **`.claude/agents/*.md` is the source of truth** for model, effort and turns, as before. Two
  further files carry copies of the tier table — `CLAUDE.md` § Session economy and `PLAN.md` §3 —
  and both are updated here. `PLAN.md` §3 was found **three ADRs stale** (sonnet `lane-server`, no
  `lane-ui-hard` row, pre-10 Sep caps); corrected in the same commit.
- **A cap is still a backstop, not a budget.** §M5's ~2–3 screens per lane is unchanged. If a lane
  now dies at 180 turns, the cap is not the diagnosis — read the transcript.

## Open ⚠️

- Two files could not be edited from the session that wrote this ADR — the harness refuses
  self-modification of its own skill and workflow definitions. **The owner must apply both by hand**
  or the decision is only half in force:
  - `.claude/workflows/lanes.js:27` — `const MAX_LANES = 3` → `5` (without it, decision 5 is inert
    and a 4-lane run is refused).
  - `.claude/skills/lane/SKILL.md` §1.4 — the tier table still shows the old models, efforts and
    caps. The agent files govern at run time, so lanes already run at the new tiers; the stale table
    misinforms the orchestrator choosing one.

⟦tests: n/a — process rule, not behaviour⟧

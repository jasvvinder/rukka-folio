---
name: cycle
description: Run one full Rukka Folio build cycle — build the slices, review each one read-only, adversarially verify every finding, send the survivors back to the lane that owns them, and stop ready-to-commit. One cycle is about one day at the pacing ceiling. The gate stays a separate run.
---

# /cycle $ARGUMENTS

`$ARGUMENTS` = the slice keys for this cycle — at most **three**. You are the orchestrator: you
hold the board, the slice rows and the cycle result, **nothing else**. You do not implement, you
do not review, and you do not gate.

## 0. The board (always, first)

```bash
.claude/bin/board.sh
```

It regenerates `.claude/state.json` and prints where the build stands: layers, **your desk**,
part-way lanes, unrouted blockers, and today's and this week's spend against the ceilings in
`.claude/rf.config.json`.

Two stopping rules, both read off that board:

- **Desk first.** If an open desk item `⟦blocks:⟧` a slice in this cycle, that slice does not run.
  Say which item holds it and what answer would release it.
- **Budget.** If today's spend is already at or over `budget.daily_tokens`, do not start a cycle.
  Say so and stop — the ceiling exists because 17–19 Sep burned 11.8 M, 45 % of all-time spend,
  in three days. `budget.weekly_tokens` is owner-set: no script can read the plan quota
  (ADR 2026-09-13e; `wf-spend.sh` says so in its own comment).

## 1. Prepare (≈5 minutes, no code)

1. **`PLAN.md` §0 and only the rows for the requested slices.** Not CHANGELOG, not whole specs.
2. **Skip what landed, resume what did not** — the board's part-way list is `complete: false`
   reports. Re-run those, and put their `notes` and `open` items in the new prompt so the lane does
   not redo finished work.
3. **Confirm the directories are disjoint.** `cycle.js` now checks this and throws, but the check
   is a backstop: two slices sharing a path is a design error in the split, not a runtime one.
4. **Pick the tier per slice** — `lane-mech` (haiku·low) transcription only, never a test ·
   `lane-ui` (opus·high) repeat screens · `lane-ui-hard` (opus·high) new components, foundation,
   200 %/360×800, state machines · `lane-server` (opus·high) migrations, RLS, edge functions ·
   `lane-sync` (opus·high) ordering, cursors, trust · `lane-core` (fable·high) **escalation only,
   owner's say-so**. Model and effort live in `.claude/agents/*.md` — never pass them as args.

## 2. Run

```js
Workflow({ name: 'cycle', args: {
  milestone: 'M12',
  slices: [
    { key: 'U1', agent: 'lane-ui', dirs: ['app/lib/features/x', 'app/test/features/x'],
      prompt: '…S-ids, spec sections, states, the F1 test…' },
    { key: 'S1', agent: 'lane-server', dirs: ['server/supabase/migrations'], risk: 'high',
      prompt: '…' },
  ],
}})
```

If the name does not resolve: `Workflow({ scriptPath: '.claude/workflows/cycle.js', args })`.

What it does, per slice, in a pipeline (slice A reviews while slice B still builds):

| Stage | Who | Notes |
|---|---|---|
| **Build** | the named tier | writes `<M>-<key>.json` as it goes |
| **Review** | `lane-review` (opus·high, **read-only**) | test-honesty first; writes `<M>-<key>.review.json` |
| **Verify** | 3 lenses on high-risk paths, 1 elsewhere | each prompted to **refute**; majority kills |
| **Repair** | the original tier | confirmed findings only; **bounded at 2 rounds** |

`risk: 'high'` is inferred from the directories (`core_*`, `sync_engine`, `server/…`) — set it
explicitly only to force the 3-vote panel somewhere else.

## 3. After

- **`/gate` is a separate invocation.** Never inside the cycle run: a session-limit kill must cost
  one stage, not the phase (ADR 2026-09-12b, unchanged).
- Findings the repair lane **disputed** and items still open after 2 rounds come back as
  `owner_items`. Put them on the desk in `PLAN.md` — with `⟦blocks: KEY⟧` if they hold a lane —
  rather than starting a third round.
- Then `/close`: `/plan` → `/changelog` → the commit block for the owner → `/clear`.

## Rules that do not change

- Lanes never run `ci.sh`, never read whole docs, never re-read a file after editing.
- Reports stay durable and `complete: false` until the work is wholly done.
- Disjoint directories are per **run**; the next cycle may take what this one released.
- A 🔒 line changed needs an ADR — the lane reports it in `open`, it does not edit the line.

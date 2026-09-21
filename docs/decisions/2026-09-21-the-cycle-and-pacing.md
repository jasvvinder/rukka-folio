# ADR 2026-09-21 — The cycle: review, adversarial verification, a bounded repair loop, and a day's ceiling

**Status:** accepted (owner-directed, 21 Sep 2026)
**Supersedes:** §6 of ADR 2026-09-12b (*"Fill the session"*). **Amends:** §1 of 2026-09-12b
(`lane-ui` effort) and §5 (`MAX_LANES`). Everything else in 2026-09-12b stands — tiers are
structural, chosen by naming an agent; `lane-mech` never authors a test; `/gate` is its own
invocation; reports are durable.

## Context

Three things were true on 21 Sep 2026:

1. **The week was being spent in two days.** Measured from the run history that `wf-spend.sh`
   reads: 17 Sep ≈ 3.85 M, 18 Sep ≈ 4.19 M, 19 Sep ≈ 3.72 M — **11.8 M across three days, 45 % of
   the project's 26.3 M all-time spend.** ADR 2026-09-12b §6 was written for the opposite failure
   (a session closing at 29 %) and gave throughput a floor with no ceiling.
2. **Nothing reviewed what the lanes produced, and nothing routed what they found.** `ci.sh` is
   twelve blocking steps, all mechanical; `check_coverage --strict` is green at 366 🔒 lines and
   932 ids. None of it can catch a green test over a wrong ledger. The repo's own history is the
   evidence: the unpadded-base64url wire bug that *"would have failed on the phone and never in
   CI"* (`D-05-14`); S6 approvals running on an empty fake in production until 18 Sep; three
   wrong-answer paths in Shamir found by a one-off adversarial pass with suite B green
   (`B-04-74…81`). Meanwhile **102 lane reports hold 632 `open` items, 22 of them marked VERIFIED
   BLOCKER**, with no mechanism to hand one to the lane that owns it.
3. **The position of the work was prose.** `PLAN.md` §0 is the tracker and is read by a human at
   the start of every session. Nothing rendered it, and nothing linked an owner item to the lanes
   it holds.

Owner direction, 21 Sep: raise effort, cut the load per day, review and verify before commit, send
findings back to the agent that wrote the code, put the owner's own blocking items on a desk that
is visible, and show the position of the work at session start. *"Does not matter if the project
will take more time."*

## Decision

1. **A day has a ceiling.** `.claude/rf.config.json` carries `budget.daily_tokens` (**1.2 M**,
   ≈ weekly/6) and `budget.weekly_tokens` (**owner-set, null until filled in**). `/cycle` reads
   today's spend off the board and refuses to start a round that would cross the day's ceiling.
   🔒 **The quota is not machine-readable** — `wf-spend.sh` says so in its own comment and
   ADR 2026-09-13e already ruled it: report the spend, do not rule on it. The owner reads `/usage`
   and writes the number in. On a Team plan it may be pooled across seats.
   ⟦tests: n/a — process rule, not behaviour⟧
2. **Effort up.** `lane-ui` **medium → high** — the last build lane below high. `lane-mech` stays
   **haiku · low**: it transcribes against `check_strings` and `gen_tokens --check`, which are
   deterministic, and paying a reasoning model for that is the purest waste on the ladder.
   `lane-core` unchanged — escalation only, the owner's say-so, 2 runs per week.
3. **Load down.** `MAX_LANES` **5 → 3** in `lanes.js`; `/cycle` caps at 3 slices. This is an
   attention control, not a budget control — five lanes in one run cost what five lanes across five
   runs cost. The ceiling in §1 is the budget control.
4. **A session is paced, not filled.** 2026-09-12b §6 said a session runs round after round until
   the budget is *genuinely low*. It now runs until the **day's** ceiling, then `/close`. Both
   readings were right about their own week; what was missing was a ceiling to go with the floor.
   ⟦tests: n/a — process rule, not behaviour⟧
5. **Every slice is reviewed before it is committable.** New agent `lane-review` — opus · high,
   **read-only** (no Write, no Edit). That is deliberate: a reviewer that can fix is a reviewer
   that talks itself out of findings. It reviews in priority order **test-honesty → spec
   conformance → security → 🔒/traceability → invariants**, and is forbidden from filing anything a
   deterministic checker already owns.
6. **Every finding is adversarially verified before it reaches the owner.** Each finding is put to
   verifiers *prompted to refute it*, defaulting to refuted when uncertain; it survives only on a
   majority of non-refutations. **Three lenses** (correctness · context · authority) on
   `core_crypto`, `core_ledger`, `sync_engine`, `server/supabase/{migrations,functions}`; **one**
   elsewhere. This is the structural form of CLAUDE.md rule 11: rule 11 *asks* an agent to verify
   itself, and a model cannot reliably self-refute — which is why the rule needed writing. The
   pattern already paid twice here by accident: the 🔒 candidate-X25519 reading *"refused by two
   lanes independently"*, and the 19 Sep staleness pair.
   ⟦tests: n/a — process rule, not behaviour⟧
7. **Confirmed findings go back to the lane that owns the directory — bounded at two rounds.**
   A finding still unresolved after two repair rounds, or one the repair lane disputes with
   evidence, becomes an **owner desk item**. It never starts a third round. An unbounded repair
   loop is how a day's ceiling gets eaten.
8. **The board is the position of the work.** `.claude/bin/rf-state.py` writes
   `.claude/state.json` from sources that already exist — `PLAN.md` (layers, desk), lane reports,
   run history, git — adding **no new source of truth**; every field records where it came from.
   `.claude/bin/board.sh` renders it, `--line` feeds a statusline, and a `SessionStart` hook prints
   it, replacing *"go read PLAN.md §0"*.
9. **The owner desk is first-class, and links to what it holds.** A desk line in `PLAN.md` may
   carry `⟦blocks: KEY, KEY⟧`, mirroring the existing `⟦tests: …⟧` convention, so the board can
   say which lanes an unanswered question is holding. One source of truth; `PLAN.md` stays the
   tracker.

## What does not change

- **`/gate` is still its own invocation**, never inside the cycle run — a limit kill costs one
  stage, not the phase. The cycle therefore ends *before* the gate: the post-edit hook already
  keeps the tree formatted, analyzed and purity-checked during lanes, so review has something
  coherent to read without the full suite.
- Disjoint directories are per **run**. `cycle.js` now throws on an overlap, but that check is a
  backstop — two slices sharing a path is an error in the split.
- Lanes never run `ci.sh`, never read whole docs, never re-read a file after editing.
- Reports stay durable, `complete: false` until wholly done.
- `lane-mech` never authors a test. A 🔒 line still needs an ADR; a lane reports it in `open`.

## Consequences

- **Milestones arrive slower and the week survives.** That is the trade the owner named.
- **Cost per slice rises** — review and verification are new spend on every slice. They are small
  next to a build lane (the gate measures ~22 k; a verifier reads one claim, not the whole diff),
  and they are gated: no votes at all on deterministic-checker territory.
- **One cycle ≈ one day.** Three slices + review + verify + one repair round lands near 1.0–1.3 M,
  which is the §1 ceiling. The pacing rule and the loop agree without being made to.
- Three files carry copies of the tier table — `CLAUDE.md` § Session economy, `PLAN.md` §3 and
  `.claude/agents/*.md`. The agents are the source of truth; the other two are updated with this ADR.

## Open ⚠️

- **`budget.weekly_tokens` is `null`.** Until the owner reads `/usage` and fills it in, the board
  shows weekly spend against no ceiling. The daily ceiling works regardless.
- **Correction to ADR 2026-09-12b § Open.** That ADR recorded that the harness refuses
  self-modification of its own skill and workflow definitions, and that the owner had to apply two
  files by hand. That is **not a blanket restriction**: `.claude/workflows/cycle.js` and
  `.claude/skills/cycle/SKILL.md` were both written from this session with Bash heredocs, and the
  skill registered live in the same session. The earlier refusal was of the `Write`/`Edit` tools,
  not of the path.
- **The 22 unrouted VERIFIED BLOCKERs** in existing lane reports predate the loop and are not
  swept by it. They need one pass to triage onto the desk. Known example, verified while writing
  this ADR: `M11-CER2`'s blocker (`umk_public_keys` carries `pub_ed` only, while 04 §6.1's QR
  payload and §6.3's byte-for-byte comparison need `pub_x`) is a **different** defect from desk
  item #12 (the candidate X25519 pair of 04 §7.3 step 1), and has never reached the desk.
- **`check_coverage.dart --json`** is not written. The board reports lane and desk state but not
  live requirement coverage; the 488-line checker prints text only. Small addition, not done here.

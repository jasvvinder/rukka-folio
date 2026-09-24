# ADR 2026-09-24 — Five-slice cycles, xhigh on the trust lanes, and a dated daily override

**Status:** accepted (owner-directed, 24 Sep 2026)
**Amends:** ADR 2026-09-21 §2 (effort), §3 (`MAX_LANES` and the `/cycle` cap) and §1 (adds dated
overrides to `budget.daily_tokens`). Everything else in 2026-09-21 stands. That includes the
review → verify → bounded repair loop, `/gate` as its own run, the board, the desk, and
`lane-core` as escalation only.

## Context

On 24 Sep the owner asked for as many milestones as possible over the weekend of 26–27 Sep, with
Opus 5.5 at extra-high effort where it is needed:
*"Use Opus 5.5 with extra high efforts where there is needed, also increase the cycle cap so
that this weekend we can complete max milestones."*

Three facts shaped the answers the owner then chose:

- **Opus 5.5 was already pinned** on every build lane and on `lane-review` (`claude-opus-5-5`,
  commit `530efbd`). The effort levels the CLI accepts are `low, medium, high, xhigh, max`
  (`claude --help`).
- **The cap is not what binds.** Desk PLAN-18 measured one 3-slice `/cycle` (2 of the slices
  high-risk) at **46 agents and 4.17 M tokens**, against a daily ceiling of 1.2 M. With a raised
  cap and the ceiling left alone, `/cycle` would refuse its second round on the same day.
- **`budget.weekly_tokens` is still `null`.** No script can read the quota (ADR 2026-09-13e), so
  nothing here can check the weekend against it. The owner reads `/usage`.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The cap is 5 slices per `/cycle` and 5 lanes per `/lane`  ⟦tests: n/a — process rule, not behaviour⟧
- `cycle.js` `MAX = 5` and `lanes.js` `MAX_LANES = 5`; `rf.config.json`
  `cycle.max_lanes_per_round = 5`.
- Directories must still be disjoint within a run, and `cycle.js` still throws on an overlap.
- Repair rounds stay bounded at **2**, and verify votes stay at 3 on high-risk paths and 1
  elsewhere.

### 2. xhigh effort goes where a subtle error means a green test over a wrong ledger  ⟦tests: n/a — process rule, not behaviour⟧
- **xhigh:** `lane-server`, `lane-sync`, `lane-review`, and the verify panel for high-risk slices
  (`core_crypto`, `core_ledger`, `sync_engine`, `server/supabase/{migrations,functions}`).
- **Unchanged:** `lane-ui` and `lane-ui-hard` stay **opus · high**. Normal-risk verifiers stay at
  **medium**. `gate` stays **sonnet · low** because it is mechanical and its measured cost is
  28 k. `lane-mech` stays **haiku · low** because it only transcribes, and the checkers behind it
  are deterministic. `lane-core` stays **fable · high**, escalation only.
- The rule from ADR 2026-09-12b still holds: model and effort live in `.claude/agents/*.md` and
  are never passed as arguments. The one place effort is set in code is the verify panel
  (`cycle.js`), because a verifier is an anonymous agent and has no agent file.

### 3. `budget.daily_tokens` can take dated, owner-set overrides  ⟦tests: n/a — process rule, not behaviour⟧
- `rf.config.json` → `budget.daily_overrides` maps a local date (`YYYY-MM-DD`) to a ceiling. For
  that day, `rf-state.py` uses the override in place of `daily_tokens`. The board marks it
  `override`, and `state.json` records `daily_base` and `daily_override`.
- **This weekend:** `2026-09-26` and `2026-09-27` are set to **20 M** each. That is roughly two
  5-slice cycles a day at the new effort levels.
- A date that is not listed falls back to `daily_tokens` (1.2 M), which stays the standing
  ceiling. So pacing resumes on its own on **Mon 28 Sep** with no edit. An expired entry does
  nothing and may be deleted.
- An override is an owner decision. A session never adds one on its own.

## Consequences

- **Cost per slice rises again.** At xhigh, a high-risk slice with its 3-lens panel should be
  expected to cost *more* than PLAN-18's measurement, which was taken at high. A 5-slice cycle is
  planned at ~7–10 M tokens, and the owner checks this against `/usage`.
- **PLAN-18 is answered, in the opposite direction from what it proposed.** It offered to cap
  `/cycle` at 1–2 slices or refuse on an estimate. The owner chose throughput for one weekend,
  bounded by a dated ceiling. The underlying observation (verify cost scales with slices × lenses)
  still stands. The board still reports spend after the fact, not before.
- Files changed: `.claude/agents/{lane-server,lane-sync,lane-review}.md`,
  `.claude/workflows/{cycle,lanes}.js`, `.claude/rf.config.json`, `.claude/bin/rf-state.py`,
  `.claude/bin/board.sh`, `.claude/skills/cycle/SKILL.md`, and the two copies of the tier table in
  `CLAUDE.md` § Session economy and `PLAN.md` §3.
- No product behaviour changes. No test is flipped.

## Open ⚠️

- **`budget.weekly_tokens` is still `null`.** Two 20 M days could exhaust a weekly quota that
  nobody has written down. Read `/usage` before Saturday and fill it in.
- **Decide after the weekend** whether 5 slices and xhigh stay. Nothing expires automatically
  except the two dated overrides.

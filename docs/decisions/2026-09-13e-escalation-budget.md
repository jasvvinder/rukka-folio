# ADR 2026-09-13e — The escalation budget is a quota and a question, not a run count

**RATIFIED by the owner, 14 Sep 2026 (proposed 13 Sep)** — *"Fix the four items that are waiting."* Answers recorded from that instruction; the reasoning for each is in the ruling it belongs to.
The cap becomes a quota plus the existing say-so; the run count is removed from `wf-spend.sh`; security and protocol reasoning is never skipped for budget. **Open question answered: print the token total only** — a soft run-count line would re-introduce the gameable unit this ADR removes. Amends the 🔒 owner-directed § Session economy
line in `CLAUDE.md`: *"Budget: **2 fable runs per week**."*

Raised because the rule and the owner's own meter disagreed three times in one session. `wf-spend.sh`
reported **2 / 2 budgeted** while the owner read **~11 % of the week's quota remaining** and authorised
more work. Overriding a 🔒 line on a verbal say-so each week is not a process; either the number is right
and should hold, or it is measuring the wrong thing and should be replaced.

It is measuring the wrong thing.

## The defect in the unit ⟦tests: n/a — process rule, not behaviour⟧

`.claude/bin/wf-spend.sh:56` counts **workflow runs that included a fable lane** and compares that to a
hard-coded `2`. A *run* is one `Workflow(...)` invocation, which may carry **one lane or five**. On
13 Sep 2026:

| Run | Lanes | Fable tokens | Counted as |
|---|---|---|---|
| `wf_249b8525-cda` | 2 (K1 quorum, K2 Shamir review) | 314,392 | **1 run** |
| `wf_1f5689b6-5a7` | 1 (K3 recovery provenance) | 227,703 | **1 run** |

Two lanes cost 1.4× one lane and scored the same against the cap. The unit is therefore both **blind to
cost** and **gameable**: packing five lanes into one invocation would have spent five lanes' quota and
read as a single run. A cap that can be satisfied by changing how work is *packaged* rather than how much
is *spent* is not a budget.

## Rulings 🔒 (proposed) ⟦tests: n/a — container heading; process rules, not behaviour⟧

### 1. The meter is quota, not runs ⟦tests: n/a — process rule, not behaviour⟧
- `wf-spend.sh` stops printing `N / 2 budgeted` as a verdict. It prints the week's **fable token spend**
  and the per-run breakdown it already computes, and names the quota as the owner's to read. The script
  keeps its job — *tell me what has been spent* — and drops the one it was doing badly: *tell me whether
  I may spend more*.
- **The hard number is removed rather than re-tuned.** A token figure would be equally wrong: the
  session's own quota is not visible to the script, so any constant it carries is a guess that will drift.

### 2. The say-so is the real control, and it stays ⟦tests: n/a — process rule, not behaviour⟧
- `CLAUDE.md`'s existing rule — *entered only when a lower tier reported a blocker it could not resolve,
  and only with the owner's say-so* — is what has actually governed every escalation this session. It
  needs no number beside it; the number only added false precision to a decision the owner was making
  anyway.
- **`No lane starts on lane-core` is unchanged.** Nothing here loosens the entry condition.

### 3. Security and protocol reasoning is never skipped for budget ⟦tests: n/a — process rule, not behaviour⟧
- Owner-directed 13 Sep 2026: *"this should not left just due to the usage limit. If required the higher
  model with max efforts, always, just say a word, on confirmation use efforts."*
- The protocol is **flag, then act on confirmation**: name the work, say in one sentence why it needs the
  escalation tier at max effort, and spend it once the owner agrees. Never silently downgrade such work to
  a cheaper tier because the budget looks spent; never auto-escalate without asking either.
- **The tell is the *kind* of question, not the volume of code** — reasoning about a 🔒 protocol step, a
  threat model, or a same-level spec conflict. K3's own report made the distinction: the tier was needed
  for the reasoning, while the code it produced was a one-type tightening a cheaper lane could have
  written *given the ADR*.
- `effort: 'max'` is passed explicitly when it overrides the agent definition
  (`.claude/agents/lane-core.md` is `fable · high · 240`), and the override is stated in the report.

## Why this is worth a ruling, not a habit
The evidence from one day: max-effort escalation proved an option circular (device certs root in the very
UMK a recovering device lacks), **corrected the previous lane's own blast-radius claim**, judged
*accept-the-risk* against `04 §1.1/§1.2` instead of by taste, and **found a second weakness in code that
shipped the same day** (the 8-digit ceremony code is grindable offline). A run-count cap would have
stopped the third and fourth of those from ever being looked at.

## Consequences
- **`CLAUDE.md` § Session economy:** the *2 fable runs per week* sentence is replaced by §2 + §3. 🔒 line,
  so the owner makes the edit on ratification — this ADR does not touch `CLAUDE.md`.
- **`.claude/bin/wf-spend.sh`:** lines 56–59 lose the verdict and keep the numbers.
- **No milestone impact.** Process only; no test changes.

## Open ⚠️
- **Should a soft signal survive?** A line such as *"3 fable runs this week — worth a look"* is honest
  (it reports, it does not rule) but re-introduces the gameable unit. Recommendation: print the token
  total only.
- **Nothing here tells the script the real quota.** If the quota ever becomes machine-readable, §1 should
  be revisited so `wf-spend.sh` can warn before the owner has to notice.

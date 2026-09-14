# ADR 2026-09-14 — The majority formula, and a 🔒 contradiction that blocks the quorum's placement

Two rulings were owed before `packages/data` could carry `structural_quorum` (lane M7-K1 flagged both and
correctly declined to decide either). **One is ruled here. The other cannot be, because the two 🔒 lines it
depends on contradict each other — and they contradict because of an edit made on 13 Sep 2026 in this
repository.** CLAUDE.md § Precedence is explicit for that case: *"If two sources at the same level
genuinely conflict, stop and ask — leave a `⚠️ SPEC:` comment, do not pick one."*

## Ruling 1 🔒 — "majority" means more than half: ⌊n/2⌋ + 1 ⟦tests: A-02-94⟧

`02 §7.2.1` reads *"a **majority** (⌈n/2⌉ + 1)"*. Taken literally that is not a majority:

| Owners | ⌈n/2⌉+1 (as written) | ⌊n/2⌋+1 (more than half) |
|---|---|---|
| 2 | **2** = all | 2 = all |
| 3 | **3** = all | **2** |
| 4 | **3** | 3 |
| 5 | **4** | **3** |

For **n ≤ 3 the written formula equals *all owners***, which makes the *majority* option identical to the
*all owners* default for exactly the family sizes this product is built around — a three-brother business
is the worked example (`joint-business-partnership.md`). A setting that does nothing in the common case is
not a setting; the parenthetical is a slip, not a design.

- The formula is **⌊n/2⌋ + 1** — a strict majority. `StructuralQuorum.requiredOf` and `A-02-94`'s quorum
  sizes follow it. ⟦tests: A-02-94⟧
- **Cheap to reverse** — one constant and one test — so if the owner intended near-unanimity, say so and
  it flips. The reason it is ruled rather than parked: the engine has to compute *something*, and shipping
  a "majority" that silently means unanimity is the worse default. ⟦tests: n/a — rationale⟧
- `02 §7.2.1`'s parenthetical is corrected to `⌊n/2⌋ + 1` in the same commit. ⟦tests: A-02-94⟧

## Ruling 2 ⛔ BLOCKED — where `structural_quorum` lives

> **Resolved (proposed) by ADR 2026-09-14b, 14 Sep 2026 — awaiting owner ratification.** The 13 Sep sentence is
> the error (seven older witnesses, three of them owner-approved 30 Aug in the same section). Structural settings
> live in two layers: the deed in `book_config` (creation-time, frozen) and every change as a dated
> `business_setting` naming its approved request; `structural_quorum` follows the ratio; `partner_shares` stays.
> ⟦tests: E-03-32, E-03-33, E-03-34⟧

Not ruled here. The inputs disagreed, and one of the disagreeing lines was a day old.

### The contradiction ⚠️ SPEC ⟦tests: n/a — a conflict to resolve, not behaviour⟧
Both of these are 🔒 lines in `02`, the doc that **owns** ledger semantics, so neither outranks the other:

- **`02 §7.1`** (line 229, added 13 Sep by ADR 2026-09-13 §3): *"Because the ratio is **fixed at creation**
  … an amend would be a second version of a number that is **not allowed to change**."*
- **`02 §7.2.1`** (line 251, added 13 Sep by lane M7-K1 from the 30 Aug owner-approved table): structural
  actions requiring quorum include *"**change the ownership ratio**"*.

The ratio is either fixed and unchangeable or changeable by quorum. It cannot be both. **The first line is
mine**: I wrote it on 13 Sep to document where `partner_shares` lives, took "fixed at business creation"
from `02 §7.1`'s profit-distribution paragraph, and hardened it into "not allowed to change" — without
checking `§7.2.1`, which sits nine lines further down the same file and says the opposite.

### Why it blocks the placement rather than being a separate tidy-up ⟦tests: n/a — rationale⟧
The two candidate homes differ **precisely on whether the value has history**:

- **`book_config`** — where `partner_shares` went. ADR 2026-09-13 §3's justification was that one envelope
  carries the whole ratio because it never changes. If the ratio *can* change, that justification is void
  and the ratio may be in the wrong place too.
- **`business_setting`** (ADR 2026-09-05e §11: *"ratio, interest terms, quorum rule, FY start"*) — a
  **dated** envelope. `02 §7.1` already requires exactly this for interest: *"recorded as a dated
  business-setting envelope, so the terms in force for any past period are always recoverable."*

Quorum needs history for the same reason interest does: an action approved under 2-of-3 must stay
auditable after the rule becomes all-of-3, and lane K1's counting already versions the owner set
(*threshold = the earliest version among request + counted records*). So the honest reading is that
`business_setting` is right for quorum — **and that the 13 Sep placement of the ratio in `book_config`
needs re-examining with it**, which is more than a one-line ruling.

### What settles it ⟦tests: n/a — process⟧
`02 §7.1` vs `02 §7.2.1` is a same-level 🔒 conflict over ledger semantics, with a worked-examples
dimension (does any of the five examples change a ratio mid-life?). That is `lane-core`'s stated remit.
Fable stands at **3 runs against a 2-run cap**, so under ADR 2026-09-13e §2–§3 it needs the owner's
say-so — named here rather than skipped, which is what §3 requires.

## Consequences
- **`02 §7.2.1`**: the parenthetical becomes `⌊n/2⌋ + 1`; `packages/core_ledger`'s `requiredOf` follows.
- **`packages/data`**: `BookConfig` still does **not** gain `structural_quorum` — ruling 2 is blocked.
  The engine is unaffected: its codec works on the payload map and serves either envelope.
- **`02 §7.1` line 229 gains a `⚠️ SPEC:` marker** naming the conflict, so no lane builds on it meanwhile.
- **Milestone:** M7.

## Open ⚠️
- **Ruling 2, above.** Until it lands, S6.3 (structural approval) can be built against the engine but the
  setting cannot be persisted.
- **Was the 13 Sep ratio placement right?** Dependent on the same answer; flagged here so it is not lost.

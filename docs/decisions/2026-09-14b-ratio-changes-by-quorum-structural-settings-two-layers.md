# ADR 2026-09-14b — The ratio changes only by quorum; structural settings live in two layers (the deed in `book_config`, every change as a dated `business_setting`)

**Status: proposed — awaiting owner ratification.** Written by lane M7-K5 (escalation tier, owner-authorised
14 Sep 2026, `effort: max` overriding `lane-core`'s `high` — stated per ADR 2026-09-13e §3). A lane never ratifies a
🔒 line: **no numbered spec is edited here**; the exact `02` edits are named in § Consequences for the owner to apply
on ratification, and the ratification checklist at the end takes a yes/no per ruling.

ADR 2026-09-14 ruling 2 was blocked on a same-level 🔒 conflict inside `02`, the doc that owns ledger semantics:
`02 §7.1` line 229 (13 Sep, ADR 2026-09-13 §3) says the ratio is *"not allowed to change"*; `02 §7.2.1` line 251
(30 Aug, owner-approved) lists *"change the ownership ratio"* as a structural action requiring quorum. Until it was
resolved, `structural_quorum` had no home and the 13 Sep placement of `partner_shares` was in doubt. This ADR
resolves the conflict from the evidence, rules both placements, and lands the `packages/data` codec that follows.

## The evidence ⟦tests: n/a — findings, not behaviour⟧

Every line below was read, not recalled (CLAUDE.md rule 11). Line numbers are `docs/02-ledger-rules.md` at
commit `9334ced`.

| Source | Date | What it says | Reading |
|---|---|---|---|
| `02 §7.1` line 177 | 30 Aug (owner-approved) | *"Ownership can be changed later (a structural change: requires every current owner's approval and is recorded as a dated envelope)."* | **changeable** |
| `02 §7.1` line 202 | 30 Aug (owner-approved) | *"× each owner's agreed ratio (fixed at business creation)"* | ambiguous — see ruling 1 |
| `02 §7.1` line 204 | 30 Aug (owner-approved, owner-locked) | *"Contribution never changes the sharing ratio. Paying more costs does not earn more profit — it earns a larger claim for repayment."* | fixed **against contribution** |
| `02 §7.1` line 229 | **13 Sep** (ADR 2026-09-13 §3) | *"an amend would be a second version of a number that is not allowed to change"* | **immutable** |
| `02 §7.2` item 3, line 239 | 30 Aug | *"business-setting and ownership changes … are written as signed envelopes and shown to every member of the tenant, forever"* | **changeable** |
| `02 §7.2.1` line 251 | 30 Aug (owner-approved table) | Structural: *"change the ownership ratio · … · add or remove an owner"* | **changeable** |
| `02 §7.2.1` line 253 | 30 Aug | Inbox card: *"Ownership ratio: Amrit 40% · Sukhdev 30% · Harjit 30% — currently equal thirds"* | **changeable** |
| `07 §26` line 321 | 5 Sep (ADR 05f §D) | S6.3 structural approval card — the worked example *is* a ratio change | **changeable** |
| `09 §3.1` H2b lines 45–47 | 30 Aug | four Given/When/Then scenarios on *"one initiates a ratio change"* | **changeable** |
| ADR 2026-09-05e §11 | 5 Sep (locked ruling) | `business_setting` carries *"ratio, interest terms, quorum rule, FY start"* | changeable, **dated** |
| ADR 2026-09-09 §2, §3 | 9 Sep | *"shares are fixed at creation, and paying in more later earns a larger claim for repayment, never a bigger share"*; *"a shared business with no ratio is not a thing the engine can create"* | fixed **against contribution**; a ratio is required at creation |
| `packages/core_ledger/lib/src/structural.dart` | 13 Sep (lane K1, `A-02-94`/`95`) | `StructuralAction.ownershipRatio` with payload `partner_shares`, applied only at quorum | **changeable** — built against §7.2.1 |

**The behavioural reference** (`docs/reference/worked-examples/`, CLAUDE.md § Accounting authority): none of the
five examples changes an ownership ratio mid-life. `joint-business-partnership.md` distributes once (voucher
**G-008**, 31 Jul 2026, ₹5,94,000 ÷ 3 = ₹1,98,000 each) under the ratio agreed at creation, and its line 222
describes interest on capital as *"compensating funding without touching the sharing ratio"*. The examples are
therefore consistent with **both** readings — they demonstrate distribution under one ratio and are silent on a
structural change — so the examples and `02` do not disagree and the stop-and-ask of § Accounting authority is not
triggered. No golden exercises a change, and placement is a configuration matter, not a posting, so the replay of
the eight books cannot move (`content_hash` `771288a0…` before and after this lane; `/goldens`).

**Provenance.** The 13 Sep sentence took *"fixed at business creation"* from line 202 and hardened it to *"not
allowed to change"* while documenting where `partner_shares` lives. It is one sentence, a day old, against seven
older statements — three of them owner-approved on 30 Aug in the same section and the same table. It is the error.

## Rulings 🔒 (proposed — owner to ratify) ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The ratio is changeable — by the structural action of §7.2.1 and by nothing else ⟦tests: A-02-64, A-02-94⟧
- *"Fixed at business creation"* (`02 §7.1` line 202) means **agreed and set when the business is created, and
  never moved by contribution** — which is exactly what the 🔒 line beneath it says (*"Contribution never changes
  the sharing ratio"*, `A-02-64`). It does not mean immutable. The two 30 Aug lines were never in conflict; the
  13 Sep sentence was. ⟦tests: A-02-64⟧
- The ratio changes **only** as *change the ownership ratio* (`02 §7.2.1`; `StructuralAction.ownershipRatio`): an
  admin initiates, it stays pending, it applies at the order point of the k-th signed approval, and nothing applies
  early (`A-02-94`). It never changes by a routine `book_config` amend, and never by contribution. ⟦tests: A-02-94⟧
- **The 13 Sep sentence is struck**, not reinterpreted: *"an amend would be a second version of a number that is not
  allowed to change"* is false and leaves `02 §7.1` (line 229) on ratification. ⟦tests: n/a — a doc correction⟧
- ADR 2026-09-09 §2/§3 and the S0.6a1 copy (`onboarding.business_owners.fixed_note`: *"Shares are fixed when the
  business is created. Putting in more money later earns a larger claim for repayment, never a bigger share."*)
  already carry the shared reading; `F1-07-45` asserts *"never a bigger share"*, not immutability. **No green test
  flips, so nothing needs `@Skip`** (ADR 2026-09-05i §4). ⟦tests: F1-07-45⟧

### 2. Structural settings live in two layers: the deed and its dated amendments ⟦tests: E-03-32, E-03-33, E-03-34, E-03-35 @M7⟧
The candidate homes differ on *history* (ADR 2026-09-14). The honest answer is that both are right about
different moments, and the partnership-deed analogy states the rule exactly: the deed is signed once; every later
change is a dated supplementary deed that names the deed it amends.
- **The deed — creation-time terms — stay in the `book_config` envelope**, authored once at creation by the
  creator, who is at that moment the book's only member (owners are *invited*, ADR 2026-09-13 §3), so a quorum of
  one holds trivially (`A-02-94` *single-owner books*). Today these keys are `partner_shares` and
  `structural_quorum`. ⟦tests: E-03-32, E-03-30⟧
- **The deed is frozen.** A routine `book_config` amend (rename, peer reviewer, ADR 2026-09-05e §9) carries the
  structural keys forward verbatim; a later `book_config` version whose structural keys **differ from the creation
  version** is an invariant violation and readers quarantine that version, as they quarantine any other
  (02 preamble: readers re-check). This is what makes a structural key inside a routinely-amendable object safe:
  it can be *read* from there and cannot be *moved* there. Cheap today: the app authors `book_config` exactly once
  (`app/lib/shared/ledger/local_ledger.dart:820`) and has no amend path. ⟦tests: E-03-35 @M7⟧
- **Every change is a dated `business_setting` envelope** (ADR 2026-09-05e §11, `03 §2.3` registry) — a **new
  object per change, never amended** — written once quorum exists and naming the `structural_approval` request
  that authorised it. This is the *"recorded as a dated envelope"* of `02 §7.1` line 177, the *"dated
  business-setting envelope"* of line 217, and the *"signed envelopes"* of `§7.2` item 3. ⟦tests: E-03-33⟧
- **The terms in force at any order point** are the deed's structural keys overridden by the verified
  `business_setting` records up to that point, folded in `(hlc, envelope_id)` order — the same merge
  `applyStructural` performs on an approved request, composed. `structuralSettingsInForce` in `packages/data` is
  that fold; it is the **only** API a distributing or counting caller may read a structural setting through.
  `BookConfig.partnerShares` and `BookConfig.structuralQuorum` are the *deed's* values and are documented as such.
  ⟦tests: E-03-34⟧
- **Why a record and not derivation alone.** The in-force value *is* derivable from request + approvals
  (`applyStructural`), and readers verify the record against them (ruling 5). The record exists because the docs
  demand a dated envelope three times over, because the admin-actions feed shows it forever, and because
  `05 §hot set` (line 97) lists `business_setting` in the **all-time** bootstrap set while `structural_approval`
  envelopes are fetched with their FY — a device bootstrapping in 2028 must recover the 2026 terms without the
  2026 approvals in hand. ⟦tests: n/a — rationale⟧

### 3. `structural_quorum` lives where the ratio lives ⟦tests: E-03-32, E-03-33, E-03-34⟧
- **At creation:** `book_config.structural_quorum`, wire values `all_owners` | `majority`
  (`core_ledger`'s `structuralQuorumKey` / `StructuralQuorum.wire`). **Absent means the default, all owners**
  (`02 §7.2.1`); a value this build cannot interpret is read as **all owners** — the strictest rule — and stays in
  `extra` verbatim (`03 §3.3` rule 4, owner-locked), exactly as `structuralQuorumOf` / `isStructuralQuorumKnown` already
  behave in the engine. ⟦tests: E-03-32⟧
- **On change:** a `business_setting` record whose `settings` carry `{"structural_quorum": "…"}`, authorised by an
  approved `quorum_setting` request (*"itself a structural action to change"*). ⟦tests: E-03-33⟧
- **In force:** `quorumInForce(structuralSettingsInForce(…))` — the rule that governs a request is the one in force
  at the owner-set version the request names (lane K1's counting: *threshold = the earliest version among request +
  counted records*), which the fold gives for any order point. ⟦tests: E-03-34, A-02-94⟧
- **No creation screen offers the choice yet.** `07`/`13` have no quorum control on S0.6a1 or anywhere before
  S6.3, so every book created today has the default; the codec is ready for the control when the `07` owner adds
  one (§ Open). ⟦tests: n/a — screen inventory, 07/13 owner⟧

### 4. `partner_shares` does **not** move ⟦tests: E-03-30, E-03-34⟧
- The 13 Sep **placement** was right for the deed; only its **justification** was wrong. `book_config.partner_shares`
  stays the ratio **agreed at creation**, keyed by Partner Current A/c id, weights never percentages, absent or empty
  = *not recorded*, never *equal* (ADR 2026-09-13 §3, unchanged). A later ratio is a `business_setting` record.
  ⟦tests: E-03-30⟧
- **The alternative was costed, not assumed.** Moving the creation ratio into a creation-time `business_setting`
  ("one home") would touch: the writer `app/lib/shared/ledger/local_ledger.dart` (held by lane T2 this run), a
  legacy read path for books written 12–14 Sep that `BookConfig` would carry forever, `E-03-30`, `F1-07-86`,
  `s0_6_setup_answers_persist_test`, the `02 §7.1` paragraph and ADR 2026-09-13 §3 — for **no gain in
  verifiability**: each option needs exactly one special reader rule (here *the deed is frozen*; there *a record
  without a request is valid only as the first for its key*), and "one home" is not reached either way because
  `fy_start_month` — a structural key the **projector** reads for FY boundaries — must stay in `book_config`
  regardless. No production data exists (the app is not yet on a device, `PLAN.md` §1), so the cost is code and
  tests, not migration; it is still cost without benefit. ⟦tests: n/a — rationale⟧

### 5. The `business_setting` wire shape, and the reader rule ⟦tests: E-03-33, E-03-36 @M7⟧
- Wire (snake_case, ids as strings, the M2 conventions of `payload_codec.dart`):
  `{ "id", "book_id", "hlc", "by_user", "request_id", "settings": { <structural key>: <value>, … } }`.
  `settings` is the flat map the engine already speaks — `structuralQuorumOf(record.settings)` reads it directly
  and `applyStructural`'s output is `{...base, ...record.settings}`. Unknown top-level fields round-trip in
  `extra`; unknown keys **or values** inside `settings` round-trip verbatim inside `settings` and are read
  conservatively by their consumers (quorum → all owners; ratio → *not recorded*). ⟦tests: E-03-33⟧
- **Reader rule (M7 data lane, with the `OwnerSetVersion` fold):** a record counts toward the in-force fold only
  when `request_id` names a `structural_approval` request whose `evaluateStructural(…).isApplied` is true **and**
  `settings` equals that request's payload. A record with no `request_id`, an unapproved one, or a differing
  payload is quarantined with its reason, never silently skipped. The codec does not judge this — `requestId` is
  nullable at the codec so that reading never throws on a policy question and the policy lives in one verifier.
  ⟦tests: E-03-36 @M7⟧
- The record is **not** a projector event: Recompute neither sums nor quarantines it on shape, `decodeEvent`
  returns null for it, and `project()` is untouched — so the golden `content_hash` is unaffected by construction.
  ⟦tests: n/a — restates 03 §3.3 rule 2; the goldens assert the hash⟧

### 6. A distribution applies the ratio in force at its own order point ⟦tests: A-02-58, A-02-59, A-02-60, A-02-61⟧
- The wizard reads `partnerSharesInForce(structuralSettingsInForce(…))` as of the distribution and hands **one**
  ratio to `splitByRatio`, which is all the engine has ever taken; the resulting paise are in the entry lines, so
  a past distribution's ratio is a historical fact of the ledger whatever changes later. ⟦tests: A-02-58, A-02-59, A-02-60, A-02-61⟧
- **Not ruled:** whether a ratio change *inside* an FY pro-rates that FY's undistributed surplus between the two
  ratios. The examples distribute at one instant under one ratio; pro-rating would be invented behaviour, so the
  conservative default is *the ratio in force at the distribution governs the whole amount* — flagged for the
  bookkeeper in § Open, not decided here. ⟦tests: n/a — open question⟧

## If the owner chooses the alternative ⟦tests: n/a — contingency⟧
Should ruling 4 be refused and the creation ratio moved to a creation-time `business_setting`, the codec landed
here survives: `BusinessSetting` is the record either way, `structuralSettingsInForce` changes its **base** from
the deed to the earliest record per key, `BookConfig.partnerShares` / `structuralQuorum` become legacy-read-only,
and the writer moves in a lane that owns `app/lib/shared/ledger`. `E-03-34`'s base-layer assertions would then
flip and take `@Skip('superseded by ADR 2026-09-14b ratification; re-lands at M7')` in that commit.

## Consequences
- **`packages/data`** (this lane): `BookConfig` gains `structuralQuorum` (nullable = not recorded / not
  interpretable; `extra` holds the latter) with the wire key from `core_ledger`; new `BusinessSetting` codec;
  `structuralSettingsInForce`, `quorumInForce`, `partnerSharesInForce`. Tests `E-03-32`, `E-03-33`, `E-03-34` in
  `test/structural_settings_test.dart`. Recompute, the projector and the mirror are untouched.
- **`packages/core_ledger`:** nothing. K1's `structuralQuorumKey`, `structuralQuorumOf`, `withStructuralQuorum`,
  `applyStructural` serve both layers unchanged, as K1 said they would.
- **Docs — exact edits, for the owner on ratification (this lane edits no numbered spec):**
  - `02 §7.1` line 202: *"(fixed at business creation)"* → *"(agreed at business creation; changed only by the
    structural action of §7.2.1 — never by contribution, never by a routine amend; ADR 2026-09-14b §1)"*.
  - `02 §7.1` line 229: delete the two sentences *"⚠️ SPEC (ADR 2026-09-14 ruling 2, **unresolved**): … waits on
    it."* and *"Because the ratio is fixed at creation, the ids are minted **before** the config is authored and one
    envelope carries the whole ratio — an amend would be a second version of a number that is not allowed to
    change."* Replace with: *"The ids are minted **before** the config is authored, and this map is the ratio
    **agreed at creation** — the deed. It is never amended: a routine `book_config` amend carries it forward
    verbatim, and a later version whose `partner_shares` differs from the creation version is an invariant
    violation. A change of ratio is the structural action of §7.2.1 and, once quorum exists, is recorded as a dated
    `business_setting` envelope naming the approved request (ADR 2026-09-05e §11); the ratio **in force** at any
    order point is the creation ratio overridden by the applied `business_setting` records up to that point, in
    `(hlc, envelope_id)` order (ADR 2026-09-14b §2, §4). A distribution applies the ratio in force at its own date
    (§6)."* The heading keeps its lock glyph and reads *"Where the ratio lives (owner-confirmed 13 Sep 2026, ADR
    2026-09-13 §3; two layers, ADR 2026-09-14b)"*; marker becomes `⟦tests: E-03-30, E-03-34, E-03-35 @M7, F1-07-86⟧`.
  - `02 §7.2.1` line 253: after *"chosen at creation and itself a structural action to change"* insert *"(recorded
    at creation as `book_config.structural_quorum`, absent = all owners; each change as a dated `business_setting`
    naming its approved request — ADR 2026-09-14b §3)"*; marker gains `E-03-32, E-03-33`.
  - `02 §7.1` line 177: unchanged — it was right all along; optionally append *(ADR 2026-09-14b §1)*.
  - `03 §2.3` under the registry line 108, house-style cross-reference:
    `> **ADR 2026-09-14b §5** — the business_setting wire shape (`id · book_id · hlc · by_user · request_id ·
    settings{…}`), one object per change, never amended; readers verify request_id against the approved request.
    ⟦tests: E-03-33, E-03-36 @M7⟧`
  - ADR 2026-09-14 ruling 2 and ADR 2026-09-13 §3: cross-reference notes added by this lane (`docs/decisions` is
    its directory).
- **`CHANGELOG.md` Decided line** (orchestrator, at `/close`): `- \`2026-09-14b-ratio-changes-by-quorum-structural-settings-two-layers.md\` — 🔒 proposed: the ratio changes only by quorum (13 Sep "not allowed to change" struck); structural settings in two layers — deed in book_config (frozen), every change a dated business_setting; structural_quorum placed; partner_shares stays.`
- **Milestone:** M7 (S6.3 can now persist the setting; the M7 data lane wires the `OwnerSetVersion` fold and the
  reader rule `E-03-35`/`E-03-36`).

## Ratification checklist — owner's answers 🔒 ⟦tests: n/a — heading; each answer below carries its own marker⟧
1. **Ruling 1** — the ratio is changeable by quorum only; the 13 Sep sentence is struck: ☐ ⟦tests: A-02-64, A-02-94⟧
2. **Ruling 2** — two layers; the deed in `book_config` is frozen; every change a dated `business_setting`: ☐ ⟦tests: E-03-32, E-03-33, E-03-34, E-03-35 @M7⟧
3. **Ruling 3** — `structural_quorum` in `book_config` at creation (absent = all owners), `business_setting` on change: ☐ ⟦tests: E-03-32, E-03-33⟧
4. **Ruling 4** — `partner_shares` stays: ☐ ⟦tests: E-03-30⟧
5. **Ruling 5** — the wire shape and the reader rule: ☐ ⟦tests: E-03-33, E-03-36 @M7⟧
6. **Ruling 6** — one ratio per distribution, the one in force at its date: ☐ ⟦tests: A-02-58⟧

## Open ⚠️
- **Pro-rating across a mid-FY ratio change** (ruling 6) — a bookkeeper question, not an engine one; the default
  until answered is *the ratio in force at the distribution governs the whole amount*.
- **Bootstrap verification gap (05 owner / lane-sync):** `05` line 97 puts `business_setting` in the all-time set and
  leaves `structural_approval` with its FY. A device that bootstraps years later can *read* the in-force terms but
  cannot *verify* `request_id` without fetching that FY on demand. Rule needed: accept provisionally and verify on
  fetch, or add `structural_approval` to the all-time set (low volume either way).
- **FY start** is the one structural key the projector reads. Its pre-close change path is unbuilt; when built, the
  change must reach the projector, which today reads `book_config.fy_start_month` — its own slice, not decided here.
- **The owner set for counting** (`OwnerSetVersion.ownerIds` = user ids who sign) is derived by the M7 data lane from
  approved `owner_add_or_remove` requests and the founding member set (K1's report); the mapping from Partner
  Current A/c ids (the ratio's key) to member ids is that lane's to define.
- **No quorum control at creation** (`07`/`13`): every book gets the default. Whether S0.6a1 gains a *Who must agree
  to big changes?* control or the setting is first offered in the book's settings is the `07` owner's call.
- **Stale docstring** on `StructuralQuorum.majority` in `packages/core_ledger/lib/src/structural.dart` still reads
  *"⌈n/2⌉ + 1, as 02 §7.2.1 writes it — which coincides with all owners for n ≤ 3"* while `requiredOf` implements
  ADR 2026-09-14 ruling 1. Two lines; not this lane's blocker; any tier.
- **S0.6a1 copy** *"Shares are fixed when the business is created"* is true under ruling 1 but a reader may hear
  *forever*; an optional softening (*"…are agreed when the business is created…"*) is a UX nicety for the ARB
  lane, not a requirement — `F1-07-45` asserts the other sentence.

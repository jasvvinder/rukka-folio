# ADR 2026-09-09 — The shared-ownership setup screen (S0.6a1), and the financial-year switcher

`07 §5.7` 🔒 has always said a business asks *"who owns it"* — **Just me** or **Shared with others →
owners and ratio** — but no screen ever existed for the second branch: canvas 4 draws the chip pair on
S9.5 and stops, and the design's own branch table lists only *name · kind · FY* for S0.6a. A shared
business therefore could not be created at all. Separately, `02 §8.1` 🔒 requires a financial-year
switcher on **every** ledger, report and export; it was described in four places and drawn in none.

Owner ruled 9 Sep 2026: *"Owners invited by phone at setup, reuse S0.6e pattern"*, and approved the
drafted artboards — which state the shares-versus-percentages and skippability calls explicitly — with
*"That looks fine, Go ahead."* The artboards are staged in the design project as
`partials/new-screens-c.json`.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. S0.6a1 "Who owns this business?" is a screen ⟦tests: F1-07-45, F1-13-15⟧
- It sits between **S0.6a** and **S0.6b**, on the **Shared with others** branch only. The *Just me*
  branch is unchanged and never sees it. ⟦tests: F1-07-45⟧
- Owners are **invited by phone at setup**, reusing the **S0.6e** row unchanged — name, number, and the
  *to invite* tag. Nobody is added by a phone number alone; the invitation waits for the in-person
  verification ceremony, exactly as S0.6e already states. ⟦tests: F1-07-45⟧
- The first row is the creating user, tagged *you*, and carries a share like any other owner.
  ⟦tests: F1-07-45⟧
- It is added to the `13 §3.2` inventory between S0.6a and S0.6b. ⟦tests: F1-13-15⟧

### 2. Shares are whole-number weights, never percentages ⟦tests: F1-07-45, F1-07-86⟧
- The control offers **Equal shares** (default) and **Different shares**. Equal holds real weights
  (1:1:1), not 33/33/34. ⟦tests: F1-07-45⟧
- Under *Different shares* each owner has a stepper in whole shares; the **percentage is computed and
  displayed beneath, never typed**. ⟦tests: F1-07-45⟧
- Consequently there is **no "must add up to 100" validation and no error state** — any set of positive
  whole numbers is a valid ratio. ⟦tests: F1-07-45⟧
- Rationale, and why this is not cosmetic: `02 §7.1` 🔒 divides by weight
  (`floor(amount × weight ÷ Σweights)`, remainder to the largest ratio, ties by earliest-created
  partner account). Three equal owners cannot be expressed in percent — 33/33/34 is a real 1%
  difference on every future distribution. Weights are what the engine already computes with.
  ⟦tests: A-02-58, A-02-59, A-02-60, A-02-61⟧
- The screen states the `02 §7.1` rule in words: shares are fixed at creation, and paying in more later
  earns a larger claim for repayment, never a bigger share. ⟦tests: F1-07-45⟧
- An owner cannot hold zero shares; the stepper floors at 1, and removing an owner is a row action.
  ⟦tests: F1-07-45⟧

> **Implemented 12 Sep 2026 (lane M5-U4d), owner to confirm the keying** — the weights persist in the
> `book_config` envelope as `partner_shares`, keyed to each **Partner Current A/c id**, not to the owner
> row or the partner's name: one account exists per owner, no member identity exists at setup (owners are
> only *invited*), and an account id is the one handle that survives a rename. ⚠️ SPEC: no doc states this
> keying — it wants a line in `02 §7.1` or the next ADR on distribution. ⟦tests: E-03-30, F1-07-86⟧

### 3. S0.6a1 is not skippable; its secondary is *Just me after all* ⟦tests: F1-07-45⟧
- Every other S0.6 branch step is skippable (`13 §3.2`, flow line; `07 §3.1.1`). **This one is not**: the
  ratio is fixed at creation, and a shared business with no ratio is not a thing the engine can create.
- Instead of *Skip for now*, the secondary action returns to the **Just me** branch, so the step is
  escapable without becoming a dead end (`07 §1` rule 6). ⟦tests: F1-07-45⟧

### 4. The financial-year switcher is one control on three surfaces ⟦tests: F1-07-46⟧
- Surfaces: **S4** (A/C statement), **S8.2** (report viewer and export), and **S10.4**, where it first
  appears after the year seals. ⟦tests: F1-07-46⟧
- The year renders as a **chip** in the header where it is currently flat muted text; tapping it opens a
  bottom sheet listing the years. ⟦tests: F1-07-46⟧
- A closed year shows the **b/f it hands to the next year** and the badge copy **Certified** — copy, not
  a state (`13 §6`) — with the word beside the tick, never colour alone (`07 §1`). ⟦tests: F1-07-46⟧
- **Before the first year close there is no switcher**: one year exists, so the year stays plain text. A
  control that opens a list of one is a lie. ⟦tests: F1-07-46⟧
- **Until Year Close exists (M9), b/f is computed** by summing entries dated before the FY start, which
  is correct for a continuous ledger. When `S10.4` lands, the **certified opening vector** of `02 §8.1`
  replaces the computed figure. The switcher does not wait for M9. ⟦tests: F1-07-46⟧

## Consequences
- **Code:** `app/lib/features/onboarding/` gains S0.6a1 (lane U1c). `app/lib/shared/ledger/local_ledger.dart`
  — `watchStatement()` gains a date range; `app/lib/features/ledger/screens/s4_account_statement_screen.dart`
  gains the switcher and loses its placeholder b/f (hard-coded 0) and "as on today" c/f. The ⚠️ SPEC comment
  in that file about the missing FY switcher is resolved by ruling 4 and should be replaced with a
  reference to it. No green test is flipped, so nothing needs `@Skip`.
- **Docs:** cross-reference lines at `07 §5.7`, `13 §3.2` (new inventory row), `02 §8.1`.
  `07 §6`'s statement bullet already demands the FY switcher and now points here.
- **Milestone:** S0.6a1 lands in **M5** lane U1c; the FY switcher in **M5** lane U3b, with the certified-b/f
  swap in **M9** alongside S10.4.
- **Design:** staged in the Claude Design project as `partials/new-screens-c.json` (3 artboards). Placement
  and rebuild remain to be done in the design app: S0.6a1 into **Canvas 1**'s five-path branch segment
  (*My shop* and *My businesses*, between S0.6a and S0.6b) — **not** Canvas 12, whose journey is a
  single-owner business; the FY switcher into **Core Patterns**, being a control rather than a journey step.

## Open ⚠️
- **The Capital/Drawings pair is still unruled** and gates U1c. `02 §7.1` says creating a business book makes
  "a single Capital/Drawings pair", but nothing creates one and the engine has no Drawings account —
  `packages/core_ledger/lib/src/accounts.dart` documents `openingBalance` as *"Opening Balance / Capital"*,
  i.e. the two are currently one system account. `S2.5` (Drawings confirmation) assumes the pair exists.
  This is `core_ledger` work and must not be invented by a UI lane.
- **The 8th quick-add tile.** `07 §6` bullet 3 lists Capital among the S3.1 tiles; S3.1 ships seven. Same
  root cause as the item above; ⚠️ SPEC comment stands in `s3_1_quick_add_sheet.dart`.
- **PA/HI copy for S0.6a1** is not written. The S0.6a–i branches were already listed in the design mirror's
  `TRANSLATION-PENDING.md`; this screen joins that list.
- **`13 §3.2` numbering.** S0.6a1 is a sub-step id in a table that otherwise runs S0.6a–i. If the owner
  prefers a letter (renumbering S0.6b–c onward), say so before U1c writes the route names.

# ADR 2026-10-04c — One *My business* card replaces *My shop* and *My businesses* (desk 121)

**Status: ruled by the owner, 4 Oct 2026** (*"merge the two into one My business card"*). Amends 07 §3.1
step 3 and §3.1.1 (owner-locked, owner-added 31 Aug 2026), 01 §2 *Purpose card 2/3*, 13 §3.2 row S0.3, and DESIGN-PACK
*S0.3 / O3 Purpose picker*. §2 (layout) is **⚠️ SPEC: owner/design to confirm**.

The roster review on 4 Oct found that a one-business professional has no card: an IT firm, consultant or
freelancer had to pick *My shop — One shop's cash and bank* (`onboarding_en.arb:87-91`). The owner's reading
is that one business is one book, whatever the trade. The code agrees: both cards go to the same S0.6a
(`app/lib/features/onboarding/onboarding_routes.dart:418-419`), and they differ only in whether S0.6c *Add
another business?* follows S0.6b (`:412-415`). Both are the **Business** entity type, so they get the same
plans and the same trial (ADR 2026-09-25 §5). The card asked about the trade and the count. The trade changed
nothing, and S0.6c already asks the count.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. S0.3 has four cards; *My business* covers any trade, one or more ⟦tests: F1-04c-1 @M13, F1-04c-2 @M13, F1-04c-3 @M13⟧
- The cards are **Myself · My business · My family · Our trust**, one per entity type of ADR 2026-09-25 §5
  (Individual · Business · Family · Trust). ⟦tests: F1-04c-1 @M13⟧
- *My business* has the description *Shop, practice, freelance work — one or more* (PA/HI drafted, native
  review at M12 per desk 111). It names no single trade. ⟦tests: F1-04c-1 @M13⟧
- Its branch is the former *My businesses* row of 07 §3.1.1: **O6a → O6b → O6c** *"Add another business?"*
  looping back to O6a → **O6** your own → checklist. Every *My business* user reaches S0.6c. A one-business
  person answers *No, that's all*, which is one tap, and goes on exactly as *My shop* did. ⟦tests: F1-04c-2 @M13⟧
- The *shop* purpose is retired from the app; nothing else branched on it (`onboarding_routes.dart` is the only
  reader). The trust card alone still sets `tenant.type = organization` (07 §3.1.1 🔒, unchanged). ⟦tests: F1-04c-3 @M13⟧
- 01 §2: *Purpose card 2* becomes **My business · ਮੇਰਾ ਕਾਰੋਬਾਰ · मेरा कारोबार**. *Purpose card 3* is retired
  and the remaining rows renumber.

### 2. Layout ⟦tests: F1-04c-1 @M13⟧ — ⚠️ SPEC: owner/design to confirm
- 07 §3.1 and DESIGN-PACK set a 2 × 2 grid with *Our trust* full width beneath, *"since five does not divide
  into a grid"*. Four cards remove that reason. The built cards already carry a description each
  (`onboarding.purpose.card.*.description`), not only the trust card, so the trust subtitle is no longer the
  odd one out. Two readings:
  - **(a) A single column of four full-width cards.** Each card has an icon, a label and a description. This
    holds the trust subtitle and the longer PA/HI labels at 200 % on 360 × 800 without truncation
    (`rkStrictViewport`).
  - **(b) A 2 × 2 grid.** It keeps the illustrated-grid look, but puts the trust subtitle in a half-width card.
- Until ruled, the conservative build is (a). It drops nothing the grid shows.

## Consequences
- **Supersession (ADR 2026-09-05i §4), same commit:** `F1-07-16 all five cards render, trust full width
  beneath a 2x2 grid` and `F1-07-83 only the My businesses card reaches S0.6c — My shop falls through` are
  `@Skip('superseded by ADR 2026-10-04c §1; re-lands at M13')`. The other F1-07-16/83 tests still hold.
- **App** (`lane-ui`, settled pattern): `OnboardingPurpose.shop` removed; `afterBusinessOpening` always goes to
  S0.6c for *My business*; S0.3 renders four cards; ARB `onboarding.purpose.card.shop.*` retired,
  `…businesses.*` relabelled (EN/PA/HI); the demo builder's card (F1-DEMO-9, *"above the five"*) re-reads
  *four*. Tests `F1-04c-1…3`.
- **Docs**: 07 §3.1 step 3 and §3.1.1 table (one *My business* row), 07 §5.7 *"after the purpose card"*,
  01 §2 rows, 13 §3.2 S0.3 (*four cards*) and 13 §5 flow F1's diagram, DESIGN-PACK *S0.3* and *O3*. Each gets
  a cross-reference line to this ADR. `requirements-architecture.md` is non-normative and is left alone.
- **Design**: the Claude Design canvas still shows five cards. Fix it there (`/design-pull` afterwards).
- **Server**: none. ADR 2026-10-03 (e) noted that 07 does not say which tenant type *My shop / My businesses*
  create. One card makes that question smaller, not settled.

## Open ⚠️
- **The *Shop* plan name** (ADR 2026-09-25 §5: *Shop ₹2,499, 1 book · 2 people*) puts the same word in front of
  a freelancer on S12.1. Plan names live in the server catalogue (§6), so a rename is a data change and needs
  no release. Owner to name it.
- **Business presets** (what accounts a business book starts with, by kind of business) are **not** part of
  this card. Today every business gets `Sales A/c` plus the shop or trade tree (ADR 2026-09-09c §1). Presets
  are a separate feature, to be discussed (PLAN backlog).

# ADR 2026-10-04c — One *My business* card replaces *My shop* and *My businesses* (desk 121)

**Status: ruled by the owner, 4 Oct 2026**: §1 *"merge the two into one My business card"*; §2 *"for
phone single column, but for ipad two column"*; §3 *"rename plan name"*, choosing Business Lite. Amends 07
§3.1 step 3 and §3.1.1 (owner-locked, owner-added 31 Aug 2026), 01 §2 *Purpose card 2/3*, 13 §3.2 row S0.3,
DESIGN-PACK *S0.3 / O3 Purpose picker*, and the plan name in ADR 2026-09-25 §5.

The roster review on 4 Oct found that a one-business professional has no card: an IT firm, consultant or
freelancer had to pick *My shop — One shop's cash and bank* (`onboarding_en.arb:87-91`). The owner's reading
is that one business is one book, whatever the trade. The code agrees: both cards go to the same S0.6a
(`app/lib/features/onboarding/onboarding_routes.dart:418-419`), and they differ only in whether S0.6c *Add
another business?* follows S0.6b (`:412-415`). Both are the **Business** entity type, so they get the same
plans and the same trial (ADR 2026-09-25 §5). The card asked about the trade and the count. The trade changed
nothing, and S0.6c already asks the count.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. S0.3 has four cards; *My business* covers any trade, one or more ⟦tests: F1-04c-1, F1-04c-2, F1-04c-3⟧
- The cards are **Myself · My business · My family · Our trust**, one per entity type of ADR 2026-09-25 §5
  (Individual · Business · Family · Trust). ⟦tests: F1-04c-1⟧
- *My business* has the description *Shop, practice, freelance work — one or more* (PA/HI drafted, native
  review at M12 per desk 111). It names no single trade. ⟦tests: F1-04c-1⟧
- Its branch is the former *My businesses* row of 07 §3.1.1: **O6a → O6b → O6c** *"Add another business?"*
  looping back to O6a → **O6** your own → checklist. Every *My business* user reaches S0.6c. A one-business
  person answers *No, that's all*, which is one tap, and goes on exactly as *My shop* did. ⟦tests: F1-04c-2⟧
- The *shop* purpose is retired from the app; nothing else branched on it (`onboarding_routes.dart` is the only
  reader). The trust card alone still sets `tenant.type = organization` (07 §3.1.1 🔒, unchanged). ⟦tests: F1-04c-3⟧
- 01 §2: *Purpose card 2* becomes **My business · ਮੇਰਾ ਕਾਰੋਬਾਰ · मेरा कारोबार**. *Purpose card 3* is retired
  and the remaining rows renumber.

### 2. Layout: one column on a phone, two on an iPad ⟦tests: F1-04c-4⟧
- Owner, 4 Oct 2026. Below the `medium` breakpoint (`layout.breakpoint.medium` = 600 logical px,
  `design/tokens/tokens.json:297`), which covers every phone, S0.3 is a **single column** of four full-width
  cards. Each card has an icon, a label and a description. ⟦tests: F1-04c-4⟧
- At `medium` and wider, which covers a portrait or landscape iPad, it is a **two-column grid**: Myself ·
  My business / My family · Our trust. ⟦tests: F1-04c-4⟧
- This replaces 07 §3.1's *"2 × 2 with the trust card full width beneath"*. That layout existed only because
  *"five does not divide into a grid"*.

### 3. The *Shop* plan is renamed **Business Lite** ⟦tests: F1-04c-5, E-04c-1⟧
- Owner, 4 Oct 2026. Amends the display name in ADR 2026-09-25 §5's table only. Limits, price, features and
  the catalogue **id `shop`** are unchanged, because the id is what tokens, subscriptions and billing carry.
  The Business ladder now reads **Business Lite · Business · Business+**, the same shape as Family Lite ·
  Family · Family+.
- The name appears in two places, and both change: the app's ARB value `subscription.plan.shop`
  (`app/lib/features/subscription/subscription_copy.dart:31`; PA/HI follow `family_lite`'s pattern), and
  `plan_catalogue.name` for id `shop` (seeded by `0018_plan_catalogue.sql:144`, also mirrored in
  `functions/_shared/store_mem.ts:114`). The catalogue changes through a **new** migration, never by editing
  0018. ⟦tests: F1-04c-5, E-04c-1⟧

## Consequences
- **Supersession (ADR 2026-09-05i §4), same commit:** `F1-07-16 all five cards render, trust full width
  beneath a 2x2 grid` and `F1-07-83 only the My businesses card reaches S0.6c — My shop falls through` are
  `@Skip('superseded by ADR 2026-10-04c §1; re-lands at M13')`. The other F1-07-16/83 tests still hold.
- **App** (`lane-ui`, settled pattern): S0.3 layout by breakpoint (§2); ARB `subscription.plan.shop` →
  *Business Lite* EN/PA/HI (§3); `OnboardingPurpose.shop` removed; `afterBusinessOpening` always goes to
  S0.6c for *My business*; S0.3 renders four cards; ARB `onboarding.purpose.card.shop.*` retired,
  `…businesses.*` relabelled (EN/PA/HI); the demo builder's card (F1-DEMO-9, *"above the five"*) re-reads
  *four*. Tests `F1-04c-1…5`.
- **Docs**: 07 §3.1 step 3 and §3.1.1 table (one *My business* row), 07 §5.7 *"after the purpose card"*,
  01 §2 rows, 13 §3.2 S0.3 (*four cards*) and 13 §5 flow F1's diagram, DESIGN-PACK *S0.3* and *O3*. Each gets
  a cross-reference line to this ADR. `requirements-architecture.md` is non-normative and is left alone.
- **Design**: the Claude Design canvas still shows five cards. Fix it there (`/design-pull` afterwards).
- **Server** (`lane-server`): one migration, `update plan_catalogue set name = 'Business Lite' where id =
  'shop'`, plus the `store_mem.ts` seed; `E-04c-1` asserts the catalogue row's name. ADR 2026-10-03 (e) noted that 07 does not say which tenant type *My shop / My businesses*
  create. One card makes that question smaller, not settled.

## Open ⚠️
- **Business presets** (what accounts a business book starts with, by kind of business) are **not** part of
  this card. Today every business gets `Sales A/c` plus the shop or trade tree (ADR 2026-09-09c §1). Presets
  are a separate feature, to be discussed (PLAN desk 122).
- The Claude Design canvas still shows five cards in the old layout. Fix it there, then run `/design-pull`.

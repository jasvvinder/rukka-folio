# ADR 2026-10-07 — Which setup steps are required, and how a skipped one comes back

07 §3.1 step 7 and §3.1.1 🔒 made every step after the PIN skippable: *"Every branch step is skippable and resumable
from the setup checklist."* The app also added *Skip for now* to the recovery sheet (S0.5b), although canvas c1/O5b
never drew one. On 6 Oct the phase 1 journeys showed nothing on Home brings a skipped branch step back (PLAN desk 174).
The checklist (O8, S0.7) knows only four rows.

**Owner ruled, 6–7 Oct 2026:**
- a checklist row for each skipped branch;
- then: *"the required steps should not be skippable"*, which made the recovery sheet, naming the chosen branch, and
  opening balances required. Invites stay skippable.
- 7 Oct, after the design session placed the frames: S0.6f (*What the pool has*) and S0.6i (*What the trust has*) are
  the family's and trust's opening-balance screens on the canvas (placed from `new-screens-d`, 10 Sep). They are
  **required** too. Canvas 11's older O6a/O6c lose their Skip as well.

The owner approved the frames on 7 Oct (review page v2; staged in the design project as `partials/new-screens-e.json`).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Required before Home 🔒 ⟦tests: F1-1007-1, F1-1007-2⟧
- Unchanged: language, phone and code, purpose card, name, PIN, *Keeping your books safe* (07 §3.1 steps 1–5).
- **Now required, with no *Skip for now*:**
  - **The recovery sheet** (S0.5b): make it, then print or save it. The canvas O5b flow stands: *I've kept it safe*
    wakes once the sheet has been opened. Scanning the printed sheet back may wait (ruling 3). This takes effect when
    RUNG3B lands (ADR 2026-10-06d). Until then S0.5b keeps its disabled-with-reason state and its Skip, because a
    step that cannot be completed must not block sign-up (07 §1 rule 6).
  - **Naming the chosen branch:** S0.6a (business name, ownership, year start), S0.6d (family name), S0.6g (trust
    name and type).
  - **Opening balances:** S0.6 (your own), S0.6b (each business's), S0.6f (the family pool's) and S0.6i (the trust's).
    Leaving every figure at ₹0 and tapping *Finish*
    is a valid answer and means starting at zero. There is no extra confirm.
- This narrows 07 §3.1 step 7 and §3.1.1's *"every branch step is skippable"* to the steps in ruling 2. 04 §7.4's
  *"mandatory for solo users"* now holds for everyone at sign-up.

### 2. Still skippable 🔒 ⟦tests: F1-1007-3⟧
- The welcome slides, and **inviting people** (S0.6e family heads, S0.6h the trust's committee). 07 §3.1.1 🔒's
  *"Invitations are always skippable at signup"* is unchanged. S0.6f and S0.6i are opening balances, so ruling 1
  covers them.

### 3. The checklist brings back what was skipped 🔒 ⟦tests: F1-1007-4, F1-1007-5, F1-1007-6⟧
- **Opening balances** always arrives ticked, because it is required.
- **Recovery sheet:** the row becomes *Check your recovery sheet · Not scanned back yet* (amber, the one item with a
  consequence) until the printed sheet is scanned back (04 §7.4 verified storage).
- **Branch row:** on the family and trust paths, one *Finish <book name>* row appears while the invite step (S0.6e /
  S0.6h) was skipped. Its subtitle names it (*Next: invite the other heads* / *who runs it*), and tapping it resumes
  there with what was saved kept. On the family path it **replaces** *Add your family*. The trust path has no family row. The
  business path has no branch row (its steps are required); another business comes from Menu → Add a business (S9.5).
- **Not needed** sits behind **⋮** on branch rows only. It hides the row, deletes nothing, and shows a toast with
  **Undo** (no confirm dialog). After that, Menu is the way in.
- A finished row ticks and strikes through. **The card leaves** when every row is ticked or set to Not needed. The
  optional *Add your family* row never holds it open.
- The chosen purpose and which branch steps are open are kept on the device, so the rows survive a cold start (ADR
  2026-10-06b ruling 2).

## Consequences
- **Code (one `lane-ui-hard` slice, after RUNG3B for the sheet part):**
  - `app/lib/features/onboarding`: remove Skip from S0.6, S0.6b, S0.6f, S0.6i, S0.6a/d/g; persist the purpose and open branch
    steps; the resume targets.
  - `app/lib/features/home`: the checklist rows (`home_cards.dart` `HomeSetupChecklist`, `home_routes.dart`
    setupDoors), ⋮ → Not needed + Undo, the card's exit rule.
  - S0.5b loses Skip in RUNG3B.
  - Journeys: add *invites skipped* for family and trust.
  - Design match against the new O8–O8f frames once placed.
- **Tests superseded:**
  - F1-1006c-4 (*S0.6 Skip → Home with the row open*) → `@Skip('superseded by ADR 2026-10-07 §1; re-lands at M13')`
    with F1-1007-2.
  - F1-07-57 where it asserts that the card stays until the opening balances are in → re-read against §3.
- **Docs:** 07 §3.1 step 7 and §3.1.1, and 13 §3.2 rows S0.6 and S0.7, carry the cross-reference. DESIGN-PACK O6's
  *"Keep Skip for now and resumability"* is superseded.
- **Design:** `PROMPT-place-setup-steps.md` in the design project. The design session places the frames, removes Skip
  from the canvas frames, and rebuilds Canvases 1 and 7.

## Open ⚠️
- ⚠️ *Not needed* on a branch row: the owner may later want it to ask again after some time. This build hides the row
  for good, and Menu stays the way in.
- ⚠️ Canvas 12's own S0.6b (*Its opening balances*) and the S0.6a/d/g frames: the prompt asks the design session to
  remove any Skip. Whether S0.6a/d/g draw one was not checked here.

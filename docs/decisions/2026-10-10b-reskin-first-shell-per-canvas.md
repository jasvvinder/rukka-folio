# ADR 2026-10-10b — Re-skin first; the shell and S1 follow the canvas

ADR 2026-10-05 made the canvas the authority on how a screen looks, but left three items open. One was the freeze on new
screen slices. Another was the budget. Its third open point (§1) said a frame never overrides a 🔒 line. The 5 Oct
pairs and the P1A inputs (PLAN desks 140, 176) show the canvas shell disagreeing with two 🔒 lines:

- canvases c1/O8, c2, c7 and c15 draw **four tabs with an Inbox badge and no centre (+)**;
- 13 §3.1 🔒 (ADR 2026-09-05f §A) and design-system §4.1 🔒 require the docked (+). ⟦tests: n/a — context, quotes the lines ruling 2 amends⟧

The verbs are now pinned on Home, so the (+) duplicates them. **Owner ruled 10 Oct 2026:** *the re-skin comes first, new
screen slices pause*, and *desk 176 is done as per design*.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. New screen slices pause until the re-skin's shared components land 🔒 ⟦tests: n/a — sequencing rule, not behaviour⟧
- Phases, from ADR 2026-10-05's 5 Oct plan:
  1. RESKIN1, the full audit;
  2. shared components;
  3. screens;
  4. undrawn screens.
- No new S-id screen is built before phase 2 lands. Fixes to existing screens (bugs, spec conformance) continue.
- Budget: the existing `budget.daily_overrides` (10 M/day to 27 Oct, owner-directed 6 Oct) carries it. Nothing new is
  set here.

### 2. The shell follows the canvas: four tabs, no centre (+) 🔒 ⟦tests: F1-1010b-1 @M13⟧
- The bottom bar is Home · Ledger · Inbox (with its badge) · Menu, as canvases c1/O8, c2, c7 and c15 draw it. There is
  **no** docked (+).
- Starting an entry is reached from the verbs pinned on Home, as drawn.
- This amends 13 §3.1 🔒 (ADR 2026-09-05f §A) and design-system §4.1 🔒 on the (+) only. The four tab icons and the rail
  presentation at `expanded` (ADR 2026-09-13b §2) are unchanged.
- Tests that assert the (+) are marked `@Skip('superseded by ADR 2026-10-10b §2; re-lands at M13')` in the slice that
  removes it, per the supersession rule.

### 3. S1's header and cards follow the canvas, within the 🔒 lines below ⟦tests: F1-1010b-2 @M13⟧
- S1 takes the canvas header (book pill · sync) and the canvas hero, cards and spacing (desk 176, `design/match/S1.json`).
  The canvas also draws a 🔔 bell, which ADR 2026-09-05f §F **dropped** (*the Inbox tab is the one tray*). It is not
  adopted (Open, resolved).
- The book pill must still satisfy 13 §2.3 🔒 *who am I, here* ⟦tests: F1-1010b-2 @M13⟧: avatar and role are reachable from it. If the frame
  cannot carry them, ⚠️ SPEC: ask; do not drop them.

### 4. Consumer wording is a front-end label; the true Dr/Cr may sit beside it 🔒 ⟦tests: F1-1010b-3 @M13⟧
Owner ruled 10 Oct 2026, refining the same day's first answer (*keep Dr/Cr as the canvas draws it*):
- **The engine never changes.** Posting logic and the accounting meaning of Dr/Cr are fixed (02 §2, §10; CLAUDE.md
  rule 9). Consumer wording such as *Money in / Money out* is a front-end label, mapped on display and never stored or
  posted.
- **The true Dr/Cr may be shown in brackets after the consumer label, where space allows.** Examples: *Money in (Dr)*,
  *₹2,450 you owe (Cr)*. The side shown is always the ledger's true side for the account the figure belongs to, computed
  from the posting. It is never the bank statement's mirror (02 §10, 01 §1.9). Where space does not allow, the
  consumer label alone stands.
- **Where Dr/Cr is technically required, it is shown plainly.** That covers the professional surfaces (A/C statement,
  trial balance, exports; 02 §10; 01 §1 rule 3 adds *ledgers*). S1's books-balance line follows ADR 2026-09-05f §F: plain
  words (*Books balanced · difference nil*), with Dr/Cr one tap in on the trial balance (Open, resolved).
- The canvas frames that draw Dr/Cr on consumer screens are matched under this ruling: S3 *Ledger index* (c7; a ledger,
  so professional under 01 §1 rule 3), S3.1 *Quick add* (c7) and S21 *Search · results* (c7), from the 8 Oct pull. S1
  (c2, c7, c15) follows ADR 09-05f instead (Open, resolved).
  A frame that draws a bare Dr/Cr where a consumer label belongs is matched as *label (Dr/Cr)* when space allows.
- A consumer label with its true side in brackets is not *mixing the two conventions* in 02 §10's sense. Mixing still
  means showing the bank's credit/debit as the ledger's Dr/Cr, or using both vocabularies for the same figure without
  the bracket form.

## Consequences
- Code: `app/lib/shared` (the shell), `features/home` (S1). This is the RESKIN phase 2/3 slice that owns the shell.
- Docs: cross-reference lines under 13 §3.1, design-system §4.1 and 02 §10, and a pointer in CLAUDE.md rule 9. PLAN
  desks 139, 140 and 176 ruled.
- Milestone: M13, the re-skin.

## Open ⚠️
- ✅ **Resolved 10 Oct (owner: *decide from the design and specs*) — ADR 2026-09-05f §F stands** for (a) S1's balance line
  and (b) the bell. By CLAUDE.md precedence a frame decides layout, and the specs and ADRs decide copy and behaviour. A
  ruled ADR beats a later drawing, and no ADR reversed 09-05f. So:
  - S1 says *Books balanced · difference nil*, with Dr/Cr one tap in on the trial balance;
  - Home has **no** bell, because the Inbox tab is the one tray.
  The canvas is the thing to fix (desk 190). The design match records both as *canvas wrong, ADR 09-05f*.
- **The shorter position card vs 02 §9** (F1-07-49): if the canvas card drops a figure that 02 §9 requires, the figure
  stays and the difference is recorded in `design/match/S1.json`.

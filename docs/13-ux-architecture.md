# 13 — UX Architecture & Flow Framework

**Version 1.1 · 5 Sep 2026 · Production handoff draft.** (v1.1 = ADR 2026-09-05f: every 5 Sep ADR state given a home; tab bar settled; inventory hygiene.)
Authorities: `docs/07-ui-flows.md` (screen detail) · `docs/02-ledger-rules.md` + `docs/reference/` (engine behaviour) · `docs/11-brand-guidelines.md` (brand) · `design/tokens/` (values) · `docs/01-glossary.md` (strings).
This document is the connective layer: it defines *what screens exist, how they relate, what states they carry, and how a user moves between them.* Where it and doc 07 disagree, 07 wins on screen-level detail and this document wins on structure. ⚠️ marks decisions still open.

---

## 1. Foundations

### 1.1 The five laws
Every screen in this system obeys these. They are the tiebreakers when a design decision is contested.

1. **The eight-second law.** App icon → saved cash entry in ≤ 8 seconds. Any structure that adds a tap to that path is wrong, however tidy it looks.
2. **Two vocabularies, one engine.** Everyday surfaces speak *Money in / Money out / You will get / You will give*. Professional surfaces (A/C statement, trial balance, exports) speak true ledger Dr/Cr with contextual headers. The posting logic never bends to the display language.
3. **Reality first, review second.** If money moved in the world, the book says so immediately. Approval gates exist only where the approval itself moves the money.
4. **Privacy is structural, not a setting.** Personal books are cryptographically private; the UI never implies otherwise, and never offers an admin a door that does not exist.
5. **No dead ends.** Every blocked action states its reason and offers the path forward.

### 1.2 The two mental models we serve simultaneously
| | The keeper (enters) | The reader (checks) |
|---|---|---|
| Wants | speed, familiarity, his own words | correctness, traceability, a page that holds up |
| Sees | verbs, plain words, colour on numbers | counter-accounts, Dr/Cr, balances with sides |
| Screens | Home, Add entry, Day book, Import | A/C statement, Reports, Exports, Trial balance |
| Failure mode | friction → he goes back to paper | ambiguity → he doesn't trust the books |

Both must be satisfied by the same data with zero reconciliation between them. This is the central UX problem of the product.

---

## 2. Domain → UX mapping

### 2.1 Books are the unit of everything
A **Book** is one independent self-balancing ledger. Entities are just book *counts*:

| Entity type | Books created | Scope switcher |
|---|---|---|
| Individual | 1 personal | hidden entirely |
| Shopkeeper | 1 personal + 1 business | 2 chips |
| Multi-business owner | 1 personal + n business | n+1 chips, grouped |
| Joint family | 1 joint + n family + n personal + n business | grouped sheet + "Everything" |
| Trust / society | 1 organization (+ members' personal) | grouped sheet |

**Every screen takes a book context.** There is no separate "family mode" — only more chips in the switcher. This is the single most important structural decision in the product.

### 2.2 Scope model
```
Scope = { Me | one Book | Everything }
   Me         → the user's personal book (private, PIN-lockable)
   one Book   → a family/business/joint/org book the user has a role in
   Everything → read-only aggregate across every book visible to the user
```
Scope persists per tab, defaults to last used, and is visible as a chip in the top bar **whenever the user has more than one book** (hidden for an individual, §2.1; 07 §2). Switching scope never loses the current screen — the same screen re-renders in the new context. In Everything scope each book card carries a **provisional** badge while that book has an author gap (ADR 2026-09-05f §B).

### 2.3 Who am I, here? 🔒 ⟦tests: F1-13-6, F1-13-7, F1-13-9, F1-13-10, F1-13-11, F1-13-12, F1-13-13, F1-13-14⟧
Because one person holds different roles in different books, **the current identity and role are always visible**: the top bar's scope chip carries the user's avatar, and tapping it shows *"Amrit Kaur · Admin in this book"*. On every screen where capability differs, the role is stated rather than implied — a viewer sees "You can view this book" where the entry button would be, not an absent button. Rule: **never hide a capability silently; either show it enabled, or state why it is not there.**

### 2.3.1 Role variants each screen must be designed for
| Screen | Admin | Head | Member | Operator | Viewer |
|---|---|---|---|---|---|
| Home | full position + admin-actions card | full position of own book | position, no P&L | day totals only, no P&L | position, read-only |
| Add entry | posts instantly | posts instantly | posts, may flag | posts, may flag | button absent + reason |
| Statement | full + amend/reverse | full + amend/reverse | full, no amend | own entries only | read + export only |
| Inbox | all flags + admin queue | flags for own book | own rejected items | own rejected items | empty state |
| Members | invite/remove/roles | view + verify | view | view | view |
| Structural actions (ratio, distribution, owner changes, year re-open) | **initiate + approve** | approve if an owner | — | — | — |
| Close | can lock, cannot lock alone | confirms own book | — | — | — |

### 2.4 Roles → capability, not navigation
Roles (admin · head · member · operator · viewer) change *what actions appear*, never *which screens exist*. A viewer sees the same statement screen without the entry button. This keeps the mental model stable across a family where everyone has different rights. **Designations are separate** (06 §1.0 🔒, Option B): a free display label per member — ਖ਼ਜ਼ਾਨਚੀ, Munshi, Patron — admin-set, always shown *with* the capability in plain words, never *instead of* it. ⟦tests: F1-07-36 @M7⟧

---

## 3. Information architecture

### 3.1 Navigation model
**Four tabs plus a docked centre action** 🔒 (ADR 2026-09-05f §A) — the 4-column bar of design-system §4.1 (Home · Ledger · Inbox · Menu) with ( + ) docked between Ledger and Inbox as an action, not a tab (no active state, no label). 07 §2 and DESIGN-PACK S1 say the same: ⟦tests: F1-13-1, F1-13-2, F1-13-3, F1-13-4, F1-13-5⟧

```
┌──────────────────────────────────────────────────────┐
│   Home      Ledger      ( + )      Inbox•     Menu    │
└──────────────────────────────────────────────────────┘
     S1         S3          S2         S6        S8
```
- **Home (S1)** — position + today. The answer screen.
- **Ledger (S3)** — A–Z index of every A/C. The find screen.
- **( + ) (S2)** — entry. The do screen. No long-press repeat — 07 §5's *nothing is pre-selected* rule (ADR 2026-09-05f §C).
- **Inbox (S6)** — one tray for everything awaiting a human. The attention screen.
- **Menu (S8)** — reports, books, members, settings. The rarely screen.

**Rule:** four thumb-reachable destinations plus one action. No hamburger, no nested tabs, no more than two levels deep from any bottom-bar root.

### 3.2 Complete screen inventory
| ID | Screen | Root | Purpose |
|---|---|---|---|
| **S0.0** | Splash | launch | mark, sealed→open animation on real unlock only |
| **S0.05** | Welcome | first launch | 3 skippable slides, after language so they are in the user's language |
| **S0.8** | Set your PIN | onboarding | 6-digit, set + confirm (06 §4.4) |
| **S15.3** | Enter PIN | app lock | 6 boxes; Face ID button; *Forgot PIN* → OTP + biometric; **cooldown** states (5 free · 30 s · 1 min · 5 min · 15 min · 1 h, countdown row) and **PIN disabled** after 10 → OTP + biometric — the canvas's "a code, not a lockout" tone stays as copy (ADR 2026-09-05d §5, ADR 2026-09-05f §B) |
| **S0.1** | Language picker | onboarding | first screen ever shown |
| **S0.2** | Phone + OTP | onboarding | identity |
| **S0.3** | "What will you use this for?" | onboarding | five cards; the trust card alone sets `tenant.type = organization` (07 §3.1) |
| **S0.4** | Name & photo | onboarding | for approvals/ceremony |
| **S0.5** | Keeping your books safe | onboarding | key sync stated on · automatic backup on with its disclosure · sheet action (04 §7.6, 07 §3.1) |
| **S0.5b** | Recovery sheet | S0.5 | generate, print/save, verify by scanning back |
| **S0.6a** | Name the business | O3 branch | name · just me / shared · FY start |
| **S0.6b** | The business's opening balances | O6a | |
| **S0.6c** | Add another business? | O6b | loop control, multi-business branch |
| **S0.6d** | Name the family | O3 branch | |
| **S0.6e** | Who else is in the family | O6d | invite heads by phone, **Skip for now** |
| **S0.6f** | The family's shared accounts | O6e | pool bank and cash |
| **S0.6g** | Name the trust and its type | O3 branch | gurudwara · temple · society · registered trust |
| **S0.6h** | Who runs the trust | O6g | Chairman/President/Trustee/Sevadar, skippable |
| **S0.6i** | The trust's accounts | O6h | bank + gollak as `cash_collection` |
| **S0.6** | Opening balances wizard | onboarding | resumable (design O6a–c: what you have · who owes you · who you owe) |
| **S0.7** | Setup checklist (Home empty state) | S1 | progressive onboarding |
| **S0.9** | Invitation accept (design O7a/O7b) | deep link | invited path: accept → OTP → personal book works immediately, shared books greyed "Meet Sunita to activate" (07 §12) |
| **S1** | Home / Position | root | banks, cash, get/give, advances, in-transit, month, verbs, today |
| **S1.1** | Position line drill-down | S1 | list behind any position row |
| **S1.4** | Book incomplete — rebuilding | S1 | replaces the Home card while projections rebuild (local corruption, Recompute on upgrade, `store_epoch` re-pull); determinate loader "{done} of {total} entries restored"; `integrity_ok` gates it (ADR 2026-09-05c §3/§6, ADR 2026-09-05f §B) |
| **S2** | Add entry (keypad-first) | action | the 8-second flow |
| **S2.1** | A/C picker + inline create | S2 | search-first, class inferred by slot |
| **S2.2** | Date picker | S2 | today default, backdate ok, future disabled |
| **S2.3** | Transfer (within/between books) | S2 (fifth position of the verb pill — ADR 2026-09-03b) | pairs |
| **S2.4** | Adjustment wizards | S5.5 · S4 ⋯ menu · S4.1 · S13 (one door each — ADR 2026-09-03b) | guided only, never freeform |
| **S2.5** | Drawings confirmation (design B5) | S2 | business books: owner takeout posts to Drawings; the sheet says "not a business expense" (07 §5) |
| **S3** | Ledger index (A–Z khatas) | root | search header, filter chips |
| **S3.1** | Quick add sheet | S3 | bottom-sheet A/C create from the Ledger tab (07 §6); the entry flow's picker is a full screen instead (design S2-C) — same component, two presentations, deliberately |
| **S4** | A/C statement | S3 | grouped listing; professional columns in export |
| **S4.1** | Entry detail | any P1 row | audit trail, photo, who entered, amend/reverse — the target of every tap in every list; a **held** entry (dangling amend/reverse/decision) shows *"waiting for the entry this changes"* (ADR 2026-09-05b §4) |
| **S4.2** | Donation receipt (design C5) | S4.1 | trust books: shareable receipt card from a donation entry; no tax language (07 §14) |
| **S5** | Advances (ਐਡਵਾਂਸ) | S1/S6 | mine held · given out, aged |
| **S5.1** | Advance request | S5 | amount + purpose → approver |
| **S6** | Inbox | root | grouped cards, all attention types |
| **S6.1** | Review — grouped card | S6 | Approve all / One by one |
| **S6.3** | Structural approval card | S6 | states exactly what will change; Approve / Veto with reason; quorum progress (2 of 3) (02 §7.2.1; 07 §26) |
| **S6.2** | Review — stepper | S6.1 | approve / reject+reason / skip |
| **S7** | Import — pick file & account | S2 (import button, header — ADR 2026-09-03; not a Menu row) | on-device parse (drawn as design S7.0a–c: file · column mapping · duplicates skipped) |
| **S7.1** | Import inbox | S7/S6 | one question per line |
| **S7.2** | Import balance check | S7 | statement's opening/closing vs the ledger; passing · matched · failing (07 §11.1, ADR 2026-09-01) |
| **S7.3** | Transfer-pair confirm | S7.1 | "same money moving?" — a row-level card in the import inbox |
| **S7.4** | Import preview & submit | S7.1 | every entry about to post, balance check restated, count in the button (owner-added 1 Sep 2026) |
| **S8** | Menu | root | hub |
| **S8.1** | Reports list | S8 | day book, cash book, P&L, position, ageing, reconciliation |
| **S8.2** | Report viewer + export | S8.1 | PDF/XLSX, FY switcher |
| **S8.3** | Family reconciliation (design D5) | S8.1 | non-zero inter-book pairs with their composing entries; normally a single green ✓ (07 §10) |
| **S9** | Books & members | S8 | roles, limits, verification log |
| **S9.5** | Add a business | S9/Menu | name · type (just me / shared) · FY start · opening balances — creates the book (02 §7.1) |
| **S1.2** | Scope switcher — two books | S1 | the small control when only Me + one business exist; **not** the grouped joint-family sheet (S1.3) |
| **S1.3** | Scope switcher — grouped sheet | S1 | Me / Family / Businesses / Organizations / Everything |
| **S9.2** | Show my code (QR + 8-digit) | ceremony | invitee side |
| **S9.3** | Verify member (camera/code) | ceremony | verifier side |
| **S9.4** | Verification mismatch | S9.3 | hard-fail, no override |
| **S5.5** | Cash count sheet (verify / collect modes) | S4/S10 | denomination grid; mandatory in trust books (02 §8.2) |
| **S14** | Partner positions | S8.1 | per-owner put-in / took-out / share / net + settlement capacity (02 §7.1) |
| **S14.1** | Profit distribution wizard | S14 | period profit → ratio preview (incl. interest lines) → one multi-line entry |
| **S14.2** | Drift & settlement card | S14 | over/under-funding notice; pay out · partner-to-partner · carry forward |
| **S10** | Month close wizard (4 steps) | S1/S8 | cash count · banks · tray · lock |
| **S10.1** | Family close status | S10 | which books are closed, who is being waited on |
| **S10.2** | Month summary card | S10 | shareable close reward |
| **S10.3** | Late arrivals tray | S6 | re-date or re-open |
| **S10.4** | Year close + carry-forward | S8 | certify, FY switcher appears; *unverified-by-you* variant "Update the app to verify this close" when this device's projector is older (ADR 2026-09-05c §3) |
| **S10.5** | Close blocked — waiting on a device | S10 | names the phone whose entries have not arrived (author gap) or the held envelope; lock disabled until it closes (ADR 2026-09-05b §3–4, ADR 2026-09-05f §B) |
| **S11.4** | Backup settings | S11 | platform key sync toggle · save recovery sheet · readable monthly copy, each with its risk line (04 §7.6) |
| **S11** | Devices & security | S8 | devices, guardians, recovery sheet, escrow, PIN |
| **S11.1** | Guardian setup (mutual ceremony) | S11 | 2-of-3 |
| **S11.2** | Recovery — ask guardians | activation | live k-of-n progress (design R2.2/R2.2b) |
| **S11.3** | Recovery — paper sheet | activation | scan/type (design R2.4/R2.4b) |
| **S11.5** | Recovery — silent restore (design R2.0) | activation | key returns from the platform keychain; the books open by themselves |
| **S11.6** | Recovery — the fork (design R2.1) | activation | choose the path: old phone · guardians · paper sheet |
| **S11.7** | Recovery — the guardian's side (design R2.3) | notification | approve a member's restore from your own phone |
| **S11.8** | Recovery — nothing worked yet (design R2.5) | activation | the honest empty-vault screen + path forward (F11) |
| **S11.9** | Recovery in progress — Cancel | notification / S11 | on every existing device while a guardian recovery or guardian phone-change waits its 24 h; one-tap Cancel (ADR 2026-09-05d §1) |
| **S11.10** | Support action pending — Cancel | notification / S11 | support-initiated revocation, 24 h window; the target device suspends, never wipes (ADR 2026-09-05d §3, 05b §2) |
| **S12** | Subscription | S8 | tiers, renewal, read-only banner |
| **S9.1** | Invite member | S9 | phone + per-book roles + limits + designation label (06 §1.0 Option B — a name, not a permission); a second admin sees *"Invited by Amrit · awaiting join"*, never the number (ADR 2026-09-05c §4) |
| **S16** | My account | S8 | name, photo, phone, language |
| **S16.1** | Edit profile | S16 | name and photo only |
| **S16.2** | Change phone number | S16 | OTP old + new, or guardian approval if the old number is lost (06 §9.4) |
| **S16.3** | Delete account | S16 | 15-day cooling, what is erased vs retained (06 §9.3) |
| **S12.1** | Plans | S12 | comparison, annual saving, current plan marked |
| **S12.2** | Checkout | S12.1 | **iOS = In-App Purchase** (08 §3.2); coupon and GSTIN on non-iOS only |
| **S12.3** | Manage subscription | S12 | plan, renewal date, change, cancel |
| **S12.4** | Payment problem | S12 | grace countdown, retry, what happens at the end |
| **S12.5** | Read-only mode | global | banner + blocked-entry sheet; export always works; the same sheet pattern serves **book full** (`rejected:quota`) → S12.1, drafts preserved (ADR 2026-09-05b §7, ADR 2026-09-05f §B) |
| **S12.6** | Invoices | S12 | list + PDF |
| **S17** | Help | S8 | search, contact, diagnostics — the grouped, searchable FAQ list lives on this hub (S17.1 folded in, ADR 2026-09-02) |
| **S17.2** | FAQ article | S17 | one answer, plain language |
| **S17.3** | Contact support | S17 | WhatsApp primary; states what support cannot do |
| **S17.4** | Send diagnostics | S17.3 | user-triggered, financial values scrubbed, shown before sending |
| **S18** | Legal | S8 | terms, privacy, licences |
| **S18.1** | Terms of service | S18 | document page, shared template patterned on S18.3; the designed surface is its summary card on the S18 hub (ADR 2026-09-02) |
| **S18.2** | Privacy policy | S18 | document page, shared template; summary card "Privacy, in four lines" on the hub |
| **S18.3** | What we can and cannot see | S18/onboarding | the impossibility table (12 §2) as a user-facing page — a trust asset, not boilerplate; one line on where the data lives (India — ADR 2026-09-05c §1) |
| **S18.4** | Open-source licences | S18 | document page, shared template |
| **S19.1** | Update required | global | 426 from the API (06 §4.5) |
| **S19.2** | Maintenance | global | |
| **S19.3** | No connection | global | non-blocking; the app works offline |
| **S19.4** | Permission priming | before OS prompt | notifications and camera, asked in context |
| **S19.5** | This phone has been modified | global, once per app version | root / debugger / instrumentation detected: plain notice → S11; never blocks; permanent S11 row (ADR 2026-09-05 §6) |
| **S20** | Attachment viewer | S4.1 | pinch-zoom bill photo, share, replace |
| **S21** | Search | S3/S1 | across accounts, parties and notes |
| **S15** | App lock | cold start / background 2 min / idle 5 min | biometric auto-prompt, **MPIN fallback — never the device passcode** (06 §4.4, 07 §5.6); idle lock suppressed while a draft has digits; copy variant after biometric re-enrolment (ADR 2026-09-05d §4) |
| **S15.1** | Privacy cover | background | mark on paper; no balances in the app switcher |
| **S15.2** | Personal Book lock — re-prompt | S11 | opt-in extra gate; asks the **same MPIN or biometric** again — one PIN, never a second number (06 §4.4, ADR 2026-09-01) |
| **S15.4** | Device suspended | global | server asserted a revocation without a signed record: read-only + persistent banner, sync stopped, nothing wiped, *Retry* (ADR 2026-09-05b §2, 05d §3) |
| **S13** | Settings | S8 | language, **Appearance** (system/light/dark), notifications, **Auto-lock (background · idle)**, **Your books → Opening balances** (ADR 2026-09-03b ruling 2), export everything |

**Depth rule** (ADR 2026-09-05f §H13): S1–S8 are roots; everything else is at most **two levels of navigation** below one of them. Detail viewers and sheets — S4.1, S4.2, S20, S7.3, S7.4, S2.4 — are exempt: they open *from* a row, they are not destinations.

### 3.4 Notification → destination map (ADR 2026-09-05f §E)

Every push in 07 §17 names where it lands. Content-free throughout (04 §4).

| Notification | Loud | Destination |
|---|---|---|
| Review requested (digest per author + book) | — | S6.1 |
| Review decided | — | S4.1 |
| Advance reminder | — | S5 |
| Verification needed / completed | — | S9 |
| Recovery requested (you are a guardian) | **loud** | S11.7 |
| Recovery in progress on your account | **loud, Cancel** | S11.9 |
| Support action pending on your account | **loud, Cancel** | S11.10 |
| New certified device on your account (every path, incl. platform key sync) | **loud** | S11 |
| Close reminder (1st) · close blocked (waiting on a device) | — | S10 / S10.5 |
| Late arrival waiting | — | S10.3 |
| Import lines waiting | — | S7.1 |
| Book full · write lost | — | S6 card → S12.1 / S6 |
| Escrow release countdown | **loud, daily** | S11 |
| *This phone has been modified* | local only, never a push | S19.5 |

### 3.3 Design ↔ doc id map (recorded 2 Sep 2026, audit B3)

The canvases predate parts of this inventory and carry their own ids. Both vocabularies
are valid; this table is the translation. Canvas captions use the design id.

| Design id | Doc id | Screen |
|---|---|---|
| O0 · O0b · O1 | S0.0 · S0.05 · S0.1 | Splash · Welcome · Language |
| O2a/O2b · O3 · O4 · O4b | S0.2 · S0.3 · S0.4 · S0.8 | Phone+OTP · Purpose · Name · Set PIN |
| O5 · O5b · O6a–c · O7a/b · O8 | S0.5 · S0.5b · S0.6 · S0.9 · S0.7 | Books safe · Sheet · Balances wizard · Invitation · Checklist |
| S2-B / S2-C | S2.1 | A/C picker (in-place state / quick-add presentation) |
| S7.0a–c | S7 | Import: file · mapping · duplicates |
| R3.1 · R3.2 · R4 | S11 · S11.1 · S11.4 | Devices & security · Guardians · Backup |
| R2.0 · R2.1 · R2.2(+b) · R2.3 · R2.4(+b) · R2.5 | S11.5 · S11.6 · S11.2 · S11.7 · S11.3 · S11.8 | The recovery ladder |
| D1 (renamed) | S1.3 | Grouped scope sheet |
| D5 · B5 · C5 | S8.3 · S2.5 · S4.2 | Family reconciliation · Drawings · Donation receipt |
| A1–A4 · B1–B4 · C1–C3c · D2/D3/D8 | — | Entity variants of S1/S3/S4/S5.5/S9 with real figures; not separate screens (C3c = the trust Cash A/c in S5.5 verify mode, owner-added 3 Sep 2026) |
| R1 | — | Role-variant strips (§2.3.1), not screens |
| E1–E7 | — | Empty/error/offline states of their parent screens (§4.3) |

---

## 4. Component system

### 4.1 The three load-bearing patterns
Ninety percent of the app is these three. Design them once, reuse everywhere.

**P1 — Entry listing** (day book, A/C statement, drill-downs, import inbox, review lists)
```
┌ group header ── date/period label ················ running balance or total ┐
│ ◯icon   Primary label (counter-account or category)              ↗ amount   │
│         narration in the user's own words · status                          │
└─────────────────────────────────────────────────────────────────────────────┘
```
No date column, no voucher — dates group, voucher stays backend. Group headers carry the balance at end of that day/period. Amount right-aligned, tabular, coloured, with a direction arrow so colour is never alone. Period tabs (Daily · Monthly · Yearly · Custom) + ← date → navigator sit above.
⚠️ Open: icon treatment (outlined / glyph-tinted / filled); group header shows balance or period total.

**P2 — Position card** (Home, Everything scope, book dashboards)
Label · value with side/colour · optional meta ("1 · Ramesh") · chevron to drill down. Grouped in a card with the 3px left rule. Carries a **provisional** badge while the book has an author gap (ADR 2026-09-05b §3, ADR 2026-09-05f §B).

**P3 — Attention card** (Inbox). Typed cards, each designed (ADR 2026-09-05f §D): reviews · imports · invites · recoveries · reminders · late arrivals · structural approval with quorum + veto (S6.3) · **book full** → S12.1 · **write lost** · **key wait > 24 h** · **author gap > 24 h** · **quarantine / security event** · **device added** · **integrity / rebuild** · **cancel-window banner with countdown** (recovery, support action, deletion).
Avatar/icon · who + where + count + total · expandable list · primary action + secondary action. One card per (author, book, day) — never one per item.

### 4.2 Atoms
Amount text (3 sizes × in/out/pending/neutral) · account chip · scope chip (avatar + role) · date chip · status chip (review/locked/in-transit/offline/**provisional**) · keypad · books-balanced verification card · search field · picker row with "+ Create" · stepper progress · loud-warning panel · **banner** (persistent: suspended, read-only, book full) · **toast** (the 10 s Undo depends on it) · **countdown** (cancel windows, PIN cooldown) · **progress meter** (the determinate loader rule) · **skeleton row** (ADR 2026-09-05f §D, §H).

### 4.3 Component states
Every interactive component ships: default · pressed · disabled-with-reason · loading · error. Every list ships: populated · empty (with the one next action) · error-with-retry · offline.

---

## 5. Primary flows

Notation: `→` step · `◆` decision · `⟳` loops until · `‖` parallel.

**F1 · First run**
`S0.0 splash → S0.1 language → S0.05 welcome (3 slides, skippable) → S0.2 phone+OTP → S0.3 purpose ◆(Myself | My shop | My businesses | My family | Our trust) → S0.4 name → S0.8 set PIN → S0.5 keeping your books safe (+ S0.5b sheet: print → verify by scanning it back) → branch steps S0.6a–i per card, each skippable (07 §3.1.1) → S0.6 own opening balances (skippable) → S1 with setup checklist`
Success: user reaches Home understanding that no password exists and the paper sheet matters. 🔒 Branch order ruled 2 Sep 2026 (ADR): **after the shared steps**, per 07 §3.1.1 — identity and safety finish before any entity setup, and every branch step lands on the checklist anyway. Canvas 0's map is aligned; Canvas 1's flow band is realigned when its partial is recovered (256 KiB cap). ⟦tests: F1-07-16 @M5⟧

**F2 · Daily entry (the 8-second path)**
`S1 verb button (or ( + )) → S2 amount keypad → account chip (none pre-selected) → S2.1 counterpart (recents first; inline create if new) → [note/photo/date optional] → Save → toast "Saved ✓" + Undo 10s → keypad stays open, zeroed`
◆ book full (`rejected:quota`) → Save blocked with the S12.5 sheet → S12.1; draft preserved (ADR 2026-09-05f §B).
◆ idle lock never fires while the keypad holds digits; a lock or a phone call mid-entry returns the draft to the same field (§8).
◆ over the member's limit → posts anyway, toast reads "Saved ✓ · Sunita will review".
◆ offline → identical; chip reads "Saved on phone · will sync".

**F3 · Statement review (the reader's path)**
`S3 search khata → S4 grouped listing → period tabs / date navigator → tap row → S4.1 entry detail (photo, audit trail, who entered) → [Amend | Reverse] → S8.2 export PDF/XLSX (classical columns, voucher, cross-check footer)`

**F4 · Bank statement import**
`S2 import button (header, top right) → S7 pick account + file → on-device parse → S7.2 balance check → S7.1 inbox: each line shows bank text (grey) + Money in/out + one question ("Where did it come from?" / "Where did it go?") → ◆ matched(auto-link) | suggested(1-tap confirm) | new(pick A/C) | transfer-pair(S7.3 "same money moving?") | unknown("record now, explain later" → Suspense) ⟳ until inbox empty → S7.4 preview (every entry about to post) → submit`
Rule learned on first correction; Suspense must reach zero before month close.

**F5 · Review cycle (post-then-review)**
Author: entry posts → amber clock on the row → one summary chip per book view.
Reviewer: `push (digest) → S6 → S6.1 grouped card ◆ Approve all → done | One by one → S6.2 stepper: approve / reject+reason (auto-reversal posts) / skip ⟳ through n`
Nothing is ever excluded from a balance because it is awaiting review.

**F6 · Advance (ਐਡਵਾਂਸ) — the exception that gates first**
`S5.1 request (amount + purpose, required) → approver notified → ◆approve → cash disbursed, Advance–{member} opens → holder records spends against it ⟳ → returns remainder → advance closes at zero`
Ageing counter from first disbursal; reminders to holder then approver; write-off requires approver + reason; open advances block member removal.

**F7 · Inter-book movement**
`S2.3 from(book+account) → to(book+account) → amount → Save → both halves post immediately` ◆ actor lacks rights on one side → that half carries a review flag; pair shows "in transit" until cleared. Family Reconciliation nets to zero from the moment of entry.

**F8 · Invite + verification ceremony**
`S9.1 invite (phone + per-book roles) → invitee installs, OTP → personal book works immediately; shared books greyed "Meet Sunita to activate" → ceremony: S9.2 Show my code ‖ S9.3 Verify member (camera default; "enter code instead") ◆ match → keys wrapped, member Active | mismatch → S9.4 full red, no override, logged`
Remote mode: verifier instructed to *call and have the code read aloud* — never a share button. Delegated: any active member may verify.

**F9 · Month close**
`S1 close card (from the 1st) → S10 step1 count cash (difference → guided adjustment) → step2 confirm each bank → step3 clear tray (review flags, Suspense, aged advances warn) → step4 confirm & lock (balance-vector hash published; every member device verifies)`
◆ any open author gap or `held` envelope → lock disabled, **S10.5** names the phone (ADR 2026-09-05b §3–4, 05e).
◆ a member's device is on an older projector → it shows *"Update the app to verify this close"* and keeps the close as unverified-by-you, never a mismatch alarm (ADR 2026-09-05c §3).
◆ late arrival after lock → S10.3 re-date (default) or re-open (admin, logged).

**F10 · Year close & carry-forward**
`March locked → S10.4 preconditions checklist → ◆ distribute business profit first (optional) → certify → year seals → FY switcher appears; new FY opens with certified b/f`

**F11 · New device / recovery**
`OTP → (device certified? no → sees nothing of the family, S0.9 variant) → ◆ own device available → link via ceremony (instant) | guardians → S11.2 k-of-n live progress → ◆ user still has an active device → 24 h wait, S11.9 Cancel on every existing device | none → immediate | paper sheet → S11.3 scan/type | none → S11.8 honest empty-vault screen + path`
Recovery completion revokes all prior sessions and notifies every tenant; **every newly certified device, on every path, notifies all the user's devices and every tenant** (ADR 2026-09-05d §1, §2, §6).

**F12 · Everything scope (joint family overview)**
`S1 scope chip → "Everything" → aggregate position with a card per book, subtotals, open advances across the family, inter-book reconciliation status. Read-only; tapping any card switches scope to that book.`

---

## 6. State models

**Entry:** `posted` (always, on save) → optional `needs-review` flag → `flag cleared` | `rejected → reversal posted`. Amended entries supersede; reversed entries strike through. **`held`** (an amend, reverse or decision whose target has not arrived) `→ projected | quarantined(target_missing)` — not counted while held (02 §5, ADR 2026-09-05b §4). No **posted, projected** entry is ever excluded from a balance because it awaits review.

**Membership:** `invited → joined_pending_verification → active` · `expired` (7 d, one-tap re-invite) · `blocked` (mismatch) · `removed` (after advance settlement + key rotation; a structural quorum action — 05e).

**Device** (ADR 2026-09-05f §B): `uncertified` (sees only itself — ADR 2026-09-05d §2) `→ certified` (announces itself everywhere — 05d §6) `→ suspended` (unsigned revocation: read-only + banner, S15.4 — 05b §2) `→ revoked` (verified signed record: wipe) · `revoked` also reachable from `certified` directly.

**App lock** (ADR 2026-09-05f §B): `open → locked` (background 2 min · idle 5 min · cold start) `→ unlock` (biometric | MPIN) · MPIN: `5 free → cooldown 30 s · 1 min · 5 min · 15 min · 1 h → disabled after 10 → OTP + biometric` · biometric re-enrolment `→ PIN once`. Lock and interruption never discard work (§8).

**Period:** `open → locked → (re-opened, logged)`; lock disabled while any author gap or `held` envelope is open (S10.5). **Year:** `open → closed/certified → (voided by re-open, loudly)` — 02 §8.1 says `closed`, this doc said `certified`; both name the same state (05e). A close carries `projector_version`; a device on an older projector shows it as **unverified-by-you** ("Update the app to verify this close"), never as a mismatch (ADR 2026-09-05c §3).

**Sync** (owner: 05 §9): `synced ✓` · `saved on phone (n)` · `offline` · `waiting for entries from {name}'s phone` (author gap < 24 h — projection **provisional**, close blocked) · `needs attention → Inbox` (rejections, quarantines, key wait > 24 h, gap > 24 h, write lost, clock warning) · `rebuilding` (S1.4, determinate loader). `rate_limited` has **no UI** by ruling. Never a spinner on save — or anywhere: waiting is shown by the 2px loader rule with a count, or by state words (11 §4.5, ADR 2026-09-03d).

**Subscription:** `trial → active → dunning grace (payment failed, tenant-wide, S12.4) → read-only (export always works, S12.5)`; separately **offline grace** (device-local, from the last entitlement token seen — never read-only before the server has said lapsed) — two graces, two copies (ADR 2026-09-05g). `book full` (quota) blocks posting only, drafts kept. Lapse blocks new entry only.

---

## 7. Permissions × surfaces

| Surface | Admin | Head | Member | Operator | Viewer |
|---|---|---|---|---|---|
| Own personal book | full (own only) | full (own) | full (own) | full (own) | full (own) |
| Book position / statements | ✓ | ✓ own book | ✓ own book | limited (no P&L) | ✓ read |
| Create entry | ✓ | ✓ | ✓ (limit → flag) | ✓ (limit → flag) | — |
| Review flags | ✓ | ✓ own book | — | — | — |
| Approve advance | ✓ | ✓ | — | — | — |
| Month/year close | ✓ | ✓ own book | — | — | — |
| Invite / remove / roles | ✓ | — | — | — | — |
| Export | ✓ | ✓ | ✓ own | ✓ own | ✓ |

**Never rendered for anyone:** another member's personal book detail; a "recover this user's data" action; a support path to content.

---

## 8. Cross-cutting rules

**Content & localization.** EN / ਪੰਜਾਬੀ / हिन्दी, per member, equal status — **all LTR: no mirroring, ever**; user-typed strings carry their own `lang` tag (design-system §3.1 item 1). Containers budget +40% width. English abbreviates months; PA/HI never do. ICU MessageFormat, no concatenation. Every amount: ₹ + Indian grouping + tabular figures, **Latin digits in the amount column even under the Devanagari-numeral opt-in**, no paise in-app (two decimals in statements and exports — ADR 2026-09-05f §H8–9).

**Interruption.** Lock (background, idle, cold start), a phone call, or a lifecycle kill **never discards work**: a half-typed entry or a half-done wizard returns to the same field after unlock (ADR 2026-09-05f §B).

**Empty states.** Each list defines: friendly line + the single next action. New-user Home shows the setup checklist, never a blank.

**Errors.** Named cause + path. Locked date → "Fix an old entry". Parse failure → supported formats + sample. Sync rejection → Inbox card, never a modal.

**Offline.** The default assumption, not an error state. Entry, statements, reports and exports all work offline from the local projection.

**Motion.** 120–400ms, brand easings, nothing bounces. The sealed→open mark animates only on real unlock (m=1.0 splash, 0.6 biometric); jump-cut under reduced-motion.

**Accessibility.** The normative list is design-system §3.1 (WCAG 2.2 AA); this is the summary: colour never alone (sign + icon + word). 200% font scale without truncation on 375×667 and 360×800. Touch targets ≥ 44dp (`minTouchTarget` token). Focus visible on every control incl. primary buttons (`focus-on-primary`). Grayscale test passes on every screen. Screen-reader labels announce amount *and* direction ("two thousand rupees, money out").

---

## 9. Handoff checklist

- [ ] Tokens imported as Figma variables from `design/tokens/tokens.json` (light + dark)
- [ ] P1/P2/P3 patterns built as components with all states before any screen
- [ ] Every screen in the S-inventory drawn in light + dark
- [ ] Every screen drawn in all three languages (Gurmukhi with Mukta Mahee, not a fallback)
- [ ] Empty / error / offline variant for every list screen
- [ ] Prototype: F2 (entry) and F5 (review) tappable end-to-end
- [ ] Prototype: **F9 (month close) and F11 (recovery)** — the two flows where money and books are at risk (ADR 2026-09-05f §H15)
- [ ] Stopwatch test on the F2 prototype: ≤ 8 seconds, biometric unlock included
- [ ] Redlines reference token names, never raw hex
- [ ] **Loading / skeleton variant** for every list screen; every countable wait has its "{done} of {total} {things} {verbed}" copy (ADR 2026-09-03d)
- [ ] `lang` attributes on user-typed strings · live regions on status chips · table semantics on the statement · camera-free ceremony path (design-system §3.1)
- [ ] Every screen holds at **375×667 and 360×800** at 200% font scale; reduced-motion and dark passes
- [ ] Token names used in the canvases follow the **token ↔ CSS ↔ Dart ↔ Figma ↔ canvas map** (design-system §4); no second palette anywhere

## 10. Decisions — settled 🔒 ⟦tests: n/a — index of decisions settled elsewhere; each is marked at its owning ruling⟧

All resolved from existing locked rules rather than fresh preference; the governing rule is cited for each.

| # | Decision | Resolution | Governed by |
|---|---|---|---|
| 1 | P1 icon treatment | **Outlined glyph, muted colour, on a hairline disc** — never saturated fills | Brand §4.3: colour lives in the numerals, one accent per screen. A page of coloured discs fights every amount |
| 2 | Group header value | **Single-account statement → running balance at end of that day** (with side). **Multi-account day book → the day's net in/out** — a running balance is meaningless across mixed accounts | 02 §9: balances are the product; context decides which figure exists |
| 3 | Home layout | **Hero + cards, verbs docked low** — total money you have on top, books-balanced card, compact position cards, four verb buttons docked above the bottom nav (thumb rest), today's entries below | Law 1 (8-second) + 07 §1.2 one-hand + owner's "card style, less dense" + the two newly approved cards |
| 4 | Month in/out figures | **Their own compact card, not on the verb buttons** | 07 §5 / design brief: verbs are doors, not displays. Reading a figure before acting costs the 8-second law |
| 5 | Dr/Cr colouring on statements | **In-app statement keeps option-A directional colour; exported PDF is monochrome** with side tags only | Law 2: the screen is a consumer surface, the export is the professional artefact. Same data, two renderings |
| 6 | Voucher & per-row date | **App: grouped by date, no voucher. Export: classical per-row date + voucher + cross-check footer** | Owner ruling (voucher is backend identity) + CA needs every printed row self-contained |
| 7 | WhatsApp statement share | **Phase 1**, shipping with exports at M12 | Brand §5 (users live on WhatsApp); it is the cheapest adoption lever we have |
| 8 | A/C merge | **Phase 2 (v1).** Long-press → *Merge into…*; same class only; re-points references, posts no entries; admin-only; logged and reversible | 02 §1.4 append-only — a merge must not fabricate postings |
| 9 | Minimum device | **iOS 16, iPhone SE 3rd gen (375×667)**; design canvas **390×844**; app size < 40 MB. Android follows from the same codebase (Android 9, 2 GB, 360×800). This is also the **perf-gate device** — p95 of 20 runs, nightly (ADR 2026-09-05i §6) | Owner ruling: iOS first |
| 10 | Reports in bottom nav | **No — stays in Menu**, reached also by tapping the books-balanced card on Home | §3.1: five slots, and Inbox carries the collaboration model that differentiates the product |
| 11 | Business tier price | **Raise to ₹2,999/yr** (Family stays ₹1,999) ⚠️ owner-adjustable | 08 §1: price the family, not the seat — but a shop avoiding a bookkeeper's fee has different price sensitivity than a household |

**Consequence for handoff:** the screen-shaping decisions the 5 Sep ADRs raised are settled in ADR 2026-09-05f (tab bar, suspended device, book full, depth rule, recovery window, modified-device cadence, paise, status colours, PIN lockout). Beyond those, everything a designer would otherwise guess is specified.

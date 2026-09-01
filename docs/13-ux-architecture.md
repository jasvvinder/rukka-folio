# 13 — UX Architecture & Flow Framework

**Version 1.0 · 30 Aug 2026 · Production handoff draft.**
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
Scope persists per tab, defaults to last used, and is always visible as a chip in the top bar. Switching scope never loses the current screen — the same screen re-renders in the new context.

### 2.3 Who am I, here? 🔒
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
Roles (admin · head · member · operator · viewer) change *what actions appear*, never *which screens exist*. A viewer sees the same statement screen without the entry button. This keeps the mental model stable across a family where everyone has different rights.

---

## 3. Information architecture

### 3.1 Navigation model
Five-slot bottom bar, persistent, with a centre action:

```
┌──────────────────────────────────────────────────────┐
│   Home      Ledger      ( + )      Inbox•     Menu    │
└──────────────────────────────────────────────────────┘
     S1         S3          S2         S6        S8
```
- **Home (S1)** — position + today. The answer screen.
- **Ledger (S3)** — A–Z index of every A/C. The find screen.
- **( + ) (S2)** — entry. The do screen. Long-press repeats last entry.
- **Inbox (S6)** — one tray for everything awaiting a human. The attention screen.
- **Menu (S8)** — reports, books, members, settings. The rarely screen.

**Rule:** four thumb-reachable destinations plus one action. No hamburger, no nested tabs, no more than two levels deep from any bottom-bar root.

### 3.2 Complete screen inventory
| ID | Screen | Root | Purpose |
|---|---|---|---|
| **S0.0** | Splash | launch | mark, sealed→open animation on real unlock only |
| **S0.05** | Welcome | first launch | 3 skippable slides, after language so they are in the user's language |
| **S0.8** | Set your PIN | onboarding | 6-digit, set + confirm (06 §4.4) |
| **S15.3** | Enter PIN | app lock | 6 boxes; Face ID button; *Forgot PIN* → OTP + biometric |
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
| **S0.6** | Opening balances wizard | onboarding | resumable |
| **S0.7** | Setup checklist (Home empty state) | S1 | progressive onboarding |
| **S1** | Home / Position | root | banks, cash, get/give, advances, in-transit, month, verbs, today |
| **S1.1** | Position line drill-down | S1 | list behind any position row |
| **S2** | Add entry (keypad-first) | action | the 8-second flow |
| **S2.1** | A/C picker + inline create | S2 | search-first, class inferred by slot |
| **S2.2** | Date picker | S2 | today default, backdate ok, future disabled |
| **S2.3** | Transfer (within/between books) | S2 | pairs |
| **S2.4** | Adjustment wizards | S2 | guided only, never freeform |
| **S3** | Ledger index (A–Z khatas) | root | search header, filter chips |
| **S4** | A/C statement | S3 | grouped listing; professional columns in export |
| **S4.1** | Entry detail | S4/S1 | audit trail, photo, amend/reverse |
| **S5** | Advances (ਐਡਵਾਂਸ) | S1/S6 | mine held · given out, aged |
| **S5.1** | Advance request | S5 | amount + purpose → approver |
| **S6** | Inbox | root | grouped cards, all attention types |
| **S6.1** | Review — grouped card | S6 | Approve all / One by one |
| **S6.3** | Structural approval card | S6 | states exactly what will change; Approve / Veto with reason; shows quorum progress (2 of 3) |
| **S6.2** | Review — stepper | S6.1 | approve / reject+reason / skip |
| **S7** | Import — pick file & account | S8 | on-device parse |
| **S7.1** | Import inbox | S7/S6 | one question per line |
| **S7.2** | Import balance check | S7 | statement's opening/closing vs the ledger; passing · matched · failing (07 §11.1, ADR 2026-09-01) |
| **S7.3** | Transfer-pair confirm | S7.1 | "same money moving?" — a row-level card in the import inbox |
| **S7.4** | Import preview & submit | S7.1 | every entry about to post, balance check restated, count in the button (owner-added 1 Sep 2026) |
| **S8** | Menu | root | hub |
| **S8.1** | Reports list | S8 | day book, cash book, P&L, position, ageing, reconciliation |
| **S8.2** | Report viewer + export | S8.1 | PDF/XLSX, FY switcher |
| **S9** | Books & members | S8 | roles, limits, verification log |
| **S9.5** | Add a business | S9/Menu | name · type (just me / shared) · FY start · opening balances — creates the book (02 §7.1) |
| **S1.2** | Scope switcher — two books | S1 | the small control when only Me + one business exist; **not** the grouped joint-family sheet (S1.3) |
| **S1.3** | Scope switcher — grouped sheet | S1 | Me / Family / Businesses / Organizations / Everything |
| **S9.1** | Invite member | S9 | phone + per-book roles |
| **S9.2** | Show my code (QR + 8-digit) | ceremony | invitee side |
| **S9.3** | Verify member (camera/code) | ceremony | verifier side |
| **S9.4** | Verification mismatch | S9.3 | hard-fail, no override |
| **S5.5** | Cash count sheet (verify / collect modes) | S4/S10 | denomination grid; mandatory in trust books (02 §8.2) |
| **S6.3** | Structural approval card | S6 | quorum progress, Approve / Veto (02 §7.2.1) |
| **S14** | Partner positions | S8.1 | per-owner put-in / took-out / share / net + settlement capacity (02 §7.1) |
| **S14.1** | Profit distribution wizard | S14 | period profit → ratio preview (incl. interest lines) → one multi-line entry |
| **S14.2** | Drift & settlement card | S14 | over/under-funding notice; pay out · partner-to-partner · carry forward |
| **S10** | Month close wizard (4 steps) | S1/S8 | cash count · banks · tray · lock |
| **S10.1** | Family close status | S10 | which books are closed, who is being waited on |
| **S10.2** | Month summary card | S10 | shareable close reward |
| **S10.3** | Late arrivals tray | S6 | re-date or re-open |
| **S10.4** | Year close + carry-forward | S8 | certify, FY switcher appears |
| **S11.4** | Backup settings | S11 | platform key sync toggle · save recovery sheet · readable monthly copy, each with its risk line (04 §7.6) |
| **S11** | Devices & security | S8 | devices, guardians, recovery sheet, escrow, PIN |
| **S11.1** | Guardian setup (mutual ceremony) | S11 | 2-of-3 |
| **S11.2** | Recovery — ask guardians | activation | live k-of-n progress |
| **S11.3** | Recovery — paper sheet | activation | scan/type |
| **S12** | Subscription | S8 | tiers, renewal, read-only banner |
| **S4.1** | Entry detail | any P1 row | audit trail, photo, who entered, amend/reverse — the target of every tap in every list |
| **S9.1** | Invite member | S9 | phone + per-book roles + limits |
| **S16** | My account | S8 | name, photo, phone, language |
| **S16.1** | Edit profile | S16 | name and photo only |
| **S16.2** | Change phone number | S16 | OTP old + new, or guardian approval if the old number is lost (06 §9.4) |
| **S16.3** | Delete account | S16 | 15-day cooling, what is erased vs retained (06 §9.3) |
| **S12.1** | Plans | S12 | comparison, annual saving, current plan marked |
| **S12.2** | Checkout | S12.1 | **iOS = In-App Purchase** (08 §3.2); coupon and GSTIN on non-iOS only |
| **S12.3** | Manage subscription | S12 | plan, renewal date, change, cancel |
| **S12.4** | Payment problem | S12 | grace countdown, retry, what happens at the end |
| **S12.5** | Read-only mode | global | banner + blocked-entry sheet; export always works |
| **S12.6** | Invoices | S12 | list + PDF |
| **S17** | Help | S8 | search, FAQ, contact, diagnostics |
| **S17.1** | FAQ list | S17 | grouped, searchable |
| **S17.2** | FAQ article | S17.1 | one answer, plain language |
| **S17.3** | Contact support | S17 | WhatsApp primary; states what support cannot do |
| **S17.4** | Send diagnostics | S17.3 | user-triggered, financial values scrubbed, shown before sending |
| **S18** | Legal | S8 | terms, privacy, licences |
| **S18.1** | Terms of service | S18 | |
| **S18.2** | Privacy policy | S18 | |
| **S18.3** | What we can and cannot see | S18/onboarding | the impossibility table (12 §2) as a user-facing page — a trust asset, not boilerplate |
| **S18.4** | Open-source licences | S18 | |
| **S19.1** | Update required | global | 426 from the API (06 §4.5) |
| **S19.2** | Maintenance | global | |
| **S19.3** | No connection | global | non-blocking; the app works offline |
| **S19.4** | Permission priming | before OS prompt | notifications and camera, asked in context |
| **S20** | Attachment viewer | S4.1 | pinch-zoom bill photo, share, replace |
| **S21** | Search | S3/S1 | across accounts, parties and notes |
| **S15** | App lock | cold start / timeout | biometric auto-prompt, **MPIN fallback — never the device passcode** (06 §4.4, 07 §5.6) |
| **S15.1** | Privacy cover | background | mark on paper; no balances in the app switcher |
| **S15.2** | Personal Book lock — re-prompt | S11 | opt-in extra gate; asks the **same MPIN or biometric** again — one PIN, never a second number (06 §4.4, ADR 2026-09-01) |
| **S13** | Settings | S8 | language, notifications, export everything |

**Depth rule:** S1–S8 are roots; everything else is at most two levels below one of them.

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
Label · value with side/colour · optional meta ("1 · Ramesh") · chevron to drill down. Grouped in a card with the 3px left rule.

**P3 — Attention card** (Inbox: reviews, imports, invites, recoveries, reminders)
Avatar/icon · who + where + count + total · expandable list · primary action + secondary action. One card per (author, book, day) — never one per item.

### 4.2 Atoms
Amount text (3 sizes × in/out/pending/neutral) · account chip · scope chip · date chip · status chip (review/locked/in-transit/offline) · keypad · books-balanced verification card · search field · picker row with "+ Create" · stepper progress · books-balanced verification card · loud-warning panel.

### 4.3 Component states
Every interactive component ships: default · pressed · disabled-with-reason · loading · error. Every list ships: populated · empty (with the one next action) · error-with-retry · offline.

---

## 5. Primary flows

Notation: `→` step · `◆` decision · `⟳` loops until · `‖` parallel.

**F1 · First run (individual)**
`S0.1 language → S0.2 phone+OTP → S0.3 purpose ◆(Myself|Shop|Businesses|Family) → S0.4 name → S0.5 recovery sheet (print → verify by scanning it back) → S0.6 opening balances (skippable) → S1 with setup checklist`
Success: user reaches Home understanding that no password exists and the paper sheet matters.

**F2 · Daily entry (the 8-second path)**
`S1 verb button (or ( + )) → S2 amount keypad → account chip → S2.1 counterpart (recents first; inline create if new) → [note/photo/date optional] → Save → toast "Saved ✓" + Undo 10s → keypad stays open, zeroed`
◆ over the member's limit → posts anyway, toast reads "Saved ✓ · Sunita will review".
◆ offline → identical; chip reads "Saved on phone · will sync".

**F3 · Statement review (the reader's path)**
`S3 search khata → S4 grouped listing → period tabs / date navigator → tap row → S4.1 entry detail (photo, audit trail, who entered) → [Amend | Reverse] → S8.2 export PDF/XLSX (classical columns, voucher, cross-check footer)`

**F4 · Bank statement import**
`S8 → S7 pick account + file → on-device parse → S7.2 balance check → S7.1 inbox: each line shows bank text (grey) + Money in/out + one question ("Where did it come from?" / "Where did it go?") → ◆ matched(auto-link) | suggested(1-tap confirm) | new(pick A/C) | transfer-pair(S7.3 "same money moving?") | unknown("record now, explain later" → Suspense) ⟳ until inbox empty → S7.4 preview (every entry about to post) → submit`
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
◆ late arrival after lock → S10.3 re-date (default) or re-open (admin, logged).

**F10 · Year close & carry-forward**
`March locked → S10.4 preconditions checklist → ◆ distribute business profit first (optional) → certify → year seals → FY switcher appears; new FY opens with certified b/f`

**F11 · New device / recovery**
`OTP → ◆ own device available → link via ceremony | guardians → S11.2 k-of-n live progress | paper sheet → S11.3 scan/type | none → honest empty-vault screen + path`
Recovery completion revokes all prior sessions and notifies every tenant.

**F12 · Everything scope (joint family overview)**
`S1 scope chip → "Everything" → aggregate position with a card per book, subtotals, open advances across the family, inter-book reconciliation status. Read-only; tapping any card switches scope to that book.`

---

## 6. State models

**Entry:** `posted` (always, on save) → optional `needs-review` flag → `flag cleared` | `rejected → reversal posted`. Amended entries supersede; reversed entries strike through. No state excludes an entry from balances.

**Membership:** `invited → joined_pending_verification → active` · `blocked` (mismatch) · `removed` (after advance settlement + key rotation).

**Period:** `open → locked → (re-opened, logged)`. **Year:** `open → certified → (voided by re-open, loudly)`.

**Sync:** `synced ✓` · `saved on phone (n)` · `offline` · `needs attention → Inbox`. Never a spinner on save.

**Subscription:** `trial → active → grace(7d offline) → read-only(export always works)`. Lapse blocks new entry only.

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

**Content & localization.** EN / ਪੰਜਾਬੀ / हिन्दी, per member, equal status. Containers budget +40% width. English abbreviates months; PA/HI never do. ICU MessageFormat, no concatenation. Every amount: ₹ + Indian grouping + tabular figures.

**Empty states.** Each list defines: friendly line + the single next action. New-user Home shows the setup checklist, never a blank.

**Errors.** Named cause + path. Locked date → "Fix an old entry". Parse failure → supported formats + sample. Sync rejection → Inbox card, never a modal.

**Offline.** The default assumption, not an error state. Entry, statements, reports and exports all work offline from the local projection.

**Motion.** 120–400ms, brand easings, nothing bounces. The sealed→open mark animates only on real unlock (m=1.0 splash, 0.6 biometric); jump-cut under reduced-motion.

**Accessibility.** Colour never alone (sign + icon + word). 200% font scale without truncation. Touch targets ≥ 44dp. Grayscale test passes on every screen. Screen-reader labels announce amount *and* direction ("two thousand rupees, money out").

---

## 9. Handoff checklist

- [ ] Tokens imported as Figma variables from `design/tokens/tokens.json` (light + dark)
- [ ] P1/P2/P3 patterns built as components with all states before any screen
- [ ] Every screen in the S-inventory drawn in light + dark
- [ ] Every screen drawn in all three languages (Gurmukhi with Mukta Mahee, not a fallback)
- [ ] Empty / error / offline variant for every list screen
- [ ] Prototype: F2 (entry) and F5 (review) tappable end-to-end
- [ ] Stopwatch test on the F2 prototype: ≤ 8 seconds
- [ ] Redlines reference token names, never raw hex

## 10. Decisions — settled 🔒

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
| 9 | Minimum device | **iOS 16, iPhone SE 3rd gen (375×667)**; design canvas **390×844**; app size < 40 MB. Android follows from the same codebase (Android 9, 2 GB, 360×800) | Owner ruling: iOS first |
| 10 | Reports in bottom nav | **No — stays in Menu**, reached also by tapping the books-balanced card on Home | §3.1: five slots, and Inbox carries the collaboration model that differentiates the product |
| 11 | Business tier price | **Raise to ₹2,999/yr** (Family stays ₹1,999) ⚠️ owner-adjustable | 08 §1: price the family, not the seat — but a shop avoiding a bookkeeper's fee has different price sensitivity than a household |

**Consequence for handoff:** no screen-shaping decision remains open. Everything a designer would otherwise guess is now specified.

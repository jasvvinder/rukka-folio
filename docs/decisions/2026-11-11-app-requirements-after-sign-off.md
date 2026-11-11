# ADR 2026-11-11 — App requirements after the accounting sign-off (PLAN-210): one book, from → to entries, correcting entries, the posted year close

**Status:** Accepted (owner, 11 Nov 2026). Rules decisions D0–D14 of `docs/app-requirements-pass.md` (the PLAN-210 pass, drafted 2 Nov 2026). That file keeps the requirements register (§3) and stays where it is until the doc edits below are made. Then it moves to `docs/archive/`.

**Context.** After the bookkeeper sign-off (ADR 2026-11-01), `docs/accounting/` ranks above the numbered specs on accounting behaviour (ADR 2026-10-22 §1). The engine, 02 and the screens were all built for the model that came before the rulings: six verbs with fixed postings, enforced by `checkShape` (`packages/core_ledger/lib/src/invariants.dart:191-262`). About thirty kinds of entry in the five reference books fit no verb. The pass compared the signed docs with 02, 07, 13, the design and the code, and put fifteen decisions to the owner.

**How the owner ruled (11 Nov 2026).**
- D1, and D0, D2, D5–D14: as recommended.
- D3: as recommended, after the amend chain was explained to him.
- D4: changed. Approval of an advance becomes a book setting, off by default for every book.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

Every ruling takes effect with its build slice (PLAN-210 step 2 onwards). That slice allocates the new test ids and marks the tests named under *Consequences* `@Skip('superseded by ADR 2026-11-11 §<n>; re-lands at M14')` in the same commit. ADR 2026-10-12 §6 and §8 work the same way.

### 0. One book; behaviour comes from its accounts, never from its kind (D0) 🔒 ⟦tests: n/a — ruled here; the build slice allocates the tests⟧
- The engine and the reports never branch on what kind of book it is (shop, firm, contractor, farm, household, trust or any other). Every behaviour follows from the accounts the book has opened:
  - **More than one owner's own-money account** (partners or co-owners): the year's result is shared through a posted appropriation (§5).
  - **One:** the result goes to that account.
  - **A fund account:** it has a fund statement, and spending from it is charged to the year and moved out of the fund.
  - **Things owned, deposits, loans:** they appear wherever such accounts exist.
- **Words are labels.** They are set at setup, can be edited, and never drive logic. That covers:
  - the name of the own-money account (*Own money*, *Capital – {name}*, *General Fund*)
  - the name of the result account (*Income & Expenses*, *Profit & Loss*, *Income & Expenditure*)
  - the result words (*Saving*, *Profit*, *Surplus*)
- **The setup purpose** (S0.3: myself, a business, a family, a trust) only chooses those starting labels and which accounts are suggested. A business is *a business*, with no list of sub-kinds.
- **Policies are book settings, not types.** Today's `BookType` branch (`packages/core_ledger/lib/src/accounts.dart:7-22`; `cash_count.dart:131`, the note-count sheet that is mandatory for a trust) becomes a setting, on by default when the purpose is a trust.
- The book keys of the register (JP, FAM, SHOP, BF, RS) only name which sample book shows a case. The app never branches on them.
- **Supersedes:** 02 §1.1's list of book types as behaviour, and the per-kind seed table of ADR 2026-09-09c §1. Per-kind seeds had already been dropped (owner, 20 Oct 2026; PLAN-122).

### 1. Entry model: any balanced entry from one opened account to another, checked by rules for each kind (D1) 🔒 ⟦tests: n/a — ruled here; the build slice allocates the tests and skips A-05e-8⟧
- The engine accepts any balanced entry between accounts the book has opened, as long as it passes the rules for each kind of account. These are the rules the reference books are already built to (`docs/accounting/reference-books/shop-sukhwinder-sales-co.tech.md:119`):
  - Money in or out touches a money account; a no-money entry does not.
  - A transfer joins two of the book's own money or deposit accounts.
  - Spending from a fund charges the year and moves the same amount out of the fund.
  - The gollak is filled only by a count, and emptied only into cash or bank.
  - No account appears twice in one entry.
  - Cash, bank and wallet never go below nil, and a card never goes past nil. Breaking this is warned, not refused; 02 §1.1-1.6's warning is kept and read as "an entry is missing" (R-02).
  - Advances, loans given, retention, things owned and deposits are never over-settled.
- Every reader re-checks these rules, as it re-checks the shapes today. A violation is quarantined, as now. The rule changes; zero-knowledge enforcement does not.
- **The six verbs become shortcuts on the entry screen.** Each one produces an entry of this kind. Guided entries cover the multi-line shapes (loan instalment, advance settled across several heads, salary with an advance recovered, thing owned sold, fund spend).
- **00-vision bet 3** changes from *"Six verbs, no jargon — the user can never build a wrong posting"* to *"No jargon — the everyday entries need no accounting knowledge; every entry is true double entry"*.
- **Supersedes:** ADR 2026-09-05e §6 (verb → posting shapes as reader-enforced invariants), 02 §1.4 rule 7, and 02 §2's *fixed postings* as the only postings allowed.

### 2. Kinds of account (D2) 🔒 ⟦tests: n/a — ruled here; the build slice allocates the tests⟧
- The kinds the reference books use are added (register R-01…R-26):
  - thing owned, at cost
  - loan taken and loan given, as their own accounts beside a person's running account
  - deposit (FD/RD)
  - deposit held, deposit paid and retention held, each on the person's page
  - *Advance – {any named person}*
  - fund for a purpose
  - own money and Drawings as real accounts named after the owner
  - partner capital and current, fixed or fluctuating
  - sub-family and joint-family running accounts, and the *Udhaar* page
  - money in a business, held at what was put in
  - *Cash short / over*
  - *Not yet sorted*, replacing *Suspense*
  - General Fund and Corpus as real accounts
- Card and KCC are liabilities used as money (R-04/05/06).
- There are no *Opening Balance*, *Adjustments* or *Due to/from* accounts.
- 02 decides how they are represented (classes, subtypes, roles), and maps its classes onto the five standard types (`docs/accounting/01` §2.3-2.4).
- **Supersedes:** ADR 2026-10-12 §6's *"No `liability` class now"*, the computed Accumulated surplus and Corpus lines of 02 §1.2 and ADR 2026-09-05e §2, and ADR 2026-09-09b §1 (*Capital is Opening Balance*).

### 3. Corrections: a posted entry is never changed (D3) 🔒 ⟦tests: n/a — ruled here; the build slice skips the amend tests named under Consequences⟧
- The amend chain goes: no amend envelope and no `refs.amends`. A posted entry is never edited, in an open period or a locked one (`docs/accounting/02` §7.1, ruling O-11-2).
- **A correction is a new balanced entry dated the day it is made. Its note names the entry it fixes, by number and date** (§7.2).
- Posted to the wrong account with the right amount: one entry moves it (§7.3).
- A correction to an income or expense of a closed year goes to that head's *earlier year* line, such as *Rent — earlier year* (§7.6).
- *Cancel this entry* stays. It posts a correction that mirrors the whole entry.
- Until the user taps Save, anything on the entry screen can be changed. That is the app's *"before posting"*.
- **Cost, accepted:** a typo fixed the same day leaves two entries.
- **Supersedes:** 02 §5's open-period amend, the *"edited by …, n changes"* history view, and the `held` rule for amendments, which stays for reversals and decisions. Of 02 §5's locked-period reversal it supersedes only the reversal's restriction to locked periods: a mirror correction now serves both.

### 4. Advances: to any named person; approval is a book setting, off by default (D4) 🔒 ⟦tests: n/a — ruled here; the build slice allocates the tests and rewrites those of 02 §7⟧
- An advance can go to any named person (driver, house help, sewadar, member). It is opened like a person's account, *Advance – {name}*.
- **Approval of advances is a book setting, off by default for every book.** An owner or admin can switch it on.
  - **Off:** the advance posts when it is saved, under post-then-review (02 §3) like any entry. Nothing waits.
  - **On:** the advance waits for an approver and posts on approval, as 02 §7 says today. The `pending` status stays, used only while a book has the setting on.
- An advance can be settled across several heads, its unspent part returned, topped up, and its remainder dealt with in three ways; it can also be recovered in a salary entry (R-39, R-40; `docs/accounting/02` §3.2-3.5, §8.4).
- A write-off of an advance or of a person's balance goes to an expense head. **Supersedes** ADR 2026-10-12 §8's second bullet (*"An advance write-off stays on Adjustments"*).
- Post-then-review (02 §3) and the structural approvals (02 §7.2) stay for every entry.

### 5. Year close and books with several owners (D5) 🔒 ⟦tests: n/a — ruled here; the build slice skips the vector and distribution tests named under Consequences⟧
- **The book posts the year close.** Income and expense heads go to the result account, then the result and Drawings go to own money. The user is shown the entries and does not type them (`docs/accounting/04` §2.1).
- A book with **more than one owner's own-money account** shares its result through a posted appropriation account (04 §6.4).
- A book with **one** own-money account, whatever it is called, takes the whole result.
- **The rules for several owners:**
  - Interest on capital is worked on opening capital plus additions by months. It is paid only if agreed, and only out of profit.
  - No agreed ratio means equal shares.
  - A ratio change during the year divides the year's profit by days.
  - Fixed capital with a current account is an option.
- The stored vector with one *net_result* line goes (`projection.dart:894-915`). Carry-forward follows 04 §2.6.
- **A closed year is never reopened** (`docs/accounting/02` §7.6). The structural reopen goes.
- The mid-year distribution wizard (S14.1, with its quorum ceiling) becomes the appropriation step of the year close. S14 and S14.2 stay as views.
- **Supersedes:**
  - 02 §1.2's *"no destructive closing journal entries"*
  - ADR 2026-09-05e §2 (the vector and the computed lines) and §8 (distribution: losses, period, ceiling)
  - ADR 2026-09-14b §6 (the ratio in force at the distribution governs the whole amount)

### 6. Between books (D6) 🔒 ⟦tests: n/a — ruled here; the build slice allocates the tests⟧
- Each book's account for another book is named after that book. *Due to/from* goes.
- A family and its sub-family (a running-account pair) agree balance for balance.
- An owner and their business agree entry by entry. The summary prints *profit kept in the business* or *taken out beyond the profit* (04 §6.6).
- Money a business sends home is the owner's *Income from {business}*, and Drawings in the business's book.
- The family book holds one running account per sub-family, plus an *Udhaar – {sub-family}* page for money taken to be returned. Sub-family books also stay books.
- A three-book entry and a year-end settle-or-carry are added.
- A fix goes only in the book that missed the item. A pair is carried forward by default (`docs/accounting/03` §4.4-4.5).
- **Supersedes:** ADR 2026-09-09c §2 (*"Sub-family shares are books, not accounts"*), its §1 interbook column, and 02 §1.1 and §6's *due-to/due-from* naming.

### 7. Month close (D7) 🔒 ⟦tests: n/a — ruled here; PLAN-211 and the build slice allocate the tests⟧
- A difference in the cash count goes to *Cash short / over*, or to the person minding the cash (`docs/accounting/02` §7.4; ADR 2026-10-27). This closes ADR 2026-10-27's Open item and ADR 2026-11-01's first Open item.
- *Not yet sorted* must be cleared before the **year** closes, not every month (`docs/accounting/02` §7.5).
- Bank: *Not checked this month* is allowed except in the year's last month (ADR 2026-10-27; PLAN-211).

### 8. Opening a book (D8) 🔒 ⟦tests: n/a — ruled here; the build slice skips A-09b-1, A-09b-5 and the opening tests named under Consequences⟧
- A book opens with **one compound opening entry**, balanced by own money (or by the partners' capitals). There is no *Opening Balance* account.
- With several owners, the partners' figures must equal assets less liabilities.
- Things owned, goods on the shelf (to *Goods bought for sale*) and sub-family accounts can be opened.
- Capital put in during the year is an ordinary money-in entry to the owner's own-money account.
- **Supersedes:**
  - ADR 2026-09-09b §1
  - ADR 2026-09-09c §4 (the per-account entry absorbed by *Opening Balance / Capital*; owners' openings via Partner Current)
  - ADR 2026-09-13 §4's account (*Cr Opening Balance/Capital*); its *ordinary money in* framing stays

### 9. Reports (D9) 🔒 ⟦tests: n/a — ruled here; the reports slices allocate the tests⟧
- The S8.1 list becomes the reports of `docs/accounting/04` §4–§6. Every report carries the five-line report head (R-100…R-119).
- For a trust, Receipts & Payments, Income & Expenditure, the Balance Sheet and one statement per fund print together. They are offered to every book, and are the default set for the trust purpose.
- **The Day Book has three layouts:**
  - **the list**, which does not show the year-close entries
  - **the accountant's layout (Dr / To)**, which opens with the opening entry and ends with the year-close entries
  - **the Cash Book**
- The Day Book also gets a *Journal entries only* filter.
- Print and export get a chooser: All or multi-select, any period, with or without notes.

### 10. Scope (D10) ⟦tests: n/a — scope, not behaviour⟧
| Scope | What it means |
|---|---|
| **Pilot** | What the owner's joint family needs to run one month (00-vision). |
| **v1** | Everything the five reference books use, because M14 exit is the engine reproducing them exactly. |
| **Later** | The opt-in adjustments no reference book uses (outstanding, prepaid, accrued, depreciation, closing stock), the donation receipt (S4.2), and the account-name chips until their PA and HI words exist. |

The scope of each row is the last column of the register. 00-vision's non-goals do not change.

### 11. Old data (D11) 🔒 ⟦tests: n/a — no migration; nothing to test⟧
- No migration. The app has not launched, so the old entry kinds are not carried forward: amend chains, *Due to/from*, *Profit Distributed* and the year-close vector.
- Dev and demo data is wiped, as PLAN-118 plans.
- Readers are not required to read the old shapes.

### 12. Older ADRs superseded by name (D12) ⟦tests: n/a — precedence record⟧
Each line below was checked against the ADR on 11 Nov 2026.

| ADR | What it said | Superseded by |
|---|---|---|
| 2026-09-05e §2 | year-close vector; Accumulated surplus and Corpus as computed lines; no closing entry | §2, §5 |
| 2026-09-05e §6 | verb → posting shapes as reader-enforced invariants | §1 |
| 2026-09-05e §8 | profit distribution: losses, period, ceiling | §5 |
| 2026-09-09b §1 | Capital is the Opening Balance account | §2, §8 |
| 2026-09-09c §1 (seed table: per-kind rows and the interbook column), §2, §4 | seeds per book kind; sub-family never an account; opening via Opening Balance / Partner Current | §0, §6, §8 |
| 2026-09-13 §4 (the account only) | capital introduced credits Opening Balance/Capital | §8 |
| 2026-09-14b §6 | the ratio at the distribution governs the whole amount | §5 |
| 2026-10-12 §6 (*no liability class*), §8 (second bullet) | no liability class; advance write-off to Adjustments | §2, §4 |

### 13. Design and the re-skin freeze (D13) ⟦tests: n/a — sequencing⟧
- The engine work (§1–§8) goes first. It does not depend on the re-skin freeze (ADR 2026-10-10b §1).
- New frames are drawn in parallel:
  - the New A/C grid with the new kinds
  - the guided entries
  - the correction
  - the two month-close answers
  - the year-close review
  - the reports of §9
  - the advance-approval setting
- UI slices start when the freeze lifts. Canvas 17's 6a frame is withdrawn (ADR 2026-09-27).

### 14. Fixes to the accounting docs (D14) ⟦tests: n/a — doc corrections⟧
- **(a)** `docs/accounting/01` rule 2 and its Source line are fixed to agree with 04 (owner ruling 27 Oct 2026, C10): a wage goes on the worker's page when it falls due, and *Wages outstanding* is not used.
- **(b)** The reference books' tech companions say the list layout of the Day Book leaves out the year-close entries and the accountant's layout includes them (§9).
- **(c)** An Udhaar page to be returned is a loan given or taken, under *What I have* or *What I owe* (`docs/accounting/03` §3.2). GAPS A11 is fixed.
- **(d)** The *Purchases* chip in `05-account-name-presets.md` becomes *Goods bought for sale* (`docs/accounting/02` §6.1).
- **(e)** GAPS and COVERAGE stop citing the pre-sign-off 02 and *Due to/from* as live conflicts.
- **(f)** The year-end adjustments opt-in (`docs/accounting/04` rule 2.2) becomes a book setting. It is off by default, and offered only when the setup purpose is not *myself* or *a family*. The signed rule is kept as a default, not as a kind of book. It is Later scope (§10).

## Consequences
- **Code (PLAN-210 step 2, tests first, `core_ledger` then `data`).** Kinds of account → kind rules in place of `checkShape` → opening entry → correction → year close and appropriation → between-books naming and agreement → reports in the projector. Every step is checked against the reference books (suite A goldens).
- **Tests to skip or rewrite** when each slice lands, read one by one. *Not checked individually today:* some of these may assert behaviour that carries over (for example, reversal or `held`).

  | Ruling | Test ids |
  |---|---|
  | §1 | A-05e-8 |
  | §3 | A-02-42…47, A-02-50, A-02-57, A-05b-1…3, F1-02-5, F1-02-6 |
  | §4 | A-02-72…77, F1-02-13…18 |
  | §5 | A-05e-2…7, A-02-53…55, A-02-58…61, F1-02-54, F1-02-59 |
  | §8 | A-09b-1, A-09b-5, A-02-17, F1-02-7 |
  | §0, §6 | A-09c-1 |

  A-09c-4, A-09c-5 and A-09c-6 are `@M5` and were never written; they are withdrawn. The verbs' own posting tests (A-02-9…21) stay, because the verbs survive as shortcuts.
- **Docs (PLAN-210 step 1).**

  | Doc | What changes |
  |---|---|
  | 00-vision | bet 3 (§1), changed in place now |
  | 02 | cross-reference lines now at §1.1, §1.2, §1.4, §2, §4, §5, §6, §7, §7.1, §8, §8.1. The rewrite of those sections follows, as listed in `app-requirements-pass.md` §4 |
  | 07 | §5, §6, §8, §10, §13, §14 |
  | 13 | — |
  | 09 | suite A re-lands against the reference books (`A-ref-*`), with new ids per guided entry and per report |
  | 10 | *Interest on hand loans* leaves the Phase 2 parking lot, because it is an ordinary entry |
  | `docs/accounting/` | the §14 fixes |
- **Milestone:** M14 (accounting engine re-land). The pilot rows come first (register, *Scope* = P).

## Open ⚠️
- **The 02 rewrite itself.** The cross-reference lines mark what is superseded, but the section bodies still describe the old model until they are rewritten. That is the next docs session.
- **07 and 13 screen text** for *Due to/from*, *Adjustments* and *Suspense* was not read (pass §6). It is part of the 07/13 edits.
- **Where the advance-approval setting lives in Settings (S16)**, and who may switch it: owner or admins under the structural rule of 02 §7.2.1, or any admin. Conservative reading until a frame decides: it is a structural setting (02 §7.2.1).

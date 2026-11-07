# App requirements and scope — the pass after the accounting sign-off (PLAN-210)

**Status:** DRAFT for the owner's ruling, 2 Nov 2026. Not normative. Once ruled, it becomes one ADR plus the edits listed in §4 (00, 02, 07, 09, 10, 13), and this file moves to `docs/archive/`.
**Inputs:** the signed-off `docs/accounting/` (ADR 2026-11-01), `docs/02-ledger-rules.md`, the design (07, 13, canvas mirror, `design/match/`), and the code as built. These were read on 2 Nov 2026 by four read-only surveys, and each claim below cites its line.
**Precedence used:** on accounting behaviour, `docs/accounting/` wins over 02 (ADR 2026-10-22 §1). 02 keeps representation: the class model, verbs, invariants and storage. Canvas frames decide how a screen looks.

---

## 1. The answer in short

The engine, the specs and the screens were all built for the model that came before the rulings. Their core is six verbs with fixed postings, enforced by `checkShape` (`packages/core_ledger/lib/src/invariants.dart:191-262`). Of the kinds of entry the five reference books use, five fit a verb exactly. About thirty fit none:

- buying or selling a thing owned
- a loan instalment
- a deposit
- an advance to a non-member
- a salary with an advance recovered
- a fund spend
- a correction
- the year-close entries
- the appropriation

The verb-fit table is in the 02 survey and is summarised in §3, R-30…R-64. The verbs can't be stretched one at a time to cover these. The recommendation is to change the engine's rule from *"the entry must match one of six verbs"* to *"the entry moves money from one account to another, between accounts this book has opened, and passes the rules for its kind"*, which is ADR 2026-10-22 §2. The verbs survive as the quick routes on the entry screen.

Most of the scope follows from that one change. With a from → to engine, many cases the docs mention need **no build of their own**: petty cash, interest on a hand loan, goods taken home, an insurance claim. They are ordinary entries between accounts of kinds that exist. What does need building is:

- the **kinds of account**
- a handful of **guided entries** for the multi-line shapes
- the **posted year close**
- the **accounts between books**
- the **reports**

---

## 2. Decisions for the owner

Each has a recommendation, so you can accept it or veto it.

**D0 — One book; behaviour comes from its accounts, never from its kind (00-vision bet 1).**
- **Recommend:** the engine and the reports never branch on *what kind of book* this is: shop, company, contractor, farm, household, trust or anything else. Every behaviour follows from the accounts the book has opened:
  - **More than one owner's own-money account** (partners, or co-owners) → the year's result is shared through an appropriation.
  - **One** → the result goes to that own money.
  - **A fund account** → it has a fund statement, and spending from it is charged to the year and moved out of the fund.
  - **Things owned, deposits, loans** → they appear wherever such accounts exist.
- **Words are labels, set at setup and editable, never logic.** This covers:
  - what the own-money account is called (*Own money*, *Capital – {name}*, *General Fund*)
  - what the result account is called (*Income & Expenses*, *Profit & Loss*, *Income & Expenditure*)
  - the result words (*Saving*, *Profit*, *Surplus*)
- **The purpose picked at setup** (S0.3: myself, a business, a family, a trust) only chooses those starting labels and which accounts are suggested. A business is *a business*, with no sub-kind list.
- **Policies are book settings, not types.** One example is today's single `BookType` branch (`packages/core_ledger/lib/src/accounts.dart:7-22`; `cash_count.dart:131`, note-count sheet mandatory for a trust). It becomes a setting, on by default when the purpose is a trust.
- **Evidence:** the engine has no business-kind type today. The only matches for *shop* or *farm* are in tests and the subscription copy. Per-kind seeded account lists were already dropped (owner, 20 Oct 2026; PLAN-122).
- The book keys in §3 (JP, FAM, SHOP, BF, RS) name **which sample book shows a case**. They are evidence only, and the app never branches on them.

**D1 — Entry model.**
- **Recommend:** the engine accepts any balanced entry between accounts the book has opened, checked by kind-level rules instead of verb shapes. These rules are the ones the reference books are already built to (`docs/accounting/reference-books/shop-sukhwinder-sales-co.tech.md:119`):
  - money in or out touches a money account; a no-money entry does not
  - a transfer joins two of the book's own money or deposit accounts
  - spending from a fund charges the year and moves the same amount out of the fund
  - the gollak is filled only by a count and emptied only into cash or bank
  - no account appears twice in one entry
  - cash, bank and wallet never go below nil; a card never goes past nil
  - advances, loans given, retention, things owned and deposits are never over-settled
- The six verbs become entry-screen shortcuts that produce such entries.
- 00-vision bet 3 is reworded from *"the user can never build a wrong posting"* to *"the everyday entries need no accounting knowledge; every entry is true double entry"*.
- **Why:** the reference books are the target output, and about thirty of their entry kinds fit no verb. Rule 7 of 02 §1.4 would quarantine them as `shape_violation` (02 survey, table B).

**D2 — Kinds of account.**
- **Recommend:** add the kinds the books use. These are R-01…R-26 in §3:
  - thing owned (at cost)
  - loan taken and loan given, as their own accounts beside a person's running account
  - deposit (FD/RD)
  - deposit held, deposit paid, and retention held, each on the person's page
  - advance – {any named person}
  - fund for a purpose
  - own money and drawings as real accounts named after the owner
  - partner capital and current
  - sub-family and joint-family running accounts
  - *Cash short / over*
  - *Not yet sorted*, replacing *Suspense*
  - General Fund and Corpus as real accounts
- No *Opening Balance*, *Adjustments* or *Due to/from* accounts.
- 02 decides the representation (enum, roles). ADR 2026-10-12 §6 (*"no liability class now"*) is superseded, because the books now show the cases it was waiting for.

**D3 — Corrections.**
- **Recommend:** a posted entry is never changed. Today's amend chain (02 §5; `local_ledger.dart:4712`) goes.
- A correction is a new balanced entry dated the day it is made, whose note names the entry it fixes. For an income or expense from a closed year, it goes to a line such as *Rent — earlier year*.
- *Cancel this entry* stays as a correction that mirrors the whole entry.
- **Cost:** a typo fixed the same day becomes a second entry. That is how the rokad does it (`docs/accounting/02-accounts-and-transactions.md:362-399`).

**D4 — Advances and approval.**
- **Recommend:** an advance can go to any named person (driver, house help, sewadar), is created like a person's account, and needs no approval request. That means:
  - S5.1 *request → approver* and the advance approval in S6 are removed
  - the `pending` status goes, since advances were its only user (02 L:41-44)
- Settlement against several heads, return of the unspent part, top-up, the three ways to deal with the remainder, and recovery in a salary entry all come in (R-39, R-40).
- The accounting docs say nothing about approval. GAPS A10 records *"without an approval flow"*. Approval is a control, not accounting, so **this one is genuinely yours.**
- Post-then-review (02 §3) and the structural approvals (02 §7.2) stay for every entry.

**D5 — Year close and partnerships.**
- **Recommend:** the year close is posted by the book: income and expense heads to the result, then the result and Drawings to own money. It is shown, not typed.
  - Per D0: a book with more than one owner's own-money account shares its result through a posted appropriation account.
  - A book with one own-money account (whatever it is called: *Own money*, *Capital – {name}*, *General Fund*) takes the whole result.
  - The stored vector with one *net_result* line goes (`projection.dart:894-915`).
- For a book with several owners:
  - Interest on capital is opening capital plus additions by months, only if agreed, and only out of profit.
  - No agreed ratio means equal shares.
  - A ratio change during the year divides the profit by days.
  - Fixed capital with a current account is an option.
- The mid-year distribution wizard (S14.1, with its quorum ceiling) becomes the appropriation step of the year close. S14 and S14.2 stay as views. This supersedes ADR 2026-09-05e §2 and §8, and ADR 2026-09-14b §6.

**D6 — Between books.**
- **Recommend:**
  - Each book's account is named after the other book; *Due to/from* goes.
  - A running-account pair (family and sub-family) agrees balance for balance.
  - An owner and their business agree entry by entry, and the summary prints *profit kept in the business* or *taken out beyond the profit*.
  - Money a business sends home is the owner's *Income from {business}*, and is Drawings in the business's book.
- The family book holds one running account per sub-family, plus an *Udhaar – {sub-family}* page for money taken to be returned. This supersedes ADR 2026-09-09c §2 (*"sub-family shares are books, never accounts"*); the sub-family books stay as books as well.
- A three-book entry and a year-end settle-or-carry come in.

**D7 — Month close.**
- **Recommend:** a cash difference goes to *Cash short / over*, or to the person minding the cash. This closes the Open of ADR 2026-10-27.
- *Not yet sorted* must be cleared before the **year** closes, not every month (`02-accounts-and-transactions.md:387`).
- Bank: *Not checked this month* is allowed except in the year's last month. That is already ruled and is PLAN-211.

**D8 — Opening a book.**
- **Recommend:** one compound opening entry, with own money (or the partners' capitals) as the balancing figure. There is no *Opening Balance* account.
- The partners' figures must equal assets less liabilities.
- Things owned, goods on the shelf (to *Goods bought for sale*) and sub-family accounts can be opened.
- This supersedes ADR 2026-09-09b and the opening part of ADR 2026-09-13 §4.

**D9 — Reports.**
- **Recommend:** the S8.1 list becomes the reports of 04 §4–§6, every one with the five-line report head (R-100…R-119). For a trust, Receipts & Payments, Income & Expenditure, the Balance Sheet and one statement per fund print together.
- The Day Book has three layouts:
  - **the list**, which does not show the year-close entries
  - **the accountant's layout (Dr / To)**, which opens with the opening entry and ends with the year-close entries
  - **the Cash Book**
- The Day Book also gets a *Journal entries only* filter.
- Print and export get a chooser: All or multi-select, any period, with or without notes.
- Nine of today's twelve S8.1 rows do nothing when tapped (`app/lib/features/reports/screens/s8_1_reports_list_screen.dart`), so this mostly builds new rather than rewrites.

**D10 — Scope.** The recommended cut is in the last column of §3:

| Scope | What it means |
|---|---|
| **Pilot** | What your own joint family needs to run one month (00-vision). |
| **v1** | Everything the five reference books use, because M14 exit is the engine reproducing them exactly. |
| **Later** | The opt-ins no reference book uses (outstanding, prepaid, accrued, depreciation, closing stock), the donation receipt (S4.2, already deferred), and the account-name chips until their PA/HI words exist. |

The non-goals of 00-vision stay unchanged.

**D11 — Old data.**
- **Recommend:** no migration. The app has not launched, so the old entry kinds (amend chains, *Due to/from*, *Profit Distributed*, the year-close vector) are not carried forward. The dev and demo data is wiped, as PLAN-118 already plans.
- **Why:** append-only envelopes in the old shapes would otherwise need a reader for both models forever.

**D12 — Older ADRs that state accounting behaviour.** ADRs rank above the specs, and ADR 2026-10-22 §1 lifted `docs/accounting/` above the specs only. These ADRs therefore stay live until the new ADR supersedes them by name:

| ADR | What it says |
|---|---|
| 2026-09-05e §2, §8 | drawings kept separate; result as one line; losses and ceiling |
| 2026-09-09b | Capital not a separate account |
| 2026-09-09c §2, §4 | sub-family never an account; opening via Partner Current |
| 2026-09-13 §4 | capital through the opening-balance role |
| 2026-09-14b §6 | ratio at the date of the distribution |
| 2026-10-12 §6, §8 | no liability class; advance write-off to Adjustments |

The 02 survey found these, and each needs its line confirmed when the ADR is written.

**D13 — Design and the re-skin freeze.**
- ADR 2026-10-10b §1 pauses new screen slices, and every one of the 77 design-match records reads `deviates`.
- **Recommend:** the engine work (D1–D8) goes first. It doesn't depend on the freeze.
- The new frames are drawn in parallel:
  - the New A/C grid with the new kinds
  - the guided entries
  - the correction
  - the two month-close answers
  - the year-close review
  - the reports of D9
- UI slices start when the freeze lifts. Canvas 17 needs its 6a frame withdrawn, as ADR 2026-09-27 already says.

**D14 — Fixes to the accounting docs themselves.** These were found by the surveys and checked on 2 Nov:
- **(a) Unpaid wages.** `docs/accounting/01-foundations.md:33` rule 2 and its Source line say a wage is entered only when paid, and a wage owed at year end is an opt-in outstanding expense. `04-year-end-and-reports.md:79` holds your later ruling (27 Oct, C10): the wage goes on the worker's page when it falls due, and *Wages outstanding* is not used. **Recommend:** 01 is fixed to agree with 04.
- **(b) The Day Book export.** `reference-books/*.tech.md:9` says the year-close entries are *"none in the Day Book export"*, while 04 §5.3 has the accountant's layout ending with them. **Recommend:** state that the list layout leaves them out and the accountant's layout includes them, as in D9.
- **(c) Udhaar pages.** GAPS A11 says udhaar pages sit under own money. The tech companions type them as an ordinary asset or liability, and 04 §5.8 prints no udhaar line in the position. Not checked against the printed position. **Recommend:** follow 03 §3.2 (`03-entities.md:276`): a page to be returned is a loan given or taken, under *What I have* or *What I owe*. GAPS is fixed.
- **(d) The *Purchases* chip.** `05-account-name-presets.md` offers an Expense chip *Purchases*, but 02 §6.1 says goods for resale go to *Goods bought for sale*. **Recommend:** the chip becomes *Goods bought for sale*.
- **(f) One rule depends on the kind of book.** `04-year-end-and-reports.md:68` (rule 2.2) lets a business, partnership or trust opt into year-end adjustments, but not a household or joint-family book (owner ruling, 21 Oct 2026). Under D0 the app can't tell *"business"* from *"household"* except by the setup purpose. **Recommend:** the opt-in becomes a book setting, off by default and offered only when the setup purpose is not *myself* or *a family*. The signed rule is then kept as a default, not as a type the engine knows. It is Later scope either way (D10).
- **(e) GAPS and COVERAGE.** They still cite the pre-sign-off 02 and *Due to/from* as live conflicts. **Recommend:** refresh them in the same commit as the ADR.

---

## 3. Requirements register

**Column key**
- **Spec now:** what 02/07/13 say today.
- **Design:** whether a canvas frame exists.
- **Built:** the code state on 2 Nov.
- **Scope:** P = pilot, V = v1, L = later.

**Book key** (evidence only: which sample book shows the case; never a type the app branches on, D0)

| Key | Book |
|---|---|
| JP | individual |
| FAM | joint family |
| SHOP | shop |
| BF | partnership |
| RS | trust |

Sources are `docs/accounting/` unless a path says otherwise.

### 3.1 Kinds of account

| id | Requirement | Source | Spec now | Design | Built | Ruling | Scope |
|---|---|---|---|---|---|---|---|
| R-01 | Five standard types with a natural side; a bank may stand Cr (overdraft) | 01 §2.3-2.4 | 7 classes (02 §1.2) | — | `accounts.dart:26-47` | 02 maps classes to the 5 types | P |
| R-02 | Cash and banks are ledger accounts; cash never below nil | 02 §1.1-1.6 | negative cash legal, warned (02 L:353) | yes | built | keep the warning; read it as "an entry is missing" | P |
| R-04/05/06 | Credit card, wallet, KCC: card and KCC are liabilities used as money | 02 §1.7, 1.9, 4.5 | money subtypes `od/cc/loan/wallet` | partly | subtypes built | confirm card and KCC as liability money accounts | P |
| R-07/08 | One running account per person; advances paid or received stand on it | 02 §2.1-2.3 | party class | yes | built | keep | P |
| R-09 | Deposit held or paid, retention held, and a loan with interest each get their own account on the person's page | 02 §2.4, 4.2, 5.11-5.12 | absent | absent | none | add (D2) | V |
| R-10 | Advance – {any named person}, no approval | 02 §3.1 | members only, approval 🔒 | S5/S5.1 contradict | member-bound | D4 | P |
| R-11/12 | Loan taken, loan given | 02 §4.1-4.2 | loan = money subtype | absent | partial | add (D2) | V |
| R-13 | Thing owned, at cost | 02 §5.1-5.8 | ruled, not applied (02 L:33) | absent | none | add (D2) | V |
| R-14 | Deposit (FD/RD) as its own type | 02 §5.9 | absent | absent | none | add | V |
| R-15/16 | Fund for a purpose; General Fund; Corpus as accounts | 03 §5.2, 5.4 | Corpus computed (02 L:31) | absent | none | add | V |
| R-17 | Gollak: filled by a count, emptied into cash or bank | 03 §5.9 | `cashCollection` | yes | built | keep; a count may credit a fund | P |
| R-18/19 | Own money and Drawings as accounts named after the owner; partner capital and current; fixed or fluctuating | 01 §2.5, 03 §2.2 | Opening Balance/Capital + Partner Current | partly | partial | D5, D8 | V |
| R-20 | Money in a business, held at what was put in | 03 §1.9 | absent | absent | none | add | V |
| R-21/22 | Sub-family and joint-family running accounts; Udhaar page | 03 §3.2, 4.1 | "never accounts" (ADR 09-09c §2) | absent | none | D6 | P |
| R-23 | Income and expense heads the books name | 02, 03, 05 | categories | yes | built | keep; names come from the user | P |
| R-24 | Cash short / over | 02 §7.4 | Adjustments | absent | Adjustments | D7 | P |
| R-25 | Not yet sorted, cleared before the year closes | 02 §7.5 | Suspense, cleared monthly | yes (S7) | Suspense | D7 | P |

### 3.2 Kinds of entry

| id | Requirement | Source | Fits a verb today? | Ruling | Scope |
|---|---|---|---|---|---|
| R-30/31 | Money in or out, transfer, credit given or taken (incl. several people in one entry) | 02 §1-2 | yes (verbs 1-5) | shortcuts stay (D1) | P |
| R-32 | Bank cash for private use is Drawings | 02 §1.4 | via ADR 09-13 §4 | keep | P |
| R-34 | One compound opening entry | 01 §4 | no (one per account) | D8 | P |
| R-35/36/37 | Loan instalment (principal + interest); purchase with a loan; principal repaid | 02 §4.3-4.6, §5.7 | no | guided entries | V |
| R-39/40 | Advance settled across several heads, returned, topped up, remainder handled; salary with an advance recovered | 02 §3.2-3.5, 8.4 | no | guided entries | P |
| R-41/42 | Thing owned added to or sold, gain or loss; selling cost as its own expense (*Dalali*) | 02 §5.3, 5.6 | no | guided entries | V |
| R-43 | Write-off to an expense head; bad debt recovered | 02 §2.5-2.6 | to Adjustments (ADR 10-12 §8) | from → to | V |
| R-44/45 | Deposit returned, set off or forfeited; retention held and released | 02 §2.4, 5.13 | no | from → to | V |
| R-46 | Interest added to a deposit; a matured deposit | 02 §5.9-5.10 | no | from → to | V |
| R-47/48/49/50 | Paid by a partner; paid by the joint family; three-book entry; sub-family settled or carried | 03 §2.9, §3.3-3.5, §4.2-4.3 | no | D6 | P |
| R-51/52/53 | Fund spend (one action, two postings); a thing bought from a fund; a donated thing at ₹1 | 03 §5.5-5.8 | no | guided entry | V |
| R-54 | Correction entry | 02 §7 | amend (02 §5) | D3 | P |
| R-56/57/58 | Rebate or kasar; cash difference same day; card sale with commission; bank items | 02 §1.5, 1.8, 7.4 | partly | from → to | P |
| R-59 | Statement line into an entry: split, three lines, transfer, card bill | GAPS A6 | one counter-account | extend import | V |
| R-60 | Year-close entries, posted by the book | 04 §2.1 | no (vector) | D5 | V |
| R-62 | Partner appropriation | 04 §6.4 | `profitDistribution` | D5 | V |
| R-63/64 | Rent charged to several tenants; arhtiya and dairy shapes | 03 §6, GAPS D5-D7 | yes, multi-line | keep | V |
| — | Petty cash, interest on a hand loan, goods taken home, insurance claim (in the docs, in no book) | 02 §3.7, 4.7, 8.6-8.7 | — | no build: ordinary from → to entries | V (free) |

### 3.3 Periods

| id | Requirement | Source | Spec / built now | Ruling | Scope |
|---|---|---|---|---|---|
| R-70/71 | Month end: cash counted; each bank reconciled or *not checked this month*; month locked | 04 §1.1-1.2 | lock built; *not checked* is PLAN-211 | PLAN-211, D7 | P |
| R-73 | Trial balance at any date | 04 §3 | `projection.dart:1016`; no screen | add screen | P |
| R-74/75 | Year close posted; the result account carries a label set at setup (Income & Expenses, Profit & Loss, Income & Expenditure; D0) | 04 §2.1, 6 | vector + one line | D5 | V |
| R-76 | Appropriation when a book has several owners (interest only out of profit, by months; equal if not agreed; ratio change by days) | 03 §2, 04 §6.4 | daily average, "never equal" | D5 | V |
| R-77/78 | Result to the one own-money account, whatever it is called (General Fund, Own money); sub-family running accounts carried | 03 §3.6, 5.11 | no | D5/D6 | V |
| R-79/80 | Carry-forward; a closed year is never reopened | 04 §2.6; 02 §7.6 | reopen is structural (02 L:299) | remove reopen | V |
| R-61, 151-153 | Opt-in outstanding, prepaid, accrued, depreciation, closing stock | 04 §2.2-2.5 | absent | the default notes print in v1 | L |

### 3.4 Between books

| id | Requirement | Source | Built | Ruling | Scope |
|---|---|---|---|---|---|
| R-90 | Account named after the other book, never *Due to/from* | 03 §4.1 | `local_ledger.dart:6800` | D6 | P |
| R-91/92 | Running pair agrees by balance; owner ↔ business agrees by entry, with the *profit kept* line | 03 §4.1, 04 §6.6 | by balance only (`interbook.dart:21-60`) | D6 | P |
| R-93 | Only money that comes home is income | 03 §3.4 | transfer, "not a drawing" (02 L:165) | D6 | P |
| R-95/96 | A fix goes only in the book that missed the item; pair carried forward by default | 03 §4.4-4.5 | — | D6 | P |
| R-97/98 | Family summary exchanged between books; each business's result shown for information | 03 §4.6, 04 §6.6 | S8.3 is a mismatch list | D9 | V |

### 3.5 Reports and prints (all V; the pilot needs R-100, R-104, R-105 list, R-107, R-108, R-109, R-111)

| id | Report | Design | Built |
|---|---|---|---|
| R-100/101/102 | Report head (five lines); last year beside this year; standing notes | absent | S8.2 header only |
| R-103 | Accounts list with openings | — | — |
| R-104/109 | Ledger page and statement for any account and period; the copy sent to a person | C17 1a-1i | S4 + export built |
| R-105/106 | Day Book: list, accountant's layout (Dr / To), Cash Book; *Journal entries only* filter | C17 2a/2b; no Dr/To | Dr/Cr day book only |
| R-107 | Cash Book with a column per bank and the gollak | C17 2b | row disabled |
| R-108 | Trial balance | C17 3a | engine only |
| R-110 | Who owes what, by age bands (≤30 / 31-90 / >90) | C17 3e | advances only |
| R-111 | Position: What I have / What I owe / Own money | C17 3d | S1 card |
| R-112-115 | Year's income and expenses; household *Saving*; P&L; appropriation and partners' table | C17 3b, S14 | partial |
| R-116 | Receipts & Payments, I&E, Balance Sheet and a statement per fund, printed together. Offered to every book; the default set for the trust purpose. | C17 3c (I&E only) | none |
| R-117/118 | Print and export chooser; one-month summary; chosen-period statement | S8.4 options | PDF/CSV/XLSX built |

### 3.6 Words

| id | Requirement | Scope |
|---|---|---|
| R-130-132 | Plain-words columns per kind of account; entry-type words; report words (GAPS A9) | V |
| R-133-135 | ਨਾਮੇ/नामे and ਜਮ੍ਹਾਂ/जमा; *khata* means account only; forbidden: *on khata*, *Due to/from*, *suspense*, *Wages outstanding*, *imprest* outside a petty cashier | P |
| R-136 | Account-name chips by type. EN only today; offered only once PA and HI exist (desk 122) | L |

---

## 4. What changes in each document, once ruled

| Doc | Change |
|---|---|
| **00-vision** | Bet 3 reworded (D1). The pilot line keeps *approvals*, meaning reviews, but advances need none (D4). |
| **02** | Keep §1.1, §1.3, §3, §7.2, §9; §8.2 denominations. Rewrite §1.2 (classes, D2), §1.4 rule 7 (kind rules, D1), §2 (verbs as shortcuts), §4 (D8), §5 (D3), §6 (D6), §7 (D4), §7.1 (D5), §8 (D7), §8.1 (D5), §10 (*Not yet sorted*, split lines). The 🔒 test ids on every rewritten heading are marked `@Skip('superseded by ADR <id>')` in the same commit (CLAUDE.md § Workflow). |
| **07 / 13** | New A/C grid (§6); entry flow with guided entries (§5); advances without a request (§8, F6); inter-book wording (§10); month and year close (§13); reports list (§14); S14.1 becomes the year-close appropriation. |
| **09** | Suite A re-lands against the five reference books (`A-ref-*`); new ids per guided entry and per report. |
| **10-roadmap** | The order of §5. *Interest on hand loans* leaves the Phase 2 parking lot (it is an ordinary entry). |
| **docs/accounting** | D14 fixes; GAPS §G kept as the development order. |
| **ADRs** | One new ADR supersedes those in D12 by name. |

## 5. Order of work after the ruling

1. **ADR + doc edits** (§4). No code.
2. **Engine (`core_ledger`), tests first:** account kinds → kind rules in place of verb shapes → opening entry → correction → year close and appropriation → between-books naming and agreement → reports in the projector. Every step is tested against the reference books (suite A goldens). This is not blocked by the re-skin freeze.
3. **Design frames** for D13, in parallel with step 2.
4. **UI slices**, once the freeze lifts and the frames exist. Pilot rows first.
5. **PLAN-211** (month close), which is already specified and can go any time after step 2's *Cash short / over*.

## 6. Not checked

- The printed reference books and `*.export.md` were not re-read. The surveys used the tech companions, GAPS and COVERAGE.
- Whether each built screen is wired to live data or to a fake (several `*_fake.dart` files exist).
- The 07 and 13 screen text for the *Due to/from*, *Adjustments* and *Suspense* labels.
- The 09 test bodies, beyond the ids on the 02 headings.

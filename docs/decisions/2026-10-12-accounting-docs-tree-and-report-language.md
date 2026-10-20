# ADR 2026-10-12 — Accounting docs tree, plain-language reports, account types, one home for worked examples

**Status:** Accepted for §1–§2, §4–§5 and §9–§14 (§3 superseded by §13; §11 amended and §14 added by the owner on 13 Oct 2026) (owner, 12 Oct 2026). §6–§8 are ruled and take effect with the build
slice that implements each: that slice changes the 🔒 spec lines, the engine/app and the tests that assert the
old behaviour together (CLAUDE.md § Workflow, *Supersession*), so no green test is left against a superseded rule.

An audit of the accounting documentation (12 Oct 2026) inventoried every file with accounting content. It found:
- the 30 Aug originals superseded;
- the owner's core requirement scattered across 00, 02, 07 and 13 and never stated once;
- no single catalogue of account types;
- no account class for a thing owned (truck, land, gold, fixed deposit);
- an add-account grid that cannot create an OD, loan, current account or wallet, although the engine holds all four
  (`app/lib/features/ledger/screens/s3_1_quick_add_sheet.dart:43–50`, `packages/core_ledger/lib/src/accounts.dart:26–74`).

The audit benchmarked the docs against professional bookkeeping practice, with taxation, GST, invoicing,
inventory, payroll and filings excluded as permanent non-goals (`docs/00-vision.md:16`). The owner ruled on the
first six recommendations, on the language of printed reports, and on where worked examples live.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Three superseded files are archived ⟦tests: n/a — file moves; nothing reads them⟧
- `docs/reference/original/Financial_Architecture_Specification.md` and `docs/reference/original/ledger_rules_specification.md`
  (30 Aug originals, superseded by `financial-accounting-standards.md` and `02-ledger-rules.md`) move to `docs/archive/reference/original/`.
- `docs/reference/punjabi_accounting_terms.md` (superseded by 01 §2 and the rulings of ADR 2026-09-02 / 2026-10-08) moves to `docs/archive/reference/`.
- `docs/archive/README.md` indexes them. Nothing in `docs/archive/` is normative.

### 2. Printed reports speak the user's language; technical terms stay behind the scenes 🔒 ⟦tests: n/a — governs the worked examples now; the app's report tests carry it when 07 §14's reports are built⟧
- The worked examples are the **real layout of the reports and statements** a user prints or shares from the app.
- Their words are the plain words a household or a small shopkeeper writes in a diary or ledger book. Examples:
  *Money in / Money out*, *You will get / You will give*, *Spent*, *Received*, *Cash in hand*, *Opening balance*,
  *Total for the year*, *What I have / What I owe*.
- In Punjabi and Hindi, the native words come from 01 §2. They are still subject to native review (01 §4).
- The true side stays as a small bracket after the plain label, e.g. *Money in (Dr)*. This is the option ADR 2026-10-10b §4 already allows.
- The owner chose this over plain words alone, so ADR 2026-10-10b §4 stands unchanged.
- Engine class names, verb names, rule or ADR references, ⚠️ notes and checks never appear on a printed report.
  They live in a technical companion file beside each example, and in the README.

### 3. ~~The use-case set becomes the exemplar and, once ready, the golden set (D1)~~ — superseded by §13 (owner, 13 Oct 2026) ⟦tests: n/a — sequencing; superseded⟧
`docs/reference/worked-examples/usecases/` becomes golden after three things:
1. the owner's rulings on its README ⚠️ SPEC readings S1–S12;
2. a bookkeeper's sign-off;
3. an engine test (`A-ref-8/9`) that replays its `fixtures.json`.

The original five files are then archived by one ADR. That ADR amends CLAUDE.md § *Accounting authority* and
02's header, and re-points `golden_worked_examples_test.dart` and `scripts/check_coverage.dart`. Until then the
original set stays golden at its path.

### 4. The accounting standard v3 keeps its filename (D2) ⟦tests: n/a — file naming⟧
- *Rukka Folio Accounting Standard v3* is written in place at `docs/reference/financial-accounting-standards.md`.
  Two 🔒 lines (CLAUDE.md § *Accounting authority*, 02's header) and seven code comments cite that path.
- v2.0 is archived at `docs/archive/reference/financial-accounting-standards-v2.0.md` when v3 lands.
- `accounting-audit-errata.md` is archived once its live items (F-5 to F-7) are folded into v3.

### 5. The owner's core requirement is written once; any period, any account (D3) 🔒 ⟦tests: n/a — the statement-range tests re-land with the reports slice (07 §14)⟧
The requirement is recorded once as v3's opening section, *What the books must do*:
- Every real entry is recorded, cash or bank. An entry comes in one of two ways, and both are first-class:
  **manual entry**, where the user types any transaction as it happens (a cash spend, a payment, a receipt, money
  given or taken on credit, a transfer, a cash withdrawal); or **bank statement import**, where each line is
  answered with one question: *where did it come from, or where did it go?*
- Each entry is posted to the user's own accounts: bank, cash, card, loan if the user keeps one, people, expense heads, income heads, things owned.
- The app shows a **live position** every day.
- The app gives a **complete or partial ledger statement for any period** (a year, a month, any custom range) **and for any account or set of accounts**.

This holds for every book type. 02 §8.1 *Presentation* gains the 🔒 clause *any date range, any account*; today
it exists only as a code note in ADR 2026-09-09. 00 §*What* gains one sentence pointing to that section.

### 6. One catalogue of account types; an *asset* class; every type creatable (D4) 🔒 ⟦tests: n/a — ruled here; takes effect with its build slice, which allocates the tests and supersedes the 7-tile assertion in `app/test/features/ledger/s3_1_quick_add_sheet_test.dart:126`⟧
- **Catalogue.** v3's *Account types* section holds the one account-type catalogue. Each row gives the standard type (asset, liability,
  capital, income, expense); the traditional type (personal, real, nominal); the engine class, subtype and role;
  the plain label in EN, PA and HI; the natural balance; its place in the position; who creates it; and its
  opening-balance question.
- **Anchors.** The catalogue's normative anchors stay where they are: 02 §1.2 (classes), 07 §6 (the grid), 01 §2 (words).
- **New class.** A new class, **`asset`**, holds a thing owned that is neither money nor a person: a truck, land,
  gold, a fixed deposit, an investment. It is shown at cost under *What I have*. *Amended 13 Oct 2026 (§14): a fixed or recurring deposit or an investment is its own type, **Deposit**, not a thing owned.*
- **No `liability` class now.** Every obligation in scope is owed to a person (a party), to a bank (a money
  subtype: loan, OD, card) or to a partner. It is revisited if a worked example shows a case these cannot hold.
- **The add-account grid (S3.1).** It offers every catalogue row: Bank (savings or current), Cash, OD, Credit card,
  Loan, Wallet, Person or shop, Expense, Income, Thing owned.
  - The loan account is **optional**: banks send their own statements, and a user keeps one only if they want it in the ledger.
  - The *Capital* tile records *capital introduced*, an entry against Opening Balance / Capital. It never creates a new account.
- **Optional, decided later.** Depreciation, accruals or prepaid items, and the split of a loan payment into
  principal and interest are optional behaviours, off by default (audit D-opt-1/2/3).

### 7. Bank reconciliation at month close (D5) 🔒 ⟦tests: n/a — ruled here; takes effect with its build slice⟧
- Before a month is locked, the bank accounts can be matched against the bank statement. This is a view over import state, with no engine change.
- Unmatched lines and book entries the statement does not show are listed.
- It extends 02 §8 step 2. Today step 2 confirms the bank balance only by reference to the bank's app.

### 8. A party who will never pay is written off to the year's result (D6) 🔒 ⟦tests: n/a — ruled here; takes effect with its build slice, which updates 02 §2 verb 6 and the tests asserting today's posting⟧
- A party balance written off posts to a seeded expense head, *Written off*. The loss therefore shows in the year's income and expenses.
- An advance write-off stays on Adjustments (02 §7), unchanged.

### 9. Every worked example lives in one place ⟦tests: n/a — file layout; A-ref-1…7 read the five original files by name and are unaffected⟧
`docs/reference/worked-examples/` is the single home of every worked example:

| Path | What it holds |
|---|---|
| the folder's root | the original golden set, until §3 archives it |
| `usecases/` | the seven use-case books (moved from `docs/reference/worked-examples-usecases/`) |
| `practice/` | the practice-based books: truck operator, committee, landlord |

An index file at the folder root lists all three. The golden test and `check_coverage.dart` name the five
original files one by one, so the subfolders do not affect them.

### 10. Practice-based examples are target output, not rule-derived ⟦tests: n/a — content policy⟧
- The practice-based books are written the way a competent bookkeeper keeps that user's books, from real
  transactions only. They follow the report order the owner set: chart and opening balances, every account's
  ledger, supporting registers, then the closing statements.
- Where the rules cannot produce what they show, the gap is listed for development. The examples are not bent to fit.
- Names are random placeholders until the owner supplies real ones.

### 11. Samples are compact; PDFs are not committed ⟦tests: n/a — reference-document size and repository policy⟧
- Each practice book carries about 40–60 typical entries over the full financial year — enough for the year end
  and the carry-forward — and prints on about 10–12 A4 pages. The generator fails a book over 14 pages.
- The Bank Book is not printed, because it repeats the bank account's own statement. ~~The Cash Book stays.~~ Amended 13 Oct 2026 — see *Amendment* below.
- The one-month statement shows the month's account summary, not the month's entries again.
- Worked-example PDFs in `usecases/` and `practice/` are local outputs of each `build.py` and are git-ignored.
  The original golden set's five PDFs stay tracked until §3 archives that set.

**Amendment (owner, 13 Oct 2026) — notes in the ledger; Day Book and Cash Book are exports; print and export options** ⟦tests: n/a — reference-document layout; the app's print and export tests are allocated with the reports slice (07 §14)⟧
- Every ledger row carries its entry's note, in small type under the other account's name.
- The Day Book and the Cash Book are **not part of the printed book**. Each worked example has them in an export file beside it (`<file>.export.md`), standing for what the app gives when the user downloads them. Nobody prints a Day Book at the year end; they are still always available.
- In the app, the user can print or export the ledger, the Day Book and the Cash Book:
  - for any period;
  - with or without the entries' notes;
  - **All**, or a multi-select of exactly what to include: sections (accounts list, ledgers, Day Book, Cash Book, positions, statements, year end) and, for ledgers, which accounts.
- The 10–12-page size and the 14-page limit apply to the printed book.

### 12. One practice set of ten books ⟦tests: n/a — reference content⟧
- The seven use cases are rebuilt as practice books in `practice/` with the same people, families, businesses
  and trust the owner gave: individual with own business, shop, partnership, joint family with its businesses,
  trust, contractor, farmer. With the truck operator, committee and landlord, that makes one set of ten.
- The seven use the owner's real names. ADR 2026-10-11 §2's permission extends to `practice/` for these names.
  The truck, committee and landlord books keep their placeholders.
- The rule-based `usecases/` set stays in place for now; §13 rules its future.

### 13. The rule-based use-case set is archived, and its golden designation removed ⟦tests: n/a — sequencing; no test reads the use-case set⟧
Owner, 13 Oct 2026:
- Once the ten-book practice set has been reviewed and finalized, `docs/reference/worked-examples/usecases/` moves
  to `docs/archive/reference/worked-examples-usecases/`.
- Its golden designation is removed at the same time: §3 above and ADR 2026-10-11 §5 no longer apply, and
  `A-ref-8/9` are not allocated against it.
- The original five-file golden set at the folder's root, which `A-ref-1…7`, CLAUDE.md § *Accounting authority* and
  02's header name, is unchanged by this ruling.
- Nothing is committed until the owner has reviewed the new set.

### 14. Owner rulings on the practice set (13 Oct 2026) ⟦tests: n/a — reference content; each becomes a test with the build slice that implements it⟧
- **Trust:** *Dairy Donation* is income (donations received for the dairy); *Construction* is an expense head.
- **Joint family:**
  - The joint family's own book is *Randhawa Joint Family*.
  - It keeps **one running account per sub-family**. On the Dr side: household money given, money taken to be returned, and bills the family pays for that household. On the Cr side: what the household puts in — into the family, straight into a family business, or by paying a family-business bill from its own money.
  - It is not a debt. At the year end it is **settled or carried forward**, as the family decides; most families carry it forward. A balance may be settled by the family bearing it, or from the sub-family's share of the family's business income.
  - Money a family business sends home is the family's income; money the family puts into a business stays at what it put in.
- **Security deposit held from a person** (a tenant): **its own account, one per person** — *Deposit held – {person}*, a liability, shown on that person's page beside the khata — never netted against what the person owes until it is set off or returned. A deposit netted inside the khata hides the arrears and makes a tenant who pays on time read *You will give*. The same holds for a security deposit **paid** to a person (the shop's landlord): its own account, *Deposit paid – {person}*, an asset, one per person.
- **Partnership:** interest on capital is **optional**. A partnership adds it only if its partners agreed to, and only out of profit.
- **Account types on reports:** a short plain word, in the accounts list (section 1) only. Examples: *Cash, Bank, Person / shop, Thing owned, Deposit, Loan, Deposit held, Fund, Own money, Drawings, Partner, Income, Expense*.
  - No bracketed standard word, and no type column in the trial balance, so the labels stay short in Punjabi and Hindi.
  - The standard type (Asset · Liability · Capital · Income · Expense) and the traditional class sit in each book's technical companion.
  - **A fixed or recurring deposit or an investment is its own type, *Deposit*** (owner, 13 Oct 2026), separate from ***Thing owned*** (a physical thing: a truck, land, gold, laptops). Both are standard type Asset; whether *Deposit* is a `money` subtype or an `asset` subtype is for its build slice.
  - **The app shows no type word**: 02 §1.2 shows every account as an A/C, and nothing is added to the add-account grid.

## Consequences
- **Docs.**
  - `docs/archive/` is created.
  - Done now: the README, `accounting-audit-errata.md` and `01-glossary.md` are re-pointed, and the use-case set is moved.
  - Pending: v3 of the standard (§4–§6), the 02 §8.1 clause (§5), and the plain-language rework of the use-case reports (§2).
- **Build slices to plan (development resumes against the worked examples):**
  - the `asset` class and the full S3.1 grid (§6);
  - month-close bank reconciliation (§7);
  - the *Written off* head (§8);
  - the reports of 07 §14 matching the examples' layout and language (§2, §5).

## Open ⚠️
- §13: which set, if any, becomes the engine's next golden reference once the practice set's gaps are ruled and
  built. The practice books follow practice rather than the rules, so they cannot be golden until the rules produce them.
- Audit decisions D7–D19 and D-opt-1 to D-opt-3 (partner settlement shape, advance/partner/link shapes in 02 §1.4
  rule 7, statements per book type, corpus donations, advances to non-members, the personal side of takeouts,
  partner remuneration, interest on hand loans, cash short/over in the result, overdraft rule, pairing window, Cash
  Book columns, kameti/retention/pro-rating, depreciation, accruals, loan split). v3 carries each as ⚠️ OWNER DECISION.
- The use-case README's S1–S12 readings (§3).

# Bookkeeper review pack — Rukka Folio accounting

> **Not a spec.** This is the brief for the bookkeeper's review (PLAN-209). The rules are in `01`–`05` and the five reference books. This file only says what to read and which points need an answer. Prepared 26 Oct 2026.

## What we are asking you to do

Rukka Folio is a ledger app for households, joint families, shops, partnerships and trusts in India. It keeps **bookkeeping only**: no tax, GST or TDS.

The accounting rules are written down in five short documents. **Five reference books** show what the app must produce: an individual, a joint family, a shop, a partnership and a trust, each a finished book for FY 2025-26. When you sign off, the app is built to reproduce those books exactly, figure for figure.

Please check that **the rules and the books shown are right**: right entries, right figures, right words, and how a working bookkeeper would keep them. You are not asked to write a rule for every case. In the app, the user opens their own accounts and chooses which one an entry is from and which one it goes to. The documents give the kinds of account and worked entries, not a rule for every situation.

In the app, every line of a bank statement is imported as its own entry. Before anything is posted, the user answers one question for each line (*where did it come from?* or *where did it go?*) by choosing the account, can add a note of their own, and sees every entry in a preview before submitting (07 §11). Entries with no bank line, such as cash paid or goods on credit, are typed by hand as they happen.

Before this pack, a review panel read every document and every book: a chartered accountant, a munim, a specialist in partnerships, joint families and trusts, and an auditor who re-derived every figure. Every finding was put to another panel member to refute. What survived was fixed. The questions below are the points the panel could not settle from the textbooks, because they depend on practice.

## What to read

| Order | File | What it is |
|---|---|---|
| 1 | `docs/accounting/README.md` | One page: what each document covers |
| 2 | `01-foundations.md` | Basis of accounting, double entry, books of account, opening a book |
| 3 | `02-accounts-and-transactions.md` | Cash and bank, persons, advances, loans, things owned, goods, corrections |
| 4 | `03-entities.md` | Sole owner and household, partnership, joint family, trust, landlord, accounts between related books |
| 5 | `04-year-end-and-reports.md` | Year close and every report |
| 6 | `05-account-name-presets.md` | The account names offered as one-tap choices (a draft) |
| 7 | `reference-books/*.pdf` | The five reference books as printed, 9–14 A4 pages per book (the individual is two books, the joint family seven) |
| — | `reference-books/*.tech.md` | For each book: every account with its standard type, and every entry with its formal voucher type |

The PDFs are produced by `reference-books/build.py`, which checks 22,289 things on every run, with 0 problems at this build. Among them: every entry balances, the trial balance agrees, the balance sheet balances, and the carry-forward sums to nil.

## A. The basis and the choices we want you to confirm

**A1. The khata basis.** Every book records money when it moves, and records an amount due to or from a named person when it arises: a credit sale or purchase, rent charged, an advance, a loan. Nothing is recorded for time alone: no accruals, no prepaid items, no depreciation, no closing stock, no provision for bad debts. A business book or a trust may opt into those year-end adjustments; a household or joint family may not. Every report states the basis. We treat this as a disclosed departure from the accrual basis, under AS 1 ¶27.
*Where:* 01 §1.3–§1.5, §1.10.
**Is the khata basis a fair description of how these books are kept, and is it disclosed well enough?** Answer: ______

**A2. A bank account is a personal account.** In the personal / real / nominal classification, a bank account is treated as personal, because the bank is a person who owes the money. The sources are split on this.
*Where:* 01 §2.6–§2.7.
**Agree?** Answer: ______

**A3. Interest on a partner's capital** is a share of profit, posted through the P&L Appropriation Account at the year close and only out of profit. It is not an accrued expense.
*Where:* 03 §2.6; 04 §6.4; partnership book, BF-Y entries.
**Agree?** Answer: ______

**A4. Closing stock is an opt-in.** A shop on the khata basis counts no stock: goods bought for sale are written as spent when bought. A book may enter one closing-stock figure at year end, which goes back into *Goods bought for sale* on the first day of the next year. The shop book continues from last year, which entered no closing-stock figure, so it opens with no stock and its report says that nothing is counted. The partnership buys steel on 31 March (BF-052) and prints no stock note, because the stock note is printed only by a book that sells goods.
*Where:* 01 §1.4, §2.10, §4.6; 02 §6.3; 04 §2.4; shop and partnership books.
**Is "no stock unless the owner opts in" acceptable as the default for a shop? And should a workshop's raw material carry the same "treated as used" note?** Answer: ______

**A5. Business owned by a family or an individual.** In the business book, the owner's *Capital* and *Drawings* accounts are named after the owner: *Capital A/c – Jasvinder Singh*, *Capital A/c – Randhawa Joint Family*. The alternative is to name them after the other *book*.
*Where:* reference books JT, RG, RE; `reference-books/COVERAGE.md` §D.
**Which would you expect?** Answer: ______

**A6. A partner's drawings** are debited straight to that partner's current account. No separate *Drawings* account is kept for a partner (BF-007, BF-016, BF-017, RK-016).
*Where:* 03 §2.4; COVERAGE §D.
**Agree?** Answer: ______

**A7. The trust's langar hall** is built as an expense, not a thing owned. It is paid partly from the Langar Hall Fund (RS-028, RS-035) and partly from general money. The cement and bricks paid for on 10 Sep 2025 (RS-013, RS-019) and the mason's second bill on 16 Mar 2026 (RS-049) came from general money, although the fund still held money on both dates. The book ends with a ₹5,409 deficit on the General Fund, while hall money is left in the fund.
*Where:* 03 §5.5, §5.7; trust book; COVERAGE §D.
**Would a committee pay hall bills from the hall fund first, and turn to general money only once the fund is used up?** Answer: ______

**A8. A cost of selling a thing owned is an expense of its own.** The joint family's real-estate book sells Plot No. 14 for ₹15,50,000 and pays the dealer ₹31,000 two days later. That is posted as `Dr Brokerage A/c · Cr Bank` (RE-015), and the profit on the plot is shown gross at ₹3,50,000. This **departs from AS 10 ¶79**, which measures the gain on net disposal proceeds. The year's result is ₹5,32,500 either way. The owner chose this so the family reads the gain it recognises.
*Where:* 02 §5.6 (its Source line records the departure); joint-family book RE-014, RE-015.
**Acceptable? And would a Punjabi family call this "brokerage", "commission" or "dalali"?** Answer: ______

## B. Citations we did not re-read against the source

These citations were taken from our research notes, not checked against the PDF itself. Please confirm or correct them.

| # | Citation | Where it is used |
|---|---|---|
| B1 | ICAI, AS 10, ¶50 and ¶52 | 04, Sources item 7 |
| B2 | ICAI, Technical Guide on Accounting by Not-for-Profit Organisations, paras 100–111; 2009 edition ¶27, ¶32 | 04, Sources item 9 (trust reports) |
| B3 | ICAI BoS Intermediate, ch. 15 §6 (head office and branch, converse accounts), used by analogy for accounts between related books | 04, Sources item 12 |

Other references to ICAI Board of Studies page numbers were taken from the same notes. A spot check of any you know well would help. Answer: ______

## C. Rules in the documents that rest on practice — ruled by the owner, 27 Oct 2026

The owner accepted the panel's reading of practice on every item below, and the documents and books were changed to match before this review. Please confirm each one, or say where practice differs.

| # | Where | What the documents and books now do |
|---|---|---|
| C1 | 03 §3.2; joint-family RJ-010 ↔ RB-008, RJ-025 ↔ RB-019, RJ-037 ↔ RB-028 | Money a sub-family takes **to be returned** is on its own udhaar page in both books (*Udhaar – Lakhbeer's Family A/c* · *Udhaar – Randhawa Joint Family A/c*), not on the household's running account. Household money is never asked back. |
| C2 | 03 §3.2 | In the sub-family's book, household money from the family stays a running balance in the family's favour, not income; its words are *"Ghar kharch aaya — household money received from the family"*. |
| C3 | 03 §5.5 | No change: the transfer from a fund already goes to a head, *Transferred from the {fund} A/c*, during the year and is closed to Income & Expenditure at the year end. |
| C4 | 03 §6.2 | A tenant who paid ahead still reads *You will give ₹6,000*, the app's words on every person's page, with the note *rent paid ahead*: his advance is lying as jama, to be set against the next months' rent. |
| C5 | 03 §5.9, 04 §5.4; trust book | The gollak is cash (rokad): a count is cash received on the day of counting, shown in the gollak's own column of the Cash Book. The *Gollak* account itself stays (owner rulings of 2–3 Sep 2026). |
| C6 | 03 §1.9 | No change: money taken home from one's own shop is income. |
| C7 | 01 §3.3–§3.4, 04 §5.3–§5.4; every book | The list of every entry is the **Day Book (rojnamcha)**; **rokad** means cash. |
| C8 | 04 §6.1 | Only an outright gift such as shagun is income. Neondra or vartan, to be returned in kind, is written on the giver's own page. |
| C9 | 04 §5.7 | No change: a part payment settles the oldest amount first unless the payer names a bill. |
| C10 | 04 §2.2 | Wages earned and not yet paid stand on the worker's own page. *Wages outstanding* is not used. |
| C11 | 02 §7.4, 04 §1.1; ADR 2026-10-27 §1 | A cash shortage that the person minding the galla will make good goes on that person's page, to be recovered. Only a small or unexplained difference goes to *Cash short / over*. |
| C12 | 04 §1.1–§1.2; ADR 2026-10-27 §2 | A bank account is checked with its statement when the statement or passbook is in hand. A household or farmer may mark it *not checked this month*; a shop usually checks monthly. At the year end, every bank account is checked. |
| C13 | 04 §5.6; statements in the shop, partnership and individual books | A statement sent to a customer names its columns *Naam (Dr)* / *Jama (Cr)* and ends *Balance due from you* or *Balance due to you*. |
| C14 | 05 | *Repairs* (marammat) is its own chip, beside *Maintenance* (the society's monthly charge). |
| C15 | 05 | *Commission* is now *Commission Received*. |

Where practice differs (by number): ______

## D. Entries in the reference books — ruled by the owner, 27 Oct 2026

The owner ruled that these are entries to be put right where needed, not rules: which head a user picks and what note they write are the user's choice. Only the kind of entry is judged. The entries below were changed before this review. Please say if any is still not how a book would be kept.

| # | Book · entries | What the book now does |
|---|---|---|
| D1 | Shop S-057; partnership BF-051 | The disputed ₹2,300 is a rebate (kasar) allowed on the bill, to *Rebate & Kasar Allowed*. The ₹1,000 of lost labour slips is wages, noted *slip lost*. *Written off* is kept for money that will not come. |
| D2 | Individual JP-033, JP-036, JP-037, JP-041, JP-042 | The driver's ₹1,800 of trip money is cut from his December pay, paid on 10 Jan 2026 (₹9,000 less ₹1,800 = ₹7,200 in cash). |
| D3 | Individual JP-036, JP-053 | No rule. The trip bills' tolls are ones the driver paid in cash; the FASTag tolls are separate. Nothing is counted twice. |
| D4 | Individual JP-016 | The ₹38,000 is the premium of an LIC term policy, a yearly expense. |
| D5 | Individual JP-018, JP-039 | The cumulative FD pays deposit and interest together at maturity (₹1,00,000 + ₹7,186). The other deposit is credited ₹7,200 of yearly interest. |
| D7 | Joint family RJ-037 ↔ RB-028 | Lakhbeer pays back the last ₹30,000 of his udhaar by bank on 24 Mar 2026. Nothing is shared out to one brother only. |
| D14 | Partnership BF-040, BF-048, BF-050 | Retention is released for the whole job: half (₹24,500 of ₹49,000) when the staircases are handed over after the final bill, the rest held for the defect period. |
| D13 | Partnership, partners' table and full position on 31 Mar 2026 | Harjeet Singh's current account ends ₹3,940 Dr after the year close. Each partner's capital account and current account now stand under own money at their own balances, and Harjeet's ₹3,940 Dr is shown under *What I have* as money he owes the firm, not netted against his capital (owner, 27 Oct 2026; 04 §5.8, §6.5; NCERT Class 12 Part I ch. 1 §1.4(a)). |
| — | D6, D8, D9, D10, D11, D12 | Kept as they are. These are the family's or the user's own choice of account or way (D6, D8, D9, D10, D12), or follow the owner's ruling that money a business sends home is the family's income (D11). |

Where practice differs (by number): ______

## Already decided — for information, not asked

- **The books are compact by design** (owner, 26 Oct 2026). To keep each book to about 50 entries, a recurring item is written once for a quarter or a half-year: a quarter's wages (JP-010, JT-011, BF-012), a half-year's groceries or milk on credit (JP-020, RJ-016), a quarter's counter sales (S-009), electricity for several months (BF-024), bank charges and interest once a year (S-055, RS-053). The note on each says what period it covers. The books show each kind of entry and every report done correctly; they do not show how often an entry recurs, and a month report from them will show months with no wages or groceries. Please judge each entry as a kind of entry, not as a record of how often it happens.
- Corrected before this review: the trust's bank is a savings account, since a current account earns no interest (RS-053); the gollak count of 30 Sep is deposited on 3 Oct, not on 2 Oct, a bank holiday (RS-027). The build now refuses a cash deposit on a day the branch is shut.
- Ruled by the owner: wages are entered in the month paid; the year runs April–March; the head for a debt that will not come back is *Written off*; a household's gollak is its own cash; a dealer's cost of selling is its own expense (A8).
- Treated as the user's choice of accounts, not rules: an interest-bearing loan from a relative on its own page; an old asset opened at cost or at today's value; members' subscription pages in a committee; a bad debt recovered; the arhtiya's running account; trip money spent without bills; EMI split; kameti / BC; cheques in hand; KCC renewal; cumulative FD interest; a supplier advance in the who-owes list. The documents show one worked way; the user may open other accounts.

## Sign-off

When every answer above is in, the owner rules on each one and the documents and books are corrected. Then:

**I have read `docs/accounting/01`–`05` and the five reference books as corrected, and they are correct bookkeeping for the books they describe.**

Name: ______ · Qualification: ______ · Date: ______

## Where each question came from

The panel's reports, with each question in full, are in `.claude/lane-reports/`:
- A1–A7: PLAN-209 and `reference-books/COVERAGE.md` §D.
- A8: `acct-docs-recheck-0206-acct-munim.json` (MU-Q2).
- The compact-entries ruling under *Already decided*: individual MU-Q1, Q2; joint family MU-Q6, Q8; partnership MU-Q2, Q5; shop MU-Q2, Q4; trust MU-Q3.
- C1–C6: `acct-docs-03-acct-munim.json` Q1–Q6 (C1 also joint family MU-Q1).
- C7–C12: `acct-docs-04-acct-munim.json` Q1–Q6.
- C13: `acct-book-shop-acct-munim.json` Q3.
- C14, C15: `acct-docs-05-acct-munim.json` Q2, Q3.
- D1: shop MU-Q1, partnership MU-Q3. D2–D5: individual MU-Q3–Q6. D6–D11: joint family MU-Q2, Q3, Q4, Q5, Q7, Q9. D12–D14: partnership MU-Q1, Q4, Q6. Trust MU-Q2 and Q4 were corrected (see *Already decided*).
- Entry numbers are checked against the build of 26 Oct 2026 (content hash `bf64cbb2…`). Joint family MU-Q8's RA-031 is RA-030 since the house-help entries were merged.

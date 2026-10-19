# Research outline — Accounting Standard and Ledger Rules

**Status:** Draft for owner approval, 15 Oct 2026. Nothing is researched or written until this outline is approved.

## Purpose

Two documents describe **real accounting**, independent of the app:

| Document | What it says | Path |
|---|---|---|
| **Accounting Standard** | *What* the books must record and show: when a transaction is recognised, at what amount, under which head, and how each entity type presents its year | `docs/reference/financial-accounting-standards.md` (rewritten in place) |
| **Ledger Rules** | *How* a ledger is kept: double entry, books of account, posting, balancing, trial balance, correcting errors, closing and carry-forward | `docs/reference/ledger-rules.md` (new) |

The ten practice books are then checked and fixed against these two. After a bookkeeper's review, the three together are the source of truth, and the app's requirements are written from them.

`docs/02-ledger-rules.md` (the engine contract) is not touched in this phase.

## Rules for the research and the documents

1. **Every rule cites its source.** That means the ICAI pronouncement and paragraph, or the textbook and chapter. A rule with no source is not written.
2. **Nothing from the app.** The documents never mention ADRs, engine classes, build status, 🔒 or test ids.
3. **Where the sources disagree, or are silent,** the document says so. The question goes on one list for the owner, *Not settled by the sources*, and is ruled once, together with the rest of that list.
4. **Every rule has a Dr/Cr example in rupees.** Each example is written once in professional terms and once in the plain words of a diary or ledger book.
5. **Out of scope** (00-vision): tax, GST, TDS, invoicing, payroll and inventory valuation. Topic 10 asks only how a book that does not count stock states its result.
6. **No statute.** The Partnership, Trusts and Societies Acts, and Hindu law on the joint family, govern legal rights, registration and tax, not how books are kept. Where an Act's rule matters to the books (for example, the partnership defaults when there is no deed), the textbooks already teach it, and the documents cite the textbook.
7. **No compliance claim.** The documents describe bookkeeping practice. They do not claim that a book kept this way complies with the Accounting Standards or with any statutory format.

## Source hierarchy

When sources conflict, the higher one wins:

1. **ICAI pronouncements.** Framework for the Preparation and Presentation of Financial Statements · AS 1, 4, 5, 9, 10, 13, 29 · Guidance Note on Financial Statements of Non-Corporate Entities · Technical Guide on Accounting for Not-for-Profit Organisations.
2. **Standard Indian textbooks.** NCERT Accountancy, Class 11 and 12 (free, and the national baseline) · T.S. Grewal · D.K. Goel.
3. **Traditional practice.** The Mahajani bahi-khata system: rokad (cash) bahi, khata (ledger) bahi, nakal bahi, and the paana/jama conventions.

Before any audit claim is relied on, it is checked against its source. This includes the ChatGPT audit of 15 Oct 2026, for example its §9.3 claim about the ICAI announcement of 31 March 2026.

## Topics

The *Settles* column traces each topic to what it closes: `practice/GAPS.md` items, the ChatGPT audit's findings (F-) and the open decisions of standard v3 (D-). It is for tracing only and never appears in the finished documents.

### A. Foundations

| # | Topic | Questions | Goes in | Settles |
|---|---|---|---|---|
| 1 | **Basis of accounting** | Cash vs mercantile (accrual) vs a mixed basis. What each entity type uses in practice: household, sole trader, partnership, joint family, trust and committee. What a book must state about its basis. The fundamental assumptions (going concern, consistency, accrual) and the considerations in choosing a policy (prudence, substance over form, materiality). | Standard | F-03, GAPS F2 |
| 2 | **Double entry and kinds of account** | Personal, real and nominal accounts, with their golden rules. The modern five types: asset, liability, capital, income, expense. How the two classifications map onto each other. The natural balance of each type. | Ledger Rules | catalogue (v3 §1.7) |
| 3 | **Books of account** | Journal, the subsidiary books (cash book, day book / rokad), and the ledger. What a small entity actually keeps. How the bahi-khata maps onto the journal and ledger. | Ledger Rules | GAPS A8 |
| 4 | **Opening a set of books** | The opening statement of affairs. Capital as the balancing figure. Opening balances of persons, banks and assets. | Both | GAPS B4 |

### B. Everyday transactions

| # | Topic | Questions | Goes in | Settles |
|---|---|---|---|---|
| 5 | **Cash and bank** | Cash book columns. Contra entries. Bank reconciliation statement. Credit card and wallet as accounts. Cash withdrawals and deposits. | Both | GAPS A6, C1; D17, D18 |
| 6 | **Persons: debtors and creditors** | One running account per person vs separate receivable and payable. Advances paid to suppliers and received from customers. Retention money. Bad debts, bad debts recovered, provision for doubtful debts. | Both | F-05, F-10; GAPS D2, D3, D7; D19 |
| 7 | **Advances and imprest** | The imprest system. Staff and labour advances. Advances to a person who is not an employee or a member. Settling against bills, returning the unspent part, writing off what has no bills. | Both | GAPS A10; F-09; D12 |
| 8 | **Loans** | Loan accounts. An EMI split into principal and interest from the lender's statement. Overdraft. KCC. Interest on loans from relatives or friends. | Both | GAPS A2, D4; F-06; D15, D-opt-3 |
| 9 | **Assets and deposits** | Capital vs revenue expenditure. Assets at cost (AS 10). Depreciation: whether a small or cash-basis book may omit it, and what it must then say. Sale or disposal. Construction in progress vs expense. Fixed and recurring deposits and investments. Security deposits held and paid. | Standard | GAPS A1, A3, E2; F-04; D-opt-1 |
| 10 | **Goods bought for sale** | Without a stock count: what the result means, and what the book must say. With a closing-stock figure: the one entry practice uses. | Standard | GAPS D1 |
| 11 | **Errors and corrections** | Rectification of errors: one-sided vs two-sided errors, before vs after the trial balance, the suspense account. Cash short or over. A correcting entry vs replacing the entry. The errors a balanced trial balance does not show: omission, commission, principle, compensating. | Ledger Rules | GAPS A12; D16a |
| 12 | **Entries that move no money** | Journal proper: write-offs, transfers between heads, settlements, adjustments. | Ledger Rules | GAPS A5 |

### C. Owners and entities

| # | Topic | Questions | Goes in | Settles |
|---|---|---|---|---|
| 13 | **Sole proprietor and household** | Capital and drawings, including drawings in kind. The owner's personal book vs the business's book: how each records the other. What a household's own account shows. Why personal money is not "profit". | Standard | GAPS C2, C3; D13; A11(2) |
| 14 | **Partnership** | The textbook defaults when there is no deed. Fixed vs fluctuating capital. P&L Appropriation Account and how it is posted. Interest on capital and on drawings. Partner's salary and commission. Settlements between partners. A change of ratio mid-year. An outside partner. | Standard | GAPS B1–B5; F-07; D7, D14, D19 |
| 15 | **Joint family** | The karta (who manages the family) and the sub-families. How a joint family keeps its own account and its sub-families' accounts. Businesses owned by the family. Money a family business sends home: income or return of capital. Settling or carrying forward at year end. | Standard | GAPS A11(1)(3), C4 |
| 16 | **Accounts between related entities** | Branch and head-office accounts. Current accounts between related entities and their reconciliation. One entity paying on another's behalf, including payments that involve three parties. | Ledger Rules | GAPS A11 |
| 17 | **Trusts, committees, not-for-profits** | Receipts & Payments, Income & Expenditure, Balance Sheet. General fund vs corpus. Earmarked and restricted funds, and the investments made from them. Spending from a fund on an asset vs on an expense. Subscriptions. Donations in kind. The gollak (donation box). | Standard | GAPS A4, E1–E6; F-08; D11 |
| 18 | **Landlord** | Rent charged vs rent received. Advance rent. Tenants' security deposits. Repairs vs improvements. | Standard | GAPS D6, D7 |

### D. Period end and reports

| # | Topic | Questions | Goes in | Settles |
|---|---|---|---|---|
| 19 | **Year end** | Trial balance. Year-end adjustments: prepaid, outstanding, accrued. Closing entries vs a computed result. Final accounts for each entity type. Balances carried forward and nominal accounts restarting at zero. Whether a trial balance with opening, period and closing columns (a working trial balance) is expected, or only closing balances. | Both | GAPS F2, F3; D9, D10 |
| 20 | **Reports** | What each entity type is expected to produce. Ledger statement for any period. Day book. Positions. Ageing of persons. What every report must state at its head: the book, the date or range, the basis, whether it is live or closed, and when it was made. | Standard | GAPS A8; D9, D10 |

## How the work proceeds after approval

1. **Research, one topic at a time.** Each topic gets one working note, `docs/reference/research/NN-<topic>.md`, holding its findings and their citations. The notes are kept, so every rule can be traced back to its source.
2. **Not settled by the sources.** Questions the sources leave open are collected in one list, `research/OPEN.md`, for one owner ruling at the end, not topic by topic. Each question is one row: *Topic · Rule chosen · Source · Book affected · Status · Ruled by and date*.
3. **Write the two documents** from the notes.
4. **Re-check the ten practice books** against them, and rewrite `GAPS.md` as *the book does X — the standard says Y (source)*.
5. **Independent review** by a bookkeeper or CA.

## For the owner to approve

- Are the 20 topics complete? Is anything to add or drop? Is the landlord topic worth keeping on its own?
- Is the source hierarchy right? In particular, is the bahi-khata tradition correctly placed below the textbooks?
- Are the file paths right: the standard rewritten in place, and the ledger rules as a new file?
- Does the scope exclusion stand as written?

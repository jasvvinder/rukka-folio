# Accounting — how the books are kept

**Status:** Draft, 20 Oct 2026 — for a bookkeeper's review. This folder is the behavioural reference for the ledger (ADR 2026-10-20). Once a bookkeeper has signed it off, the app's requirements are written from it, once.

## Who keeps these books

Indian households, joint families, their small businesses (a shop, a contractor, a farm, a truck, a landlord's property, a partnership) and trusts or committees. Today they keep a rokad (day book), a khata for every person they deal with, and a ledger, on paper. They are not accountants. Their books are kept for themselves: to know what they have, what they owe and who owes them, and how the year went. Tax, GST, TDS, invoicing, inventory and payroll are not part of these books.

## What the books must give them

- **Every entry recorded**, whether typed by hand as it happens or taken from a bank statement.
- **A live position every day**: *What I have*, *What I owe*, *Own money*.
- **A statement for any account and any period**, every line with its note.
- **Who owes what, and since when.**
- **Each kind of book's year result**: *Saving* for a household; profit or loss for a business; the partners' shares for a partnership; surplus or deficit for a trust.
- **A clean carry-forward** into the next year.

All of this is in plain household words, with the true Dr/Cr side in brackets where it helps.

## How they are kept: the khata basis

Every book uses one basis (*01 — Accounting foundations*, Basis of accounting):
- a receipt or payment is recorded when the money moves;
- an amount due to or from a named person is recorded when it arises: a credit sale, rent charged to a tenant, an advance, a loan;
- nothing is recorded for the passage of time alone.

Depreciation, accrued and prepaid items, and closing stock are an optional year-end step. Every report says which way its book was kept. These books describe sound bookkeeping practice. They make no claim to comply with the Accounting Standards or any statutory format.

## Reading order

| File | What it settles |
|---|---|
| [`01-foundations.md`](01-foundations.md) | Basis of accounting, double entry and the kinds of account, the books kept, opening a set of books |
| [`02-accounts-and-transactions.md`](02-accounts-and-transactions.md) | The rule for each kind of account and transaction: cash and bank, persons, advances, loans, things owned and deposits, goods bought for sale, corrections, entries that move no money |
| [`03-entities.md`](03-entities.md) | How each kind of owner keeps its book: household and sole proprietor, partnership, joint family, related books, trusts and committees, landlord |
| [`04-year-end-and-reports.md`](04-year-end-and-reports.md) | Month end, year end and carry-forward; what every report states and contains |
| [`05-account-name-presets.md`](05-account-name-presets.md) | Common account names, one list grouped by account type, offered as one-tap suggestions when an account is named |
| [`reference-books/`](reference-books/) | Five finished ledger books for FY 2025-26, made to these rules. They are the output the app must produce: individual, joint family, shop, partnership, trust. `COVERAGE.md` shows where each rule appears; `GAPS.md` lists what the app still needs to produce them. |

## Where the rules come from

Every rule cites its source. In order of authority:
1. ICAI pronouncements and the ICAI Technical Guide for not-for-profits;
2. the standard Indian textbooks (NCERT Accountancy, ICAI study material);
3. bahi-khata practice.

Where the sources were silent or split, a ruling of 20 Oct 2026 decided the question, made against the facts above. Those rulings are listed, each with its reason, in `docs/archive/reference/accounting-research/OPEN.md`. That file and the twenty research notes behind it are archived and kept for tracing only (ADR 2026-10-20 §5).

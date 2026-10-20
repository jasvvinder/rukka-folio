# Worked examples — index

Every worked example of Rukka Folio lives in this folder (ADR 2026-10-12 §9). Each one is a finished ledger book: the report a user prints or shares from the app. Development aims the app at these outputs.

| Set | Where | What it is | Status |
|---|---|---|---|
| Original golden set | this folder's root: `README.md`, `individual-rahul-sharma.md`, `business-sharma-textile.md`, `trust-singh-sabha-gurudwara.md`, `joint-family-sharma.md`, `joint-business-partnership.md` | 5 entity types, 8 books, 185 vouchers; read by the engine's golden test (A-ref-1…7) | Golden (engine test A-ref-1…7); its known defects are listed in `usecases/README.md` §7 |
| Use cases | `usecases/` | 7 use cases, 14 books, FY 2025-26: individual + own business, shop, partnership, joint family with its businesses, trust, contractor, farmer. Built from the financial architecture standard and the ledger rules | Rule-based reference; to be archived (no golden designation) once the practice set is finalized (ADR 2026-10-12 §13) |
| Practice | `practice/` | 10 books, FY 2025-26: the seven use cases rebuilt from practice, plus truck operator, committee, landlord. Built from real bookkeeping practice, not from our rules; `practice/GAPS.md` lists what the app still needs to produce them | Target output, being finalized; the seven use the owner's real names, the other three placeholders |

In `usecases/` and `practice/`, each book has:
- a printed report (`.md`, `.html`, `.pdf`) in plain words, with the true side in brackets, e.g. *Money in (Dr)*;
- a technical companion (`.tech.md`) for development and the bookkeeper;
- in `practice/`, the Day Book and Cash Book as an export beside it (`.export.md`, `.export.html`) — ADR 2026-10-12 §11, amended 13 Oct 2026.

Each folder regenerates with `python3 -I build.py`, and `check_md.py` re-checks every printed figure.

Every practice book reads in one order:
1. accounts and opening balances;
2. every account's ledger, each row with its note;
3. what the app shows — positions, one month, one account for a chosen period, who owes what, and the bank-statement table where the user works from one;
4. closing balances (trial balance), the year's income and expenses, the position, and the carry-forward into the next year.

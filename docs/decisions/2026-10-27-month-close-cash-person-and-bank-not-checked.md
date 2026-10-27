# ADR 2026-10-27 — Month close: a cash shortage may go to the person minding the cash; a bank account may be *not checked this month*

**Status:** Accepted (owner, 27 Oct 2026). Rules on the bookkeeper review pack, section C, items C11 and C12 (`docs/accounting/bookkeeper-review-pack.md`): the owner accepted the accounting panel's reading of practice for every item of section C, and confirmed this ADR for the two that change the 🔒 month-close wizard of 02 §8.

Practice, as the panel found it: a shortage at the counter is often put on the khata of the person minding the galla, to be recovered, and only a small or unexplained difference goes to a loss head (C11); a household or a farmer with a passbook checks the bank only when the passbook is printed, while a shop checks monthly (C12). The wizard of 02 §8 posted every cash difference to *Adjustments* and asked for every bank balance every month. The accounting docs are amended in the same change (`docs/accounting/02` §7.4, `04` §1.1–§1.2).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. A cash shortage may go on the page of the person minding the cash 🔒 ⟦tests: F1-1027-1, F1-1027-2⟧
- When the count differs from the book (02 §8 step 1, §8.2 `cash`), the guided entry asks where the difference goes: **the person minding this cash** — a person account the closer picks, to be recovered — or the book's difference account (today *Adjustments*, 02 §8.2).
- A shortage put on a person posts `Dr {person} · Cr Cash` — the ordinary `money_out` shape of 02 §2; no new verb, no engine change. An excess goes to the difference account only.
- Nothing is pre-selected (07 §5 🔒): the closer chooses one of the two every time.
- A `cash_collection` account (gollak) is unchanged: a count there records income, it never verifies (02 §8.2).

### 2. A bank account may be marked *not checked this month*; never in the year's last month 🔒 ⟦tests: F1-1027-3, F1-1027-4, A-1027-1⟧
- Step 2 (*Confirm each bank balance*, 02 §8) offers a third answer per bank account: **Not checked this month** (passbook not printed, statement not in hand), beside *Matches ✓* and *Doesn't match ▸ reconcile*. It is open to every kind of book.
- It warns and never blocks (07 §8, *Blocking vs warning*). The close envelope lists the account under `banks_not_checked` and records no declared balance for it; readers that do not know the field keep it (03 §3.3.4, unknown-field round-trip). The balance-vector hash is unchanged by it.
- **The year's last month is the exception:** *Not checked this month* is not offered, and the month does not lock until every bank account is *Matches ✓* or reconciled — a book is always checked with the bank at the year end (`docs/accounting/04` §1.2).

## Consequences
- Code: `app/lib/features/close/` (S10 step 1 destination choice, step 2 third answer and the last-month rule; `CloseProgress` carries the not-checked set; the close envelope writes `banks_not_checked`), `app/lib/features/cash_count/` (the person choice on a shortage), ARB keys EN/PA/HI. No engine change: a shortage to a person is an existing verb. No green test flips: F1-07-130 still finds *Matches* and *Doesn't match* per account.
- Docs: 02 §8 steps 1–2 and §8.2 (`cash` row), 07 §8 (wizard line and *Blocking vs warning*) carry a cross-reference line. `docs/accounting/02` §7.4 and `04` §1.1–§1.2 amended in the same change.
- Milestone: M13 (the close wizard), PLAN item added.

## Open ⚠️
- **The difference account's name.** 02 §8 and §8.2 post a cash difference to *Adjustments* (`equity_system`); `docs/accounting/02` §7.4 and `04` §1.1 post it to *Cash short / over* (an expense when short, income when over). The disagreement predates this ADR and is not ruled here: from the bookkeeper's sign-off the accounting docs rank above 02 on which account an entry uses (ADR 2026-10-22 §1), and 02 is then fixed to agree.

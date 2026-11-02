# ADR 2026-11-01 — Bookkeeper sign-off of `docs/accounting/` and the five reference books (PLAN-209)

**Status:** Accepted (owner, 1 Nov 2026). Records the answers to the bookkeeper review pack (`docs/accounting/bookkeeper-review-pack.md`) and the sign-off that ADR 2026-10-22 §1 waits on.

**Who signed.** The owner, Jasvinder Singh, answered the pack and signed it **as the bookkeeper**, on 28 Oct 2026. No independent bookkeeper or chartered accountant signed. The owner chose this on 1 Nov 2026, when asked whether to sign as bookkeeper or keep PLAN-209 open for a practising one. This record says so plainly, so that nobody later reads the sign-off as an outside review.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The sign-off is given; ADR 2026-10-22 §1 takes effect 🔒 ⟦tests: n/a — precedence rule, not behaviour⟧
- From 1 Nov 2026, on accounting behaviour, `docs/accounting/` and its reference books rank above the numbered specs. That covers which accounts an entry debits and credits, balances, the year close and carry-forward, and what each report shows and states. Where 02 disagrees, 02 is fixed to agree; 02 keeps the representation.
- The reference books, at the build recorded in the pack, become the golden fixtures of suite A (09). `A-ref-*` re-land against them at M14.

### 2. Answers to the pack ⟦tests: n/a — record of answers; the books carry them⟧
- **A1–A6:** agreed as written.
- **A7 (trust):** a committee spends a fund first. A bill for the fund's purpose paid from general money while the fund still held money is met from the fund at the year end. The trust book adds `RS-057`: Dr *Langar Hall Fund* ₹61,000 · Cr *Transferred from the Langar Hall Fund* ₹61,000. The fund closes at nil, the year's result is a ₹55,591 surplus (it was a ₹5,409 deficit), and the General Fund ends at ₹5,12,591. The deposit made from the hall donations is renamed *SBI Fixed Deposit A/c*, because it no longer holds fund money at the year end. `docs/accounting/03` §5.5 states the practice.
- **A8 (joint family, real estate):** a cost of selling stays an expense of its own (the departure from AS 10 ¶79 is accepted). In Punjabi practice the word is *dalali*, so the account is *Dalali A/c*, used the same way throughout the book (owner, 1 Nov 2026: one word per book). `docs/accounting/02` §5.6 follows.
- **B1–B3 and the BoS page references:** checked against the sources and found correct (owner, 1 Nov 2026). The "as cited in the research notes" markers are removed from 04's Sources list.
- **C1–C15, D1–D14:** no item differs from practice.

## Consequences
- Docs: `docs/accounting/02` §5.6, `03` §5.5 and `04` Sources (items 7, 9 and 12) amended. Reference books rebuilt through `build.py`, with a new entry kind `Journal (from a fund)`, printed *Moved from a fund*; `check_md.py` knows it. `COVERAGE.md` (O-17-1) and `GAPS.md` (A4, E2, E3) cite `RS-057`.
- Precedence: CLAUDE.md § Precedence item 3 already says what happens after the sign-off; it applies from today.
- Milestone: PLAN-209 closed. M14 exit no longer waits on the bookkeeper; it waits on `A-ref-*` re-landing against the reference books.

## Open ⚠️
- **02 must now be fixed to agree with `docs/accounting/` wherever they differ (ADR 2026-10-22 §1).** One difference is already known: 02 §8 and §8.2 post a cash difference to *Adjustments*, while `docs/accounting/02` §7.4 and `04` §1.1 post it to *Cash short / over* (ADR 2026-10-27, Open). No full comparison of 02 against `docs/accounting/` has been run yet; it is part of PLAN-210, the app-requirements pass.

# ADR 2026-10-22 — Rank of `docs/accounting/`, and what the accounting docs cover

**Status:** Accepted (owner, 22 Oct 2026). Closes the Open item *Rank* of ADR 2026-10-20 and desk items 207 and 208. Amends CLAUDE.md § Precedence item 3 and § Accounting authority.

ADR 2026-10-20 left open whether `docs/accounting/` should rank above 02 once a bookkeeper has signed it off (desk 208). The owner ruled "do as recommended" on 22 Oct 2026. On the same day, after the panel on 02 reported six "gaps" (cases no rule covers), the owner said the docs must not grow a ruling for every case: a ledger only moves amounts from one account to another, between accounts of a type the user has opened, and the user decides how to write it. The owner also confirmed the khata / account basis for every book and accepted all the rulings of 20 Oct 2026 (desk 207).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. After the bookkeeper's sign-off, `docs/accounting/` ranks above 02 on accounting behaviour 🔒 ⟦tests: n/a — precedence rule, not behaviour⟧
- **Until the sign-off (PLAN-209):** nothing changes. The folder ranks at CLAUDE.md § Precedence 3, and a conflict with 02 is a stop-and-ask.
- **From the sign-off:** on accounting behaviour — which accounts an entry debits and credits, how balances, the year close and the carry-forward come out, and what each report shows and states — `docs/accounting/` and its reference books rank above the numbered specs. Where 02 disagrees, 02 is fixed to agree in the same commit; no stop-and-ask is needed for that conflict.
- **02 keeps** how the ledger is represented: the class model, the verbs, the invariants (append-only, integer paise, balanced entries), storage, sync and everything that is not accounting behaviour.
- ADRs still rank first. An ADR that changes accounting behaviour amends `docs/accounting/` in the same commit, so the two never disagree.
- **Why:** the reference books are the output the app must produce (golden fixtures of suite A, ADR 2026-10-20 §2), and the app requirements are written from the folder once (owner, 15 Oct 2026). A spec ranking above its own target output would make the target negotiable.

### 2. The accounting docs give the kinds of account and worked entries, not a rule for every case 🔒 ⟦tests: n/a — scope of documentation, not behaviour⟧
- Every entry moves an amount from one account to another, between accounts the user has opened, each of a kind in 02's table. The user decides which accounts an entry uses.
- The docs set the kinds of account, the rules of double entry, the year close and the reports, and show common transactions as worked entries. A case they do not show is entered the same way and needs no rule of its own.
- The accounting panel (`/acct-review`) does not report a case the docs do not show, as a finding or as a question for the bookkeeper. It reports what is wrong in what the docs and books do show: a wrong figure or side, a contradiction, plain words that disagree with the Dr/Cr, a citation that does not support its rule, a report statement missing.
- The six "gaps" of the 02 panel run (settlement discount, an unidentified bank line at the year end, retention the book holds back, fund-first spending, a tenant's deposit kept for damage, gifts in kind for sale) and the practice questions of the 01 and 02 runs are therefore closed with no rule.

### 3. Every book is kept on the khata / account basis, and all the rulings of 20 Oct 2026 stand 🔒 ⟦tests: n/a — confirms ADR 2026-10-20 rulings, no new behaviour⟧
- The owner confirmed the khata basis for every book and accepted all the rulings of 20 Oct 2026 (owner, 22 Oct 2026; desk 207), among them: one running khata per person, with deposits, retention, advances and interest-bearing loans on their own accounts; corrections as new entries; the year close posted by the book, with the result and drawings to own money; money a business sends home is the owner's income; a trust's fund spending through Income & Expenditure with a transfer from the fund; a donated thing kept at ₹1.

## Consequences
- Code: none. Suite A (`A-ref-*`) still re-lands against the reference books at M14.
- Docs: CLAUDE.md § Precedence item 3 and § Accounting authority; ADR 2026-10-20 §1 and Open; `docs/accounting/02-accounts-and-transactions.md` opening paragraph (entries are from → to, between accounts the user opens).
- Environment: `.claude/agents/acct-munim.md`, `acct-entities.md`, `.claude/workflows/acct-review.js` and `.claude/skills/acct-review/SKILL.md` no longer treat an uncovered case as a finding.
- Milestone: PLAN-207 and PLAN-208 closed; PLAN-209 (bookkeeper sign-off) unchanged and still blocks M14 exit.

## Open ⚠️
- None.

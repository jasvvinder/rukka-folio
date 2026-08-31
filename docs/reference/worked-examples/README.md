# Worked Examples — reading guide and class mapping

Four entity types, seven books, 175 vouchers, FY 2026-27. Every ledger and trial balance here is generated from the voucher register and verified to balance.

**Status:** ⚠️ pending bookkeeper sign-off. On sign-off these freeze as **golden fixtures** (09 suite A) and the engine must reproduce every ledger and trial balance exactly.

| File | Entity | Books | Vouchers | TB total |
|---|---|---:|---:|---:|
| `individual-rahul-sharma.md` | Individual | 1 | 33 | ₹5,94,800 |
| `business-sharma-textile.md` | Business | 1 | 31 | ₹8,56,200 |
| `trust-singh-sabha-gurudwara.md` | Trust / organization | 1 | 28 | ₹7,78,000 |
| `joint-family-sharma.md` | Joint family | 4 | 83 | ₹10,58,500 · ₹12,22,900 · ₹12,29,000 · ₹3,16,400 |

---

## 1. Account-type labels ⇄ engine classes 🔒

**These documents are written for a bookkeeper, not for the parser.** They use the traditional labels a CA expects to see on a chart of accounts. The engine has seven classes (02 §1.2) and does not know these words. Fixtures must compare on the **class** column, never on the label.

| Label used here | Engine class (02 §1.2) | Note |
|---|---|---|
| Money | `money` | subtype carried separately (saving / current / OD / **CC** / loan) |
| **Debtor** | `party` | ⚠️ **not a separate class** |
| **Creditor** | `party` | ⚠️ **not a separate class** |
| Advance | `advance` | one per member per book, auto-created |
| Expense | `category_expense` | |
| Income | `category_income` | |
| Equity | `equity_system` | Opening Balance / Capital, Adjustments, Suspense |
| Interbook | `equity_system` | the `Due to/from {Book}` pairs of 02 §6 |

### Why Debtor and Creditor are one class 🔒

02 §1.2 locks **one party, one account, both roles** — placement is **by sign**, so a party that owes you (Dr) shows under *You will get* and the same account showing Cr shows under *You will give*, with no reclassification and no second account. The Debtor/Creditor split in these documents is **presentation only**: each label happens to match that account's sign on the closing date, and would be wrong the moment the balance crossed zero.

This is not cosmetic. It is the same error class the audit errata caught as **E-1** (an account classified as both expense and liability), and 02's single-party model exists precisely so it cannot be entered. A fixture that asserts `type == 'Creditor'` would encode the bug the design removes.

### The credit card 🔒

`PNB Credit Card A/c` is class **`money`, subtype `CC`** — not a party. 02 §1.2 puts cards in `money` (sign flips to liability when overdrawn, exactly like an OD), and 02 §2 verb 5 routes the bill payment as a **Transfer** (`Dr CC · Cr bank`), not a party settlement. The postings are arithmetically identical either way — V-018 and V-019 are correct as written — but the class drives report placement and which verb the entry screen offers, so the engine and the fixture must agree.

---

## 2. What a fixture harness should and should not assert

**Assert:** every voucher's Dr/Cr account pair and amount; every ledger's running balance and closing `c/f`; every trial-balance row; both column totals; that all seven books balance; that each `Due to/from` pair nets to zero (02 §6).

**Do not assert:** the type label (map it first, per §1); the `To`/`By` particulars wording; row ordering within a day; Indian-format digit grouping in the source markdown.

---

## 3. Known coverage gaps ⚠️

1. **Two unpaired inter-book balances.** The joint-family common pool carries `Rahul Sub-family` ₹2,00,000 Dr and `Geeta Sub-family` ₹2,60,000 Dr, but neither sub-family book is modelled — so 2 of the 5 due-to/due-from pairs cannot be reconciliation-tested. Only Agriculture (₹4,00,000), Super Store (₹1,80,000) and Pankaj (₹2,00,000) close the loop. Add both books before freeze, or the Family Reconciliation report (02 §6) ships with fixture coverage on 3 of 6 pairs.
2. **No period lock or year close** is exercised anywhere in these examples — the period runs 01 Apr – 29 Aug 2026 with no month locked. The close ceremony and certified vectors (02 §8, §8.1) therefore have no golden fixture and rest entirely on suite H.
3. **No amend, reversal, or rejected entry** appears, so 02 §5 corrections have no worked illustration for the bookkeeper to review.
4. **No statement-import or Suspense line** appears (02 §10).

None of these blocks sign-off on what *is* here — the arithmetic is sound. They bound what the fixtures can prove.


**Class `partner`** (added 30 Aug 2026) — `{Owner} — Partner Current A/c` in a shared-ownership business; presented as "Partner", placed by sign like Debtor/Creditor (02 §7.1).

## Joint business / partnership example (added 30 Aug 2026)
`joint-business-partnership.md` — Kaur family Agriculture, three sub-families owning equally, each paying business costs from their own pocket. Demonstrates 02 §7.1: partner current accounts, the contribution/drawing/profit-share distinction, one-entry profit distribution via `Profit Distributed`, and the equalisation view. TB ₹18,99,000, machine-verified. Class `partner` maps to the label "Partner" in the presentation table above; like Debtor/Creditor it is placed by sign, never statically typed.


## Known coverage gaps (stated, not hidden)
- **Six inter-book links exist, three are shown closing the loop.** Pankaj's book carries *Geeta Sharma (personal book) ₹14,500 Cr* whose mirror lives in Geeta's personal book, which is not reproduced here; likewise the Rahul and Geeta sub-family halves of the pool's allowances. The Family Reconciliation table lists the three pairs whose both sides are in this package.
- **ADR `2026-08-30-audit-remediation.md` predates the partnership example** added the same day: its verification counts and its L3 note describe the package before `joint-business-partnership.*` and the `partner` class existed.

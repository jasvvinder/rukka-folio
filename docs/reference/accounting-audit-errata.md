# Accounting Audit — Errata for the Uploaded Reference Files

**Scope:** full re-audit of `original/ledger_rules_specification.md` ("File 2", the revised worked example) and `original/Financial_Architecture_Specification.md` ("File 1", the architecture doc). Every ledger and trial balance was recomputed by hand. Corrections are consolidated in `financial-accounting-standards.md`, which supersedes both originals. ⚠️ Pending: bookkeeper re-verification of the corrected version before the scenarios freeze as golden test fixtures.

---

## 1. File 2 — errors requiring correction

| # | Location | Error | Correction |
|---|---|---|---|
| E-1 | §2 item 9 | **Milk Man classified "Expense/Accrued Liability"** — an account cannot be both; this hybrid causes every downstream error | Split into two accounts: `Milk Expense A/c` (Expense) and `Milk Man A/c` (Liability — Creditor/party). Delete `Accrued Milk Payable` (redundant once Milk Man is the payable) |
| E-2 | §3 E14 | Bill accrual posted **Dr Milk Man / Cr Accrued Milk Payable** — books the bill into the wrong debit account and a redundant payable | **Dr Milk Expense ₹3,500 / Cr Milk Man ₹3,500** (expense recognized, payable created) |
| E-3 | §3 E15 | Payment posted **Dr Milk Man (as expense) / Cr Cash** — paying a bill never increases an expense | **Dr Milk Man ₹3,000 / Cr Cash ₹3,000** (payable reduced) |
| E-4 | §4.9 ledger | Milk Man ledger **contradicts its own daybook**: 28 Aug shown as *Credit* ₹3,000 ("By Cash") while the daybook says *Debit*. As ledgered, E15 = Cr Milk Man + Cr Cash — **two credits, no debit: double entry itself violated** | Corrected ledgers in the standards doc: Milk Expense closes **₹3,500 Dr**; Milk Man closes **₹500 Cr** |
| E-5 | §4.9 note | Footnote claims the ₹500 sits in Accrued Milk Payable while the ledger above it shows Milk Man ₹500 **Dr** — internally inconsistent, and ₹500 Dr on a creditor is meaningless here | The ₹500 is Milk Man's **Cr** balance: amount payable (ਦੇਣੇ ਹਨ / देने हैं) |
| E-6 | §5 | **The trial balance does not balance.** Printed debit rows sum to **₹1,82,500**, not the printed ₹1,85,500 — short by exactly the ₹3,000 orphaned by E-3/E-4. The claimed "mathematical equilibrium" is false as printed | With E-1…E-4 corrected, both columns genuinely equal **₹1,85,500** (proof in standards doc §5) |
| E-7 | §5 rows | Rows "Milk Man ₹500 Dr" and "Accrued Milk Payable ₹500 Cr" | Replace with "Milk Expense ₹3,500 Dr" and "Milk Man A/c ₹500 Cr" |
| E-8 | §2 | Master setup omits two accounts its own daybook uses: **Salary Income** (E01) and the **Opening Balance/Capital** equity that absorbs the ₹31,000 of openings (the TB references both) | Added as accounts 11 and 12 in the corrected setup |
| E-9 | §1.1 | Milk Man listed among *Expense* examples; Equity's class column reads "Liability" | Milk Man moves to Liability examples; Equity column reads "Internal claim (own class)" |
| E-10 | §4.9 header | Milk Man "Natural State: Debit Balance (tracks expense…)" | Creditor: natural **Credit** balance |

**Verified correct in File 2 (credit where due):** all nine other ledgers recompute exactly — Utility 4,500 Dr · Saving 63,500 Dr · Salary Bank 14,000 Dr · Business Bank 30,000 Dr · Business Expense 12,000 Dr · Cash 33,000 Dr · Personal Expense 18,000 Dr · Ramesh 7,000 Dr · Rahul 4,000 Cr. E01–E13 postings are all sound. The To/By convention is applied correctly throughout. Dated *Opening Balance b/f* and *Closing Balance c/f* rows and the per-row Dr/Cr sign column are correct practice — both match or improve Rukka Folio's locked statement rules.

## 2. File 1 — errors (its individual scenario §6 is fully correct)

| # | Location | Error | Correction |
|---|---|---|---|
| F-1 | §5.4 | **Business Cash ₹1,500** — actual: 1,000 + 12,000 − 1,500 = **₹11,500** | ₹11,500 Dr |
| F-2 | §5.3/5.4 | HDFC opening ₹50,000 Dr has **no equity counterpart**, so the business TB cannot balance; the printed ₹85,000 = ₹85,000 is false | Add Opening Balance/Capital ₹50,000 Cr; corrected TB balances at **₹95,000 / ₹95,000** |
| F-3 | §4.4 | Trust TB labels ₹20,000 of *Donation Income* as "Trust Capital / Corpus" | Mid-period TB shows **Donation Income ₹20,000 Cr**; it closes to Corpus only at year end |
| F-4 | §3 / §4.3 | Advance-as-cash-tags design: Day-02 is a dated ledger row with **no debit and no credit** — a mutation outside double entry, unauditable by the document's own §1 rules; the TB then shows one account twice as "sub-states" | Rukka Folio keeps per-member `Advance` sub-accounts (02 §7): same visibility (vault vs. per-person), every movement a real journal entry, plus ageing/reminders/settlement gates. Their *display* idea (Cash ₹18,000 — Vault 15,000 · with A 3,000) is adopted as presentation |

## 3. What this audit validates about Rukka Folio's locked design

- The engine rules in **doc 02 survive unchanged** — the mockup's Verma Dairy postings match File 1's correct Day 12–13 pattern exactly.
- E-1 is a live demonstration of *why* 02 separates the **party** from the **expense category**: the error class cannot be entered in our engine.
- File 1 §8 (zero-crossing inversions) is precisely our placement-by-sign rule, case for case; §9 (atomicity, month lock, adjustment-only corrections) is already 02 §5/§8 and 03/05.
- Presentation gaps our statement must adopt (pending owner approval): To/By counter-account particulars; Dr/Cr side on every running balance; no minus sign on professional surfaces.

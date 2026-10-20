# Rukka Folio Accounting Standard v3

**Status:** v3, 12 Oct 2026. Supersedes v2.0 (*Financial Architecture Specification v2.0*), archived verbatim at `docs/archive/reference/financial-accounting-standards-v2.0.md` (ADR 2026-10-12 §4; same path kept because two 🔒 lines and seven code comments cite it). **Place in the precedence ladder:** reference level (CLAUDE.md § Precedence 3) — the behavioural reference for the ledger engine, with the five golden worked examples; the class model, verbs and invariants of `02-ledger-rules.md` govern how anything here is represented, and the newest ADR on a topic beats both. Every rule here names its source. Rulings of 12 Oct 2026 whose build has not landed are marked **ruled 12 Oct 2026, build pending**. Questions the owner has not ruled are **⚠️ OWNER DECISION** boxes (indexed in §17) and are never decided here.

**Scope.** Ledger bookkeeping only. Invoicing, GST, taxation, statutory filings, inventory and payroll are permanent non-goals (`00-vision.md` *Non-goals*); nothing in this standard adds them, and nothing is written as if they were coming.

**Reading order.** §0 what the books must do · §1 theory, the meaning of Dr/Cr, and the account-type catalogue (§1.7) · §2 how a ledger is laid out · §3–§6 the four short entity cases kept from v2.0, each pointing to the full worked examples · §7–§9 zero-crossing, split vouchers, integrity · §10 governance · §11 books, charts and openings · §12 everyday transactions · §13 statement import and bank reconciliation · §14 month close and year end · §15 the year-end statements per book type · §16 reports cross-reference · §17 open owner decisions · appendices A–G. **Section numbers §1–§9 keep the meaning they had in v2.0**, because other files cite them by number (Appendix F).

---

## 0. What the books must do 🔒 (owner, 12 Oct 2026 — ADR 2026-10-12 §5) ⟦tests: n/a — the statement-range tests re-land with the reports slice (07 §14)⟧

The books exist for one loop, the same for every book type — individual, joint family, shop, partnership, contractor, farmer, trust, committee, landlord, truck operator:

**an entry comes in → it is posted to the user's own accounts → the position is live every day → any statement can be printed for any period and any account.**

1. **Every real entry is recorded, cash or bank.** An entry comes in one of two ways, and **both are first-class**:
   - **Manual entry** — the user types any transaction as it happens: a cash spend, a payment, a receipt, money given or taken on credit, a transfer, a cash withdrawal. The six verbs (02 §2) are the whole vocabulary; the posting is derived from the verb and the account's class, never chosen (§1.3.1).
   - **Bank statement import** — each statement line is answered with one question: *where did it come from, or where did it go?* (02 §10). The line already states the amount and the direction; the only unknown is the counterpart. Import is a way of entering many lines at once (07 §11), not a different kind of bookkeeping.
2. **Each entry is posted to the user's own accounts:** bank, cash, card, a loan account if the user keeps one, people, expense heads, income heads, things owned. The one catalogue of those account types is §1.7.
3. **The app shows a live position every day** — money by account, *You will get*, *You will give*, advances, in transit, this month's income and expenses — computed from the entries, correct offline (02 §9; 07 §4).
4. **The app gives a complete or partial ledger statement for any period — a year, a month, any custom range — and for any account or set of accounts.** *Complete* means every account: Day Book, Cash Book, Trial Balance and the year-end statements of §15. *Partial* means one account or a chosen set: the A/C statement (S4) of a party, a bank, a card, a loan, a head. Each opens with *Opening balance b/f* and ends with *Closing balance c/f* (02 §8.1 *Presentation*; §2 below).

The same postings serve both routes. What an entry *is* decides where it posts — whether the user typed it or an imported line asked for it:

| What the entry is | Posting (02 §2) |
|---|---|
| an expense | Dr expense head · Cr money |
| income received | Dr money · Cr income head |
| paying someone you owe (a bill, a hand loan, a supplier) | Dr party · Cr money — your payable shrinks |
| money received from someone who owed you | Dr money · Cr party — their udhaar shrinks |
| goods or work taken on credit; money lent or borrowed | Dr expense head · Cr party / Dr party · Cr income head / Dr money · Cr party / Dr party · Cr money (verbs 3–4) |
| a credit-card bill paid | Transfer — Dr card · Cr bank |
| a loan instalment | without a loan account: Dr expense head (or the lender as a party) · Cr bank; with a `money · loan` account: a Transfer for the principal, the bank-debited interest a Money out (§12.3) |
| a cash withdrawal, a move between own accounts | Transfer — Dr to-account · Cr from-account; one event, never counted twice (02 §10 pairing) |
| a thing bought to keep (truck, land, gold, FD) | Dr thing owned · Cr money — ruled 12 Oct 2026, build pending (§12.4) |

**Normative hooks.** 02 §8.1 *Presentation* carries the 🔒 clause *any date range, any account or set of accounts*; `00-vision.md` *What* points here. 07 §4, §11 and §14 remain the screen catalogue.

---

## 1. Core accounting theory

### 1.1 The accounting identity
$$\text{Assets} = \text{Liabilities} + \text{Equity}$$
Every transaction is a set of journal lines summing to zero. A standalone entry cannot exist.

### 1.2 Five-type classification matrix (corrected)

| Type | Class | Natural balance | Dr impact | Cr impact | Examples |
|---|---|---|---|---|---|
| Asset | Asset | **Dr** | + | − | Cash, banks, debtors (Ramesh), advances (ਐਡਵਾਂਸ) |
| Expense | P&L | **Dr** | + | − | Utility, Milk Expense, Langar, Purchases |
| Liability | Liability | **Cr** | − | + | Creditors (Rahul, Milk Man, Aggarwal), OD, CC |
| Equity | Internal claim (own class) | **Cr** | − | + | Capital, Opening Balance, Drawings (contra) |
| Income | P&L | **Cr** | − | + | Salary Income, Sales, Donation Income |

Things owned — a truck, land, gold — are Assets too, and so are deposits — a fixed or recurring deposit, an investment — which are their own type, *Deposit* (owner, 13 Oct 2026; ADR 2026-10-12 §14; §1.7.2 row 22). The engine gains a class for them, `asset`, shown at cost under *What I have* (ADR 2026-10-12 §6, **ruled 12 Oct 2026, build pending**; §1.7 row 14). There is no `liability` class: every obligation in scope is owed to a person (a party), to a bank (a money subtype — loan, OD, card) or to a partner (ADR 2026-10-12 §6).

### 1.3 What Dr and Cr *mean*, per account type 🔒 ⟦tests: A-02-26, A-ref-4⟧
Ledger columns never say bare "Dr/Cr" — each account type carries its contextual meaning in the column header, exactly as used in every ledger image below:

| Account type | Debit (Dr.) means | Credit (Cr.) means | Balance side reads as |
|---|---|---|---|
| Bank / Cash (money) | *Money in* | *Money out* | Dr = you have · Cr = overdraft (you owe bank) |
| Debtor (party) | *Given / they owe you ↑* | *Received back* | Dr = you will get (ਲੈਣੇ ਹਨ) |
| Creditor (party) | *You paid* | *You took / you owe ↑* | Cr = you will give (ਦੇਣੇ ਹਨ) |
| Advance / ਐਡਵਾਂਸ | *Handed out* | *Bills settled / returned* | Dr = money out with the person |
| Expense | *Spent* | *Refund / adjustment* | Dr = total spent |
| Income | *Refund / adjustment* | *Earned / received* | Cr = total earned |
| Equity / Capital | *Withdrawn (drawings)* | *Added (capital in)* | Cr = own money in the books |
| Due to/from {Book} | *That book owes this one* | *This book owes that one* | Sign shows direction |

Two account types the engine holds that the table above predates, stated here below the table rather than inside it:
- **Partner Current A/c** (`partner`, 02 §7.1): Dr = *took out / owes the business*; Cr = *put in, or profit share*; balance Cr = the business owes them, Dr = they owe the business. Both cases are shown as plainly (02 §7.1 *Debit balances are real*).
- **Thing owned** (`asset`, ruled 12 Oct 2026, build pending): Dr = *bought, at cost*; Cr = *sold or taken off the books*; balance Dr = what you own, at cost. The column wording is proposed here and is for the build slice to set.

*Debtor* and *Creditor* are two readings of one `party` account, placed by sign (02 §1.2; §7). *Capital* is the book's `Opening Balance / Capital` account (ADR 2026-09-09b §1).

### 1.3.1 Why classification, not direction, decides Dr/Cr 🔒 ⟦tests: A-02-26⟧
Debit and credit follow the **account's class**, never the direction in which money appears to travel. Prepositional shortcuts ("from = credit, to = debit") hold for simple two-party transfers and fail for revenue, liabilities, equity and adjustments. The engine therefore derives every posting from the verb plus the classification matrix (§1.1), and the UI's entry preview (07 §5.5) uses a neutral arrow that states flow without asserting a rule.

**Modern frame — DEAD CLIC:** **D**ebit increases **E**xpenses, **A**ssets, **D**rawings · **C**redit increases **L**iabilities, **I**ncome, **C**apital.

### 1.4 The three golden rules (traditional frame)
- **Personal accounts** (people, firms, banks-as-parties): *debit the receiver, credit the giver.*
- **Real accounts** (cash, assets): *debit what comes in, credit what goes out.*
- **Nominal accounts** (expenses, incomes): *debit expenses and losses, credit incomes and gains.*

### 1.5 The bank-statement illusion and the two vocabularies
The bank's SMS says "credited" because in *the bank's* ledger your deposit is its liability (owed back to you) — a Cr in *its* books. In *your* books that account is an asset, so the same deposit is a **Dr / Money in**. The engine always keeps the user's perspective. (Adopted as onboarding help copy.)

**Two vocabularies, one engine** (02 §10; CLAUDE.md rule 9; ADR 2026-10-10b §4; ADR 2026-10-12 §2). The posting logic never changes with the words. Entry screens, import screens and day-book lists say *Money in / Money out*; the bank's own debit/credit column is mapped on read and never shown as Dr/Cr. Professional surfaces — the A/C statement, the trial balance, exports — show the true ledger side. A consumer label may carry its true side in brackets, *Money in (Dr)*, and that is not mixing the conventions. Printed reports and statements speak the plain words a household or a shopkeeper writes in a diary — *Money in / Money out, You will get / You will give, Spent, Received, Cash in hand, Opening balance, Total for the year, What I have / What I owe* — with the true side as a small bracket after the label; engine class names, verb names, rule or ADR references, ⚠️ notes and checks never appear on a printed report (ADR 2026-10-12 §2). The Punjabi and Hindi words come from 01 §2 and remain subject to native review (01 §4).

### 1.6 Rukka Folio mapping
Classes: `money` + `party` + `advance` ↔ Asset/Liability **resolved by sign** (02 §1.2) · categories ↔ Expense/Income · `equity_system` ↔ Equity. The six entry verbs (02 §2) generate every posting in this document; the user never chooses Dr/Cr.

Extended by ADR 2026-10-12 §6 (build pending): `asset` ↔ Asset for things owned, at cost; `partner` ↔ Asset/Liability by sign (02 §7.1). §1.7 is the full catalogue.

### 1.7 The account-type catalogue (ADR 2026-10-12 §6)

This is the **one** catalogue of account types. Its normative anchors stay where they are: 02 §1.2 owns the classes, subtypes and roles; 07 §6 step 1 owns the add-account grid (S3.1); 01 §2 owns the words. The engine column was checked against `packages/core_ledger/lib/src/accounts.dart` (`AccountClass` 7 values, `MoneySubtype` 8, `SystemRole` 6) and the tile column against `QuickAddTile` in `app/lib/features/ledger/screens/s3_1_quick_add_sheet.dart:43–50` (7 tiles: bank→`saving`, cash, credit→`cc`, creditor, debtor, expense, income) on 12 Oct 2026. Rows the owner ruled on 12 Oct 2026 that are not yet built say so. *Place in the position* follows 02 §9 and the Home card of 07 §4; *opening-balance question* follows 02 §4. PA/HI are given by their 01 §2 row where one exists; otherwise the row says **⚠️ needs a 01 key** — new terms are added to 01, never defined here (Appendix C).

| # | Standard type | Traditional type | Engine class · subtype · role | Plain label EN (PA / HI by 01 §2 row) | Natural balance | Place in the position | Who creates it | Opening-balance question | Optional? |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Bank — savings | Real (asset; liability when overdrawn) | `money · saving` | Bank — ⚠️ needs a 01 key (01 §2 has only *Bank balance* ਬੈਂਕ ਬਾਕੀ / बैंक बाकी) | Dr | *Total money you have* and its own line; a Cr balance is an overdraft, subtracted from the hero (07 §4) | S3.1 tile *Bank* (`QuickAddTile.bank`); never seeded (ADR 2026-09-09d §1) | *balance today*, negative allowed = overdraft (02 §4) | as needed |
| 2 | Bank — current | Real | `money · current` | Bank (current) — same key as row 1 — **ruled 12 Oct 2026, build pending**: today the Bank tile creates `saving` only | Dr | as row 1 | S3.1 tile *Bank (savings or current)* — build pending | as row 1 | as needed |
| 3 | Cash in hand | Real | `money · cash` | Cash — 01 §2 *Cash in hand* ਹੱਥ ਵਿੱਚ ਰੋਕੜ / हाथ में रोकड़; a shop drawer is *Galla* ਗੱਲਾ / गल्ला | Dr; a negative balance is always a missing entry and warns (02 §9) | *Total money you have*; counted at month close (02 §8 step 1) | seeded in every book (ADR 2026-09-09c §1); more via S3.1 tile *Cash* | *balance today* | one is always there |
| 4 | Collection box | Real | `money · cash_collection` | Gollak — 01 §2 *Gollak* ਗੋਲਕ / गोलक | Dr = what is still in the box | *Total money you have*; a count *recognises income* (02 §8.2); emptied only by Transfer to cash or bank | seeded in organization books (07 §3.1; ADR 2026-09-09c §1); not on the grid | none — the contents are unknown until counted | organization books |
| 5 | Overdraft (OD) | Real; liability by sign | `money · od` | OD — ⚠️ needs a 01 key — **ruled 12 Oct 2026, build pending**: today the tile *Credit card or OD* creates `cc` | Cr when drawn | money list, subtracted from the hero; reads *you will give* the bank (§7) | S3.1 tile *OD* — build pending | *balance today*, negative = drawn | as needed |
| 6 | Credit card | Liability by sign | `money · cc` | Credit card (tile EN *Credit card*) — ⚠️ needs a 01 key | Cr | money list, subtracted (07 §4 shows *HDFC CC −*) | S3.1 tile (`QuickAddTile.credit`) | *balance today*, negative = you owe the card | as needed |
| 7 | Loan (bank) | Liability | `money · loan` | Loan — ⚠️ needs a 01 key — **ruled 12 Oct 2026, build pending**: no tile today | Cr = principal still owed | money list, subtracted; Full Position: *What I owe* | S3.1 tile *Loan* — build pending | *balance today* as what is owed | **optional** — banks send their own statements; a user keeps one only if they want it in the ledger (ADR 2026-10-12 §6) |
| 8 | Wallet (UPI / prepaid) | Real | `money · wallet` | Wallet — ⚠️ needs a 01 key — **ruled 12 Oct 2026, build pending**: no tile today | Dr | *Total money you have* | S3.1 tile *Wallet* — build pending | *balance today* | as needed |
| 9 | Person or shop (party) | Personal | `party` | Person or shop — the type label ⚠️ needs a 01 key (today's tiles read *Someone who owes me* / *Someone I owe*); the balance reads by 01 §2 *Debtors — You will get* ਦੇਣਦਾਰ (ਤੁਸੀਂ ਲੈਣੇ ਹਨ) / देनदार (आपने लेने हैं) or *Creditors — You will give* ਲੈਣਦਾਰ (ਤੁਸੀਂ ਦੇਣੇ ਹਨ) / लेनदार (आपने देने हैं) | by sign — one party, one account, both roles (02 §1.2) | *You will get* (Dr) / *You will give* (Cr), with ageing | S3.1 tiles (two today, `creditor` / `debtor`; one *Person or shop* tile ruled, build pending); inline from *To whom?* / *From whom?* (02 §1.2); never seeded (ADR 2026-09-09c §1) | *do they owe you, or do you owe them?* + amount (02 §4) | as needed |
| 10 | Advance to a member | Real — money out with a person | `advance` (`memberId`) | Advance — 01 §2 *Advance* ਐਡਵਾਂਸ / एडवांस | Dr; open while > 0 | *Advances out* on the book; *Advance with you* on the member (02 §7), aged | system — one per member per book (02 §1.2) | ⚠️ not stated in 02 §4; the use-case set posts one opening per 02 §4 where a member already holds money | automatic |
| 11 | Partner's account | Personal (an owner) | `partner` (`memberId`) | Partner Current A/c — ⚠️ needs a 01 key | Cr = the business owes them; Dr = they owe it (02 §7.1) | *Partner positions* (S14); Full Position by sign | system — one per owner of a *Shared* business (ADR 2026-09-09c §1) | each owner's contribution, asked and never derived from the ratio (ADR 2026-09-09c §4) | shared businesses only |
| 12 | Expense head | Nominal | `category_expense` | Expense — 01 §2 *Expenses* ਖਰਚੇ / खर्चे | Dr | *This month: Out*; the year's result (§15) | seeded tree per book type (ADR 2026-09-09c §1; Appendix A); S3.1 tile *Expense*; inline from *For what?* | none — starts each FY at zero (02 §4; ADR 2026-09-05e §2) | tree always seeded |
| 13 | Income head | Nominal | `category_income` | Income — 01 §2 *Income* ਆਮਦਨ / आमदनी | Cr | *This month: In*; the year's result | seeded tree; S3.1 tile *Income*; inline from *From what?* | none — starts each FY at zero | tree always seeded |
| 14 | Thing owned | Real | **`asset` — ruled 12 Oct 2026, build pending** (not in `AccountClass` today) | Thing owned — ⚠️ needs a 01 key (01 §2 *Assets* ਸੰਪੱਤੀ / संपत्ति is a report side) | Dr | *What I have*, at cost (ADR 2026-10-12 §6); never inside *Total money you have* | S3.1 tile *Thing owned* — build pending | its cost — wording set by the build slice | optional |
| 15 | Capital (Opening Balance / Capital) | Personal — the owner's own account | `equity_system · openingBalance` | Capital — 01 §2 *Capital* ਪੂੰਜੀ / पूँजी; the opening row is 01 §2 *Opening balance* ਸ਼ੁਰੂਆਤੀ ਬਕਾਇਆ / शुरुआती बकाया | Cr | the make-up of Accumulated surplus / Corpus (§15.4) | system — exactly one per book (ADR 2026-09-09b §1); the *Capital* tile records **capital introduced**, an entry, and never creates an account (ADR 2026-10-12 §6, build pending) | none — it is the counterpart of every opening (02 §4) | always |
| 16 | Drawings | Personal — contra-equity | `equity_system · drawings` | Drawings — 01 §2 *Drawings* ਘਰੂ ਖਾਤਾ / निजी खर्च | Dr | deducted in the make-up of Accumulated surplus | seeded for a *Just me* business (ADR 2026-09-09b §2) | none | Just-me business only |
| 17 | Profit Distributed | contra-equity | `equity_system · profitDistributed` | Profit Distributed — ⚠️ needs a 01 key | Dr | deducted in the make-up of Accumulated surplus | seeded for a *Shared* business (ADR 2026-09-09c §1) | none | shared business only |
| 18 | Adjustments | Equity (system) | `equity_system · adjustments` | Adjustments — ⚠️ needs a 01 key (01 §2 has the verb *Fix / Adjust* ਠੀਕ ਕਰੋ / ठीक करें) | either | its own line in the Full Position (§14.4; D16a) | system | none | always |
| 19 | Suspense | Equity (system) | `equity_system · suspense` | Unexplained — 01 §2 *Suspense* ਅਣਪਛਾਤੀ ਰਕਮ / अज्ञात रकम | either; must be 0 at every lock (02 §10) | the *unexplained* chip; blocks the lock | system | none | always |
| 20 | Due to/from {Book} (link) | Personal — the other book | `equity_system · dueToFrom` (`counterpartBookId`) | the other book's name and type, e.g. *Randhawa Joint Family (joint family book)* (renamed 13 Oct 2026, ADR 2026-10-12 §14) (ADR 2026-10-11 §4) — ⚠️ needs a 01 key | by sign | *In transit* while a half is flagged; Full Position by sign; Family Reconciliation (02 §6) | auto on first inter-book use (02 §6) | none | multi-book tenants |
| 21 | Written off (expense head) | Nominal | `category_expense`, seeded — **ruled 12 Oct 2026 (ADR 2026-10-12 §8), build pending** | Written off — 01 §2 *Write off* ਡੁੱਬਿਆ ਕਰਜ਼ਾ / डूबा कर्ज़ा | Dr | the year's result (§12.5) | seeded — build pending | none | always, once built |

Not accounts: **Accumulated surplus** (business, family, personal) and **Corpus** (trust) are computed lines — Σ certified net results + opening equity − distributions — never stored and never closed by an entry (02 §1.2; ADR 2026-09-05e §2). **Capital** is row 15, not a second account. Every obligation in scope is a party (row 9), a bank product (rows 5–7) or a partner (row 11); a `liability` class is revisited only if a worked example shows a case these cannot hold (ADR 2026-10-12 §6).

The add-account grid (S3.1), as ruled: **Bank (savings or current) · Cash · OD · Credit card · Loan · Wallet · Person or shop · Expense · Income · Thing owned**, plus the *Capital* tile that opens capital introduced (ADR 2026-10-12 §6). Its build slice allocates the tests and supersedes the 7-tile assertion in `app/test/features/ledger/s3_1_quick_add_sheet_test.dart:126`.

### 1.7.1 How Dr and Cr work for every type in the catalogue

One row per §1.7 row. *Dr means* and *Cr means* are what a line on each side of that account records; *Natural balance* is the side its balance normally sits on and how that balance reads; *Used by* lists the entries (02 §2 verbs, §12) that post to it. The engine derives every line from the verb and the account's class (§1.3.1); the user never chooses a side.

| # | Type | Dr means | Cr means | Natural balance — how it reads | Used by |
|---|---|---|---|---|---|
| 1–2 | Bank (savings, current) | money in — a receipt, a transfer in | money out — a payment, a transfer out, bank charges | Dr = money you have; Cr = overdrawn | Money in, Money out, Transfer, import (§13) |
| 3 | Cash in hand | cash in — a receipt, cash withdrawn from the bank | cash out — a payment, cash deposited in the bank | Dr; a Cr balance is a missing entry and warns (02 §9) | Money in, Money out, Transfer; month-close count (02 §8) |
| 4 | Collection box (gollak) | the counted amount (the count is income) | emptied into cash or bank — only by Transfer | Dr = still in the box; nil after it is emptied | count (02 §8.2), Transfer |
| 5 | Overdraft (OD) | paid in | drawn; interest and charges | Cr = owed to the bank | Transfer, Money out |
| 6 | Credit card | the bill paid (Transfer from a bank), a refund | spent on the card, fees | Cr = owed on the card | Money out, Transfer |
| 7 | Loan (bank) | principal paid back | loan taken; interest the bank adds to the loan | Cr = principal still owed | Transfer, Money out (interest), opening (§12.3) |
| 8 | Wallet | recharged, money received | spent | Dr | Transfer, Money out |
| 9 | Person or shop | you paid them, or gave money or goods on credit | they paid you, or you took goods or money on credit | by sign — Dr = *you will get*; Cr = *you will give* | Gave / Took on credit, Money in / out (§12.5) |
| 10 | Advance to a member | money handed out | spent against bills, or returned | Dr = money still with the person | Money out, spend, Money in (§12.6) |
| 11 | Partner's account | took money out | put money in, paid a business cost from own pocket, profit share | by sign — Cr = the business owes them; Dr = they owe it | Money out, Money in, own-pocket entry, distribution (§12.7) |
| 12 | Expense head | spent | a refund or a correction | Dr = total spent this year; not carried | Money out, Took on credit, advance spend |
| 13 | Income head | a refund or a correction | earned or received | Cr = total earned this year; not carried | Money in, Gave on credit, gollak count |
| 14 | Thing owned *(build pending)* | bought or added, at cost | sold or taken off, at cost | Dr = what you own, at cost | purchase, sale (§12.4) |
| 15 | Capital (Opening Balance / Capital) | capital taken back (rare) | capital put in; the counterpart of every opening | Cr = own money | openings (02 §4), Money in (capital introduced, §11.5) |
| 16 | Drawings | money the owner took out | put back (rare) | Dr; deducted from own money | Money out (§11.5) |
| 17 | Profit Distributed | profit shares credited to the partners | a reversal | Dr; deducted from accumulated surplus | distribution (§12.7) |
| 18 | Adjustments | cash short at a count; a write-off (today) | cash over at a count | either | guided Adjustment (02 §2 verb 6) |
| 19 | Suspense (*Unexplained*) | money out not yet explained | money in not yet explained | must be nil at every month lock | statement import (02 §10) |
| 20 | Inter-book link | this book gave to, or paid for, the other book | this book received from the other book | by sign; the pair nets to zero | Transfer across books (02 §6, §12.8) |
| 21 | Written off *(build pending)* | a party balance written off | a later recovery or a correction | Dr; part of the year's result | write-off (ADR 2026-10-12 §8) |

### 1.7.2 Types the practice worked examples use that the engine does not have yet

The ten practice books (`worked-examples/practice/`, ADR 2026-10-12 §10–§14) keep twelve more types. **None is built**; each is a gap listed in `worked-examples/practice/GAPS.md` and needs a ruling before its build slice. Printed words are the short plain words of ADR 2026-10-12 §14; entry numbers are the printed ones.

| # | Type (printed word) | Standard type | Dr means | Cr means | Natural balance — how it reads | In the practice books | Gap |
|---|---|---|---|---|---|---|---|
| 22 | Fixed or recurring deposit, investment (*Deposit*) | Asset | money kept aside (Transfer from a bank) | taken back when it matures | Dr — *What I have* | `JP-043`, `L-023`, `RC-017`; interest is a Money in to an income head | A3 — **ruled 13 Oct 2026: its own type, *Deposit*, not *Thing owned*** (ADR 2026-10-12 §14); whether it is a `money` subtype or an `asset` subtype is for its build slice |
| 23 | Deposit held from a person (*Deposit held*) — one account per person, *Deposit held – {person}* | Liability | returned, or set off against what the person owes | received | Cr — *What I will give*; shown on the person's page beside the khata | `L-034` received, `L-025` set off | A2b — **ruled 13 Oct 2026: one account per person**, never netted against the khata (ADR 2026-10-12 §14, §12.4) |
| 24 | Money kept for a purpose (*Fund*) | Capital (earmarked fund) | spent on that purpose | donations given for it; its deposit's interest | Cr — beside the General Fund, under *What I will give* | `C-011`, `C-024`, `C-033` | A4 |
| 25 | Partner's fixed capital (*Partner's capital*) | Capital | capital withdrawn by the partners' decision | capital put in by the partners' decision | Cr; does not move in the year | Bal Fabricators chart | B2 — 02 §7.1 has one account per partner |
| 26 | Partner's current account (*Partner's current*) | Capital | drawings | own-pocket payments; interest on capital and share when posted | by sign | `BF-006`, `BF-042` | B1, B2 |
| 27 | Money put into a business (*Money in a business*) | Asset | money put into the business | that money taken back as capital | Dr — at what was put in | `RJ-005`, `RJ-022`; `JP` *Jasvinder Technologies A/c* | A11 |
| 28 | The owner's account in a business book (*Owner*) | Capital | money sent to the owner's book | money put in by the owner | Cr; mirrors row 27 for money put in | `RG-005`, `JT` *Jasvinder Singh A/c* | A11, C2 |
| 29 | A sub-family's account in the joint book (*Sub-family*) | Capital (running account) | household money given, a bill the family paid for it, money taken to be returned | money it put in — into the family, straight into a family business, or by paying a family-business bill; a year-end settlement | by sign — **settled or carried forward** at the year end, as the family decides | `RJ-001`, `RJ-010`, `RJ-023`, `RJ-025`, `RJ-037`, `RJ-038` | A11 |
| 30 | The household's account with the joint family (*Joint family*) | Capital (running account) | money put in or paid back | money received from the family; a bill the family paid for it | by sign — mirrors row 29 entry for entry | `RA-001`, `RB-023`, `RC-010` | A11 |
| 31 | Money a family business sends home (*Income from {business}*) | Income | a correction | money received from the business | Cr — the family's income for the year | `RJ-004`, `RJ-007`, `RJ-015` | A11 |
| 32 | Advance to someone who is not a member (*Advance*) | Asset | money handed out | settled against bills (one or several heads), or returned | Dr — money still with the person | `T-009`, `L-018`, `RS-013`, `RJ-013` | A10 — D12 above |
| 33 | Deposit paid to a person (*Deposit paid*) — one account per person, *Deposit paid – {person}* | Asset | paid | got back, or set off against what you owe that person | Dr — *What I have* | the shop's *Deposit paid – Kapoor Properties A/c* (opening balance) | A2b — **ruled 13 Oct 2026: one account per person** (ADR 2026-10-12 §14, §12.4) |

### 1.8 Basis of accounting, and the boundary
- **Accrual by party, cash otherwise.** A bill taken on credit is an expense the day it is taken, with the party as the payable (02 §2 verb 4); a receipt or a payment is recorded the day the money moves. Nothing is accrued, spread or provided for at the year end unless the owner adopts an optional behaviour (§14.4; D-opt-2).
- **Integer paise** everywhere (02 §1.4 rule 2); INR only (rule 5).
- **Append-only.** Nothing is updated or deleted; a correction is an amend or a reversal (02 §5).
- **No closing entries.** The year closes by certifying balances, never by posting (02 §1.2, §8.1).
- **The boundary.** Invoices, GST, tax computations, statutory filings, stock and payroll are not kept here (`00-vision.md`). A registered business exports cleanly to Tally et al. for those.

---

## 2. Ledger presentation standard 🔒 (used in all images below) ⟦tests: A-ref-4, A-02-37⟧
Columns: **Date · Particulars (counter-account: "To …" on the debit side, "By …" on the credit side) · Debit (Dr.) [contextual] · Credit (Cr.) [contextual] · Balance · Side (Dr./Cr. on every row)**. Dated *Opening balance b/f* (period's first day) and *Closing balance c/f* (day forwarded) rows. Professional surfaces show absolute values + side, never a minus sign.

> **ADR 2026-09-24b §9** — on screen an FY view ends *Closing balance c/f*, as §3 draws it; a **printed or exported** ledger ends with the paper block *Closing balance c/d · Total · Opening balance b/d* and carries **no** c/f row above it. The opening row is unchanged.
> **ADR 2026-09-05e §2** — income and expense ledgers open each FY at zero and carry **no** *b/f* row; they end with the year's total. Money, party, advance, partner and equity_system ledgers carry *Opening balance b/f*.
> **ADR 2026-10-12 §5** — a statement is drawn for **any date range and any account or set of accounts**, not only a financial year: the b/f row is the balance before the range's first day, the c/f row falls on the range's last day (or today while the period is open, 07 §6). The 02 §8.1 clause is the rule; the FY switcher of ADR 2026-09-09 §4 is one preset of it.
> **ADR 2026-10-12 §2** — on a printed statement the contextual header is the plain word with the true side in a bracket — *Money in (Dr)*, *Received (Cr)* — and no technical term appears. The use-case worked examples are the reference layout (Appendix B).

Columns are the three of 01 §1 rule 9 — ਨਾਮੇ | ਜਮ੍ਹਾਂ | ਬਾਕੀ / नामे | जमा | बाकी / Dr | Cr | Balance — with Side as its own column and the running balance sorted by `(accounting_date, hlc, envelope_id)` on every device (02 §9).

---

## 3. Entity architecture 1 — Individual (Personal Book)

One person, one book: salary, household spending, lending to friends, borrowing, the dairy khata, plus an informal side activity. (A formal business gets its own book — §4 and §11.2.) Full worked examples: `docs/reference/worked-examples/individual-rahul-sharma.md` (golden) and `worked-examples/usecases/individual-jasvinder-singh.md` (a person and his own business as two books).

**Accounts:** 1 Utility Expense (E) · 2 Saving Bank (A, opens 10,000 Dr) · 3 Salary Bank (A, 5,000 Dr) · 4 Business Bank (A, 12,000 Dr) · 5 Business Expense (E) · 6 Cash (A, 4,000 Dr) · 7 Personal Expense (E) · 8 Ramesh — debtor (A) · 9 Milk Expense (E) · 10 Milk Man — creditor (L) · 11 Salary Income (I) · 12 Opening Balance/Capital (Eq, 31,000 Cr = counterpart of the four openings).

**Transaction types covered (verb in brackets):** income receipt [Money in] · ATM/cash withdrawal & inter-bank moves [Transfer] · expense by bank/cash [Money out] · lend money [Gave on credit] · recover in cash/UPI [Money in→party] · borrow [Took on credit] · repay [Money out→party] · **credit purchase / bill accrual** [Took on credit→expense] · partial supplier payment [Money out→party].

### 3.1 Daybook (Aug 2026)

| ID | Date | Event | Dr | Cr | ₹ |
|---|---|---|---|---|---|
| E01 | 01 | Salary received | Salary Bank | Salary Income | 1,50,000 |
| E02 | 02 | ATM withdrawal | Cash | Salary Bank | 40,000 |
| E03 | 03 | Moved to savings | Saving Bank | Salary Bank | 50,000 |
| E04 | 05 | Allocated to side business | Business Bank | Salary Bank | 30,000 |
| E05 | 06 | Lent to Ramesh | Ramesh | Cash | 20,000 |
| E06 | 08 | Electricity bill | Utility Expense | Saving Bank | 4,500 |
| E07 | 10 | Side-business stock | Business Expense | Business Bank | 12,000 |
| E08 | 12 | Ramesh repays (cash) | Cash | Ramesh | 5,000 |
| E09 | 14 | Ramesh repays (UPI) | Saving Bank | Ramesh | 8,000 |
| E10 | 15 | Borrowed from Rahul | Cash | Rahul | 40,000 |
| E11 | 18 | Repaid Rahul (cash) | Rahul | Cash | 15,000 |
| E12 | 20 | School fees | Personal Expense | Cash | 18,000 |
| E13 | 22 | Repaid Rahul (UPI) | Rahul | Salary Bank | 21,000 |
| E14 | 25 | Monthly milk bill accrued | Milk Expense | Milk Man | 3,500 |
| E15 | 28 | Paid milkman (part) | Milk Man | Cash | 3,000 |

### 3.2 Ledger account images

**Cash A/c** (money) — Dr *[Money in]* · Cr *[Money out]* — the §2 layout as drawn on screen:

| Date | Particulars | Dr | Cr | Balance | Side |
|---|---|---|---|---|---|
| 01 Aug | Opening balance b/f | — | — | 4,000 | Dr |
| 02 Aug | To Salary Bank A/c | 40,000 | — | 44,000 | Dr |
| 06 Aug | By Ramesh A/c | — | 20,000 | 24,000 | Dr |
| 12 Aug | To Ramesh A/c | 5,000 | — | 29,000 | Dr |
| 15 Aug | To Rahul A/c | 40,000 | — | 69,000 | Dr |
| 18 Aug | By Rahul A/c | — | 15,000 | 54,000 | Dr |
| 20 Aug | By Personal Expense A/c | — | 18,000 | 36,000 | Dr |
| 28 Aug | By Milk Man A/c | — | 3,000 | 33,000 | Dr |
| 31 Aug | Closing balance c/f | — | — | **33,000** | **Dr** |

**Salary Bank A/c**: b/f 5,000 Dr · 01 To Salary Income 1,50,000 → 1,55,000 · 02 By Cash 40,000 → 1,15,000 · 03 By Saving Bank 50,000 → 65,000 · 05 By Business Bank 30,000 → 35,000 · 22 By Rahul 21,000 → c/f **14,000 Dr**.
**Saving Bank A/c**: b/f 10,000 Dr · 03 To Salary Bank 50,000 → 60,000 Dr · 08 By Utility Expense 4,500 → 55,500 Dr · 14 To Ramesh 8,000 → 63,500 Dr · c/f **63,500 Dr**.
**Business Bank A/c**: b/f 12,000 Dr · 05 To Salary Bank 30,000 → 42,000 Dr · 10 By Business Expense 12,000 → 30,000 Dr · c/f **30,000 Dr**.
**Ramesh A/c** (party, Dr side) — Dr *[Given / owed to you ↑]* · Cr *[Received back]*: 06 To Cash 20,000 → 20,000 Dr · 12 By Cash 5,000 → 15,000 Dr · 14 By Saving Bank 8,000 → c/f **7,000 Dr** — *You will get ₹7,000 · ਰਮੇਸ਼ ਤੋਂ ਲੈਣੇ ਹਨ · रमेश से लेने हैं*.
**Rahul A/c** (party, Cr side) — Dr *[You paid]* · Cr *[You took ↑]*: 15 By Cash 40,000 → 40,000 Cr · 18 To Cash 15,000 → 25,000 Cr · 22 To Salary Bank 21,000 → c/f **4,000 Cr** — *You will give ₹4,000 · ਰਾਹੁਲ ਨੂੰ ਦੇਣੇ ਹਨ · राहुल को देने हैं*.
**Milk Expense A/c** (expense) — Dr *[Spent]* · Cr *[Refund/adj.]*: 25 Aug To Milk Man 3,500 → **3,500 Dr**.
**Milk Man A/c** (party, Cr side): 25 Aug By Milk Expense 3,500 → 3,500 Cr · 28 Aug To Cash 3,000 → **500 Cr** c/f — *You will give ₹500*.
**Utility Expense** 08 Aug To Saving Bank → **4,500 Dr** · **Business Expense** 10 Aug To Business Bank → **12,000 Dr** · **Personal Expense** 20 Aug To Cash → **18,000 Dr** · **Salary Income** 01 Aug By Salary Bank → **1,50,000 Cr** · **Opening Balance/Capital** → **31,000 Cr**.

### 3.3 Trial balance — 31 Aug 2026 (figures as machine-verified for v2.0)
Dr — Utility Expense 4,500 · Saving Bank 63,500 · Salary Bank 14,000 · Business Bank 30,000 · Business Expense 12,000 · Cash 33,000 · Personal Expense 18,000 · Ramesh 7,000 · Milk Expense 3,500 = **₹1,85,500**. Cr — Rahul 4,000 · Milk Man 500 · Opening Balance/Capital 31,000 · Salary Income 1,50,000 = **₹1,85,500**. ✓

---

## 4. Entity architecture 2 — Commercial Business (Business Book)

Owner capital, cash & credit sales, credit purchases, customer receipts, supplier payments, drawings — strictly insulated from personal books. Full worked examples: `worked-examples/business-sharma-textile.md` (golden); `usecases/shop-sukhwinder-sales-co.md`, `usecases/contractor-bal-aluminium-pvc-works.md`, `usecases/farmer-bal-agriculture.md` (one-owner books with a KCC loan account); the practice book `truck-operator-sukhdev-singh-transport.md` (things owned, a vehicle loan — Appendix B).

**Accounts:** Business Bank–HDFC (A, opens 50,000 Dr) · Business Cash (A) · Business Expense (E) · Purchases (E) · Singhania & Co. — customer/debtor (A) · Aggarwal Traders — supplier/creditor (L) · Sales (I) · Capital (Eq, incl. 50,000 opening — the book's `Opening Balance / Capital A/c`, ADR 2026-09-09b §1) · Drawings (Eq-contra, seeded for a *Just me* business, ADR 2026-09-09b §2).

**Transaction types:** capital introduced · bank→cash · **credit sale** · rent · customer receipt UPI/cash · petty cash expense · **credit purchase** · supplier part-payment · **cash sale** · **owner drawings**.

### 4.1 Daybook

| ID | Day | Event | Dr | Cr | ₹ |
|---|---|---|---|---|---|
| B01 | 01 | Owner adds capital | HDFC | Capital | 5,000 |
| B02 | 02 | Cash drawer from bank | Business Cash | HDFC | 1,000 |
| B03 | 03 | Credit sale to Singhania | Singhania | Sales | 40,000 |
| B04 | 04 | Office rent | Business Expense | HDFC | 15,000 |
| B05 | 05 | Singhania pays (UPI) | HDFC | Singhania | 18,000 |
| B06 | 06 | Singhania pays (cash) | Business Cash | Singhania | 12,000 |
| B07 | 07 | Tea/courier/stationery | Business Expense | Business Cash | 1,500 |
| B08 | 08 | Credit purchase — Aggarwal | Purchases | Aggarwal | 25,000 |
| B09 | 09 | Paid Aggarwal (bank, part) | Aggarwal | HDFC | 10,000 |
| B10 | 10 | Cash sale over counter | Business Cash | Sales | 8,000 |
| B11 | 11 | Owner drawing (cash) | Drawings | Business Cash | 5,000 |

B01 is an ordinary **Money in** whose counterpart is `Opening Balance / Capital` (ADR 2026-09-13 §4); B11 is an ordinary **Money out** to Drawings, never an expense (ADR 2026-09-09b §3). The two are one event seen from either end.

### 4.2 Ledger images

**Business Bank–HDFC** (money) — Dr *[Money in]* · Cr *[Money out]*: b/f 50,000 Dr · B01 To Capital 5,000 → 55,000 · B02 By Business Cash 1,000 → 54,000 · B04 By Business Expense 15,000 → 39,000 · B05 To Singhania 18,000 → 57,000 · B09 By Aggarwal 10,000 → **47,000 Dr** c/f.
**Business Cash** (money): B02 1,000 → B06 +12,000 = 13,000 → B07 −1,500 = 11,500 → B10 +8,000 = 19,500 → B11 −5,000 = **14,500 Dr** c/f.
**Singhania & Co.** (customer) — Dr *[Sold on credit ↑]* · Cr *[Payment received]*: B03 To Sales 40,000 → 40,000 Dr · B05 By HDFC 18,000 → 22,000 Dr · B06 By Business Cash 12,000 → **10,000 Dr** c/f.
**Aggarwal Traders** (supplier) — Dr *[You paid]* · Cr *[Bought on credit ↑]*: B08 By Purchases 25,000 → 25,000 Cr · B09 To HDFC 10,000 → **15,000 Cr** c/f.
**Business Expense 16,500 Dr · Purchases 25,000 Dr · Sales 48,000 Cr · Capital 55,000 Cr · Drawings 5,000 Dr.**

### 4.3 Trial balance (figures as machine-verified for v2.0): Dr — HDFC 47,000 · Business Cash 14,500 · Singhania 10,000 · Business Expense 16,500 · Purchases 25,000 · Drawings 5,000 = **₹1,18,000**. Cr — Aggarwal 15,000 · Sales 48,000 · Capital 55,000 = **₹1,18,000**. ✓

---

## 5. Entity architecture 3 — Joint Family (multi-book: the Rukka Folio differentiator)

One family, four independent self-balancing books linked only by **Due to/from** pairs: **Joint Book** (the joint fund — 01 §2, ADR 2026-10-08 §1), **Family-A Book** (a sub-family), **Kirana Book** (a family business), **Amit's Personal Book**. Every inter-book event posts once in each book; the pair must always net to zero (02 §6). Full worked examples: `worked-examples/joint-family-sharma.md` and `joint-business-partnership.md` (golden); `usecases/joint-family-randhawa.md` (sub-family books, three businesses, 47 pairs).

**Use cases demonstrated:** business remits to the joint fund · the fund pays a common expense · monthly allowance to a sub-family · a member pays a family expense from his own pocket · the full **ਐਡਵਾਂਸ (advance) cycle** · a bank crossing zero into overdraft.

### 5.1 Daybooks (all four books)

| ID | Book | Event | Dr | Cr | ₹ |
|---|---|---|---|---|---|
| K01 | Kirana | Remit to Joint pool | Due to/from Joint | Kirana Bank | 50,000 |
| J01 | Joint | (pair of K01) | Joint Bank | Due to/from Kirana | 50,000 |
| J02 | Joint | House repair (common) | House Repair Expense | Joint Bank | 12,000 |
| J03 | Joint | Monthly allowance to Family-A | Due to/from Family-A | Joint Bank | 15,000 |
| F01 | Family-A | (pair of J03) | Family-A Bank | Due to/from Joint | 15,000 |
| F02 | Family-A | Groceries (cash) | Groceries Expense | Family-A Cash | 1,500 |
| P01 | Amit personal | Pays Family-A electricity from own cash | Due from Family-A | Amit Cash | 2,300 |
| F03 | Family-A | (pair of P01) | Electricity Expense | Due to Amit | 2,300 |
| K02 | Kirana | ਐਡਵਾਂਸ to Ramesh (approved) | Advance–Ramesh | Kirana Bank | 20,000 |
| K03 | Kirana | Ramesh submits repair bills | Shop Repair Expense | Advance–Ramesh | 17,400 |
| K04 | Kirana | Ramesh returns remainder | Kirana Cash | Advance–Ramesh | 2,600 |

Openings: Joint (Cash 10,000 · Bank 40,000 · Opening 50,000 Cr) · Family-A (Cash 2,000 · Opening 2,000 Cr) · Kirana (Bank 60,000 · Opening 60,000 Cr) · Amit (Cash 5,000 · Opening 5,000 Cr).

### 5.2 Key ledger images

**Kirana Bank A/c** (money) — Dr *[Money in]* · Cr *[Money out]* — **watch the side flip:**

| Date | Particulars | Dr | Cr | Balance | Side |
|---|---|---|---|---|---|
| 01 Aug | Opening balance b/f | — | — | 60,000 | Dr |
| 05 Aug | By Due to/from Joint | — | 50,000 | 10,000 | Dr |
| 09 Aug | By Advance–Ramesh | — | 20,000 | 10,000 | **Cr** |
| 31 Aug | Closing balance c/f | — | — | **10,000** | **Cr — overdraft (you owe the bank)** |

**Advance–Ramesh A/c** (ਐਡਵਾਂਸ) — Dr *[Handed out]* · Cr *[Bills settled / returned]*

| Date | Particulars | Dr | Cr | Balance | Side |
|---|---|---|---|---|---|
| 09 Aug | To Kirana Bank *(disbursed)* | 20,000 | — | 20,000 | Dr |
| 17 Aug | By Shop Repair Expense *(bills)* | — | 17,400 | 2,600 | Dr |
| 21 Aug | By Kirana Cash *(returned)* | — | 2,600 | 0 | — |
| 31 Aug | Closing balance c/f | — | — | **0** | closed |

**Joint Bank**: b/f 40,000 → +50,000 = 90,000 → −12,000 = 78,000 → −15,000 = **63,000 Dr**. **Family-A Cash**: 2,000 → −1,500 = **500 Dr**. **Due to/from Amit** (in Family-A): **2,300 Cr** — *the family owes Amit*, shown on his position as money to receive.

The Kirana Bank overdraft is deliberate teaching: a bank account may sit Cr and the side flips with no special handling (02 §1.2; §7). A *cash* account going negative is a different thing — always a missing entry (02 §9).

### 5.3 Trial balances (each book balances alone — figures as machine-verified for v2.0)
- **Joint:** Dr — Bank 63,000 · Cash 10,000 · House Repair 12,000 · Due Family-A 15,000 = **1,00,000** · Cr — Due Kirana 50,000 · Opening 50,000 = **1,00,000** ✓
- **Family-A:** Dr — Bank 15,000 · Cash 500 · Groceries 1,500 · Electricity 2,300 = **19,300** · Cr — Due Joint 15,000 · Due Amit 2,300 · Opening 2,000 = **19,300** ✓
- **Kirana:** Dr — Due Joint 50,000 · Cash 2,600 · Shop Repair 17,400 = **70,000** · Cr — Bank (OD) 10,000 · Opening 60,000 = **70,000** ✓
- **Amit personal:** Dr — Cash 2,700 · Due from Family-A 2,300 = **5,000** · Cr — Opening 5,000 = **5,000** ✓

### 5.4 Family Reconciliation (the only cross-book check that exists or is needed)

| Pair | Book 1 says | Book 2 says | Net |
|---|---|---|---|
| Joint ↔ Kirana | Due to Kirana 50,000 Cr | Due from Joint 50,000 Dr | **0** ✓ |
| Joint ↔ Family-A | Due from Family-A 15,000 Dr | Due to Joint 15,000 Cr | **0** ✓ |
| Family-A ↔ Amit | Due to Amit 2,300 Cr | Due from Family-A 2,300 Dr | **0** ✓ |

A pair whose other side sits in a book the reader cannot open is shown *one-sided · unconfirmed*, never as a mismatch (ADR 2026-09-05e §7). On a printed reconciliation the true side is shown with the plain words in brackets (ADR 2026-10-10b §4; use-case README §7 item 6).

---

## 6. Entity architecture 4 — Trust / Organization (Trust Book)

Non-profit: no commercial profit; inflows are donations, and the year's surplus or deficit is **presented under Corpus** as a computed line — never closed to it by an entry (02 §1.2; ADR 2026-09-05e §2; Appendix D, F-5). Trustee advances are per-person **Advance sub-accounts** — never tags inside Cash — so every movement stays a real journal entry (Appendix D, F-4). The collection box is its own `cash_collection` account beside a plain Cash A/c: a count recognises income on the box, and the box empties only by Transfer to cash or bank (02 §8.2; ADRs 2026-09-02, 2026-09-03). Full worked examples: `worked-examples/trust-singh-sabha-gurudwara.md` (golden; its gollak postings predate 02 §8.2's rulings — use-case README §7 item 1); `usecases/trust-radha-soami-satsang-sabha.md`; the practice book `committee-guru-nanak-welfare-committee.md` (Appendix B).

**Accounts:** Gollak Cash (money · cash_collection) · Trust Cash (A) · Trust Bank–SBI (A) · Advance–Assistant A (A/ਐਡਵਾਂਸ) · Langar Expense (E) · Donation Income (I).

### 6.1 Daybook

| ID | Day | Event | Dr | Cr | ₹ |
|---|---|---|---|---|---|
| T01a | 01 | Gollak opened and counted (counter and witness named) | Gollak Cash | Donation Income | 20,000 |
| T01b | 01 | Counted cash moved to the cash box [Transfer] | Trust Cash | Gollak Cash | 20,000 |
| T02 | 02 | Sponsor donation (UPI) | Trust Bank | Donation Income | 15,000 |
| T03 | 03 | ਐਡਵਾਂਸ to Assistant A for langar | Advance–Asst A | Trust Cash | 5,000 |
| T04 | 04 | A submits vegetable bills | Langar Expense | Advance–Asst A | 2,000 |
| T05 | 05 | LPG cylinder paid (bank) | Langar Expense | Trust Bank | 3,200 |
| T06 | 06 | A returns part cash | Trust Cash | Advance–Asst A | 1,000 |

v2.0 drew T01 as one posting straight to Trust Cash; v3 shows the count and the deposit as the two postings 02 §8.2 prescribes. Gollak Cash nets to zero and every other figure is unchanged (Appendix D).

### 6.2 Ledger images

**Advance–Assistant A** — Dr *[Handed out]* · Cr *[Bills settled / returned]*: T03 5,000 → T04 −2,000 = 3,000 → T06 −1,000 = **2,000 Dr** c/f — *still with Assistant A, ageing since 03rd; the position screen shows "Cash ₹16,000 · with Asst A ₹2,000".*
**Gollak Cash**: T01a 20,000 → T01b −20,000 = **0** (nothing left in the box). **Trust Cash**: 20,000 → −5,000 = 15,000 → +1,000 = **16,000 Dr**. **Trust Bank**: 15,000 → −3,200 = **11,800 Dr**. **Langar Expense**: 2,000 → 5,200 = **5,200 Dr**. **Donation Income**: 20,000 → **35,000 Cr** (shown as Donation Income mid-period; presented under Corpus on the Position as a computed line, never closed by an entry — Appendix D F-3, F-5 / ADR 2026-09-05e §2).

### 6.3 Trial balance (figures unchanged from v2.0, where they were machine-verified): Dr — Cash 16,000 · Bank 11,800 · Advance–A 2,000 · Langar 5,200 = **₹35,000** · Cr — Donation Income **₹35,000** ✓

The year-end statements of an organization book are the **Income & Expenditure Account** and the **Position** with the make-up of the Corpus (§15; ADR 2026-10-11 §6). Purpose funds and corpus donations are **D11** (§12.10); whether the Corpus line also shows a restricted/unrestricted split is ADR 2026-09-05e Open 1, for the owner at bookkeeper sign-off.

---

## 7. Zero-crossing inversions (placement-by-sign)

| Context | Crossing zero means | Professional label | Display (EN / ਪੰਜਾਬੀ / हिन्दी) |
|---|---|---|---|
| Bank (asset) drops past zero | Overdraft | Current liability — Bank OD | You will give · ਦੇਣੇ ਹਨ · देने हैं |
| Debtor overpays you | Advance from customer | Current liability | You will give · ਦੇਣੇ ਹਨ · देने हैं |
| You pre-pay a creditor | Advance to supplier | Current asset | You will get · ਲੈਣੇ ਹਨ · लेने हैं |

Balances never wear a minus sign on professional surfaces — the **side flips** (live example: Kirana Bank, §5.2). On the Home position card (07 §4) a money account in credit stays in the money list with its sign and is subtracted from *Total money you have*; a party in credit moves to *You will give*. Both are the same rule: placement by sign, no reclassification (02 §1.2).

**Negative balances, stated once.** A `cash` account below zero is legal but always a missing entry — it warns (02 §9; ADR 2026-09-05e §12). Bank subtypes, cards, OD and loan accounts may sit Cr: that is an overdraft or a debt, shown as such, and does not warn. A `cash_collection` account cannot go below zero by construction (it empties only by Transfer of what was counted, 02 §8.2).

> ⚠️ **OWNER DECISION D16b — should a savings or current account also warn when it goes negative?** 02 §9 warns on `cash` only. The use-case set adopts a stricter policy for itself — *no cash, collection, savings or current account is negative after any posting* (use-case README §8) — while v2.0 §5.2 deliberately shows a savings account overdrawn. *Audit recommends (T16):* keep the rule above — cash warns, bank subtypes may sit Cr and show under *You will give* — and treat the use-case policy as a modelling choice, not a rule. No 🔒 line changes either way.

## 8. Multi-party split vouchers
One voucher, n lines, Σ Dr = Σ Cr. Example: ₹50,000 langar provisions = Dr Langar Expense 50,000 · Cr Cash 20,000 · Cr Trust Bank 20,000 · Cr Aggarwal Traders 10,000. Engine-supported (02 §1.4); the use-case trust book carries twelve such vouchers (README §4, *standards §8*). A split-payment **entry screen** was an open product item in v2.0 and its status was not re-verified for v3.

## 9. Integrity rules
1. **Atomicity** — a multi-line entry commits whole or not at all (one envelope).
2. **No raw negatives to the UI layer** — signed math internally; absolute value + side tag on professional surfaces.
3. **Month lock** — post-lock corrections only via dated reversal/adjustment entries; history is immutable (02 §5/§8).
4. **Shape** — every `kind`'s lines match its class-shape, re-checked by every reader; a violation is quarantined, never summed (02 §1.4 rule 7; ADR 2026-09-05e §6). The shapes as the engine reads them are listed in §12.1.
5. **Sum to zero, integer paise, in-book accounts** — 02 §1.4 rules 1–3, property-tested across every verb (09 suite A).

---

## 10. Status, precedence and governance

- **What is golden.** The gate v2.0 §10 described — *§3–§6 freeze as golden fixtures* — was transferred to the worked examples by ADR 2026-09-05i §3. The engine's golden fixtures are the five files at `docs/reference/worked-examples/` (`A-ref-1…7`, `golden_worked_examples_test.dart`), provisional until bookkeeper sign-off, with the use-case set becoming golden on the three conditions of ADR 2026-10-12 §3 (`A-ref-8/9`, ADR 2026-10-11 §5). No test replays §3–§6 of this standard; unit tests cite single postings from it (`capital_test.dart` B01, `drawings_test.dart` B11).
- **Precedence.** ADRs, newest first → 02 (ledger semantics), 01 (terms), 07 (screens), 13 (UX) → this standard and the worked examples → `requirements-architecture.md` (background only). When 02 and a worked example appear to disagree, stop and ask (CLAUDE.md § Accounting authority).
- **Amendments.** Every ADR that changes what this standard says is folded in at the section it affects with a `> **ADR …** —` block, and listed in Appendix E. "Is this ADR already in?" is a lookup there.
- **Open questions** are ⚠️ OWNER DECISION boxes, indexed in §17. Each gives the audit's recommendation (audit of 12 Oct 2026, §4.1 and §5d) and the conservative reading until ruled. None is decided here.

---

## 11. Books, charts and openings

### 11.1 Books per user type
A book is an independent, self-balancing ledger with its own chart, financial year and locks; books never nest and connect only through Due to/from pairs (02 §1.1, §6). The flow never changes with the entity, only the count of books (00 bet 1):

| User | Books | Type (`BookType`) |
|---|---|---|
| individual | one personal book | `personal` |
| shop, contractor, farmer, truck operator, landlord | one business book, *Just me* (Drawings seeded) | `business` |
| partnership | one business book, *Shared with others* (one Partner Current per owner) | `business` |
| joint family | a joint fund book + a book per sub-family + a book per business, linked by pairs | `joint`, `family`, `business` |
| trust, society, committee (kameti) | one organization book (gollak seeded, denomination counts mandatory) | `organization` |

### 11.2 When a side activity becomes a book
v2.0 §3 keeps an informal side activity inside the personal book (*Business Bank*, *Business Expense*); the use-case set gives the same person two books linked by an owner loan (`usecases/individual-jasvinder-singh.md`). Both are right for their case. Guidance: a side activity stays inside the personal book while it has no money of its own to answer for; it becomes its own book when it needs its own position, its own parties on credit, its own month close, or has more than one owner. Once it is a book, the owner's money moving in or out is a 02 §6 pair (or capital introduced / drawings, §11.5) — never income or expense in either book.

### 11.3 The seeded chart
Created with the book from the setup answers (ADR 2026-09-09c §1): every book seeds its cash account (`Cash A/c`, `Business Cash A/c`, `Joint Cash A/c`; a trust seeds `Cash` and `Gollak Cash`), its `Opening Balance / Capital`, and the category tree for its type; a *Just me* business adds `Drawings A/c` (ADR 2026-09-09b §2); a *Shared* business adds `Profit Distributed` and one `{Name} — Partner Current A/c` per owner. **No bank is ever seeded** — a bank arrives through *Add an account* and asks its opening balance (ADR 2026-09-09d §1). **No party is ever seeded** — customers and suppliers appear inline as they are traded with (02 §1.2; ADR 2026-09-09c §1). Due to/from accounts are never typed; a pool book gains one per linked book automatically (02 §6). The seeded chart is a floor, not a guess (ADR 2026-09-09d §3). The category names per book type are Appendix A.

### 11.4 Opening balances and the start date
- Every new account asks for its opening balance at creation, phrased by class and never as Dr/Cr (02 §4): money — *balance today* (negative = overdraft); party — *do they owe you, or do you owe them?* plus the amount; expense and income — nothing, they start the FY at zero. The per-type question is the catalogue column in §1.7.
- Each answer posts one `adjustment` against `Opening Balance / Capital`; individual openings need not net to zero — **Opening Balance / Capital absorbs the difference, and that is correct** (02 §4; ADR 2026-09-09c §4).
- A book carries an **immutable start date**; openings are dated there and nothing is dated before it (ADR 2026-09-09d §4). The books begin at the start date: an asset that matured straight into a bank account before it is never on the books (use-case README §6).
- **Shared business:** each owner's opening contribution posts `Dr money · Cr {owner} — Partner Current A/c`; it is asked, never derived from the ratio, and `Opening Balance / Capital` carries only the difference (ADR 2026-09-09c §4; use-case vouchers BF-004…006, RB-005…006).
- An account created inline during an entry asks **afterwards**, on its statement — *Opening balance not set · Add opening balance / Not needed* — and the account carries `opening: "pending"` until answered (ADRs 2026-10-07b, 2026-10-10c). Corrections after the fact go through *Settings → Your books → Opening balances* (ADR 2026-09-03b ruling 2).
- Re-running setup corrects amounts, never the date (ADR 2026-09-09d §4).

### 11.5 Capital introduced and owner takeout
- **Capital introduced is an ordinary Money in:** `Dr money · Cr Opening Balance / Capital`, never income (ADR 2026-09-13 §4; §4.1 B01). The *Capital* tile of the add-account grid opens this entry with Capital preselected; it never creates an account (ADR 2026-10-12 §6, build pending).
- **Owner takeout is an ordinary Money out:** `Dr Drawings · Cr money`, never an expense (ADR 2026-09-09b §3; §4.2 B11). In a shared business the same event is `Dr Partner Current · Cr money` (02 §7.1).
- The receiving side — what the owner's *personal* book records — is **D13** (§12.9).

---

## 12. Everyday transactions

### 12.1 The six verbs, and the shapes as the engine reads them
The user answers plain questions; the app builds the lines (02 §2). Party-facing verbs resolve against the existing balance — paying ₹500 to a party you owe ₹2,000 simply reduces the payable. Verbs 3 and 4 with the *money* answer overlap verbs 1 and 2 with a party: same posting, two doors, both kept (02 §2).

| # | Verb | Posting |
|---|---|---|
| 1 | Money in | Dr money · Cr income head, **or** Cr party |
| 2 | Money out | Dr expense head **or** Dr party · Cr money |
| 3 | Gave on credit | Dr party · Cr money **or** Cr income head |
| 4 | Took on credit | Dr money **or** Dr expense head · Cr party |
| 5 | Transfer (*Move money*) | Dr to-account · Cr from-account — cash↔bank, bank↔bank, card and loan payments; across books, a 02 §6 pair |
| 6 | Adjustment (guided only) | exactly one `equity_system` counter-account, or the reversed entry's mirror — openings, cash-count differences, write-offs, reversals |

Every row is a reader-enforced invariant (02 §1.4 rule 7). The engine's `checkShape` (`packages/core_ledger/lib/src/invariants.dart`, read 12 Oct 2026) admits slightly more than 02 §1.4 rule 7 writes down — `money_in` credits may also be an `advance` (remainder returned) or the Opening Balance / Capital account (capital introduced); `money_out` debits may also be an `advance` (disbursed) or Drawings, and its credits an `advance` (spent against) or a Due to/from account (the payee half of a pocket expense); `transfer` lines are money or Due to/from, never Due on both sides; `partner` is treated as party-like throughout; `adjustment` needs exactly one `equity_system` account.

> ⚠️ **OWNER DECISION D8 — write the advance, partner and link shapes into 02 §1.4 rule 7.** The rule lists six shapes with no `advance`, `partner` or Due to/from word, while the engine admits them and the use-case set labels its vouchers the same way (README §5 S1–S4: advance request and spend `money_out`, return `money_in`, write-off `adjustment`; own-pocket `took_credit`, takeout `money_out`, appropriation `adjustment`; pocket-expense payer half `transfer`, payee half `money_out`; Suspense cleared by one `adjustment`). *Audit recommends:* ratify the engine's current reading and S1–S4 as written, in 02 §1.4 rule 7 (a 🔒 line). *Until ruled:* the engine's reading stands; fixtures compare on class, never on label.

### 12.2 Transfers, cash withdrawals, card payments
A cash withdrawal, a move between two bank accounts, a card bill or a loan instalment from the bank is one event: `Dr to-account · Cr from-account` (verb 5). On import, an opposite line in another own-account within the window asks *"Is this the same money moving between your accounts?"* and one tap posts a single Transfer — un-paired, it is the notebook error of counting the same rupees as both an expense and an income (02 §10). A credit card is `money · cc`, not a party: card spends are Money out from the card account; the bill paid is `Dr card · Cr bank` (02 §1.2, §2 verb 5).

### 12.3 Loans
- **A loan account is optional** (ADR 2026-10-12 §6). The bank keeps the loan's own statement; a user keeps a `money · loan` account only if they want the loan in the ledger.
- **Without a loan account:** the instalment is a Money out to an expense head named for the loan, or to the lender as a party you owe (02 §2 verb 2). The year's result then carries the whole instalment.
- **With a loan account:** the drawdown is a Transfer into the bank; each principal repayment is a Transfer `Dr loan · Cr bank`; interest the bank debits separately is a Money out from the loan account to an interest expense head — the farmer use case keeps a KCC this way (`usecases/farmer-bal-agriculture.md`, vouchers AG-003…045; README §4 *money subtypes*). The loan's A/C statement then reads like the bank's loan statement. Interest is an expense of the period it is charged for, on a time basis (ICAI AS 9 para 13(i), Appendix G).
- **A private loan from a person** is a party balance in credit (row 9), repaid by Money out to that party.

> ⚠️ **OWNER DECISION D-opt-3 — one bank line holding principal and interest.** Ruled *optional, off by default* (ADR 2026-10-12 §6). Open: whether and when to build a *Loan payment* that posts `Dr loan (principal) · Dr interest expense · Cr bank` as one entry — today no `kind` admits a money debit beside an expense debit (`checkShape`). The practice truck book splits every EMI *as the lender's statement splits it* (`truck-operator-sukhdev-singh-transport.md` accounts 13 and 28). *Audit recommends:* build it only for users who keep a loan account; never auto-split.

> ⚠️ **OWNER DECISION D15 — interest on hand loans (sood, arhtiya interest).** Parked in the roadmap (10, *Interest on hand loans*). Representable today as *Gave on credit → income head "Interest"* (02 §2 verb 3), with no computation. *Audit recommends (T14):* a posting rule plus an optional simple-interest calculator (Actual/365, like 02 §7.1), never auto-posted. The use-case farmer book does not post Sodhi & Sons' sood (README §6).

### 12.4 Things owned, at cost (ruled 12 Oct 2026, build pending)
- A thing owned that is neither money nor a person — a truck, land, gold, a security deposit paid to an unnamed body — is an **`asset`** account, shown **at cost** under *What I have* and never inside *Total money you have* (ADR 2026-10-12 §6; ICAI AS 10 paras 7, 17 for recognition at cost — Appendix G). Until the class is built, a construction is an expense and an FD is off the books — the use-case trust book says so (README §5 S9, §6).
- Postings proposed for the build slice (not yet ruled in 02): bought — `Dr asset · Cr money` (or `Cr party` when bought on credit); sold — `Dr money · Cr asset` for the cost, with any difference to an income or expense head; opening — one adjustment at cost against Opening Balance / Capital, like every other opening (02 §4). The practice truck book shows the shape: *Truck 1 at what it cost*, *Truck 2 — chassis, registration and body building* (`truck-operator-sukhdev-singh-transport.md` accounts 11–12).
- **A security deposit held from a named person** (a tenant, a customer) is kept in **its own account, one per person** — *Deposit held – {person}*, a liability, shown on that person's page beside their khata — and never netted against what the same person owes until it is actually set off or returned (owner, 13 Oct 2026; ADR 2026-10-12 §14; §1.7.2 row 23). The landlord and Randhawa Real Estate practice books keep tenants' deposits this way. **A security deposit paid to a named person** (the shop's landlord, a supplier) is likewise its own account, one per person — *Deposit paid – {person}*, an asset (money you will get back), shown under *What I have* and never netted against what you owe that person (owner, 13 Oct 2026; §1.7.2 row 33). The shop practice book keeps its landlord's deposit this way.

> ⚠️ **OWNER DECISION D-opt-1 — depreciation.** Ruled *optional, off by default* (ADR 2026-10-12 §6). Open: whether to offer, once `asset` lands, an optional year-end adjustment `Dr Depreciation expense · Cr asset` at a rate the user types, book value only (ICAI AS 10 paras 50, 52). *Audit recommends:* off by default; never a tax computation.

### 12.5 Parties — udhaar both ways, bills on credit, deposits, write-off
- One party, one account, both roles; the sign places it under *You will get* or *You will give* (02 §1.2). Udhaar given and taken, bills on credit, part payments and overpayments all post to that one account (02 §2 verbs 1–4); a crossing of zero flips the side (§7).
- **Ageing**: party chips at 30 and 90 days (07 §7); the use-case set reads settlement as FIFO (README §5 S6) — a reading, not a rule.
- **Deposits**: one held from a named person is its own *Deposit held – {person}* account, one paid to a named person its own *Deposit paid – {person}* account; neither is netted against the khata (§12.4).
- **Write-off of a party balance — ruled 12 Oct 2026 (ADR 2026-10-12 §8), takes effect with its build slice.** A party balance that will never be paid posts to a seeded **expense head, *Written off***, so the loss shows in the year's income and expenses. Today 02 §2 verb 6 and 01 §2 route it to Adjustments (`equity_system`), which keeps the loss out of the year's result; the build slice updates 02 §2 verb 6 and the tests that assert today's posting. **An advance write-off stays on Adjustments** (02 §7), unchanged. *Recovery after a write-off* is not ruled; the conservative reading until it is: reverse the write-off (02 §5) and post the receipt as Money in from the party. The audit (T8) recommends a *Recovered* income head.

### 12.6 Advances (ਐਡਵਾਂਸ)
The one place approval moves money (02 §7): request → on approval `Dr Advance – {member} · Cr money`; spending `Dr expense head · Cr Advance`; remainder `Dr money · Cr Advance`; open while > 0, aged from the oldest unsettled debit, reminders at 15/30 days; write-off (never repaid) `Dr Adjustments · Cr Advance`, approver-only, reason required; settlement is the precondition for member removal. Advance = unexplained money *with a responsible person*; Suspense = unexplained money with none (01 §2).

> ⚠️ **OWNER DECISION D12 — advances to people who are not app members** (drivers, sevadars, site staff). `advance` is per member per book (02 §1.2, §7); a non-member today becomes a `party` with no approval gate and no ageing reminder. The practice truck book keeps *Trip Advance – {driver}* accounts. *Audit recommends (T11):* allow `Advance – {named person}` for non-members — same class, `memberId` null — so ageing and the settlement gate apply.

### 12.7 Partners (02 §7.1)
One Partner Current A/c per owner holds the whole relationship: a cost paid from their own pocket `Dr Expense · Cr Partner Current`; a takeout `Dr Partner Current · Cr money`; a profit share `Dr Profit Distributed · Cr Partner Current` — one multi-line entry per distribution that moves no cash. Contribution never changes the sharing ratio; the ratio lives in `book_config.partner_shares` and changes only by the structural action of 02 §7.2.1 (ADR 2026-09-14b). Interest on capital is optional, Actual/365, half-up to the paisa, credited first; the remainder splits by `floor(amount × weight ÷ Σweights)` in paise with the remainder to the largest ratio (02 §7.1). Losses mirror the posting; cumulative distributions never exceed accumulated surplus (ADR 2026-09-05e §8). Debit balances are real and shown plainly. The full illustration is `usecases/partnership-bal-fabricators.md` (appropriation BF-183) and the golden `joint-business-partnership.md`.

> ⚠️ **OWNER DECISION D7 — partner-to-partner settlement (02 §7.1 route 2) cannot be posted.** 02 §7.1 prescribes `Dr {over-funded partner} · Cr {under-funded partner}` — two `partner` lines with no money line and no `equity_system` line — and `checkShape` admits no such shape (`invariants.dart`, read 12 Oct 2026). The use-case set avoids it (README §6). *Audit recommends (T9):* add a `partner_settlement` shape (two partner lines, no money), reader-checked — a 🔒 rule must be postable. Touches 🔒 lines in 02 §1.4 rule 7 and §7.1.

> ⚠️ **OWNER DECISION D14 — partner remuneration, interest on drawings, debit-balance interest.** 02 §7.1 has interest on capital and the share, no remuneration and no interest on drawings; a debit balance is *charged at the same rate unless the setting says otherwise ⚠️* (ADR 2026-09-05e Open 2). The use-case set chose *credit balances only* (README §5 S7). *Audit recommends (T13):* remuneration as a second tagged appropriation line through the same structural-setting path as interest; interest on drawings off by default; rule debit balances *credit-only*. Absent a deed the textbook defaults are no interest on capital and 6 % on a partner's loan (NCERT Class 12, partnership; chapter not yet confirmed — Appendix G).

> ⚠️ **OWNER DECISION D19 (part) — a ratio changed mid-year.** ADR 2026-09-14b leaves pro-rating open. *Audit recommends:* the ratio in force at the distribution governs the whole amount unless the deed says otherwise.

### 12.8 Inter-book pairs (02 §6)
One action, two envelopes sharing `transfer_group`: `Dr Due to/from B · Cr money` in A and `Dr money · Cr Due to/from A` in B; both post at once, a half the actor may not post in carries the review flag and shows *in transit*. A member paying a family expense from his own pocket is the same mechanism (`Dr Due to/from Family · Cr Cash` / `Dr Expense · Cr Due to/from Member`). The Family Reconciliation report is the only cross-book check: every pair nets to zero, and a side the reader cannot open shows *one-sided · unconfirmed* (ADR 2026-09-05e §7). **Naming:** the engine's account is `Due to/from {Book}`; the use-case set names the account after the other book and its type, by owner ruling for that set (ADR 2026-10-11 §4) — the class and placement are unchanged. Business surplus remitted to the joint fund is a pair, never a drawing and never income (02 §7.1).

### 12.9 Owner's takeout — the receiving side
The business side is settled: Drawings (*Just me*) or Partner Current (*Shared*), §11.5. What the owner's **personal** book records when the money arrives is not ruled; the use-case set avoids it (README §6).

> ⚠️ **OWNER DECISION D13 — the receiving side of a takeout; drawings in kind.** *Audit recommends (T12):* in the personal book, *Money in from {Business}* against the business's link or party account — never income; goods taken for own use as a guided *Drawings in kind* `Dr Drawings · Cr purchases head`, which needs a category credit the shapes do not admit today. Also ADR 2026-10-11 Open 4.

### 12.10 Trust and committee specifics
- **The gollak** (02 §8.2): a count on a `cash_collection` account *recognises income* for the full amount, with counter and witness named; a count never moves money; the box empties only by Transfer to the Cash A/c or a bank, in one deposit or several; nothing is ever paid straight from it; every organization book also seeds a plain Cash A/c. Denomination sheets are mandatory on every cash count in a trust book.
- **Donations** are income heads (*Donation A/c*, *Dairy Donation A/c*, *Bhent A/c*…); a receipt card is next phase (ADR 2026-09-25 §7). Donations **in kind** are not ruled — record as a memo note, or at a value only if the committee values them; nothing posts without an owner ruling.
- **Honoraria and wages**: a sevadar or labourer paid in full each month is an expense head, not a party; a party is needed only if wages are left owing at a month end (ADR 2026-10-11 §6).
- **The Corpus** is a computed line (§15.4). A trust's year-end statements are the Income & Expenditure Account and the Position (ADR 2026-10-11 §6); a Receipts & Payments account is **D9/D10** (§15.3).

> ⚠️ **OWNER DECISION D11 — corpus donations and purpose funds** (a building fund, a langar fund, a *Community Hall Fund*). Every donation is income today and Corpus = Σ surpluses; funds are a post-pilot candidate (ADR 2026-09-25 §8; ADR 2026-09-05e Open 1). The practice committee book keeps a *Community Hall (Dharamshala) Fund* with receipts, spending and a balance (`committee-guru-nanak-welfare-committee.md` §5). *Audit recommends (T10):* phase 1, a *Corpus donation* income head flagged *not part of the year's result* and added to Corpus directly; phase 2 after the pilot, purpose funds. Touches a 🔒 line in 02 §1.2.

> ⚠️ **OWNER DECISION D19 (part) — a kameti (chit) case.** Deliberately absent from the use-case set (ADR 2026-10-11 §3); the Chit Funds Act 1982 defines discount, dividend and prize (Appendix G). *Audit recommends:* one worked kameti case once the *Written off* head lands, written the way a committee keeps it.

---

## 13. Statement import and bank reconciliation

### 13.1 The import loop (02 §10; 07 §11)
Pick the bank A/C → pick the file (PDF, with its password asked once and never stored; CSV; XLS; a photo or screenshot read on the phone — ADR 2026-09-25 §3) → confirm the column mapping, remembered per bank → duplicates skipped before anything is shown (hash of account, date, amount, normalised description, per-file ordinal) → **balance check**: the statement's opening and closing against the ledger for those dates → the inbox, one question per line (*Where did it come from? / Where did it go?*) with the states *Matched · Suggested · New · Transfer? · Suspense* → **preview** of every entry about to post → submit. Nothing readable leaves the phone. The bank's text is stored verbatim as evidence and never edited; the user's own note is optional and additive; a row shows the note, else the bank text in muted monospace (02 §10 *Narration*). A line whose counterpart is unknown posts `Dr/Cr Bank · Cr/Dr Suspense` — unexplained for a while, never unrecorded — and Suspense must reach zero before the month locks (02 §8 step 3). Clearing Suspense: one guided adjustment `Dr Suspense · Cr {counterpart}` carrying the same `import_line` is the use-case set's reading (README §5 S4); a reversal plus a fresh entry is also legal — **D8** covers the choice.

### 13.2 Pairing window and matching tolerances

> ⚠️ **OWNER DECISION D17 — the numbers.** 02 §10 says *amount equal, date within window* for a transfer pair and *amount within date window ± party/note fuzz* for a match, and gives no numbers. *Audit recommends (T17):* fix the defaults here — a ± 3-day window; exact amount for a pair; for a match, exact amount and a normalised party or note token in common — and let a learned rule widen them per bank. No 🔒 line changes.

### 13.3 Bank reconciliation at month close — ruled 12 Oct 2026 (ADR 2026-10-12 §7), takes effect with its build slice
Before a month is locked, each bank account can be matched against the bank statement. It is a **view over import-inbox state, with no engine change**, and it extends 02 §8 step 2, which today confirms the bank balance only by reference to the bank's app:

- **book balance ± unmatched items = statement balance.** The screen lists statement lines not yet in the book (deposits and charges the user has not recorded) and book entries the statement does not show (cheques issued and not presented, transfers the bank has not run yet) — the timing differences of a classical Bank Reconciliation Statement (ICAI BoS, Appendix G).
- A difference that is a missing entry is answered with the one question (§13.1); a timing difference is simply shown. The lock does not wait for a timing difference; it waits for Suspense to reach zero.
- The statement is for the user and the accountant; it never posts anything by itself.

---

## 14. Periods, close and year end

### 14.1 Month close (02 §8)
Periods are calendar months inside the book's FY; a lock is a signed envelope and so is an unlock. The wizard: (1) **count the cash** — a figure or the denomination sheet (02 §8.2); a difference posts one guided adjustment to Adjustments with the count attached; (2) **confirm each bank balance** — against the bank's app or statement; differences open the reconciliation of §13.3 (ruled, build pending); (3) **clear the tray** — open review flags, Suspense lines and `pending` advance requests block; aged advances and unverified counts warn; an author-sequence gap or a `held` envelope blocks, and the lock waits until every writing phone is clear for the month (ADR 2026-09-27b); (4) **confirm & lock** — the close records the declared balances and the balance-vector hash that every other device recomputes. Late arrivals (authored before the lock, synced after) count in every live balance and sit in a tray for the closer, who re-dates them (default) or re-opens the month (admin, logged) (ADR 2026-09-05e §3).

### 14.2 Year close and carry-forward (02 §8.1; ADR 2026-09-05e §2)
The ledger is continuous: money, party, advance, partner and equity_system balances carry across 31 March by themselves. The **Year Close ceremony** certifies them: preconditions (every month locked, Suspense 0, no open flag, no pending advance, no gap or held envelope; businesses are prompted to distribute profit first) → the closer's device computes the **closing balance vector** — every balance-sheet account restricted to entries dated on or before the FY's last day, regardless of when they synced; category accounts are **not** carried, the year's net surplus or deficit is one line → every member's device recomputes and verifies → the year is `closed` and the vector is the **certified opening b/f** of the new FY. There is **no closing entry**: income and expense heads start the new year at zero because P&L is computed per FY, not because anything was posted (02 §1.2). *Prior-year corrections* post as reversals dated in the open FY; a closed year's certified opening and its printed reports never change. *Reopening* a month of a closed year voids that year's certificate and every later one, admin-only, logged, and re-closing is in order. After a close, live balances are *certified vector + current-FY entries*.

### 14.3 Profit distribution at year close (02 §7.1)
Net profit for the FY = that year's income − expense − distributions already posted in the year (`netProfit`, ADR 2026-09-05e §8). Order: interest on capital first (if enabled), then the remainder by ratio; the preview shows both lines per partner before anything posts; cumulative distributions may never exceed accumulated surplus; a loss mirrors the posting. Settlement after distribution: *business pays out*, *partner-to-partner* (**D7** — not postable today), or *carry forward* — the default, certified by the year close.

### 14.4 What goes into the year's result
The engine computes the result from income and expense heads dated in the FY (`netProfit`); **Accumulated surplus / Corpus** = Σ certified net results + opening equity − distributions (`accumulatedSurplus`; ADR 2026-09-05e §2). Adjustments and Suspense are `equity_system` accounts the formula does not name, so the projector leaves them out and shows them as their own lines (`projection.dart`, ⚠️ SPEC noted in code). The use-case and practice books print *Adjustments A/c (cash differences, write-offs)* as a line in the make-up of the surplus (§15.4), which is the honest presentation of that gap.

> ⚠️ **OWNER DECISION D16a — cash short / cash over inside the year's result.** A cash-count difference posts to Adjustments (02 §8 step 1) and never reaches the result. *Audit recommends (T15):* post count differences to a *Cash short / Cash over* pair of expense/income heads, so the year's result carries them, and keep Adjustments for opening corrections and member write-offs only; this closes the ⚠️ SPEC in `projection.dart`. Touches 🔒 lines in ADR 2026-09-05e §2 and 02 §8 step 1.

> ⚠️ **OWNER DECISION D-opt-2 — accruals, prepaid and outstanding items at the year end.** Ruled *optional, off by default* (ADR 2026-10-12 §6). Accrual **by party** already exists (a bill taken on credit, 02 §2 verb 4). Prepaid rent, accrued interest receivable or an outstanding bill with no party would need an asset or liability line and a guided year-end adjustment with a day-one reversal (ICAI AS 1, accrual assumption). *Audit recommends:* decide only after the `asset` class lands; off by default.

---

## 15. Year-end statements per book type

Every statement below is a **presentation of figures the engine already computes** — balances, `netProfit`, `accumulatedSurplus`, the certified vector (02 §8.1; 07 §14). No closing entry is posted and nothing new is stored (ADR 2026-10-11 §6). Each book reads in one order, chart and openings → every account's ledger → supporting registers → the closing statements (ADR 2026-10-12 §10; use-case README §1). On a printed statement the words are plain and the true side is a small bracket (ADR 2026-10-12 §2); the use-case and practice books are the reference layouts (Appendix B). There is **no trading account**: closing stock is out of scope (`00-vision.md`).

### 15.1 Closing balances — the trial balance
Two surfaces (02 §8): the always-visible *Books balanced* card on Home, in plain words; and the **Trial Balance** report — every account's closing balance, Dr in one column, Cr in the other, totals equal. After a year close the certified net-result lines follow the chart's accounts so a state seeded from a close still balances (`trialBalance`). Label: *Trial Balance* ਟ੍ਰਾਇਲ ਬੈਲੇਂਸ / ट्रायल बैलेंस (01 §2).

### 15.2 The result for the year, named per book type
Each head shows its **total for the whole year** — the same figure as the *Total for the year* row of its ledger — and the number of entries that made it up; income on one side, expenses on the other; the balancing line names the result.

| Book type | Statement | Balancing line |
|---|---|---|
| personal, family, joint fund | **Income & Expenses** (01 §2 *Income / Expenses* ਆਮਦਨ / ਖਰਚੇ · आमदनी / खर्चे) | *Saved this year* / *Spent more than came in*, carried into Accumulated surplus. The joint fund's statement shows only common spending — business surplus reaches it through pairs, never through an income head (02 §7.1) |
| business, *Just me* | **Profit & Loss Account** (01 §2 ਨਫਾ-ਨੁਕਸਾਨ ਖਾਤਾ / नफ़ा-नुकसान खाता) | *Net profit / Net loss for the year* |
| business, *Shared* | **Profit & Loss Account**, then the **appropriation** beneath it: interest on capital and each partner's share, exactly the lines of the Profit Distributed entry (02 §7.1) | *Net profit*, then *Undistributed* (what stays in Accumulated surplus) |
| trust, society, committee | **Income & Expenditure Account** | *Excess of income over expenditure (surplus) — added to the Corpus* / *Excess of expenditure over income (deficit) — taken from the Corpus* |

A written-off party balance appears here as the *Written off* head once ADR 2026-10-12 §8 is built (§12.5).

### 15.3 Receipts & Payments (organization books)

> ⚠️ **OWNER DECISION D9 / D10 — statements per book type; Receipts & Payments and Income & Expenditure by name in 07 §14; the capital account statement.** 07 §14 lists *Profit/Loss* and *Full Position* and not the organization names or a Receipts & Payments account — the classified cash summary a committee hands its auditor beside the I&E (ICAI BoS ch. 9, Appendix G). The practice committee book prints one: opening cash and bank, every receipt and payment by account with things bought included, closing cash and bank, contra moves left out (`committee-guru-nanak-welfare-committee.md` §5.2). *Audit recommends (T7):* presentation only, no engine change — the statements named in §15.2 for every book type, R&P for organization books, and the capital account reconciliation of §15.5, all joining 07 §14. Touches a 🔒 line in 07 §14.

### 15.4 Position (Full Position, 07 §14) and the make-up of Capital / Accumulated surplus / Corpus
What the book **has** (Dr balances — money, amounts others will pay, advances held, things owned at cost) against what it **owes** (Cr balances — amounts it will pay, bank loans, cards and overdrafts, partners' balances), each account on the side its balance falls (02 §1.2). The difference is **Accumulated surplus** (business, family, personal) or **Corpus** (trust) — a computed line, never a stored account — shown with its **make-up**:

| Particulars | Side |
|---|---|
| Opening Balance / Capital A/c — opening equity and capital introduced | Cr |
| Net result for the year (from §15.2) — profit / surplus Cr, loss / deficit Dr | Cr or Dr |
| Drawings A/c — taken out by the owner (*Just me* business) | Dr |
| Profit Distributed A/c — handed to the partners (*Shared* business) | Dr |
| Adjustments A/c — cash differences, write-offs (§14.4) | Cr or Dr |
| = **Accumulated surplus** / **Corpus** | Cr |

Plain words on the printed page: *What I have / What I owe* (ADR 2026-10-12 §2). A shared business shows each partner's balance on the *owes* side (Cr) or the *has* side (Dr); the equity line is then only opening equity plus what is undistributed.

### 15.5 The capital account, reconciled
For a sole owner the make-up table **is** the capital account statement a bookkeeper asks for: *opening capital + capital introduced + the year's result − drawings = closing capital*. It needs no new figure; it is §15.4 read as one account. Naming it on the report is part of **D9/D10**.

### 15.6 Carry-forward
The certified vector of §14.2 is printed as *FY {next} opening balances b/f* — every money, party, advance, partner and equity_system balance, with the year's net result as one line, and no income or expense head (ADR 2026-09-05e §2). On a printed ledger the year ends *Closing balance c/d · Total · Opening balance b/d* (ADR 2026-09-24b §9).

---

## 16. Reports — cross-reference to 07 §14

07 §14 is the report catalogue and owns each report's screen; this section says which accounting figure each prints. *Built* is as the audit found it on 12 Oct 2026 (`app/lib/features/reports/screens/s8_1_reports_list_screen.dart`): Day Book, Family Reconciliation and Partner positions, with the A/C statement living in the ledger feature as S4; the rest are specified, not built.

| 07 §14 row | What it prints | Engine figure | This standard |
|---|---|---|---|
| Day Book | every entry of the period, newest or oldest first, Money in / Money out | counted entries | 01 §2 *Day Book* ਰੋਜ਼ਨਾਮਚਾ / रोज़नामचा |
| Cash Book | the cash and bank accounts' movements with contra rows | money ledgers | **D18** below |
| A/C statement (any) — S4 | one account for any period: b/f, rows, running balance, c/f (print: c/d · Total · b/d) | `watchStatement(from, to)` | §2; §0 item 4 |
| Trial Balance | every closing balance, Dr / Cr, totals | `trialBalance` | §15.1 |
| You-will-get / You-will-give with ageing | party balances by sign, aged | party balances | §12.5 |
| Profit/Loss (per FY / range) | the result statement of the book type | `netProfit` | §15.2 |
| Full Position | has / owes by sign with the make-up of the surplus or Corpus | balances + `accumulatedSurplus` | §15.4 |
| Advances ageing | open advances and days since the oldest unsettled debit | advance balances | §12.6 |
| Family Reconciliation — S8.3 | every pair and its net; one-sided pairs *unconfirmed* | pair balances | §12.8 |
| Partner positions — S14 | per owner: put in, took out, share, net; settlement capacity in words | partner balances | §12.7 |
| Business comparison (Everything scope) | each business's result side by side | `netProfit` per book | §15.2 |
| *(not in 07 §14)* Receipts & Payments; Income & Expenditure by name; capital account | §15.3, §15.5 | — | **D9/D10** |
| *(not in 07 §14)* Bank Reconciliation Statement | §13.3 — ruled, build pending | import state | ADR 2026-10-12 §7 |

Every report takes a financial year **or any date range**, per scope, and exports as PDF, CSV and XLSX with amount-in-words on the print (07 §14; ADR 2026-09-12). A report is generated only when no entry in its books and period awaits approval (ADR 2026-09-27).

> ⚠️ **OWNER DECISION D18 — Cash Book columns.** In 07 §14 by name only. *Audit recommends (T18):* the two-column cash book — a cash column and a bank column per row, contra entries shown on both sides — as the Day Book's sibling, one page per month, closing with the counted cash of 02 §8 step 1 and the confirmed bank balance of step 2.

> ⚠️ **OWNER DECISION D19 (part) — a contractor's retention money.** Representable today as part of the party balance. *Audit recommends:* show it as a labelled portion of the customer's statement (Appendix B), not a new class.

---

## 17. Open owner decisions — index

Each box above gives the audit's recommendation (audit §4.1, §5d) and the reading taken until the owner rules. None is decided in this standard; D1–D6 were ruled on 12 Oct 2026 (ADR 2026-10-12 §3–§8) and are folded in above.

| Id | Topic | Where | Touches a locked line? |
|---|---|---|---|
| D7 | partner-to-partner settlement shape (02 §7.1 route 2) | §12.7 | yes — 02 §1.4 rule 7, §7.1 |
| D8 | advance / partner / link shapes written into 02 §1.4 rule 7; use-case S1–S4 | §12.1, §13.1 | yes — 02 §1.4 rule 7 |
| D9 / D10 | statements per book type by name; Receipts & Payments; capital account statement | §15.2–§15.5 | yes — 07 §14 (presentation only) |
| D11 | corpus donations and purpose funds | §12.10 | yes — 02 §1.2 |
| D12 | advances to non-members | §12.6 | 02 §7 (per member) |
| D13 | the receiving side of an owner's takeout; drawings in kind | §12.9 | 02 §7.1 shapes |
| D14 | partner remuneration; interest on drawings; debit-balance interest | §12.7 | 02 §7.1 |
| D15 | interest on hand loans | §12.3 | no (roadmap item) |
| D16a | cash short / over inside the year's result | §14.4 | yes — ADR 2026-09-05e §2, 02 §8 step 1 |
| D16b | whether bank subtypes also warn when negative | §7 | no |
| D17 | pairing window and matching tolerances | §13.2 | no (02 §10 gives no numbers) |
| D18 | Cash Book columns | §16 | 07 §14 (presentation) |
| D19 | kameti case; retention money; mid-year ratio pro-rating | §12.10, §16, §12.7 | ADR 2026-09-14b Open |
| D-opt-1 | depreciation (optional, off by default — ruled) | §12.4 | after `asset` lands |
| D-opt-2 | accruals, prepaid, outstanding items (optional, off — ruled) | §14.4 | after `asset` lands |
| D-opt-3 | loan payment with principal and interest in one entry (optional, off — ruled) | §12.3 | 02 §1.4 rule 7 shape |

Also open, outside this standard's scope to decide: the use-case README's readings S1–S12 (ADR 2026-10-12 §3); ADR 2026-09-05e Open 1–3; 02 §12 items 1–5.

---

## Appendix A — Chart of accounts per book type
The seed's **structure** is ADR 2026-09-09c §1 (§11.3). The **names** are `docs/reference/seed-category-trees.md` — a draft, EN only, unratified: household, shop/trade, farm (the fourth tree, owner's yes pending) and trust. Punjabi and Hindi columns come from native review, never translation (01 §1.8). Seeded names are account names the user may rename — content, not UI strings. On ratification the file folds into this appendix and is archived.

## Appendix B — Worked examples: where each rule is shown
All worked examples live under `docs/reference/worked-examples/` (ADR 2026-10-12 §9); this standard points to them and never duplicates them.

| Set | Files | Status | What it exercises |
|---|---|---|---|
| **Golden** (root) | `individual-rahul-sharma.md` · `business-sharma-textile.md` · `trust-singh-sabha-gurudwara.md` · `joint-family-sharma.md` · `joint-business-partnership.md` | the engine's fixture, `A-ref-1…7`; provisional (no bookkeeper sign-off); eleven defects recorded in the use-case README §7, left for the owner (ADR 2026-10-11 Open 2) | five entity types, eight books, 185 vouchers, FY 2026-27; no lock, close, amend, import or Suspense (09 §2) |
| **Use cases** (`usecases/`) | `individual-jasvinder-singh.md` · `shop-sukhwinder-sales-co.md` · `partnership-bal-fabricators.md` · `joint-family-randhawa.md` · `trust-radha-soami-satsang-sabha.md` · `contractor-bal-aluminium-pvc-works.md` · `farmer-bal-agriculture.md`, with `fixtures.json`, `build.py`, `check_md.py` | the exemplar of the printed reports (ADR 2026-10-12 §2–§3); becomes golden on S1–S12 rulings, bookkeeper sign-off and `A-ref-8/9` | a full FY with every month locked and every book closed; every verb; locks, counts, gollak, advances, partners with interest, pairs, import, Suspense, corrections, year close. **README §4** maps every rule to voucher ids |
| **Practice** (`practice/`) | `truck-operator-sukhdev-singh-transport.md` · `committee-guru-nanak-welfare-committee.md` · `landlord-gurdial-singh-sandhu.md`, each with a `.tech.md` companion; `GAPS.md` lists what the rules cannot yet produce | target output written as a bookkeeper keeps those books, not rule-derived; gaps listed for development (ADR 2026-10-12 §10) | things owned at cost and a vehicle loan with the EMI split (truck); purpose fund, FD, Receipts & Payments (committee); tenants' deposits and rent (landlord) |

The folder's `INDEX.md` lists all three sets (ADR 2026-10-12 §9).

The v2.0 cases kept in §3–§6 are teaching illustrations, not goldens.

## Appendix C — Terms
01 §2 is the authority for every word; this standard adds none. Terms this standard uses that 01 §2 does not yet carry, listed for 01 to adopt after native review: **OD · current account · loan account · wallet · thing owned (asset) · Partner Current · Profit Distributed · Adjustments · link (Due to/from) · Written off (head) · Corpus · Accumulated surplus · Income & Expenditure · Receipts & Payments · bank reconciliation · fund**. The plain report words of ADR 2026-10-12 §2 that 01 §2 already holds: *Money in / Money out* (verbs), *You will get / You will give* (debtors / creditors rows), *Cash in hand*, *Opening balance*, *Income / Expenses*; still to add there: *Spent · Received · Total for the year · What I have / What I owe*.

## Appendix D — Corrections applied
From `accounting-audit-errata.md` (archived 12 Oct 2026 at `docs/archive/reference/accounting-audit-errata.md`; its §1–§3 corrected the 30 Aug originals and are complete):

| # | Issue | Disposition in v3 |
|---|---|---|
| F-3 / F-5 | *"Donation Income closes to Corpus only at year end"* — a closing entry, which 02 §1.2 forbids | Folded. §6 and §6.2 now say *presented under Corpus as a computed line, never closed by an entry* (ADR 2026-09-05e §2). Corpus is struck from 02 §1.2's stored-role list the same day |
| F-6 | partnership interest on capital ₹1,355 / remaining ₹5,86,038 | The rule is 02 §7.1: half-up to the paisa → ₹1,354.52 → ₹1,354 displayed; remaining ₹5,86,039. The golden partnership file no longer prints a figure; the use-case set computes every interest line to the paisa (BF-183). Suite A stays un-refrozen until the bookkeeper signs (09 §2) |
| F-7 | equal share of costs stated in rupees (1,11,668 / 1,11,666 / 1,11,666) | The rule is paise: `floor(amount × weight ÷ Σweights)`, remainder to the largest ratio, ties to the earliest account (02 §7.1). The golden file still states rupees at `joint-business-partnership.md` §5 — left for the owner with the other defects of that set (ADR 2026-10-11 Open 2; use-case README §7 item 4) |
| F-4 | advances as cash tags | Per-member `advance` accounts (02 §7); the display idea *Cash ₹18,000 — Vault 15,000 · with A 3,000* adopted (§6.2) |
| v2 §6 T01 | the gollak count and its deposit drawn as one posting to Trust Cash | Split into T01a (count on Gollak Cash) and T01b (Transfer to Trust Cash) per 02 §8.2 and ADRs 2026-09-02 / 2026-09-03; totals unchanged |
| v2 §2 | no note of the printed closing block | ADR 2026-09-24b §9 block added under §2 |
| v2 §10 | *§3–§6 freeze as golden fixtures* | Retired; §10 states the governance of ADR 2026-09-05i §3 |
| golden set defects 1–11 | use-case README §7 | not fixed in that set; owner decision (ADR 2026-10-12 §3 sequencing) |

## Appendix E — Amendments applied (ADR → section)

| ADR | What it changed here |
|---|---|
| 2026-08-30 audit-remediation | post-then-review; the golden README; precedence (§10) |
| 2026-09-02 ratifications | drawings and donation receipt ratified; gollak → Cash; *Trial Balance* transliterated (§6, §12.10, §15.1) |
| 2026-09-03 gollak-deposit-flexibility | the box empties into Cash **or** bank, one deposit or several (§6, §12.10) |
| 2026-09-03b entry doors | the opening-balance correction door (§11.4) |
| 2026-09-05e ledger-time-boundary | balance formula; certified vector as-of, balance-sheet classes only; computed surplus / Corpus (F-5); no b/f on category ledgers; shapes reader-enforced; sealed-book pairs; losses, ceiling, Actual/365; negative cash warns (§2, §6, §7, §9, §12.7, §14) |
| 2026-09-05i test-contract | golden governance; the gate moves to the worked examples (§10) |
| 2026-09-09 shared ownership + FY switcher | `watchStatement` takes a range; the switcher as one preset (§2, §16) |
| 2026-09-09b capital-drawings pair | Capital = Opening Balance; Drawings seeded for *Just me*; takeout is Money out (§4, §11.5) |
| 2026-09-09c seeded chart | the seed per book; partner openings credit Partner Current, OB absorbs the difference (§11.3, §11.4) |
| 2026-09-09d no seeded bank + start date | no bank seeded; immutable start date (§11.3, §11.4) |
| 2026-09-13 §4 capital introduced | Money in to Opening Balance / Capital (§4.1, §11.5) |
| 2026-09-14 / 14b quorum + ratio layers | ratio in `book_config`, changes structural (§12.7) |
| 2026-09-24b §9 export khata block | printed ledgers end c/d · Total · b/d, no c/f (§2, §15.6) |
| 2026-09-25 §3, §7, §8 | import formats; receipts deferred; funds post-pilot (§12.10, §13.1) |
| 2026-09-27 / 27b | export waits for approval; the lock waits for every phone (§14.1, §16) |
| 2026-10-07b / 10-10c | inline-created accounts ask later; `opening` marker (§11.4) |
| 2026-10-08 | *joint fund* wording (§5, §11.1) |
| 2026-10-10b §4 | consumer label with the true side in brackets (§1.5) |
| 2026-10-11 | the use-case set; plain link labels; labourers as expense heads; the report order and statement names (§12.8, §12.10, §15, Appendix B) |
| 2026-10-12 | this version: §0 requirement; §1.7 catalogue and the `asset` class; §13.3 bank reconciliation; §12.5 *Written off*; printed-report language; one home for worked examples; archives |

## Appendix F — Section numbering, v2.0 → v3

| v2.0 | v3 | Note |
|---|---|---|
| — | §0 | *What the books must do* — new |
| §1.1–§1.6 | §1.1–§1.6 | same numbers, same content; §1.2 and §1.6 gain a sentence on `asset`; §1.3 gains two rows **below** its 🔒 table |
| — | §1.7, §1.8 | the account-type catalogue; basis and boundary — new |
| §2 | §2 | same 🔒 line; ADR blocks added beneath |
| §3, §3.1–§3.3 | §3, §3.1–§3.3 | individual — ledgers condensed, Cash A/c image kept, TB as one line |
| §4, §4.1–§4.3 | §4, §4.1–§4.3 | business — daybook verbatim (B01, B11 cited by tests); ledgers as one-liners |
| §5, §5.1–§5.4 | §5, §5.1–§5.4 | joint family — Kirana Bank and Advance images kept |
| §6, §6.1–§6.3 | §6, §6.1–§6.3 | trust — intro corrected (F-5); T01 split per 02 §8.2 |
| §7 | §7 | zero-crossing — table verbatim; negative-balance rule stated; D16b |
| §8 | §8 | split vouchers — verbatim plus a status note |
| §9 | §9 | integrity — rules 1–3 verbatim; 4–5 added |
| §10 Gate | §10 Governance | the gate moved to the worked examples (ADR 2026-09-05i §3) |
| — | §11–§17, A–G | new |

Citations elsewhere that this map keeps true: `standards §1.2, §1.3, §1.4, §2` (practice `build.py`, `.tech.md` files); `§1.3` contextual headers and `§2` layout (use-case `build.py`, `check_md.py`, README); `§3` (ADR 2026-09-24b §9); `§4.1 B01` (`capital_test.dart`, `invariants.dart`, ADR 2026-09-13 §4); `§4.2 B11` (`drawings_test.dart`); `§5.2` (§7's live example); `§6` (errata F-5, ADR 2026-09-05e); `§7`, `§8` (use-case README, `golden_worked_examples_test.dart`); `§9` (`money.dart`).

## Appendix G — Sources
Professional-practice references, as cited by the audit of 12 Oct 2026 (§6 there; *fetched* = text read directly, *search* = search-engine extract with the primary URL for the bookkeeper to confirm). Used for bookkeeping practice only; taxation sources are excluded by scope.
- ICAI, *Guidance Note on Financial Statements of Non-Corporate Entities* — vertical formats; capital, drawings and retained earnings disclosed separately (search; primary PDF on kb.icai.org).
- ICAI, *Technical Guide on Accounting for Not-for-Profit Organisations*; ICAI Board of Studies ch. 9 *Financial Statements of Not-for-Profit Organisations* — the receipts and payments account as a classified cash summary; income and expenditure on the accrual principle (search).
- ICAI AS 10 *Property, Plant and Equipment*, paras 7, 17 (recognition at cost), 50, 52 (depreciation) — fetched.
- ICAI AS 9 *Revenue Recognition*, para 13(i) — interest on a time basis — fetched.
- ICAI AS 1 *Disclosure of Accounting Policies* — accrual assumption (search).
- ICAI Board of Studies, *Bank Reconciliation Statement* — cash-book bank column vs pass book; timing differences (search).
- Partnership defaults when there is no deed — no interest on capital unless agreed; 6 % on a partner's loan — NCERT Class 12 Accountancy, partnership chapter (**not yet fetched**; confirm at research topic 14). Statute is not a source for these documents (research outline, rule 6).
- Partnership accounts — appropriation, fixed vs fluctuating capital (search). Bad debts and recoveries — journal entries (search). Chit Funds Act 1982 — discount, dividend, prize (search). Retention money as a contractor's receivable (search).

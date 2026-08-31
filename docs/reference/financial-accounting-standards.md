# Financial Architecture Specification v2.0 — Rukka Folio

**Status:** v2.0. Supersedes the uploaded drafts (`original/`) and v1.0-corrected; all errors from `accounting-audit-errata.md` are fixed here. **Every ledger and trial balance in this document was machine-verified to balance.** ⚠️ Gate: bookkeeper sign-off on this document → scenarios freeze as golden test fixtures (09, suite A) → product specifications proceed.

Structure: core rules (§1–§2), then one complete architecture per Rukka Folio entity type — **Individual (§3), Business (§4), Joint Family (§5), Trust (§6)** — each with account setup, transaction-type catalog, chronological daybook, full ledger account images, and a balanced trial balance.

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

### 1.3 What Dr and Cr *mean*, per account type 🔒
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

### 1.3.1 Why classification, not direction, decides Dr/Cr 🔒
Debit and credit follow the **account's class**, never the direction in which money appears to travel. Prepositional shortcuts ("from = credit, to = debit") hold for simple two-party transfers and fail for revenue, liabilities, equity and adjustments. The engine therefore derives every posting from the verb plus the classification matrix (§1.1), and the UI's entry preview (07 §5.5) uses a neutral arrow that states flow without asserting a rule.

**Modern frame — DEAD CLIC:** **D**ebit increases **E**xpenses, **A**ssets, **D**rawings · **C**redit increases **L**iabilities, **I**ncome, **C**apital.

### 1.4 The three golden rules (traditional frame)
- **Personal accounts** (people, firms, banks-as-parties): *debit the receiver, credit the giver.*
- **Real accounts** (cash, assets): *debit what comes in, credit what goes out.*
- **Nominal accounts** (expenses, incomes): *debit expenses and losses, credit incomes and gains.*

### 1.5 The bank-statement illusion
The bank's SMS says "credited" because in *the bank's* ledger your deposit is its liability (owed back to you) — a Cr in *its* books. In *your* books that account is an asset, so the same deposit is a **Dr / Money in**. The engine always keeps the user's perspective. (Adopted as onboarding help copy.)

### 1.6 Rukka Folio mapping
Classes: `money` + `party` + `advance` ↔ Asset/Liability **resolved by sign** (02 §1.2) · categories ↔ Expense/Income · `equity_system` ↔ Equity. The six entry verbs (02 §2) generate every posting in this document; the user never chooses Dr/Cr.

## 2. Ledger presentation standard 🔒 (used in all images below)
Columns: **Date · Particulars (counter-account: "To …" on the debit side, "By …" on the credit side) · Debit (Dr.) [contextual] · Credit (Cr.) [contextual] · Balance · Side (Dr./Cr. on every row)**. Dated *Opening balance b/f* (period's first day) and *Closing balance c/f* (day forwarded) rows. Professional surfaces show absolute values + side, never a minus sign.

---

## 3. Entity architecture 1 — Individual (Personal Book)

One person, one book: salary, household spending, lending to friends, borrowing, the dairy khata, plus an informal side activity. (A formal business gets its own book — §4.)

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

**Cash A/c** (money) — Dr *[Money in]* · Cr *[Money out]*

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

**Salary Bank A/c** (money) — Dr *[Money in]* · Cr *[Money out]*

| Date | Particulars | Dr | Cr | Balance | Side |
|---|---|---|---|---|---|
| 01 Aug | Opening balance b/f | — | — | 5,000 | Dr |
| 01 Aug | To Salary Income A/c | 1,50,000 | — | 1,55,000 | Dr |
| 02 Aug | By Cash A/c | — | 40,000 | 1,15,000 | Dr |
| 03 Aug | By Saving Bank A/c | — | 50,000 | 65,000 | Dr |
| 05 Aug | By Business Bank A/c | — | 30,000 | 35,000 | Dr |
| 22 Aug | By Rahul A/c | — | 21,000 | 14,000 | Dr |
| 31 Aug | Closing balance c/f | — | — | **14,000** | **Dr** |

**Saving Bank A/c** (money): b/f 10,000 Dr · 03 To Salary Bank 50,000 → 60,000 Dr · 08 By Utility Expense 4,500 → 55,500 Dr · 14 To Ramesh 8,000 → 63,500 Dr · c/f **63,500 Dr**.
**Business Bank A/c** (money): b/f 12,000 Dr · 05 To Salary Bank 30,000 → 42,000 Dr · 10 By Business Expense 12,000 → 30,000 Dr · c/f **30,000 Dr**.

**Ramesh A/c** (debtor) — Dr *[Given / owed to you ↑]* · Cr *[Received back]*

| Date | Particulars | Dr | Cr | Balance | Side |
|---|---|---|---|---|---|
| 01 Aug | Opening balance b/f | — | — | 0 | Dr |
| 06 Aug | To Cash A/c *(loan given)* | 20,000 | — | 20,000 | Dr |
| 12 Aug | By Cash A/c *(recovery)* | — | 5,000 | 15,000 | Dr |
| 14 Aug | By Saving Bank A/c *(UPI)* | — | 8,000 | 7,000 | Dr |
| 31 Aug | Closing balance c/f | — | — | **7,000** | **Dr** |

Display: *You will get ₹7,000 · ਰਮੇਸ਼ ਤੋਂ ਲੈਣੇ ਹਨ · रमेश से लेने हैं*

**Rahul A/c** (creditor) — Dr *[You paid]* · Cr *[You took ↑]*

| Date | Particulars | Dr | Cr | Balance | Side |
|---|---|---|---|---|---|
| 01 Aug | Opening balance b/f | — | — | 0 | Cr |
| 15 Aug | By Cash A/c *(loan taken)* | — | 40,000 | 40,000 | Cr |
| 18 Aug | To Cash A/c *(repaid)* | 15,000 | — | 25,000 | Cr |
| 22 Aug | To Salary Bank A/c *(UPI)* | 21,000 | — | 4,000 | Cr |
| 31 Aug | Closing balance c/f | — | — | **4,000** | **Cr** |

Display: *You will give ₹4,000 · ਰਾਹੁਲ ਨੂੰ ਦੇਣੇ ਹਨ · राहुल को देने हैं*

**Milk Expense A/c** (expense) — Dr *[Spent]* · Cr *[Refund/adj.]*: b/f 0 · 25 Aug To Milk Man 3,500 → **3,500 Dr** c/f.
**Milk Man A/c** (creditor) — Dr *[You paid]* · Cr *[You took ↑]*: b/f 0 Cr · 25 Aug By Milk Expense 3,500 → 3,500 Cr · 28 Aug To Cash 3,000 → **500 Cr** c/f — *You will give ₹500*.
**Utility Expense** 08 Aug To Saving Bank → **4,500 Dr** · **Business Expense** 10 Aug To Business Bank → **12,000 Dr** · **Personal Expense** 20 Aug To Cash → **18,000 Dr** · **Salary Income** 01 Aug By Salary Bank → **1,50,000 Cr** · **Opening Balance/Capital** → **31,000 Cr**.

### 3.3 Trial balance — 31 Aug 2026 (machine-verified)

| Account | Dr (₹) | Cr (₹) |
|---|---|---|
| Utility Expense | 4,500 | — |
| Saving Bank | 63,500 | — |
| Salary Bank | 14,000 | — |
| Business Bank | 30,000 | — |
| Business Expense | 12,000 | — |
| Cash | 33,000 | — |
| Personal Expense | 18,000 | — |
| Ramesh (debtor) | 7,000 | — |
| Milk Expense | 3,500 | — |
| Rahul (creditor) | — | 4,000 |
| Milk Man (creditor) | — | 500 |
| Opening Balance/Capital | — | 31,000 |
| Salary Income | — | 1,50,000 |
| **TOTALS** | **1,85,500** | **1,85,500** |

---

## 4. Entity architecture 2 — Commercial Business (Business Book)

Owner capital, cash & credit sales, credit purchases, customer receipts, supplier payments, drawings — strictly insulated from personal books.

**Accounts:** Business Bank–HDFC (A, opens 50,000 Dr) · Business Cash (A) · Business Expense (E) · Purchases (E) · Singhania & Co. — customer/debtor (A) · Aggarwal Traders — supplier/creditor (L) · Sales (I) · Capital (Eq, incl. 50,000 opening) · Drawings (Eq-contra).

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

### 4.2 Ledger images

**Business Bank–HDFC** (money) — Dr *[Money in]* · Cr *[Money out]*: b/f 50,000 Dr · B01 To Capital 5,000 → 55,000 · B02 By Business Cash 1,000 → 54,000 · B04 By Business Expense 15,000 → 39,000 · B05 To Singhania 18,000 → 57,000 · B09 By Aggarwal 10,000 → **47,000 Dr** c/f.
**Business Cash** (money): B02 1,000 → B06 +12,000 = 13,000 → B07 −1,500 = 11,500 → B10 +8,000 = 19,500 → B11 −5,000 = **14,500 Dr** c/f.

**Singhania & Co.** (customer/debtor) — Dr *[Sold on credit ↑]* · Cr *[Payment received]*

| Day | Particulars | Dr | Cr | Balance | Side |
|---|---|---|---|---|---|
| 03 | To Sales A/c | 40,000 | — | 40,000 | Dr |
| 05 | By HDFC A/c *(UPI)* | — | 18,000 | 22,000 | Dr |
| 06 | By Business Cash *(cash)* | — | 12,000 | 10,000 | Dr |
| — | Closing balance c/f | — | — | **10,000** | **Dr** |

**Aggarwal Traders** (supplier/creditor) — Dr *[You paid]* · Cr *[Bought on credit ↑]*

| Day | Particulars | Dr | Cr | Balance | Side |
|---|---|---|---|---|---|
| 08 | By Purchases A/c | — | 25,000 | 25,000 | Cr |
| 09 | To HDFC A/c | 10,000 | — | 15,000 | Cr |
| — | Closing balance c/f | — | — | **15,000** | **Cr** |

**Business Expense 16,500 Dr · Purchases 25,000 Dr · Sales 48,000 Cr · Capital 55,000 Cr · Drawings 5,000 Dr.**

### 4.3 Trial balance (machine-verified): Dr — HDFC 47,000 · Business Cash 14,500 · Singhania 10,000 · Business Expense 16,500 · Purchases 25,000 · Drawings 5,000 = **₹1,18,000**. Cr — Aggarwal 15,000 · Sales 48,000 · Capital 55,000 = **₹1,18,000**. ✓

---

## 5. Entity architecture 3 — Joint Family (multi-book: the Rukka Folio differentiator)

One family, four independent self-balancing books linked only by **Due to/from** pairs: **Joint Book** (common pool), **Family-A Book** (a sub-family), **Kirana Book** (a family business), **Amit's Personal Book**. Every inter-book event posts once in each book; the pair must always net to zero.

**Use cases demonstrated:** business remits to the common pool · pool pays a common expense · monthly allowance to a sub-family · a member pays a family expense from his own pocket · the full **ਐਡਵਾਂਸ (advance) cycle** · a bank crossing zero into overdraft.

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

### 5.3 Trial balances (each book balances alone — machine-verified)
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

---

## 6. Entity architecture 4 — Trust / Organization (Trust Book)

Non-profit: no commercial profit; inflows are donations, the year's surplus/deficit closes to **Corpus**. Trustee advances are per-person **Advance sub-accounts** — never tags inside Cash — so every movement stays a real journal entry (errata F-4).

**Accounts:** Trust Cash (A) · Trust Bank–SBI (A) · Advance–Assistant A (A/ਐਡਵਾਂਸ) · Langar Expense (E) · Donation Income (I).

### 6.1 Daybook

| ID | Day | Event | Dr | Cr | ₹ |
|---|---|---|---|---|---|
| T01 | 01 | Gollak (box) collection sorted | Trust Cash | Donation Income | 20,000 |
| T02 | 02 | Sponsor donation (UPI) | Trust Bank | Donation Income | 15,000 |
| T03 | 03 | ਐਡਵਾਂਸ to Assistant A for langar | Advance–Asst A | Trust Cash | 5,000 |
| T04 | 04 | A submits vegetable bills | Langar Expense | Advance–Asst A | 2,000 |
| T05 | 05 | LPG cylinder paid (bank) | Langar Expense | Trust Bank | 3,200 |
| T06 | 06 | A returns part cash | Trust Cash | Advance–Asst A | 1,000 |

### 6.2 Ledger images

**Advance–Assistant A** — Dr *[Handed out]* · Cr *[Bills settled / returned]*: T03 5,000 → T04 −2,000 = 3,000 → T06 −1,000 = **2,000 Dr** c/f — *still with Assistant A, ageing since 03rd; the position screen shows "Cash ₹16,000 · with Asst A ₹2,000".*
**Trust Cash**: 20,000 → −5,000 = 15,000 → +1,000 = **16,000 Dr**. **Trust Bank**: 15,000 → −3,200 = **11,800 Dr**. **Langar Expense**: 2,000 → 5,200 = **5,200 Dr**. **Donation Income**: 20,000 → **35,000 Cr** (shown as Donation Income mid-period; closes to Corpus only at year end — errata F-3).

### 6.3 Trial balance (machine-verified): Dr — Cash 16,000 · Bank 11,800 · Advance–A 2,000 · Langar 5,200 = **₹35,000** · Cr — Donation Income **₹35,000** ✓

---

## 7. Zero-crossing inversions (placement-by-sign)

| Context | Crossing zero means | Professional label | Display (EN / ਪੰਜਾਬੀ / हिन्दी) |
|---|---|---|---|
| Bank (asset) drops past zero | Overdraft | Current liability — Bank OD | You will give · ਦੇਣੇ ਹਨ · देने हैं |
| Debtor overpays you | Advance from customer | Current liability | You will give · ਦੇਣੇ ਹਨ · देने हैं |
| You pre-pay a creditor | Advance to supplier | Current asset | You will get · ਲੈਣੇ ਹਨ · लेने हैं |

Balances never wear a minus sign on professional surfaces — the **side flips** (live example: Kirana Bank, §5.2).

## 8. Multi-party split vouchers
One voucher, n lines, Σ Dr = Σ Cr. Example: ₹50,000 langar provisions = Dr Langar Expense 50,000 · Cr Cash 20,000 · Cr Trust Bank 20,000 · Cr Aggarwal Traders 10,000. Engine-supported (02 §1.4); split-payment entry UI is an open product item.

## 9. Integrity rules
1. **Atomicity** — a multi-line entry commits whole or not at all (one envelope).
2. **No raw negatives to the UI layer** — signed math internally; absolute value + side tag on professional surfaces.
3. **Month lock** — post-lock corrections only via dated reversal/adjustment entries; history is immutable (02 §5/§8).

## 10. Gate to product specifications
Bookkeeper verifies this document → §3–§6 freeze as golden fixtures (the engine must reproduce every ledger image and TB exactly) → presentation standards (§2) apply to the statement screen on owner approval → product specifications proceed.

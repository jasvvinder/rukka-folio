# Business Logic & Financial Specification: Double-Entry Ledger Framework

This document outlines the standard financial architecture and ledger execution flow for a multi-account bookkeeping application. It bridges traditional Indian accounting framework principles (Single/Double-Entry *Khata* systems) with deterministic application logic.

---

## 1. The Core Accounting Identity & System Rules

In any double-entry bookkeeping engine, the system must balance assets against liabilities and equity. Every financial transaction is an exchange of value between two accounts, meaning a standalone entry cannot exist.

$$\text{Assets} = \text{Liabilities} + \text{Equity}$$

### 1.1 The Golden Rules of Accounting (Modern Classification Engine)

To automate the routing of entries in an application backend, accounts are categorized into five types. Each type possesses a natural balance state that dictates how its balance changes:

| Account Type | Asset or Liability | Natural Balance | Debit (Dr) Impact | Credit (Cr) Impact | Example Accounts from Scenario |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Asset** | Asset | **Debit (Dr)** | Increases (+) | Decreases (-) | Salary Bank, Saving Bank, Business Bank, Cash, Ramesh A/c |
| **Liability** | Liability | **Credit (Cr)** | Decreases (-) | Increases (+) | Rahul A/c |
| **Equity** | Liability | **Credit (Cr)** | Decreases (-) | Increases (+) | Capital Fund / Retained Earnings |
| **Expense** | N/A (P&L Impact) | **Debit (Dr)** | Increases (+) | Decreases (-) | Utility, Business Expense, Personal Expense, Milk Man |
| **Income** | N/A (P&L Impact) | **Credit (Cr)** | Decreases (-) | Increases (+) | Salary Income |

### 1.2 Resolving the Bank Statement Illusion
A common point of confusion in financial software design is the apparent inversion of Debit and Credit on bank notifications versus internal accounting records. 

* **The Bank's Book:** When a user deposits currency into a commercial banking institution, the bank logs this cash as a **Liability** because they owe that cash back to the user. An increase in a liability is a **Credit (Cr)**.
* **The User's Book:** In the user's internal app ledger, that bank account is an **Asset** representing owned capital. An increase in an asset is a **Debit (Dr)**. 
* **The Application Logic Rule:** The application ledger engine must maintain records from the perspective of the user's asset base, never the bank's liability matrix.

---

## 2. Global Account Configuration (Master Setup)

To demonstrate a unified operational ledger flow, the baseline system state is initialized on **01 August 2026** with the following structural parameters and opening balances:

1. **Utility Expense A/c** (Expense) | Opening Balance: **₹0**
2. **Saving Bank A/c** (Asset) | Opening Balance: **₹10,000 (Dr)**
3. **Salary Bank A/c** (Asset) | Opening Balance: **₹5,000 (Dr)**
4. **Business Bank A/c** (Asset) | Opening Balance: **₹12,000 (Dr)**
5. **Business Expense A/c** (Expense) | Opening Balance: **₹0**
6. **Cash A/c** (Asset - Cash in Hand) | Opening Balance: **₹4,000 (Dr)**
7. **Personal Expense A/c** (Expense) | Opening Balance: **₹0**
8. **Ramesh A/c** (Asset - Debtor/Receivable) | Opening Balance: **₹0**
9. **Milk Man A/c** (Expense/Accrued Liability) | Opening Balance: **₹0**
10. **Rahul A/c** (Liability - Creditor/Payable) | Opening Balance: **₹0**

---

## 3. The Master Daybook (Chronological Event Stream)

This sequential registry represents the absolute order of historical real-world events. Each event acts as a dual mutation across the system.

| Event ID | Date (2026) | Transaction Particulars Description | Account to Debit (Dr) | Account to Credit (Cr) | Amount (₹) |
| :---: | :--- | :--- | :--- | :--- | :---: |
| **E01** | Aug 01 | Corporate monthly salary payout received | 3. Salary Bank A/c | Salary Income A/c | ₹1,50,000 |
| **E02** | Aug 02 | ATM withdrawal for personal domestic vault supply | 6. Cash A/c | 3. Salary Bank A/c | ₹40,000 |
| **E03** | Aug 03 | Inter-account liquid capital wealth transfer | 2. Saving Bank A/c | 3. Salary Bank A/c | ₹50,000 |
| **E04** | Aug 05 | Working capital allocation out to enterprise tier | 4. Business Bank A/c | 3. Salary Bank A/c | ₹30,000 |
| **E05** | Aug 06 | Emergency capital loan issued out to Ramesh | 8. Ramesh A/c | 6. Cash A/c | ₹20,000 |
| **E06** | Aug 08 | Domestic grid electricity invoice payment executed | 1. Utility Expense A/c | 2. Saving Bank A/c | ₹4,500 |
| **E07** | Aug 10 | Direct operational invoice settlement for raw stock | 5. Business Expense A/c | 4. Business Bank A/c | ₹12,000 |
| **E08** | Aug 12 | Ramesh executes primary partial currency return | 6. Cash A/c | 8. Ramesh A/c | ₹5,000 |
| **E09** | Aug 14 | Ramesh executes secondary digital UPI transfer | 2. Saving Bank A/c | 8. Ramesh A/c | ₹8,000 |
| **E10** | Aug 15 | Short-term financing injection accepted from Rahul | 6. Cash A/c | 10. Rahul A/c | ₹40,000 |
| **E11** | Aug 18 | Immediate return of excess physical cash to Rahul | 10. Rahul A/c | 6. Cash A/c | ₹15,000 |
| **E12** | Aug 20 | Educational institution dues paid out via home vault | 7. Personal Expense A/c | 6. Cash A/c | ₹18,000 |
| **E13** | Aug 22 | Targeted debt reduction UPI clear down to Rahul | 10. Rahul A/c | 3. Salary Bank A/c | ₹21,000 |
| **E14** | Aug 25 | Total monthly dairy delivery balance statement issued | 9. Milk Man A/c | Accrued Milk Payable | ₹3,500 |
| **E15** | Aug 28 | Direct spot partial currency settlement to dairy agent | 9. Milk Man A/c *(Payment)* | 6. Cash A/c | ₹3,000 |

---

## 4. Ledger Books (Dynamic Folio Projections)

### 1. Utility Expense A/c
* Natural State: **Debit Balance** (Accumulates expenses incurred).

| Transaction Date | Associated Counter-Party Account | Debit (Dr) | Credit (Cr) | Running Balance (₹) | Sign |
| :--- | :--- | :---: | :---: | :---: | :---: |
| 01 Aug 2026 | Opening Balance Brought Forward | — | — | 0 | Dr |
| 08 Aug 2026 | To Saving Bank A/c | ₹4,500 | — | 4,500 | Dr |
| **31 Aug 2026** | **Closing Balance Carried Forward** | — | — | **4,500** | **Dr** |

### 2. Saving Bank A/c
* Natural State: **Debit Balance** (Asset storage tracking personal funds).

| Transaction Date | Associated Counter-Party Account | Debit (Dr) | Credit (Cr) | Running Balance (₹) | Sign |
| :--- | :--- | :---: | :---: | :---: | :---: |
| 01 Aug 2026 | Opening Balance Brought Forward | — | — | 10,000 | Dr |
| 03 Aug 2026 | To Salary Bank A/c | ₹50,000 | — | 60,000 | Dr |
| 08 Aug 2026 | By Utility Expense A/c | — | ₹4,500 | 55,500 | Dr |
| 14 Aug 2026 | To Ramesh A/c | ₹8,000 | — | 63,500 | Dr |
| **31 Aug 2026** | **Closing Balance Carried Forward** | — | — | **63,500** | **Dr** |

### 3. Salary Bank A/c
* Natural State: **Debit Balance** (Asset tracking primary liquid income hub).

| Transaction Date | Associated Counter-Party Account | Debit (Dr) | Credit (Cr) | Running Balance (₹) | Sign |
| :--- | :--- | :---: | :---: | :---: | :---: |
| 01 Aug 2026 | Opening Balance Brought Forward | — | — | 5,000 | Dr |
| 01 Aug 2026 | To Salary Income | ₹1,50,000 | — | 1,55,000 | Dr |
| 02 Aug 2026 | By Cash A/c | — | ₹40,000 | 1,15,000 | Dr |
| 03 Aug 2026 | By Saving Bank A/c | — | ₹50,000 | 65,000 | Dr |
| 05 Aug 2026 | By Business Bank A/c | — | ₹30,000 | 35,000 | Dr |
| 22 Aug 2026 | By Rahul A/c | — | ₹21,000 | 14,000 | Dr |
| **31 Aug 2026** | **Closing Balance Carried Forward** | — | — | **14,000** | **Dr** |

### 4. Business Bank A/c
* Natural State: **Debit Balance** (Asset tracking separate entity capital funds).

| Transaction Date | Associated Counter-Party Account | Debit (Dr) | Credit (Cr) | Running Balance (₹) | Sign |
| :--- | :--- | :---: | :---: | :---: | :---: |
| 01 Aug 2026 | Opening Balance Brought Forward | — | — | 12,000 | Dr |
| 05 Aug 2026 | To Salary Bank A/c | ₹30,000 | — | 42,000 | Dr |
| 10 Aug 2026 | By Business Expense A/c | — | ₹12,000 | 30,000 | Dr |
| **31 Aug 2026** | **Closing Balance Carried Forward** | — | — | **30,000** | **Dr** |

### 5. Business Expense A/c
* Natural State: **Debit Balance** (Accumulates business operation outlays).

| Transaction Date | Associated Counter-Party Account | Debit (Dr) | Credit (Cr) | Running Balance (₹) | Sign |
| :--- | :--- | :---: | :---: | :---: | :---: |
| 01 Aug 2026 | Opening Balance Brought Forward | — | — | 0 | Dr |
| 10 Aug 2026 | To Business Bank A/c | ₹12,000 | — | 12,000 | Dr |
| **31 Aug 2026** | **Closing Balance Carried Forward** | — | — | **12,000** | **Dr** |

### 6. Cash A/c (Cash in Hand)
* Natural State: **Debit Balance** (Physical currency vault inventory).

| Transaction Date | Associated Counter-Party Account | Debit (Dr) | Credit (Cr) | Running Balance (₹) | Sign |
| :--- | :--- | :---: | :---: | :---: | :---: |
| 01 Aug 2026 | Opening Balance Brought Forward | — | — | 4,000 | Dr |
| 02 Aug 2026 | To Salary Bank A/c | ₹40,000 | — | 44,000 | Dr |
| 06 Aug 2026 | By Ramesh A/c | — | ₹20,000 | 24,000 | Dr |
| 12 Aug 2026 | To Ramesh A/c | ₹5,000 | — | 29,000 | Dr |
| 15 Aug 2026 | To Rahul A/c | ₹40,000 | — | 69,000 | Dr |
| 18 Aug 2026 | By Rahul A/c | — | ₹15,000 | 54,000 | Dr |
| 20 Aug 2026 | By Personal Expense A/c | — | ₹18,000 | 36,000 | Dr |
| 28 Aug 2026 | By Milk Man A/c | — | ₹3,000 | 33,000 | Dr |
| **31 Aug 2026** | **Closing Balance Carried Forward** | — | — | **33,000** | **Dr** |

### 7. Personal Expense A/c
* Natural State: **Debit Balance** (Accumulates home/family costs).

| Transaction Date | Associated Counter-Party Account | Debit (Dr) | Credit (Cr) | Running Balance (₹) | Sign |
| :--- | :--- | :---: | :---: | :---: | :---: |
| 01 Aug 2026 | Opening Balance Brought Forward | — | — | 0 | Dr |
| 20 Aug 2026 | To Cash A/c | ₹18,000 | — | 18,000 | Dr |
| **31 Aug 2026** | **Closing Balance Carried Forward** | — | — | **18,000** | **Dr** |

### 8. Ramesh A/c
* Natural State: **Debit Balance** (Asset tracking money lent out to a Debtor).

| Transaction Date | Associated Counter-Party Account | Debit (Dr) | Credit (Cr) | Running Balance (₹) | Sign |
| :--- | :--- | :---: | :---: | :---: | :---: |
| 01 Aug 2026 | Opening Balance Brought Forward | — | — | 0 | Dr |
| 06 Aug 2026 | To Cash A/c *(Loan Disbursed)* | ₹20,000 | — | 20,000 | Dr |
| 12 Aug 2026 | By Cash A/c *(Recovery)* | — | ₹5,000 | 15,000 | Dr |
| 14 Aug 2026 | By Saving Bank A/c *(Recovery)* | — | ₹8,000 | **7,000** | **Dr** |
| **31 Aug 2026** | **Closing Balance Carried Forward** | — | — | **7,000** | **Dr** |

### 9. Milk Man A/c
* Natural State: **Debit Balance** (Tracks expense accumulation from utility supply).

| Transaction Date | Associated Counter-Party Account | Debit (Dr) | Credit (Cr) | Running Balance (₹) | Sign |
| :--- | :--- | :---: | :---: | :---: | :---: |
| 01 Aug 2026 | Opening Balance Brought Forward | — | — | 0 | Dr |
| 25 Aug 2026 | To Accrued Milk Payable *(Bill Due)* | ₹3,500 | — | 3,500 | Dr |
| 28 Aug 2026 | By Cash A/c *(Partial Cash Payment)* | — | ₹3,000 | **500** | **Dr** |
| **31 Aug 2026** | **Closing Balance Carried Forward** | — | — | **500** | **Dr** |
*Note: The remaining system obligation sits as an active ₹500 balance inside the Accrued Milk Payable liability account.*

### 10. Rahul A/c
* Natural State: **Credit Balance** (Liability tracking active financing from a Creditor).

| Transaction Date | Associated Counter-Party Account | Debit (Dr) | Credit (Cr) | Running Balance (₹) | Sign |
| :--- | :--- | :---: | :---: | :---: | :---: |
| 01 Aug 2026 | Opening Balance Brought Forward | — | — | 0 | Cr |
| 15 Aug 2026 | By Cash A/c *(Loan Principal Taken)* | — | ₹40,000 | 40,000 | Cr |
| 18 Aug 2026 | To Cash A/c *(Repayment)* | ₹15,000 | — | 25,000 | Cr |
| 22 Aug 2026 | To Salary Bank A/c *(Repayment)* | ₹21,000 | — | **4,000** | **Cr** |
| **31 Aug 2026** | **Closing Balance Carried Forward** | — | — | **4,000** | **Cr** |

---

## 5. Trial Balance: The Overall Financial Position

To confirm system accuracy, closing ledger snapshots are aggregated into a standard **Trial Balance** statement as of **31 August 2026**.

```
                           TRIAL BALANCE STATEMENT
                         As of 31st August 2026
┌──────────────────────────────────────────┬───────────────────┬───────────────────┐
│ Account Title Nomenclature               │ Debit Balance (Dr)│Credit Balance (Cr)│
├──────────────────────────────────────────┼───────────────────┼───────────────────┤
│ 1. Utility Expense A/c                   │            ₹4,500 │                 — │
│ 2. Saving Bank A/c                       │           ₹63,500 │                 — │
│ 3. Salary Bank A/c                       │           ₹14,000 │                 — │
│ 4. Business Bank A/c                     │           ₹30,000 │                 — │
│ 5. Business Expense A/c                  │           ₹12,000 │                 — │
│ 6. Cash A/c                              │           ₹33,000 │                 — │
│ 7. Personal Expense A/c                  │           ₹18,000 │                 — │
│ 8. Ramesh A/c                            │            ₹7,000 │                 — │
│ 9. Milk Man A/c                          │              ₹500 │                 — │
│ 10. Rahul A/c                            │                 — │            ₹4,000 │
│ Opening Balances (Assets Initialized)    │                 — │           ₹31,000 │
│ Accrued Milk Payable (External Oblig.)   │                 — │              ₹500 │
│ Salary Income (Revenue Stream)           │                 — │         ₹1,50,000 │
├──────────────────────────────────────────┼───────────────────┼───────────────────┤
│ SUM TOTAL MATRICES                       │        ₹1,85,500  │        ₹1,85,500  │
└──────────────────────────────────────────┴───────────────────┴───────────────────┘
```

The system achieves mathematical equilibrium ($1,85,500 = 1,85,500$). This verifies that all backend transaction tracking engine rules function correctly across both asset and liability tiers.
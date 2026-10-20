# COVERAGE.md — where each ruling and each merged mechanic is shown

Technical, hand-written (ADR 2026-10-20 §2). It maps (A) every ruled row of `docs/archive/reference/accounting-research/OPEN.md` that a book can show, and (B) every mechanic of the five practice books merged into the kept five, to the **book** and the **entry numbers** (the printed ones, `JP-049`) or the **section** of the printed book that shows it. (C) lists the ruled rows these books deliberately do not show, with one line each. `check_md.py` checks that every entry number cited here exists in the regenerated books; the rest was read against the regenerated output.

**Book keys.** `individual` = `individual-jasvinder-singh` (`JP` Jasvinder Singh's personal book, `JT` Jasvinder Technologies) · `family` = `joint-family-randhawa` (`RJ` Randhawa Joint Family, `RA` Amarjeet's Family, `RB` Lakhbeer's Family, `RC` Lakhwinder's Family, `RG` Randhawa Agriculture, `RE` Randhawa Real Estate, `RK` Randhawa Brick Field) · `shop` = `shop-sukhwinder-sales-co` (`S`) · `partnership` = `partnership-bal-fabricators` (`BF`) · `trust` = `trust-radha-soami-satsang-sabha` (`RS`). Year-close entries carry `Y` numbers (`BF-Y4`). **Section** numbers are those of the printed book: 1 accounts · 2 ledgers · 3.1 / 3.2 positions · 3.3 one month · 3.4 chosen period · 3.5 ageing · 3.6 bank statement → entries · 4.1 trial balance · then the year's statement, fund statements, appropriation, year close, balance sheet, carry-forward (numbers differ by book, the heading says which).

---

## A. Ruled rows a book shows

### 1. Basis of accounting
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-01-1, O-01-2, O-01-3, O-01-4 | all five | the head line under every numbered heading of every book and export | one basis for household, joint family, partnership and every other book: the head carries the book, the date or period, *Kept on money paid and received, and what people owe; no year-end adjustments.*, *Year closed*, *Made on 02 Apr 2026, 10:00* (a pinned string — no clock). No Day Book has an accrued, prepaid or outstanding entry, a depreciation entry or a closing-stock entry. |
| O-01-6, O-06-7 | shop, family | `S-057`, `RE-029` | no provision for doubtful debts anywhere; a balance stays on the person's account until it is known not to come, then it is written off. |

### 2. Double entry and kinds of account
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-02-1 | all five | section 1, *Type* column; `RS` *General Fund* | five types; capital is its own type, printed *Own money* (the trust's: *General Fund*). |
| O-02-2 | all five | each book's `.tech.md` accounts table | a bank is an *Asset* with traditional class *Personal*; it would be a liability by its balance when overdrawn. |
| O-02-3 | individual, shop, family | `JT-001`, `JT-016`, `JT-032`, `JT-035`, `JT-Y4`; `S-005`, `S-Y4`; `RG-006`, `RG-032`, `RG-Y4`; `RE-009`, `RE-Y4` | a separate *Drawings* account, debited for each withdrawal and closed to own money at the year close; never an expense. |
| O-02-4 | individual | `JP-007`, `JP-031`, `JP-032`, `JP-049`; section 3.4 | a loan to a friend that carries interest has its own account, *Loan to – Gurpreet Sandhu*, apart from any khata. (The liability side, *Loan from – {person}*, is C.) |

### 3. Books of account
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-03-1, O-20-7 | all five | `<file>.export.md` | the Day Book (every entry, date order) and the Cash Book (cash and bank entries only, balanced each month). |
| O-03-2 | all five | section 2 and 4.1 | income and expense heads are posted to the ledger and the trial balance includes them. |
| O-03-3 | all five | the Type cell of every Day Book row in the export | an entry that moves no money is marked *no money moved*; no nakal bahi. |
| O-03-5 | all five | the export and sections 1–2 | a Day Book, a Cash Book and a ledger with an account for every person, head and thing owned. |

### 4. Opening the books
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-04-1 | all five | section 1 of every book | no *Opening Balance* account: each asset, each liability in its own account, and own money (*Capital A/c*) as the balancing figure. |
| O-04-2 | individual | section 1 of `JP` | the household's own money is *Capital A/c – Jasvinder Singh*, the balancing figure. |
| O-04-3 | family | section 1 of `RJ`, `RA`, `RB`, `RC` | the family's own money opens at assets less liabilities; each sub-family account opens at the agreed balance (`RA` −18,000 mirrored in `RJ`) and is mirrored in the household's book. |
| O-04-6 | all five | section 1 of every book | every book begins on the first day of the financial year, 01 Apr 2025; the opening balances are taken that day and the first period runs from it. |
| O-04-7 | all five | section 1, *What it is* column of every thing owned (the car *at what it cost (2023)*, the family house, gold, land, the machinery, the kiln) | a thing owned enters the opening at cost, and the accounts list says so; the figure stays unchanged through the year. |
| O-04-5, O-14-8 | partnership, family | section 1 of `BF`, `RK` | the partners' agreed figures balance the firm's assets and liabilities with no balancing line (the build asserts it). |

### 5. Cash and bank
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-05-1 | individual, family | `JP-006`, `JP-015`, `JP-029` (spends), `JP-005`, `JP-009`, `JP-017`, `JP-025` (bills by transfer); `RC-005`, `RC-003` | a card is a liability account of its own: a spend credits the card, the bill is a transfer. |
| O-05-2 | individual | `JP-022` (loaded by transfer), `JP-051` (tolls spent) | the FASTag wallet is a money account of its own, cash-like. |
| O-05-4 | individual, shop | section 3.6 of `JP`, `JT`, `S` | one month of bank statement, every line given its account, closing balance equal to the ledger. (Listing the cheques not yet presented is C.) |
| O-05-5 | individual, shop, family | `JT-001`, `S-005`, `RG-006` | a withdrawal for private or family use is drawings, never a transfer. |

### 6. Persons: debtors and creditors
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-06-1 | individual, shop | `JT-006`, `JT-017`, `JT-021` (Kaur Exports crosses zero once); `S-008`, `S-015`, `S-036` (Dhillon) | one running account per person; the balance changes side and is read as *You will get* or *You will give* (section 3.5). |
| O-06-2 | partnership | `BF-006`, `BF-015`, `BF-020` | a supplier paid in advance: his account is the Dr side until the goods come, crosses to Cr with his bill, back to nil when the rest is paid. |
| O-06-3 | partnership, individual, shop | `BF-002`; `JT-006`; `S-008` | a customer's advance is his account on the Cr side until the work is billed. |
| O-06-4 | partnership | `BF-009`, `BF-025`, `BF-040` (retention held at billing), `BF-048` (released to the khata), `BF-050` (paid) | *Retention held by – Sandhu Builders* is its own asset account beside the khata, released by a transfer when due; ₹34,000 stays at the year end. |
| O-06-5 | shop, family, individual | `S-057`, `RE-029`, `JP-049` | written off by a plain entry to *Written off* / *Rent written off*; no provision. |

### 7. Advances and imprest
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-07-1, O-07-6 | all five | `JP-011`, `JP-033`; `JT-018`; `S-019`; `BF-035`, `BF-047`; `RS-001`, `RS-026`, `RS-040`; `RG-012`, `RG-022`, `RG-037`; `RE-026`; `RJ-012`; `RB-013`; `RC-011`; `RK-001`, `RK-023`, `RK-029` | an advance for spending, to a house help, driver, salesman, foreman, sewadar, farm manager, registry clerk, mason, painter, electrician or moulder, is *Advance – {person}* (an asset), a personal advance (never *imprest*). |
| O-07-2 | individual, partnership, trust, family | `JP-036`, `BF-037`, `BF-051`, `RS-012`, `RS-039`, `RS-056`, `RG-015`, `RG-026`, `RG-038`, `RE-027` | settled in one entry, Dr each head · Cr the advance, several heads in one entry. |
| O-07-3 | individual, family | `JP-037`, `RE-028`; top-ups `RG-022`, `RG-037` | the unspent part returned, Dr cash · Cr the advance; a top-up is a fresh hand-out to the same account. |
| O-07-4, O-12-3 | individual, partnership, trust | left open and carried forward: `BF-051` (₹1,700 with the foreman), `RS-056` (₹1,100 with the sewadar); moved to the person's own account: `JP-036` (₹1,800 → *Balwinder Singh A/c*); written off: `BF-051` (₹1,000 of lost slips) | the three ways to deal with what is left, chosen in the settlement entry; `JP-036` and `BF-051` are one entry with several heads and the remainder. |
| O-07-5 | individual, shop | `JP-021`, `JT-026`, `S-028` | a salary advance is recovered in the salary entry: Dr salary (full) · Cr advance (part) · Cr cash or bank (net). |

### 8. Loans
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-08-1, O-08-2 | individual | `JP-030`, `JP-040`, `JP-042`, `JP-046` | one bank line, Dr *Car Loan* (principal) · Dr *Interest on Car Loan* · Cr bank, with the lender's figures; the lender's statement governs. (A later difference corrected by an entry is C.) |
| O-08-3 | family | drawn by transfer: `RG-009`, `RG-027`; costs paid from the KCC: `RG-016`; interest charged: `RG-020`, `RG-039`; repaid by transfer: `RG-005`, `RG-031` | the KCC is a loan account used as money. |
| O-08-5, O-08-7 | individual | `JP-032` | interest on a loan the book gave, recorded when received. |
| O-08-6 | family | `RJ-010` ↔ `RB-008` | ₹50,000 taken for a while carries no interest entry. |

### 9. Assets and deposits
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-09-1, O-09-2 | all five | sections 3.1, 3.2 and the balance sheet of every book that shows things owned; `RJ` gold and house; `RG` land | *Things owned are shown at what they cost; no depreciation is charged.* printed exactly where things owned are shown; land, gold and jewellery at cost. |
| O-09-3, O-09-4, O-09-5 | individual, family, trust | `JP-018` (a deposit matured, a transfer); `RJ-032`, `RC-017` (new deposits by transfer); `JP-039`, `RJ-040` (interest paid out to savings); `RS-050` (interest added to the fund's cumulative deposit) | a deposit is its own type, not part of cash and bank; interest recorded when the bank credits it, as the bank does it. |
| O-09-6, O-12-4 | individual | `JP-027` | a car bought on a loan the lender paid to the dealer: one entry, Dr *Car* ₹9,00,000 · Cr *Car Loan* ₹8,00,000 · Cr bank ₹1,00,000 (the margin). |
| O-09-7 | trust | `RS-013`, `RS-028`, `RS-035`, `RS-049` | the langar hall is *Construction*, an expense head, as the trust says in its statements. |
| O-09-8, O-12-2, O-18-3 | family | `RE-019` (₹25,000 of the deposit set off against unpaid rent), `RE-020` (the other ₹5,000 forfeited to *Deposit forfeited*); `RE` chart: *Deposit held – {tenant}* per tenant; `S` chart: *Deposit paid – Kapoor Properties* | a deposit has its own account on the person's page; set off by an entry that moves no money; forfeited to income; held and paid mirrored. (Return in cash is C.) |

### 10. Goods bought for sale
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-10-1 | shop | the year's statement (4.2) | *No stock is counted. Everything bought for sale is treated as sold or used in the year it was bought.* |

### 11. Errors and corrections
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-11-1 | shop | `S-042` (₹1,150 short, Dr *Cash short / over*), `S-056` (₹300 over, Cr) | a cash count that differs goes at once to *Cash short / over*, no suspense. |
| O-11-2, O-11-5 | all five | `JP-045`, `JT-028`, `S-023`, `BF-023`, `RS-021`, `RJ-031`, `RA-010`, `RB-021`, `RC-028`, `RG-036`, `RE-024`, `RK-013` | a wrong head is put right by a new *Correction* entry (Dr right head · Cr wrong head, no money), never an edit; its note names the entry it fixes with its number and date (*Entry JP-043 of 20 Feb 2026 …*). |
| O-11-3 | all five | no account named suspense in any chart; section 3.6 of `JP`, `JT`, `S` | a bank-statement line is always given an account; nothing waits in suspense at the year end. |

### 12. Entries that move no money
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-12-1, O-18-5 | individual, shop, family | `JP-049` (a loan to a friend), `S-057` (a customer), `RE-029` (rent) | a balance known not to come back is written off to a head: *Written off* or *Rent written off*. |
| O-12-5, O-14-5 | partnership, family | `BF-008`, `BF-049`; `RK-026` | a partner paying a firm cost from his own pocket: Dr expense · Cr his current account (a loan only if the partners agree, none here). |

### 13. Sole proprietor and household
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-13-1, O-19-6 | individual, shop, family | `JT-Y4`, `S-Y4`, `RG-Y4`, `RE-Y4` | a separate *Drawings* account closed to own money at the year close. |
| O-13-2, O-13-6 | individual, shop | section 1 of `JT`, `S` | one *Capital* (own money) and one *Drawings* account; no current account, no salary or interest for the owner. |
| O-13-4 | individual | `JP-001`, `JP-012`, `JP-026`, `JP-034` (money the business sent home = *Income from Jasvinder Technologies*); `JT-001`, `JT-016`, `JT-032`, `JT-035` (Drawings); `JP-008` ↔ `JT-007` (money put in, held at that amount) | the personal book holds the business at the money put in; money sent home is income; the summary at the end of the file shows the pair agreeing. |
| O-13-5 | individual, family | `JP`: the *Income & Expenses* statement (4.2), result *Saving*; `RA`, `RB`, `RC`, `RJ` the same, `RB` *Spent more than came in* (`RB-Y3`) | income: salary, interest, rent, *Income from {business}* and gifts received (`JP-014`); not income: the loan taken (`JP-027`), money returned (`JP-031`, `JP-037`), transfers between own accounts (`JP-005`), a deposit that matured (`JP-018`). |

### 14. Partnership
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-14-1, O-14-2, O-14-3 | partnership, family | `BF-Y3`, `BF-Y4`, `BF-Y5`; `RK-Y3`, `RK-Y4`; section *P&L Appropriation Account* | the appropriation is posted by the book at the year close: net profit to the account, interest on capital (6%, agreed, out of profit) as an appropriation below the line, then the shares 2 : 2 : 1 (`BF`) and 3 : 2 with no interest (`RK`). |
| O-14-4 | partnership, family | section 1 of `BF`, `RK` | fixed capital with a current account per partner (`BF`); one account per partner (`RK`). |
| O-14-7 | family | `RK-016`, `RK-034` | the outside partner's drawings entered on his instruction. |

### 15–16. Joint family and accounts between related books
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-15-1 | family | `RJ-001`, `RJ-002`, `RJ-009`, `RJ-010`, `RJ-018`, `RJ-019`, `RJ-006`, `RJ-030` ↔ `RA-001`, `RB-001`, `RB-006`, `RB-008`, `RC-010`, `RC-031` | one running account per sub-family in the family's book, mirrored in the household's book under its own money; not a debt. |
| O-15-2 | family | `RC-023` · `RK-019` · `RJ-023`; `RB-019` · `RK-026` · `RJ-025` | a household's money into a business, or its payment of a business bill: three books, one transaction; the family's book records it as an entry that moves no money. |
| O-15-3, O-15-4 | family | `RJ-004`, `RJ-007`, `RJ-015`, `RJ-024`, `RJ-027`, `RJ-036` (*Income from …*) ↔ `RG-006`, `RG-032`, `RK-015`, `RK-033`, `RE-009`, `RE-016` (Drawings); the note under the family summary | money sent home is the family's income; money put in stays at cost; each business's own profit is stated in the summary, not taken into the family's income. |
| O-15-5, O-16-4 | family | settled by the family bearing it: `RJ-038` ↔ `RA-030`; settled from the share of business income: `RJ-037` ↔ `RB-028` (Dr *Business Income Shared Out*, a share-out of the family's own money like drawings — not a cost, outside the Saving, closed to own money by `RJ-Y4`; in `RB` it is income); carried forward: Lakhwinder's (`RC` carry-forward) | settle or carry forward, as the family decides; carried forward by default. |
| O-15-6 | family | the introduction of `joint-family-randhawa` | Amarjeet keeps the family's book; his household is a sub-family like the others, with no separate account as karta. |
| O-16-1 | family, individual | the family summary and the two-books summary at the end of each file; the *Profit kept in the business* line under each owner ↔ business pair (`JP`↔`JT`, `RJ`↔`RG`, `RE`, `RK`) | every pair of related books keeps converse accounts named after the other book. A running-account pair (family ↔ sub-family) agrees balance for balance; an owner ↔ business pair agrees entry by entry (money put in ↔ capital, *Income from {business}* ↔ drawings) but not in balance, and the difference is printed as *profit kept in the business* (the business's own money less the money put in = its profit less what was taken out; `check_md.py` verifies it). A sole proprietor's business names its capital and drawings after the owner, whose personal book is the other book. |
| O-16-2, O-16-3 | family | `RJ-028` ↔ `RA-022`; `RJ-033` ↔ `RB-023`; `RB-019` · `RK-026` | one book pays another's bill: Dr *{other} A/c* · Cr money in the payer's book, Dr the expense · Cr *{payer} A/c* in the other; no hub. |

### 17. Trusts, committees
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-17-1 | trust | `RS-028`, `RS-035`; section *Each fund — its year* | spending from the fund is one action in plain words (*paid from the Langar Hall Fund*) and two postings in the `.tech.md`: Dr *Construction* · Cr bank, and Dr the fund · Cr *Transferred from the Langar Hall Fund*; every rupee is in Income & Expenditure and the fund's own result is nil. |
| O-17-2 | trust | `RS-050` | interest on the fund's deposit goes to the fund. |
| O-17-4 | trust | `RS-002`, `RS-016`, `RS-031`, `RS-048` | general donations are income in Income & Expenditure. |
| O-17-6 | trust | section 1 | no corpus: everything not given for a purpose is the General Fund. |
| O-17-7 | trust | `RS-045` | a donated almirah kept by the trust: ₹1, with the estimated value (₹18,000) in the note. |
| O-17-8 | trust | `RS-004`, `RS-014`, `RS-022`, `RS-032`, `RS-042`, `RS-051` (counts, Dr *Gollak* · Cr *Donations – gollak*); `RS-005`, `RS-006`, `RS-015`, `RS-023`, `RS-027`, `RS-033`, `RS-043`, `RS-044`, `RS-052` (emptying, transfers) | the count records the donation; emptying the box is a transfer to cash or bank; uncounted money is not recorded. |
| O-17-9, O-20-4 | trust | sections 4.2 (Receipts & Payments), 4.3 (Income & Expenditure), 4.4 (each fund), the balance sheet | all three statements and a statement for each fund, from the same entries. |

### 18. Landlord
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-18-1 | family | `RE-001`, `RE-007`, `RE-012`, `RE-021` | rent charged to each tenant's account when due, several tenants in one entry (Dr tenants · Cr *Rent Income*). |
| O-18-4 | family | `RE-017` (a mezzanine floor, added to the shops' cost), `RE-006`, `RE-023` → `RE-024` (repairs, expense) | an improvement is added to the building's cost; a repair is an expense; no depreciation. |

### 19. Year end
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-19-1 | all five | `JP-Y1…Y3`, `JT-Y1…Y4`, `S-Y1…Y4`, `BF-Y1…Y5`, `RK-Y1…Y4`, `RS-Y1…Y3`, `RJ-Y1…Y3`, `RA-Y1…Y3`, `RB-Y1…Y3`, `RC-Y1…Y3`, `RG-Y1…Y4`, `RE-Y1…Y4` | the book makes the closing entries itself and prints them in the year-end section and on the last rows of the ledgers they touch: heads to the result; the result and the drawings to own money; the partnerships through the posted P&L Appropriation Account; the trust's deficit to the General Fund (`RS-Y3`); the joint family's saving to its own money (`RJ-Y3`). |
| O-19-2 | all five | section 4.1 | the trial balance has closing balances only. |

### 20. Reports
| Row | Book | Entries / section | What shows it |
|---|---|---|---|
| O-20-1, O-20-2 | all five | head lines | see O-01-1. |
| O-20-3 | all five | year-end sections | accounts list, ledgers, Day Book, Cash Book, trial balance, statement of one account, who owes what, position, the year's statement, carry-forward; household *Income & Expenses* (`JP`, `RJ`, `RA`, `RB`, `RC`), business and farm *Profit & Loss* (`JT`, `S`, `BF`, `RG`, `RE`, `RK`), partnership P&L Appropriation and partners' accounts (`BF`, `RK`), joint family the family summary, trust the three statements and the fund statement. |
| O-20-6 | all five | section 3.4 | one account for a chosen period: opening, every entry with its note, totals, closing. |
| O-20-9 | all five | section 3.5 | who owes what, up to 30 · 31–90 · over 90 days, oldest settled first. |

---

## B. Mechanics merged from the five practice books

The finished outputs of the merged books are in `docs/archive/reference/practice-books-merged/`.

| From | To | Mechanic | Entries / section |
|---|---|---|---|
| truck | individual | a vehicle bought on a loan, the lender paying the seller (`Dr Thing owned · Cr Loan · Cr Bank` for the margin) | `JP-027` |
| truck | individual | EMI lines split from the lender's statement (`Dr Loan · Dr Interest on loan · Cr Bank`) | `JP-030`, `JP-040`, `JP-042`, `JP-046` |
| truck | individual | a driver's advance settled against several heads, the part with no bill moved to his account, the rest returned | `JP-033`, `JP-036`, `JP-037` |
| truck | individual | a FASTag wallet: loaded by transfer, spent on tolls | `JP-022`, `JP-051` (`JP-036` has the driver's tolls) |
| farmer | family (Agriculture) | KCC as a loan account: drawn, costs paid from it, interest charged, repaid | `RG-009`, `RG-027`, `RG-016`, `RG-020`, `RG-039`, `RG-005`, `RG-031` (already there; verified) |
| farmer | family (Agriculture) | arhtiya: full sale on khata, his charges taken on credit, the net paid | `RG-024`, `RG-025`, `RG-030`, `RG-034` (already there; verified) |
| farmer | family (Agriculture) | MSP wheat paid into the bank; straw sold | `RG-004`, `RG-007` (already there) |
| farmer | family (Agriculture) | added: milk to the dairy society on khata, paid later (the opening bill, two half-year bills) | `RG-002`, `RG-021`, `RG-023`, `RG-040` |
| farmer | family (Agriculture) | added: PM-Kisan instalments, cattle feed and the vet, four buffaloes at cost | `RG-017`, `RG-019`; buffaloes in section 1 of `RG` |
| farmer | family (Agriculture) | a worker's advance (Aman's labour money), settled against slips | `RG-012`, `RG-015` and later (already there) |
| landlord | family (Real Estate) | an improvement added to a building's cost; a repair stays expense | `RE-017`; `RE-006`, `RE-023` → `RE-024` |
| landlord | family (Real Estate) | rent written off (*Rent written off*) | `RE-029` |
| landlord | family (Real Estate) | a deposit set off against unpaid rent | `RE-019` |
| landlord | family (Real Estate) | a deposit forfeited to income (*Deposit forfeited*) | `RE-020` |
| landlord | family (Real Estate) | tenants on khata, rent charged in one entry, deposits per tenant | `RE-001`, `RE-007`, `RE-012`, `RE-021`; chart |
| contractor | partnership | a contract job for a builder with 5% retention held back, in its own account | `BF-009`, `BF-025`, `BF-040`; released `BF-048`, paid `BF-050` |
| contractor | partnership | a mobilisation advance recovered bill by bill | `BF-002`, `BF-019`, `BF-032`, `BF-045` |
| contractor | partnership | a supplier paid in advance whose account crosses to the other side and back | `BF-006`, `BF-015`, `BF-020` |
| contractor | partnership | an advance settled with part written off | `BF-047`, `BF-051` |
| committee | trust | an earmarked fund (*Langar Hall Fund*) receiving donations given for that purpose | `RS-003`, `RS-017`, `RS-041` |
| committee | trust | the fund's fixed deposit, its interest credited to the fund | `RS-050`; deposit in section 1 of `RS` |
| committee | trust | spending from the fund | `RS-028`, `RS-035` |
| committee | trust | R&P, I&E, Balance Sheet | sections 4.2, 4.3 and the balance sheet |

Practice-book items that did not need a new home because an existing entry already shows the same thing: freight on khata by quarter, diesel khata, a customer who pays late and in part (`S`, `BF`, `RE`, `RK` khatas); a mela advance with the unspent part returned (`JP-037`, `RE-028`); a sponsor on khata and a tent bill on credit (the ordinary khata entries in `S` and `BF`); subscriptions written when received (the trust's donations, `RS-002`); a fixed deposit by transfer (`RJ-032`). Not carried, because the ADR does not list them and nothing in the rulings needs them: the committee's subscriptions and mela as such, the landlord's caretaker float, a tenant who paid ahead, and the truck's quarterly freight and diesel khata.

---

## C. Ruled rows deliberately not shown

| Row | Reason |
|---|---|
| O-01-5, O-03-4, O-04-4 | source citation, terminology or a class label shown only in the technical companion; no book owes more than it owns, so O-04-4 does not arise. |
| O-02-4 (*Loan from – {person}*) | the asset side (`JP-007`) is shown; a loan taken from a person who charges interest is the same account kind on the liability side and no book here borrows from a person. |
| O-05-3, O-08-4 | no book runs an overdraft. |
| O-05-4 (listing cheques not yet presented) | the bank-statement table shows every line given an account; timing differences are an app view. |
| O-06-6 | no bad debt is recovered in the year. |
| O-08-2 (a later correction of the lender's interest) | no difference arises in the books. |
| O-09-8 (a deposit returned in cash) | no tenant's deposit is returned in the year; the set-off and the forfeiture are shown. |
| O-09-9, O-13-3, O-12-6 | no rupee limit is an entry; no goods are taken by an owner and none is lost by fire or theft in the year. |
| O-10-2, O-10-3, O-19-3, O-19-4 | opt-in year-end adjustments (closing stock, accruals, depreciation) — the books are kept on the khata basis and none opts in. |
| O-11-4 | no correction to a closed year arises. |
| O-14-6 | no ratio changes during the year. |
| O-16-5 | the per-pair statement is the family summary's table (opening, given, received, entries, agree); a side-by-side listing of every entry is the same entries as the two ledger accounts. |
| O-17-3 | the hall is *Construction*, an expense head (O-09-7), so no asset is bought from the fund and the fund is not released to the General Fund. |
| O-17-5, O-17-10 | no legacy is received, and the trust has no members' dues to track. |
| O-18-2 | no tenant pays ahead in the year (the landlord's flat tenant was not carried into the Real Estate book). |
| O-19-5 | a month lock and the month-end count are app behaviour, not entries. |
| O-20-2 (*Year open – figures may change*) | every book here is a closed year, so only the *Year closed* head is printed; the open-year head is an app state. |
| O-20-5, O-20-8 | no cash flow statement and no statement of affairs are produced (ruled). |

---

## D. Readings the rulings leave open (flagged, not decided)

- **Partners' drawings.** O-13-1 gives a sole trader a separate *Drawings* account closed to own money; O-14-4 and O-14-5 give a partner a current account but do not say whether a partner's drawings go through a *Drawings* account. The books debit a partner's drawings straight to his current account (`BF-007`, `BF-016`, `BF-017`, `RK-016`) and close nothing separately; the posted appropriation then adds interest and share to that account.
- **Own-money account of a business owned by a family or an individual.** O-13-4 and O-15-3 say the business account is held at the money put in; O-13-1 and O-19-6 say the owner's *Capital* and *Drawings* in the business book. The books name those two accounts after the owner (`JT`, `RG`, `RE`) so the pair summary can show them against the owner's book; whether the summary should name the accounts after the other *book* instead (the ADR of 12 Oct 2026 rule) is for the bookkeeper's review.
- **Fund spending when construction is an expense head.** O-17-1 (charge Income & Expenditure, transfer from the fund) and O-17-3 (an asset bought from a fund releases the fund to the General Fund) together with O-09-7 (construction may be an expense head) leave the trust's hall paid partly from the fund and partly from general money: the books follow O-17-1 for the part paid from the fund (`RS-028`, `RS-035`) and charge the rest in full (`RS-049`).

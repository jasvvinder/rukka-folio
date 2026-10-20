# GAPS.md — what the five reference books need that the app's rules do not yet provide

Developer document (technical by design). The five printed books in this folder are the **target output** (ADR 2026-10-12 §10, reworked by ADR 2026-10-20 §2): how a competent Indian bookkeeper keeps these books from real transactions, on the khata basis — no tax, no stock, no payroll, no depreciation, no accruals — with the year close **posted by the book itself**. This file lists every place where producing them needs something `docs/02-ledger-rules.md` or the ADRs do not provide, or provide differently. Re-derived on 20 Oct 2026 for the five books; it replaces the ten-book version of 13 Oct 2026, takes in the mechanics of the five practice books merged on 20 Oct (their outputs are archived at `docs/archive/reference/practice-books-merged/`) and reflects the 124 rulings of 20 Oct 2026 in `docs/archive/reference/accounting-research/OPEN.md`. `COVERAGE.md` is the map from each ruling to the entries that show it.

**Where the rulings now contradict the app.** The ADR of 20 Oct 2026 (Consequences) leaves these to the app-requirements pass after the bookkeeper's review: 02 §5 **amends** an open-period entry where the rulings correct by a new entry (A12); 02 §7 requires approval for an advance (A10); ADR 2026-09-05e §2 keeps drawings separate and carries no closing entries where the rulings post the year close and close drawings to own money (A13, C2); 02 §8.1 carries the year's result as one line where the rulings carry one own-money figure per owner. Nothing below changes behaviour; it records what the books need.

**Citations.** `02` section numbers as read on 20 Oct 2026 (`grep -n "^## \|^### " docs/02-ledger-rules.md`): §1.2 Accounts :19, §1.4 invariants :72 (rule 7, shapes, :79), §2 the six verbs :83, §4 openings :124, §5 corrections :143, §6 inter-book :151, §7 advances :169, §7.1 partner accounts :181, §8.1 year close :283, §8.2 cash counts :303, §9 balances :346, §10 statement import :354. **Entry numbers** are the printed ones: `JP` Jasvinder Singh's personal book, `JT` Jasvinder Technologies, `S` the shop, `BF` Bal Fabricators, `RJ` `RA` `RB` `RC` `RG` `RE` `RK` the seven Randhawa books (Joint Family, Amarjeet's, Lakhbeer's, Lakhwinder's, Agriculture, Real Estate, Brick Field), `RS` the trust; `-Y` numbers are the year-close entries the book makes. Each book's `.tech.md` maps every entry to its formal voucher type and the 02 §2 verb it would need.

---

## A. Gaps common to several books

### A1. Things owned, carried at cost — the `asset` class (ADR 2026-10-12 §6, ruled, not built)
- **Practice:** a car, laptops, a display rack, a welding set, machinery, a motorcycle, a tractor, farm land, buffaloes, a house, gold, shops, plots and a kiln are asset accounts at cost, under *What I have*, never in the year's statement; every position that shows them prints *Things owned are shown at what they cost; no depreciation is charged.* (O-09-1). Bought from the bank: `JT-008`, `S-035`, `BF-038`, `RB-007`, `RE-025`; **bought on a loan the lender paid to the seller:** `JP-027` (one Money out — Dr car ₹9,00,000 · Cr loan ₹8,00,000 · Cr bank ₹1,00,000); added to an existing asset: `RE-017` (a mezzanine floor — an improvement, where a repair `RE-006` stays expense), `RE-027` (stamp duty and registry, through an advance, into the plot's cost); **sold at a profit:** `RE-014` (one Money in — Dr bank ₹15,50,000 · Cr plot at cost ₹12,00,000 · Cr *Profit on Sale of Plot* ₹3,50,000); donated and kept, at ₹1 with the estimated value in the note: `RS-045` (O-17-7). Openings at cost in every chart that has one (O-04-7).
- **02 says:** §1.2 (:19) has no asset class; §1.4 rule 7 (:79) lets Money out debit only `{expense | party}`. ADR 2026-10-12 §6 rules the class; 02's table changes with its build slice.
- **App needs:** the `asset` class (printed *Thing owned*; a deposit prints *Deposit*, also standard type Asset), purchase and addition shapes (`Dr asset · Cr money`, `Dr asset · Cr advance`, `Dr asset · Cr loan · Cr money`), **sale of an asset** with the difference to an income head (or an expense head on a loss), asset openings, and the one-line cost statement on every report that shows them. Depreciation stays off (F1).

### A2. Loans, deposits held and amounts owed that are not an everyday khata
- **Practice:** the car loan (`JP-027` opens it; `JP-030`, `JP-040`, `JP-042`, `JP-046` — one bank line each, split `Dr Car Loan (principal) · Dr Interest on Car Loan · Cr bank` from the lender's statement, O-08-1). **A loan to a person** that carries interest has its own account beside the khata, *Loan to – {person}* (O-02-4): `JP-007` lends, `JP-031` returns part, `JP-032` interest received, `JP-049` the rest written off (O-12-1). The KCC as a running loan account used as money: drawn `RG-009`, `RG-027`; costs paid from it `RG-016`; interest charged `RG-020`, `RG-039`; repaid `RG-005`, `RG-031` (O-08-3). Deposits held from tenants, **one account per tenant** (*Deposit held – {tenant}*; owner, 13 Oct 2026; O-09-8): `RE` chart; `RE-019` set off, `RE-020` forfeited. A deposit paid, per person: `S` chart (*Deposit paid – Kapoor Properties*). **Retention money** a customer holds back, in its own asset account beside the khata (O-06-4): `BF-009`, `BF-025`, `BF-040` (held), `BF-048` (released by transfer), `BF-050` (paid).
- **02 says:** a loan is a `money` subtype (§1.2 :19), so paying it is a Transfer (§2 verb 5) — but an instalment that is part principal, part interest, a purchase that is part loan, part bank, and a retention line are shapes §1.4 rule 7 does not admit. Deposits held and retention money have no class: Money in credits only income or a party (§2 verb 1).
- **App needs:** (a) a loan-instalment shape (one money line → loan principal + interest expense); (b) a Money out or purchase that also credits a loan (`Dr asset · Cr loan · Cr money`); (c) **ruled:** per-person accounts on the person's page beside the khata — *Deposit held*, *Deposit paid*, *Retention held by*, *Loan to / from* — with set-off, forfeiture, release and return as explicit entries (A5); (d) the KCC as a named subtype.

### A3. Money kept aside — fixed and recurring deposits
- **Practice:** a deposit that matured, back to savings by Transfer `JP-018` (not income, O-13-5); new deposits by Transfer `RJ-032`, `RC-017`, `RC-037` (post-office RD); the Langar Hall Fund's fixed deposit (a chart opening) and **its interest added to the deposit by the bank** `RS-050` (O-09-5); interest paid out to savings `JP-039`, `RJ-040`.
- **02 says:** money subtypes are saving / current / OD / CC / loan / wallet (§1.2 :19); no deposit subtype and no "interest added to a deposit" shape (Dr deposit · Cr income or fund, no money).
- **Ruled 13 Oct and 20 Oct 2026:** a deposit is its own type, *Deposit*, not a *Thing owned*, not part of cash and bank (O-09-3); interest recorded when the bank credits it (O-09-4).
- **App needs:** a *Deposit* account reachable by Transfer, under *What I have*, and the non-money interest-credit entry.

### A4. Money kept for a purpose — the earmarked fund (trust)
- **Practice:** donations for the langar hall `RS-003`, `RS-017`, `RS-041` and the deposit's interest `RS-050` are added to *Langar Hall Fund A/c*; the hall is paid from it `RS-028`, `RS-035`. The fund sits with the own money, beside the General Fund (O-02-1), in the positions and the balance sheet, with its own statement (section *Each fund — its year*). Interest on a fund's deposit goes to the fund (O-17-2).
- **02 says:** no fund role in `equity_system` (§1.2 :19); Money in may credit only income or a party.
- **App needs:** a *fund* class, natural Cr, outside the year's result, shown with the own money, receiving Money in and the deposit's interest, with a statement of its own; spending from it is E2.

### A5. Entries that move no money, or move money and something else
- **Practice:** a deposit set off against what a tenant owes `RE-019` (`Dr Deposit held · Cr tenant`); the rest of a deposit kept `RE-020` (`Dr Deposit held · Cr Deposit forfeited`, income); a balance written off to an expense head — `JP-049` (*Written off*), `S-057` (*Written off*), `RE-029` (*Rent written off*), and the lost slips inside an advance settlement `BF-051`; retention released to the khata `BF-048`; a partner paying a firm cost from his own pocket `BF-008`, `BF-049` (supported — B3); a **cash count that differs** charged at once `S-042` (short), `S-056` (over) to *Cash short / over* (O-11-1); a **salary advance recovered in the salary entry** — `JP-021`, `JT-026`, `S-028` (`Dr Salary · Cr Advance · Cr bank`: one Money out with a non-money credit line, O-07-5); a settlement of an advance against several heads, with the remainder moved to the person or written off — `JP-036`, `BF-037`, `BF-051`, `RE-027`.
- **02 says:** verb 6 is guided only, counter-account always `equity_system` (§2 :83); a write-off goes to Adjustments, not the P&L (§2, §7) — superseded in direction by ADR 2026-10-12 §8 (*Written off* head, ruled, not built); a Money out may credit only money (§1.4 rule 7).
- **App needs:** party-to-liability set-off; deposit forfeiture to income; write-off to an expense head (§8's build slice); an advance settlement that may carry several heads, a remainder moved to the person and a write-off; a Money out that also recovers an advance; retention release; the cash short / over head.

### A6. Bank statement → entries (the owner's own workflow)
- **Practice:** the individual (both books) and the shop print one month's statement with every line given its account (section 3.6). One line can be a two-debit instalment (`JP-030`), a three-line purchase (`JP-027`: the lender's part never passes through the bank, only the margin does), a party receipt, a transfer to cash, a card bill, a drawings line, a deposit, an expense. A line not yet given an account waits as *Not yet sorted* and must be sorted before the year closes (O-11-3).
- **02 says:** §10 (:354) file-upload import with matched lines and Suspense; postings are the six verbs.
- **App needs:** per line, every account class above (A1–A4) and the split-line case (A2a); the extract as a printable view; *Not yet sorted* in place of Suspense.

### A7. Registers and entry tags — dropped (owner, 12 Oct 2026)
- No registers and no tags. A trip, a member, a tenant or a deposit is an account the user names; details are in the entry's note; *who owes what, and since when* is the ageing list (07 §14), drawn from the person/shop ledgers alone.

### A8. Statements and heads every book prints
- **Report head on every report (O-01-1, O-20-1, O-20-2):** the book, the date or period, the basis in one line (*Kept on money paid and received, and what people owe; no year-end adjustments.*), *Year closed* (or *Year open – figures may change*), *Made on {date and time}*. Not in 07 §14. In the books the date is pinned so reruns are byte-identical; the app uses the real time.
- **Positions at 30 Sep and 31 Mar** with the own money's make-up (start + put in − taken out + income − spent): 07 §14 *Full Position* and 02 §9 (:346), except that A1–A4 accounts have nowhere to sit.
- **One month as an account-by-account summary** (section 3.3) — not described in 02; verify in 07 §14 before building.
- **One account for a chosen period, with each line's note** (section 3.4; O-20-6) — ADR 2026-10-12 §5 rules *any period, any account*; 02 §8.1's clause lands with the reports slice.
- **You will get / You will give with ageing** — 07 §14; buckets up to 30 / 31–90 / over 90 days, oldest settled first (O-20-9).
- **Receipts & Payments, Income & Expenditure, Balance Sheet and a statement for each fund** (trust `RS`; O-17-9, O-20-4) — not among the app's reports.
- **P&L Appropriation and the partners' table** (`BF`, `RK`) — see B1.
- **Family summary** (`joint-family-randhawa`) and the two-books summary (`individual-jasvinder-singh`) — 02 §6's Family Reconciliation (:151) in a printed form; see A11.
- **Day Book marks an entry that moves no money** *no money moved* (O-03-3); no nakal bahi.
- **Print and export options** (ADR 2026-10-12 §11, amended 13 Oct 2026). The printed book is accounts, ledgers (each row with its note in small type), statements and year end; the Day Book and the Cash Book are an export (`<file>.export.md`). The app needs print and export of the ledger, the Day Book and the Cash Book for any period, with or without notes, and a chooser: **All**, or a multi-select of sections and of the accounts whose ledgers to include. 07 §14 should carry it.

### A9. Plain words that the glossary does not yet have
- **Printed type words** — short and plain, in the accounts list only (owner, 13 Oct 2026; ADR 2026-10-12 §14): *Cash, Gollak, Bank, Wallet, Credit card, KCC loan, Person / shop, Money in a business, Advance, Loan given, Retention held, Thing owned, Deposit, Loan, Deposit held, Fund, Own money, Drawings, Owner, Partner, Partner's capital, Partner's current, Sub-family, Joint family, Income, Expense*.
- **Column words:** *Given (Dr) / Received (Cr)* (other family book), *Put in (Dr) / Taken out (Cr)* (own business), *Lent (Dr) / Paid back / written off (Cr)*, *Held back (Dr) / Released (Cr)*, *Paid in (Dr) / Spent on the card (Cr)*, *Paid in (Dr) / Drawn / charged (Cr)* (KCC), *Counted in (Dr) / Emptied (Cr)* (gollak), *Taken out (Dr) / Put in (Cr)* (partners).
- **Entry types:** *Advance settled, Paid by a partner, Paid by the joint family, Paid from a fund, Interest added to a deposit, Written off, Deposit set off, Deposit forfeited, Retention released, Correction*, *no money moved* beside the glossary's *Money in, Money out, Transfer, Gave on credit, Took on credit, Fix / Adjust*.
- **Heads and report words:** *Written off, Rent written off, Deposit forfeited, Cash short / over, Income from {business}, Transferred from the {fund}*; *Receipts & Payments, Income & Expenditure, Income & Expenses, Saving / Spent more than came in, P&L Appropriation, Family summary, Year closed, Made on*.
- **App needs:** EN · ਪੰਜਾਬੀ · हिन्दी rows in 01 §2 (native review per 01 §4).

### A10. Advances to people who are not book members
- **Practice:** a house help (`JP-011`, `RA-016`), a driver (`JP-033`, settled `JP-036`, unspent part returned `JP-037`), a developer (`JT-018`), a salesman (`S-019`), a foreman (`BF-035`, `BF-047`), the trust's sewadar (`RS-001`, `RS-026`, `RS-040`), a farm manager (`RG-012`, `RG-022`, `RG-037`), a moulder jamadar (`RK-001`…), a registry clerk (`RE-026`, unspent part returned `RE-028`), a mason (`RJ-012`), a painter (`RB-013`), an electrician (`RC-011`). Settled in one entry against several heads (`JP-036`, `BF-037`, `RE-027`); what is left is **carried forward** (`BF-051` ₹1,700; `RS-056` ₹1,100), **moved to the person** (`JP-036` ₹1,800), or **written off** (`BF-051` ₹1,000) — O-07-4. A salary advance is recovered in the salary entry (A5, O-07-5).
- **02 says:** §7 (:169) `Advance – {member}`, auto-created per member, request and approval always required.
- **App needs:** an advance account for any named person (*Advance – {person}*), created like a party and shown on the person's page beside the khata, with hand-out, multi-head settlement, return of the unspent part, top-up, the three ways to deal with the remainder, and recovery in a salary entry, recorded by the owner without an approval flow. The word *imprest* is not used (O-07-6).

### A11. Accounts between books named after the other book — the joint family and the owner's book
- **Practice (owner, 13 Oct 2026; O-13-4, O-15-*, O-16-*):** every pair is named after the other book (never *Due to/from*); each file's summary shows the brought-forward balances agreeing and every entry mirrored; a running-account pair also agrees balance for balance, while an owner and his business agree entry by entry and the summary prints the *profit kept in the business* as the difference (O-16-1, amended 20 Oct 2026). Three shapes:
  1. **Joint family ↔ sub-family — a running account, not a debt.** In the joint book, *Amarjeet's Family A/c* (and Lakhbeer's, Lakhwinder's): household money given (`RJ-001`), money taken *to be returned* (`RJ-010`), a household bill the family pays directly (`RJ-028`, `RJ-033` — mirrored in the household book as *Paid by the joint family*, `RA-022`, `RB-023`) on the Dr side; money the household puts in on the Cr side — into the family (`RJ-006`) or **straight into a family business**, written in three books (`RC-023` · `RK-019` · `RJ-023`), or by **paying a family-business bill from its own money** (`RB-019` · `RK-026` · `RJ-025`). At the year end the account is **settled or carried forward** (O-15-5): settled with the family bearing it (`RJ-038` ↔ `RA-030`), settled from the sub-family's **share of the family's business income** (`RJ-037` ↔ `RB-028`; a share-out of the family's own money like drawings, never a reduction of the family's income — O-15-5), or carried forward (Lakhwinder's). In both books these accounts sit under own money, never under *will get / will give*.
  2. **Owner's book ↔ a business it owns.** The owner's book holds the business at the money put in (`JP-008` ↔ `JT-007`; `RJ-005`, `RJ-022` ↔ the Agriculture and Brick Field accounts) and **money the business sends home is income, *Income from {business}*** (`JP-001`, `JP-012`, `JP-026`, `JP-034`; `RJ-004`, `RJ-007`, `RJ-015`, `RJ-024`, `RJ-027`, `RJ-036`) — the cost method, the same rule for the individual and the joint family (O-13-4, O-15-3). In the business book of a sole proprietor the same money is *Capital A/c – {owner}* (put in) and *Drawings A/c – {owner}* (sent home), accounts named after the owner, whose personal book is the other book of the pair (`JT`, `RG`, `RE`); in a partnership it is the partner's account (`RK`).
  3. **The business's own profit** is computed in its own book and stated in the summary, not taken into the owner's income (O-15-4).
- **02 says:** §6 (:151) pairs are `equity_system` *Due to/from {Book}*, one account per side, placed by sign; its one-sided case (*a member pays a family expense from his own pocket*) is the nearest to the *Paid by the joint family* entries. ADR 2026-09-09c §2: sub-family shares are books, never accounts inside one book. 02 §7.1 gives a *Just me* business a Capital/Drawings pair and a shared business Partner Current accounts. Nothing in 02 provides an income head as one side of a pair, a three-book entry, or a year-end settlement of a pair.
- **App needs:** (a) a pair whose sides are own-money accounts in both books (sub-family ↔ joint family) — ADR 2026-09-09c §2 should be re-read against it; (b) a pair whose owner-book side is two accounts (money put in at cost + *Income from …*) and whose business side is capital and drawings named after the owner; (c) a three-book entry, with the joint book's side written as a no-money entry; (d) a year-end **settle or carry forward** choice per sub-family account; (e) the family summary as the printed form of 02 §6's Family Reconciliation.

### A12. Corrections as their own entry — now ruled (O-11-2, O-11-5)
- **Practice:** every book corrects one entry written to the wrong head by a separate *Correction* entry (`JP-045`, `JT-028`, `S-023`, `BF-023`, `RS-021`, `RJ-031`, `RA-010`, `RB-021`, `RC-028`, `RG-036`, `RE-024`, `RK-013`) — `Dr right head · Cr wrong head`, no money — and **its note names the entry it fixes, with number and date** (*Entry JP-043 of 20 Feb 2026 …*). A correction to a closed year is made in the current year with a note naming the year; a closed year is never reopened (O-11-4).
- **02 says:** §5 (:143) an open-period entry is **amended** (a new version replacing the old); only a locked period uses a reversal and re-entry.
- **App needs:** the rulings overrule 02 §5 in practice: corrections are new entries citing the entry fixed. A change to 02 §5 and to the amend flow, taken up after the bookkeeper's review.

### A13. The year close is posted (O-19-1, O-19-6, O-13-1, O-14-1, O-17) — new in this version
- **Practice:** every book prints the entries the book makes itself on 31 Mar 2026 and carries them on the last rows of the ledgers they touch: `JP-Y1…Y3`, `JT-Y1…Y4`, `S-Y1…Y4`, `BF-Y1…Y5`, `RK-Y1…Y4`, `RS-Y1…Y3`, `RJ-Y1…Y3`, `RA`, `RB`, `RC` `Y1…Y3`, `RG`, `RE` `Y1…Y4` — income and expense heads to the result (*Profit & Loss*, *Income & Expenses*, *Income & Expenditure*); the result and *Drawings* to own money; a partnership's through a posted *P&L Appropriation Account* to each partner's account; a trust's surplus or deficit to the General Fund. The carry-forward then opens with one own-money figure for each owner and no result line.
- **02 says:** §8.1 (:283) carries balances forward without re-posting and records the year's net surplus or deficit as one line; category accounts are not carried; ADR 2026-09-05e §2 keeps each FY's P&L computed from that FY's envelopes alone and drawings separate.
- **App needs:** a year-close step that posts the closing entries (never typed by the user), their display in the year-end section and on the ledger rows, and a carry-forward of own money per owner. A ruling on whether a posted close changes the certified closing vector's shape (02 §8.1) — taken up after the bookkeeper's review.

---

## B. Shared businesses — Bal Fabricators (`BF`) and Randhawa Brick Field (`RK`)

| # | What practice does | 02 / ADR position | What the app needs |
|---|---|---|---|
| B1 | **P&L Appropriation posted** at the year close (O-14-1): `BF-Y3` net profit to the account, `BF-Y4` 6% interest on fixed capital (the partners agreed it, and only out of profit — O-14-3), `BF-Y5` the 2 : 2 : 1 shares to each partner's current account; `RK-Y3`, `RK-Y4` 3 : 2 with no interest. Interest on capital and partners' salary are appropriations below the line (O-14-2). The balance sheet's partners' table shows each partner's account before and after the close; the carry-forward opens with one own-money figure per partner. | §7.1 (:181) posts the distribution as one multi-line entry `Dr Profit Distributed · Cr Partner Current`; no interest on capital in 02 | adopt the posted appropriation (ruled); interest on capital as an option, paid only out of profit |
| B2 | **Fixed capital + current account per partner** (`BF`: *Capital A/c – X* never moves; drawings and own-pocket payments go to *Current A/c – X*) vs **one fluctuating account per partner** (`RK`) (O-14-4) | §7.1 has one Partner Current account per owner | a fixed-capital option (a second partner account that only a partners' decision moves) |
| B3 | A partner pays a firm cost from his own pocket `BF-008`, `BF-049`; `RK-026` (`Dr expense · Cr Current A/c`) (O-12-5, O-14-5) | §7.1 row 1 — **supported** | none; plain type *Paid by a partner* |
| B4 | Partnership openings are each partner's agreed figures; the firm's assets balance them (`BF` chart) with no balancing line (O-04-5) | §4 openings against Opening Balance / Capital; §7.1 contributions credited to partners | confirm that no Opening Balance / Capital line appears when the partners' figures balance the firm's |
| B5 | An outside partner's drawings entered on his instruction (`RK-016`, `RK-034`) (O-14-7) | §7.1 settlement routes; ADR 2026-10-11 reading for a partner not on the app | confirm entry by another member for a non-member partner |

## C. Individual and households — `JP`, `JT`, `RJ`, `RA`, `RB`, `RC`

| # | What practice does | 02 / ADR position | What the app needs |
|---|---|---|---|
| C1 | Credit card as a money account that sits Cr: spends `JP-006`, `JP-015`, `JP-029`, `RC-005`; bill paid by Transfer `JP-005`, `JP-009`, `JP-017`, `JP-025`, `RC-003` (O-05-1). A FASTag wallet as a cash-like money account: loaded `JP-022`, spent `JP-051` (O-05-2). | §1.2 lists money subtypes saving / current / OD / CC / loan and §2 verb 5 `Dr CC · Cr bank`; 02 does not say whether *CC* means a credit card or cash credit — **supported if a card is a CC**; wallet is a subtype | confirm; the card and the wallet in the add-account grid (ADR 2026-10-12 §6) |
| C2 | A one-owner business book keeps *Capital* and *Drawings* named after the owner (`JT`, `RG`, `RE`), the year's result and drawings closed to capital at the year close (O-13-1, O-13-2, O-19-6) | ADR 2026-09-09b seeds a Drawings account for *Just me*; ADR 2026-09-05e §2 does not close it | the year close (A13); the naming rule of A11 (b) |
| C3 | **Household statements** titled *Income & Expenses*, result *Saving* / *Spent more than came in* (`JP-Y3`, `RB-Y3`): income is salary, interest, rent, *Income from {business}* and gifts received (`JP-014`); never loans taken (`JP-027`), money returned (`JP-031`, `JP-037`), transfers between own accounts or a deposit coming back (`JP-018`) — **ruled** (O-13-5). | 07 §14 report names per book type | report naming for personal / household books, and the income test for a household |
| C4 | A household's account with the joint family sits under its own money, not under *What I will give* (owner, 13 Oct 2026) | §6 places a pair by sign | A11 (a) |
| C5 | A loan to a friend that carries interest: *Loan to – {person}* (`JP-007`, `JP-031`, `JP-032`, `JP-049`) (O-02-4) | no loan-given class | A2 |

## D. Shop, partnership job work, farm, landlord

| # | What practice does | 02 / ADR position | What the app needs |
|---|---|---|---|
| D1 | Goods bought for sale are spent when bought (`S` *Goods Bought for Sale*); no closing stock; the shop's statement prints *No stock is counted. Everything bought for sale is treated as sold or used in the year it was bought.* (O-10-1) | inventory is a non-goal (00) | the line on the shop's statement |
| D2 | A builder's **5% retention in its own account** beside the khata: `BF-009`, `BF-025`, `BF-040`, released `BF-048`, paid `BF-050`; the **mobilisation advance recovered bill by bill** `BF-002`, `BF-019`, `BF-032`, `BF-045` (O-06-4) | party by sign for the advance — **supported**; no retention concept | a *Retention held by – {party}* account and a release entry (A2) |
| D3 | A supplier paid in advance crosses to Dr and back (`BF-006`, `BF-015`, `BF-020`) (O-06-2) | party by sign — **supported** | none |
| D4 | KCC as a running loan account used as money (`RG`, A2) | money subtype loan, Cr by sign; verbs 2 and 5 — **supported** | the KCC as a named subtype with its plain words |
| D5 | Arhtiya: full sale on khata `RG-024`; charges taken on credit `RG-025`; the net paid `RG-030`, `RG-034` | verbs 3 and 4 — **supported** | none |
| D6 | Rent charged to several tenants in one entry (`RE-001`, `RE-007`, `RE-012`) (O-18-1); a deposit set off and the rest forfeited (`RE-019`, `RE-020`); rent written off (`RE-029`); an improvement added to a building's cost, a repair expensed (`RE-017`, `RE-006`) (O-18-3…O-18-5) | verb 3 with several Dr parties — §1.4 rule 1 allows ≥ 2 lines; the shape check (rule 7) must admit several parties; A1, A5 | confirm multi-party *Gave on credit*; A1, A5 |
| D7 | Milk to a dairy society on khata, paid later (`RG-021`, `RG-023`, `RG-040`); PM-Kisan by direct transfer (`RG-017`); cattle feed and the vet (`RG-019`); buffaloes at cost (`RG` chart) | verbs 1–4 — **supported**; A1 | none |
| D8 | A customer's advance and a supplier's advance sit on the person's own account (`JT-006`, `S-008`, `BF-002`, `BF-006`) (O-06-2, O-06-3) | party by sign — **supported** | none |

## E. Trust — `RS`

| # | What practice does | 02 / ADR position | What the app needs |
|---|---|---|---|
| E1 | **Gollak: the count records the donation** (`RS-004` … `RS-051`: Dr *Gollak* · Cr *Donations – gollak*); **emptying is a transfer** into the cash box or the bank (`RS-005`, `RS-006`, …); money not yet counted is not recorded (O-17-8) | money subtype cash_collection; 02 §8.2 counts — **supported**; the donation-on-count posting is stated differently if 02 §8.2 makes the count a transfer only | confirm the count's posting |
| E2 | **Spending from a fund is one action, two postings** (`RS-028`, `RS-035`): Dr *Construction* · Cr bank (charged to Income & Expenditure) and Dr the fund · Cr *Transferred from the Langar Hall Fund*; the fund's own result is nil (O-17-1) | no fund (A4); a four-line entry | the fund spend shape (plain words: *paid from the Langar Hall Fund*) |
| E3 | *Construction* as an expense head (owner, 13 Oct 2026; O-09-7) — so a hall paid from the trust's own money is a deficit (`RS-049`) and the part paid from the fund is offset by the transfer | ADR 2026-10-12 §6's asset class could carry it at cost | none (ruled) |
| E4 | *Dairy Donation* is income — owner, 13 Oct 2026; general donations are income in Income & Expenditure (O-17-4) | categories — **supported** | none (ruled) |
| E5 | Manni and Ravinder as expense heads, paid each quarter in cash (`RS-010`, `RS-011`, …) | categories — **supported** | none |
| E6 | Material for the hall on a store's khata (`RS-013`, `RS-019`) | verbs 3 and 4 — **supported** | none |
| E7 | Receipts & Payments, Income & Expenditure, Balance Sheet and a statement of each fund from the same entries (O-17-9, O-20-4) | not among the app's reports | the four statements (A8) |

---

## F. Optional owner decisions (listed, not required)

| # | Decision | What it would need |
|---|---|---|
| F1 | **Depreciation** of things owned (opt-in year-end step, a rate per asset; O-09-1) | A1 + a guided year-end entry |
| F2 | **Year-end adjustments** — prepaid / outstanding / accrued and a closing-stock figure (O-19-3, O-19-4, O-10-2) — now ruled **opt-in, never the default**, reversed on day one of the next year; every report then says so in its head | a *paid ahead* asset and an *owed, not yet paid* liability, a closing-stock pair and a year-end wizard |
| F3 | **Closing to capital** — now ruled **posted** (A13): drawings and the result close to own money and the next year opens with one figure per owner | the year-close step |
| F4 | **Posting the partnership appropriation** (B1) — now ruled **posted** | 02 §7.1's distribution entry, with interest on capital as an option |
| F5 | **Write-off to an expense head** (A5, ADR 2026-10-12 §8) — ruled | its build slice |

---

## G. The order that steers development

1. **A1** — the asset class, with purchase, addition, sale at a profit or loss, openings, asset against a loan, and the cost line.
2. **A13 / B1** — the posted year close and the posted appropriation; 02 §8.1 and ADR 2026-09-05e §2 against the rulings.
3. **A11** — the joint family's sub-family accounts (settle or carry forward), the owner ↔ business pair, *Income from …* and capital/drawings named after the owner, three-book entries: rule them against 02 §6 and ADR 2026-09-09c §2 before building more pairs.
4. **A2 / A5** — the loan-instalment and loan-purchase shapes, per-person deposit / retention / loan accounts, set-off, forfeiture, write-off, release.
5. **A10** — advances to any named person, multi-head settlement, return, the three ways to deal with the remainder, recovery in a salary entry, no approval.
6. **A4 / A3 / E2** — the earmarked fund, its statement and its spend shape; the kept-aside deposit and its interest credit.
7. **A12** — the correction shape, overruling 02 §5's amend.
8. **A8** — the report head, Receipts & Payments, Income & Expenditure, fund statements, the one-month summary, the chosen-period statement, the ageing, the family summary, and print/export with a chooser (All or multi-select, any period, with or without notes).
9. **A6** — statement import mapping to every class above, to the two-debit line and the three-line purchase.
10. **A9** — glossary rows (EN · PA · HI) for the plain words above.

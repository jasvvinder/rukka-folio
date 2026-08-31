# 02 — Ledger Rules

**Status:** Draft 1 for build. 🔒 = locked. ⚠️ = decide/verify before the affected milestone.
**Behavioural reference 🔒:** `reference/financial-accounting-standards.md` and `reference/worked-examples/` — verified ledgers for all four entity types; the engine must reproduce them exactly.

**Companions:** 04-crypto.md (every ledger object travels as a signed, encrypted envelope), 06-auth-devices.md (roles, limits, membership states).

**Design goal:** Textbook double-entry underneath; a cashbook on top. The user chooses one of six verbs and answers two or three plain questions; the posting rule is fixed and cannot be gotten wrong. **The entry screen speaks plain verbs; statements, ledgers, and reports speak the professional terms** — Dr./Cr. as ਨਾਮੇ/ਜਮ੍ਹਾਂ, नामे/जमा in the traditional three-column layout (01 §1.9) — because professionals cannot be asked to work without them. Deep jargon (journal, voucher, contra, accrual, folio, narration) never appears.

**Zero-knowledge consequence 🔒:** the server cannot read entries, so **it enforces no ledger rule**. Every invariant in this document is enforced by the authoring client and re-verified by every reading client (entries are author-signed, 04 §8.3). An envelope violating an invariant is quarantined and raised as a security event — never silently displayed or summed.

---

## 1. Objects

### 1.1 Books 🔒
A book is an independent, self-balancing ledger. Types: `personal`, `family`, `joint`, `business` (and, per tenant type `organization`, books are the same objects with different display names). Books never nest; they connect only via due-to/due-from pairs (§6). Each book has its own chart of accounts, its own financial year (default 1 April – 31 March), and its own period locks.

### 1.2 Accounts 🔒
Accounts are encrypted content with stable UUIDs. Each has a **class**, which drives behavior and report placement:

| Class | Examples | Report placement |
|---|---|---|
| `money` | Cash in hand, each bank account (subtype: saving / current / OD / CC / loan), wallet | **By sign:** Dr balance → asset, Cr balance → liability. An OD swinging past zero or a savings account overdrawn needs no special handling — the sign flips, the display color flips. |
| `party` | one account per person/shop/firm you deal with | By sign: Dr → *You will get* (asset), Cr → *You will give* (liability). One party, one account, both roles. |
| `advance` | `Advance – {member}` auto-created per member per book | Asset; drives the peshgi flow (§7) |
| `partner` | `{Owner} — Partner Current A/c`, one per owner of a jointly-owned business | By sign: Cr = business owes them · Dr = they owe the business (§7.1) |
| `category_income` / `category_expense` | Salary, Shop sales, Diesel, Groceries… (seeded tree per book type, editable) | P&L |
| `equity_system` | Opening Balance, Adjustments, Due to/from {Book} (§6) | Equity / inter-book |

Placement-by-sign means the user never classifies anything. There are **no destructive closing journal entries** at year end 🔒 — carry-forward happens through the Year Close ceremony (§8.1), which certifies the closing balances and brings them forward as the opening balances (b/f) of the next financial year. P&L is computed per financial year; the balance sheet shows *Accumulated surplus*. Fewer concepts, nothing for a layperson to run or get wrong.

**User-facing naming 🔒:** every account of every class appears to the user as simply an **A/C (khata)** — one unified, searchable A–Z list with live balances (the Ledger tab *is* the index page of a bound ledger). The words *party* and *category* are internal. Creation is always **inline**: typing an unknown name in any picker slot offers *"+ Create '{name}' A/C"* on the spot; the class is **inferred from the slot** (created in *To whom?* → `party`; in *For what?* of Money Out → `category_expense`; in *From what?* of Money In → `category_income`). Where a slot legitimately allows both (e.g. Money Out's counterpart may be an expense category or a party being repaid), the app asks one plain question with two icon chips: *person/shop (udhaar possible)* vs *type of expense*. The same real-world name may exist as both — *Verma Dairy A/c* (`party`) and *Dairy Expense A/C* (`category_expense`) — and a party may carry an optional **usual category** so credit purchases auto-fill their expense side. Seeded trees per tenant type use the traditional names (household: Kirana, Doodh/Dairy, School Fees…; trust: Donation A/C, Langar A/C, Bhent A/C…), all renamable and deletable-if-unused, shipped trilingually per 01.

### 1.3 Entries 🔒
The plaintext JSON inside an envelope (04 §4):

```
Entry {
  id            : uuid
  kind          : money_in | money_out | gave_credit | took_credit
                | transfer | adjustment
  status        : pending | posted | void
                // 🔒 `pending` is ONLY an advance request awaiting approval (§7),
                // the one case where approval itself moves the money. Every other
                // entry is `posted` from the moment it is saved (§3). An ordinary
                // over-limit entry is `posted` with review_required=true — never
                // `pending`, and it counts in balances from the first moment (§9).
                // The open/approved/rejected *state* is not stored on the envelope:
                // it is projected by folding approval_decision envelopes (03 §3.3.5).
  review_required : bool           // 🔒 authored at save time by the client that
                                   // knows the limit; the projector may NOT read
                                   // book_roles (03 §3.3.5). Readers re-check it
                                   // against review_limit_paise below.
  review_limit_paise : int         // the limit in force at this entry's HLC
  review_approver?: user_id        // who must act, then who acted
  accounting_date : ISO date        (user-visible date; may differ from created time)
  lines         : [ { account_id, amount_paise } ]   // signed: + = debit, − = credit
  party_id?     , advance_id?      // denormalized refs for lists & ageing
  note?         , attachment_ids[]
  refs?         : { amends?: entry_id, reverses?: entry_id,
                    transfer_group?: uuid, import_line?: uuid, close?: uuid }
  created_by_user, created_by_device, hlc
}
```

### 1.4 Universal invariants 🔒
1. `sum(lines.amount_paise) == 0`, ≥ 2 lines, every line non-zero.
2. Amounts are **integer paise**. No floats anywhere — client, export, or display math.
3. Every `account_id` belongs to the entry's book. Cross-book effects only via §6.
4. Append-only: nothing is updated or deleted; state changes are new envelopes (amend, void, approve, lock).
5. Currency: INR only in Phase 1; the field exists (`"INR"`) so multi-currency is a migration, not a rewrite. ⚠️ revisit if NRI members demand it.
6. `accounting_date` defaults to today, is freely editable to any **backdate within an open period** (the forgot-an-entry case), must not be in the future (recurring entries own the future), and must fall in an open period as of the entry's HLC (§8).

---

## 2. The six verbs and their fixed postings 🔒

The user answers plain questions; the app builds the lines. Party-facing verbs auto-resolve against existing balances (paying ₹500 to a party you owe ₹2,000 simply reduces the payable — the user never chooses debit or credit).

| # | Verb (EN / ਪੰਜਾਬੀ / हिन्दी) | Questions | Posting |
|---|---|---|---|
| 1 | **Money in** / ਪੈਸੇ ਆਏ / पैसे आए | Into (cash/bank)? From (category or party)? | Dr money · Cr income-category, **or** Cr party (their udhaar to you shrinks / your payable to them grows) |
| 2 | **Money out** / ਪੈਸੇ ਗਏ / पैसे गए | From (cash/bank)? For (category or party)? | Dr expense-category **or** Dr party (your payable shrinks / their udhaar grows) · Cr money |
| 3 | **Gave on credit** / ਉਧਾਰ ਦਿੱਤਾ / उधार दिया | To whom? Gave what — money, or work/goods (income category)? | Dr party · Cr money **or** Cr income-category |
| 4 | **Took on credit** / ਉਧਾਰ ਲਿਆ / उधार लिया | From whom? Took what — money, or goods/expense (expense category)? | Dr money **or** Dr expense-category · Cr party |
| 5 | **Transfer** | Within a book: from/to two money accounts (covers cash↔bank, bank↔bank, and CC/loan payments: Dr CC · Cr bank). Across books: §6. | Dr to-account · Cr from-account |
| 6 | **Adjustment** (guided only) | Never freeform. Wizards: opening balances (§4), cash-count difference (§8), write-off a party/advance balance, reversal (§5). | Counter-account is always `equity_system` or the reversed entry's mirror |

Verbs 3 and 4 with the "money" answer overlap verbs 1 and 2 with a party — same posting, reached from either door. 🔒 Keep both doors; users think in both idioms.

**Online/offline paid** (from your one-screen requirement) is simply which money account the entry touches — cash vs a bank/UPI account — plus an optional `channel` tag for filtering. No separate accounting treatment.

---

## 3. Status lifecycle — post-then-review 🔒 (revised by owner decision)

**Principle: if the money already moved in the world, the book says so immediately. Approval-before exists only where the approval itself moves the money (advances §7).**

```
  create ────────────────────────────▶ posted            (always counts, instantly)
                                          │ over auto_post_limit for this member+book
                                          ▼
                                   posted + NEEDS-REVIEW flag ──approve──▶ flag cleared
                                          │──reject (reason)──▶ auto-reversal posted (§5),
                                                                 member notified; both
                                                                 entries stay in history
```

- **Every entry posts and affects balances the moment it is saved** — the collaborator's cash-in-hand always matches the drawer. There is no state in which recorded reality is excluded from a balance.
- `auto_post_limit_paise` (06 §1.1) is a **review threshold, not a gate**: above it, the entry carries a *needs review* flag shown in amber with the approver's name, and lands in the approver's Inbox.
- Approve = a signed envelope clearing the flag. Reject = a signed rejection that auto-posts the mirror reversal (§5) with the reason; the original and the reversal both remain visible — the audit trail never hides a dispute.
- **Nothing escapes review:** month close step 3 (§8) requires zero open flags before a book can lock.
- A member in their **own personal book** is never flagged.

---

## 4. Opening balances 🔒

**Every new account asks for its opening balance at creation 🔒 (owner-approved)** — not only during first-run setup. The question is phrased by class, never as Dr/Cr: money accounts ask *"balance today"* (negative allowed → overdraft); party accounts ask *"do they owe you, or do you owe them?"* with the amount (**you will get** / **you will give**); expense/income accounts default to zero for the current FY. Each posts one `adjustment` against Opening Balance (equity).

Guided setup per book, re-runnable until first lock: for each money account and party, the user states today's balance; each produces one `adjustment`: Dr/Cr account · Cr/Dr **Opening Balance** (`equity_system`). Individual entries need not net to zero across the book — Opening Balance absorbs the difference, and that is correct.

---

## 5. Corrections 🔒

- **Open period:** an entry may be **amended** — a new envelope, `kind` unchanged, `refs.amends = original`, carrying the complete replacement payload. Views show the latest amendment; history is preserved and inspectable ("edited by Ramesh, 2 changes"). Amend chains are linear (amend the head only).
- **Locked period:** amendment is forbidden by rule. The only path: **reversal** — an auto-built mirror entry dated in the open period, `refs.reverses = original`, plus (optionally) the corrected re-entry. One guided flow: *"Fix an old entry"* → app posts both.
- Reversed and amended-away entries remain visible in history, struck through. `void` status exists only as the derived state of a fully reversed entry.

---

## 6. Inter-book movement 🔒

Books connect through **paired system accounts** auto-created on first use: in book A, `Due to/from B`; in book B, `Due to/from A` (class `equity_system`, placement by sign).

One user action ("Move ₹50,000 from Kirana Store to Sharma Family") creates **two envelopes sharing `refs.transfer_group`**, one per book:

```
Business book:   Dr Due to/from Family   50,000 · Cr Bank 50,000
Family book:     Dr Bank 50,000 · Cr Due to/from Business 50,000
```

- Both halves post immediately (the money moved). If the actor lacks posting rights in one of the books, that half carries the *needs review* flag (§3) for that book's approver; position screens label the pair *in transit* while the flag is open. Reconciliation nets to zero from the moment of entry.
- The one-sided everyday case — a member pays a family expense from his own pocket — is the same mechanism: personal book `Dr Due to/from Family · Cr Cash`; family book `Dr Expense · Cr Due to/from Personal(member)` (flagged for review if over limit). Nothing is ever lost in someone's pocket.
- **Family Reconciliation report 🔒:** for every pair, balance(A→B) + balance(B→A) must equal 0. Any non-zero pair is listed with the entries composing it. This is the only cross-book integrity check that exists or is needed.
- Business↔business movement is the same mechanism. **Profit distribution is *not* an inter-book operation** — it is a single multi-line entry inside the business book against Partner Current A/cs (§7.1). Remitting business surplus to a family pool *is* an inter-book transfer, and the two must not be conflated.

---

## 7. Advances — the peshgi (ਪੇਸ਼ਗੀ / पेशगी) flow 🔒

- Advances are the deliberate exception to §3's post-then-review: **here the approval itself moves the money** — cash leaves the drawer upon approval, so nothing exists to mismatch. Requesting ₹X posts, on approval: `Dr Advance – {member} · Cr money`. Purpose text required; approval always required regardless of limit.
- Spending against it: `Dr expense-category · Cr Advance – {member}` (entered by the member, approved per limits, bill photo encouraged).
- Returning the remainder: `Dr money · Cr Advance – {member}`.
- The advance is **open** while balance > 0; **ageing** = days since the oldest unsettled debit. Reminders at N days to the holder, then the approver (N configurable per book, default 15/30).
- The member's own dashboard shows *money you are holding* per book; each book's dashboard shows *money out with people*, aged. Both derive purely from `advance` account balances — no separate state to drift.
- Write-off (never repaid): guided adjustment `Dr Adjustments (equity_system) · Cr Advance`, approver-only, reason required.
- Advance settlement is the **precondition for member removal** (04 §5.3) and appears as a hard gate in that flow.

---

## 7.1 Jointly-owned businesses — partner accounts 🔒 (owner-approved, 30 Aug 2026)

**Shared ownership is optional 🔒 (owner-approved).** Adding a business asks one question — *"Who owns this business?"* → **Just me** (default) or **Shared with others**. Choosing *Just me* creates a plain business book with a single Capital/Drawings pair and **never mentions partners, ratios or profit distribution anywhere in the app**. Only *Shared with others* asks for the owners and their ratio, and only then do partner accounts, the distribution wizard and the partner-position screen exist. Ownership can be changed later (a structural change: requires every current owner's approval and is recorded as a dated envelope).

A business owned by several people or sub-families gets one **Partner Current A/c** per owner (class `partner`, natural balance **Cr** = the business owes them). It is the single place that relationship lives.

**Three distinct events post to it — keeping them distinct is the whole model:**

| Event | Posting | Meaning |
|---|---|---|
| Owner pays a business cost from their own pocket | `Dr Expense · Cr Partner Current` | business now owes them |
| Owner takes money out of the business | `Dr Partner Current · Cr business money a/c` | business owes them less |
| Profit share credited | `Dr Profit Distributed · Cr Partner Current` | business owes them more |

🔒 **The payer never books an expense in their own book.** In their personal book it is `Dr {Business} · Cr Cash` — money owed to them, not an expense. The expense belongs to the business.

**Profit distribution 🔒.** Net profit for the period × each owner's agreed ratio (fixed at business creation), posted as **one multi-line entry**: `Dr Profit Distributed (equity_system) · Cr each Partner Current`. It moves no cash — it converts undistributed surplus into debts the business owes its owners. Using a `Profit Distributed` account preserves §1.2's no-closing-entries rule: accumulated surplus stays computed, and this account records how much of it has been handed out.

🔒 **Contribution never changes the sharing ratio.** Paying more costs does not earn more profit — it earns a larger claim for repayment. The two are separate rows of the same account.

**Settlement 🔒 — default is carry forward.** Three routes, offered at year close after distribution, with *carry forward* preselected:
1. **Business pays out** a partner's balance (needs cash) — `Dr Partner Current · Cr bank`.
2. **Partner-to-partner** settlement outside the business — `Dr {over-funded partner} · Cr {under-funded partner}`: the payer has bought part of the other's claim.
3. **Carry forward** — the balance closes and re-opens under the year-close ceremony (§8.1) as a certified, dated opening balance. Never a remembered number.

**Settlement capacity 🔒.** The partner-position screen states in words whether the business could pay everyone out today: *"The business can settle all partner balances today"* (money accounts ≥ total partner credit balances) or *"Short by ₹X to settle all balances"*. Figures are shown beneath, never left for the reader to subtract.

**Debit balances are real and must be shown 🔒.** An owner who has taken out more than they put in plus their profit share carries a **Dr** balance: *they owe the business*. This is displayed as plainly as the credit case.

**Drift visibility 🔒.** Where one partner's balance exceeds the group average by a configurable margin, the business dashboard shows a quiet card ("Harjit has ₹2,40,000 more with the business than the others"). Informational, never a demand.

**Interest on capital 🔒 — optional, off by default (owner-approved, Phase 1).** The classical remedy for the partner who funds but rarely draws. A per-business setting; enabling, changing the rate, or disabling it requires **every partner's approval** and is recorded as a dated business-setting envelope, so the terms in force for any past period are always recoverable.

- **Computation:** `interest = average daily balance × rate × days in period ÷ 365`, per partner, computed by the app from the ledger itself — never typed. Only **credit** balances earn interest; a partner in debit balance is charged at the same rate unless the setting says otherwise ⚠️.
- **Posting:** it is an **appropriation of profit, not a business expense** — `Dr Profit Distributed · Cr Partner Current`, tagged `interest`, exactly like a profit share but for a different reason. Keeping it out of the expense accounts means the farm's true operating cost is never distorted by how the partners chose to fund it.
- **Order of operations:** interest is credited first, then the **remaining** profit splits by the agreed ratio. Worked illustration on the §7.1 example at 8% for the 122-day season: Amrit ₹4,296 · Sukhdev ₹2,311 · Harjit ₹1,354 (total ₹7,961); remaining profit ₹5,86,039 splits three ways.
- **Rounding:** each partner's interest is computed independently and rounded **half-up to the nearest paisa**; interest is not a ratio split, so the §7.1 remainder rule does not apply to it. The residual profit that is then split *does* use the remainder rule.
- **The distribution preview shows both lines per partner** — interest and share — before anything posts, so the family sees the effect of the setting rather than discovering it.

**Rounding rule 🔒 (applies to every ratio split, including profit shares).** Divide in integer paise; assign each partner `floor(amount × ratio)`; the remainder — always fewer paise than there are partners — goes to the partner with the **largest ratio**, ties broken by the earliest-created partner account. Deterministic on every device, so the split can never break §1.4's sum-to-zero invariant or diverge across the family's phones.

**Business surplus remitted to a family pool is not a drawing 🔒.** It is an ordinary inter-book transfer (§6) between the business book and the pool book. Money the family then takes "as needed" is tracked by the pool's own sub-family accounts. Two separate fairness ledgers — partner accounts for the business, sub-family accounts for the pool — and conflating them corrupts the partnership arithmetic.

## 7.2 Who checks the admin 🔒 (owner-approved, 30 Aug 2026)

The admin holds every permission, so review cannot rely on someone senior to them. Four mechanisms, none of which depends on hierarchy:

1. **Nobody clears their own flag.** A review flag (§3) can only be cleared by a *different* member. Each shared book names a **peer reviewer** — normally another sub-family head — who receives the admin's flagged entries. If a book has exactly one member, no flag is raised (there is nothing to check and nobody to check it).
2. **The admin's own entries can be held to a lower threshold** than everyone else's, per book — a deliberate inversion of the usual hierarchy, off by default, set when the book is created ⚠️ default value to confirm.
3. **A permanent, member-visible admin-actions feed.** Role changes, limit changes, period re-opens, business-setting and ownership changes, member removals and profit distributions are written as signed envelopes and shown to every member of the tenant, forever. The admin can perform these; they cannot perform them quietly.
4. **Closing is a joint act, verified by arithmetic.** The admin cannot close a period alone — each book owner confirms their own book (§8), and every member's device independently recomputes the balance-vector hash. A tampered book fails on other people's phones, not on the admin's.

### 7.2.1 Multiple admins and the quorum rule 🔒 (owner-approved, 30 Aug 2026)

**A book may have any number of admins.** Roles are per-book (06 §1.1), so all three sub-family heads can be admins of the joint business while holding different roles elsewhere. Recommended for any shared book, for one reason beyond convenience: **succession** — with a single admin, a lost phone or a death leaves the book with nobody who can invite, close or manage it.

Admin power then splits in two:

| | Who may act | Examples |
|---|---|---|
| **Routine admin** | any one admin, alone | invite a member, set an auto-post limit, create or rename accounts, lock a period, run the close wizard |
| **Structural** 🔒 | **quorum of owners required** | change the ownership ratio · distribute profit · enable/change/disable interest on capital · add or remove an owner · remove a member · re-open a **closed year** · change the book's financial-year start · delete or archive the book |

**How quorum works.** Each shared book carries a `structural_quorum` setting: **all owners** (default) or a **majority** (⌈n/2⌉ + 1), chosen at creation and itself a structural action to change. An admin *initiates* a structural action; it enters a **pending-structural** state and appears in every owner's Inbox as a distinct card stating exactly what will change ("Ownership ratio: Amrit 40% · Sukhdev 30% · Harjit 30% — currently equal thirds"). It takes effect only when the quorum of **signed approval envelopes** exists; each approval is authored on that owner's own device, so the server cannot manufacture one.

- **Nothing is applied early.** A pending structural action changes no balance and no permission until quorum is reached.
- **Any owner may veto**, which closes the request immediately with a recorded reason.
- **Expiry:** 14 days without quorum → lapsed, logged, re-initiable ⚠️ confirm window.
- **Single-owner books** (a *Just me* business, a personal book) have a quorum of one; the concept is invisible there.
- **Every initiation, approval, veto and lapse** joins the member-visible admin-actions feed (§7.2 item 3) permanently.
- **Period lock stays routine** (a month can be locked by one admin, since §8's independent hash verification already guards it), but **re-opening a closed year is structural** — it voids certified balances and must not be a solo act.

🔒 **The boundary this draws:** the admin's authority is over *structure and permission* — who is a member, what the limits are, when a period locks. It is **not** authority over the truth of the record. That is protected by the append-only journal (§1.4), per-entry author signatures (04 §8.3), independent close verification (§8), and the fact that personal books are cryptographically closed to them (04 §5.2). An admin can add themselves to a book; they cannot make an entry that never happened, alter one that did, or read a member's personal book.

## 8. Periods and locking 🔒

- Periods are calendar months within the book's financial year. States: `open` → `locked` (re-openable by book admin, logged).
- A **lock is itself a signed envelope** with an HLC. Deterministic rule every client applies: an entry whose `accounting_date` falls in period P is valid only if its HLC precedes the HLC of P's lock. Violations from a tampered client are quarantined by every honest reader.
- **Late arrivals** (created offline before the lock, synced after): they are *valid* by the rule above but would silently change closed figures — so they land in a **Late Arrivals tray** for the book's closer, who either re-dates them into the open period (default, one tap) or re-opens the month (admin, logged, requires re-close).
- **Month-close wizard** (this is what replaces the CA):
  1. *Count your cash* — either a single counted figure, or the **denomination sheet** (§8.2); any difference posts a guided adjustment (`Dr/Cr Cash · Cr/Dr Adjustments`) with the difference shown plainly.
  2. *Confirm each bank balance* against the bank's app/statement; differences prompt the reconciliation screen (§10).
  3. *Clear the tray* — every open *needs review* flag (§3), open import line in Suspense (§10), and (warn-only) aged advance.
  4. *Confirm & lock* — the close envelope records the declared balances **and the client-computed balance vector hash; every other member's device recomputes and verifies it**, flagging any mismatch. Books close only when their own arithmetic agrees everywhere.
- **Two distinct surfaces 🔒 (conflict resolved 30 Aug 2026):** (a) the **integrity check** is the always-visible books-balanced card on Home (07 §4) — status, total Dr, total Cr, difference — verifying stored state and catching sync or storage corruption; (b) the **Trial Balance report** exists under Reports (07 §14) and in exports, because the accounting reference is built on it and any accountant will ask for one. The earlier rule that a trial balance "never appears as a report" is superseded: it was written before the verification card was approved.

### 8.1 Financial year close and carry-forward 🔒

The ledger is continuous, so money, party, and advance balances carry forward across 31 March automatically — no amounts are ever re-posted. The **Year Close ceremony** makes that carry-forward official, verified, and displayable, exactly like *"To Balance b/d"* in a paper khata:

- **Year states:** `open` → `closed`, per book. Preconditions to close FY: every month locked, Suspense = 0, **no open review flags** (`review_state = 'open'`, §3) **and no `pending` advance requests** (§7) — these are two distinct queues and both must be empty; businesses are prompted (optional) to run profit distribution first; aged advances warn but don't block.
- **Ceremony:** the closer's device computes the **closing balance vector** (every account) and publishes it as a signed year-close envelope; every member's device independently recomputes and verifies it — the same mechanism as month-close step 4. On success the year flips to `closed` and the vector becomes the **certified opening balances (b/f) of the new FY**.
- **Presentation:** a financial-year switcher on every ledger, report, and export. Each FY view opens with *Opening balance b/f* and ends with *Closing balance c/f*; P&L figures are scoped to the selected FY; printed/exported ledgers carry the b/d and c/d rows so they read exactly like the traditional book.
- **Prior-year corrections:** after a year closes, corrections post as reversals dated in the current FY (§5 already enforces this via month locks). The certified opening of a closed year **never changes** — the fix appears in the year it is made, which is standard practice and keeps every past-year report permanently true once printed.
- **Reopening:** unlocking any month of a closed year voids that year's certificate *and every later year's*, admin-only, loudly warned, logged; re-closing is required in order.
- **Performance and archive:** after a year close, clients compute live balances as *certified opening vector + current-FY envelopes* instead of replaying all history, and closed-year envelopes may be cold-archived server-side and fetched on demand. Ten years of family data stays instant.

---

## 8.2 Cash counts and note denominations 🔒 (owner-approved, 30 Aug 2026)

Any `money` account of subtype **cash** supports a **cash count**: a dated record of how much was physically there and, optionally, **how many notes of each denomination**.

**Denominations are a memo, never a sub-ledger 🔒.** Ordinary entries record value only — requiring a note breakdown on every payment would destroy the 8-second rule (§07 law 1) and is not how cash works anyway, since paying ₹2,400 usually means tendering ₹2,500 and taking change. The composition is captured **at count time** and held as a snapshot on that count.

**Denominations (INR):** ₹500 · ₹200 · ₹100 · ₹50 · ₹20 · ₹10 · coins (₹20/10/5/2/1 entered as a value, not counted individually). ₹2000 is shown only if a previous count used it — still legal tender but rarely held.

### Two kinds of count 🔒 (owner-directed, 30 Aug 2026)
Cash accounts carry a subtype that decides what a count *means*:

| Subtype | Example | Balance before counting | What the count is | Posting |
|---|---|---|---|---|
| `cash` | household cash · shop **galla** (ਗੱਲਾ) · home vault | **known** from entries | a **verification** | equal → no entry, account marked *verified on {date}* · different → one guided adjustment (`Dr/Cr Cash · Cr/Dr Adjustments`) with the count attached as evidence |
| `cash_collection` | gurudwara **gollak** (ਗੋਲਕ) · donation box · hundi · temple thaal | **unknown** — nobody knows what is inside until it is opened | a **recognition of income** | `Dr {collection cash a/c} · Cr {chosen income a/c}` for the full counted amount |

This is the difference a shopkeeper and a granthi would both recognise instantly: the galla's balance is already known from the day's sales, so counting checks it; the gollak's contents are unknown until opened, so counting *creates* the record. Treating them the same would either invent phantom adjustments in a gurudwara or book a shop's daily takings twice.

**A count never moves money 🔒.** Counted gollak cash that stays in the gollak stays on that account — the common real case where the committee counts, records, and leaves the money where it is. Depositing it later is an ordinary Transfer (§2 verb 5). **A count never silently changes a balance without an entry.**

**Denomination sheet: optional by default, mandatory where it matters 🔒.**
- **Organization (trust) books — always mandatory**, for every cash account including plain cash in hand, not only the gollak. A trust must be able to prove every rupee it holds.
- **All other books** — optional; a single counted figure is always accepted.
- **`cash_collection` accounts** additionally require **two names** (*counted by* and *witness*), because a collection count is the one case with no independent record to check against.

**Where it appears:** the Cash A/c statement header shows *"Last counted 27 Aug · 20×500, 15×200, 25×100 …"* with a **Count again** button · month close step 1 (§8) · any time from the account screen · the trust gollak flow, which is this same sheet with two *counted by* name fields.

**Multiple cash accounts** each count separately (shop drawer, home vault, gollak) — this is why cash is an account, not a single global figure.

## 9. Balances and derived state 🔒

All balances are **derived, never stored authoritatively**: balance(account) = Σ signed lines of entries with `status = posted`. Per §3 that is **every saved entry except an advance request still awaiting approval** (§7), which sits at `status = pending` and is excluded until approved — the one case where the money genuinely has not moved. **`review_state` never affects a balance:** a `posted` entry counts in full whether its review flag is open, approved, or rejected (a rejection removes its effect through the mirror reversal, not by excluding the original). Clients maintain a local running-balance cache and per-day snapshots for O(1) rendering of the position screen and reports; the cache is rebuildable from envelopes at any time (*Recompute* in settings, also run automatically on integrity-light ✗). After a year close, the rebuild baseline is the certified opening vector (§8.1) rather than all-time history.

**The position screen** (the product's reason to exist) derives entirely from this section: per selected scope (Me / a book / everything I can see): money accounts with signed balances; You-will-get and You-will-give totals with drill-down and ageing; open advances held and given; in-transit inter-book transfers; this-month income vs expense. One screen, all live-computed, correct offline.

---

## 10. Statement import postings 🔒 (Phase 1: file upload)

**The vocabulary rule 🔒 (owner-directed):** users read bank statements, where *credit = money in* and *debit = money out* — the mirror of our ledger, because the bank keeps its own book (your deposit is its liability). **The engine's Dr/Cr logic never changes; the words the user sees do.** Import screens, entry screens and day-book lists speak only **Money in / Money out**; the bank's own credit/debit column is mapped on read and never shown as "Dr/Cr" to the user. Professional surfaces (A/C statements, trial balance, exports) show true ledger Dr/Cr per 01 §1.9. Mixing the two conventions anywhere in one surface is a defect.

**The one question 🔒:** a statement line already states direction and amount; the only unknown is the **counterpart** — where the money came from or went to. Every import line therefore asks exactly one question — *"Where did it come from?"* (money in) or *"Where did it go?"* (money out) — answered by picking or inline-creating an A/C. The user never sees or chooses a side. This is precisely the gap a paper bank-column notebook cannot fill: it records the balance but not the source, so it can never produce a position, a P&L, or "who owes me".

**Narration 🔒:** the bank's raw text is retained on the envelope for matching and shown greyed for recognition only; whatever the user types is the entry's note and the only narration that appears in their books, statements and exports.

**Transfer pairing 🔒:** money leaving one own-account and arriving in another is **one** event. When an import line matches an opposite line in another own-account (amount equal, date within window), the app asks *"Is this the same money moving between your accounts?"* — one tap posts a single Transfer (02 §2 verb 5) instead of two entries. Un-paired, this is the classic notebook error of counting the same rupees as both an expense and an income.

- Parsed lines land in an **inbox**, never directly in the ledger.
- **Match** to an existing entry (amount within date window ± party/note fuzz): links `refs.import_line`, marks both reconciled. No posting.
- **Confirm as new**: user (or a learned rule) picks the counterpart → normal verb posting with `refs.import_line`.
- **Unknown counterpart**: posts `Dr/Cr Bank · Cr/Dr Suspense (equity_system)`. Suspense must reach zero to pass close step 3 — imported money can be *unexplained* for a while, but never *unrecorded*.
- Duplicate defense: hash of (account, date, amount, normalized description) rejects re-uploads; near-duplicates flag for review.

---

## 11. Acceptance tests (excerpt — full set in 09-acceptance-tests.md)

- **Given** any generated posting from any verb flow (property test across all inputs), **then** lines sum to zero, all integer paise, all accounts in-book.
- **Given** ₹500 *money out* to a party you owe ₹2,000, **then** the party balance becomes ₹1,500 *you will give* and no debtor asset appears.
- **Given** an OD account at +₹10,000 then a ₹25,000 payment, **then** its balance is −₹15,000, it moves to the liabilities side, and no error occurs.
- **Given** a member with limit ₹5,000 entering ₹7,000 in the family book, **then** it posts instantly and balances update, a *needs review* flag notifies the approver; on approve the flag clears with balances untouched; on reject an auto-reversal posts with the reason and balances return to the prior figure, with both entries visible in history.
- **Given** an inter-book transfer where the actor lacks rights in the receiving book, **then** both halves post at once, book B carries a review flag, the pair shows *in transit* until cleared, and Family Reconciliation nets to zero from the moment of entry.
- **Given** an advance of ₹20,000 with ₹17,400 settled and ₹2,600 returned, **then** the advance balance is zero and the ageing list no longer shows it.
- **Given** an advance request awaiting approval **and** an over-limit ordinary entry in the same book, **then** the advance request is `status='pending'` and contributes **nothing** to any balance, while the ordinary entry is `status='posted'` with `review_state='open'` and contributes **in full**; the Inbox lists the second, the advance queue lists the first, and FY close is blocked by both until each is cleared.
- **Given** an entry dated 5 May synced after May's lock but created (HLC) before it, **then** it appears in Late Arrivals and is absent from all report totals until re-dated or the month is re-opened.
- **Given** an envelope whose lines sum to −100 (hostile client), **then** every reading client quarantines it, raises a security event, and no balance includes it.
- **Given** close step 4 on two devices with identical envelope sets, **then** both compute the identical balance-vector hash.
- **Given** the same bank CSV uploaded twice, **then** zero new inbox lines the second time.
- **Given** FY 2026-27 with all months locked and Suspense at zero, **when** Year Close runs, **then** every member device computes an identical closing vector, and the FY 2027-28 view of each ledger opens with those exact figures as *Opening balance b/f*.
- **Given** a correction to an entry in a closed FY, **then** it posts as a reversal dated in the open FY, and the closed year's exported reports are byte-identical before and after the correction.
- **Given** an admin unlocking a month inside a closed FY, **then** that year's certificate and all later years' certificates are voided, the action is logged, and reports for those years show an *uncertified* banner until re-closed in order.

---

## 12. Open items ⚠️

1. Default seeded category trees per book type (household vs shop vs trust) — draft with the family pilot; ship in EN + PA.
2. Reminder-day defaults for advance ageing (15/30 proposed).
3. `channel` tag taxonomy for online/offline filtering (UPI / card / netbanking / cash) — finalize with 07-ui-flows.md.
4. Whether Late Arrivals may auto-post if the month is re-opened anyway — decide after pilot friction is observed.
5. Optional **expert Dr/Cr entry mode** (raw two-line ਨਾਮੇ/ਜਮ੍ਹਾਂ journal screen for professional users) — decide post-pilot; the verb-based entry remains the default and only mode until then.

# ADR 2026-09-09d — No book seeds a bank account, the trust included

ADR 2026-09-09c §1 fixed the seed per book type and, following `07 §3.1` 🔒 and the S9.5 artboard, seeded
a bank account for business, family and trust books. Owner ruled 9 Sep 2026 that a bank is **added, not
seeded** — *"if user want to keep in ledger, user can add during setup or later any time"* — and, on the
trust, *"drop it"*.

The reasoning is `02 §4` itself, which says: **"Every new account asks for its opening balance at creation 🔒 — not only during first-run setup."** ⟦tests: n/a — quotes 02 §4, which carries its own marker⟧
A bank added later is therefore no more work than a bank seeded early: one
tap, and it asks for its balance in the same breath. Seeding it buys nothing, and costs something —
`local_ledger.dart:982` skips zero balances (`if (paise == 0) continue;`), so a bank left blank posts no
entry and simply sits in the ledger under a name the user never chose, as a chore for the S0.7 checklist.

Nothing is lost from the product: `07 §6` already offers **rename** and **delete-if-unused** under ⋮, so a
seeded account is recoverable — but not seeding it is better than making the user undo our guess.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. A bank account is never part of any seed ⟦tests: A-09d-1 @M5⟧
- No `BookType` seeds a bank account — personal, business (either ownership), family, joint or
  organization. ⟦tests: A-09d-1 @M5⟧
- Every book still seeds the cash account it certainly has, its `Opening Balance / Capital A/c`, its
  category tree, and — for a *Just me* business — `Drawings A/c` (ADR 2026-09-09b §2). ⟦tests: A-09d-1 @M5⟧
- A bank arrives through **Add an account** (S3.1's type grid), during setup or at any time after, and
  asks for its opening balance at creation per `02 §4` 🔒. ⟦tests: F1-09d-1 @M5⟧

### 2. `07 §3.1`'s trust seed loses its bank ⟦tests: A-09d-2 @M5⟧
- The trust seed becomes **`Cash`** (the ordinary cash-in-hand A/c every ledger has) and **`Gollak Cash`**
  (`cash_collection`), plus the category accounts it already names — Donation Income, Langar Expense,
  Building Repair, Honorarium. `Trust Bank` is removed from the seed list. ⟦tests: A-09d-2 @M5⟧
- **Everything else in that 🔒 line is untouched**, and this ADR changes none of it: the trust card remains
  the only one setting `tenant.type = organization`; trustee role labels, the gollak as a
  `cash_collection` account and **denomination counting mandatory on every cash account** all stand; and
  🔒 the gollak and the Cash A/c remain **different accounts** — counted money leaves the gollak only by
  deposit, and expenses are never paid straight from it (`02 §8.2`). ⟦tests: A-09d-2 @M5⟧
- A trust that banks — most do — adds its bank on the same screen, one tap, named properly the first time.
  ⟦tests: F1-09d-1 @M5⟧

### 3. The seeded chart is a floor, not a guess ⟦tests: n/a — restates 07 §6 and 02 §4, no new behaviour⟧
- Seed only what the entity **certainly** has. Where we would be guessing, leave it to *Add an account*.
  A wrongly seeded account is a chore the user must notice and undo; a missing one is a tap.

### 4. Nothing is ever dated before the book's start date ⟦tests: A-09d-3⟧
Owner-ruled 9 Sep 2026: *"It should not be before the opening balance, never"* — and, on the boundary,
*"the date on which the first time user recorded the o/b during account setup or ledger book setup."*

- **The book carries a start date, stamped when the book is created.** Owner-ruled *"during account setup
  or ledger book setup"*; **creation**, not first opening balance — a lazy stamp leaves a hole (skip the
  balances, post for a week, record a balance on day 8: the floor lands after entries that already exist).
  Immutable thereafter. It lives on `book_config` (`start_date`, ISO) and is projected to `books_p` — a
  stored property of the book, not a figure derived from the entry stream, so every device agrees on the
  floor the moment it holds the book. ⟦tests: A-09d-3, A-09d-4, A-09d-5, E-09d-1⟧
- **Opening balances are dated at the start date by default**, whenever the account is added — an opening
  balance is the position on the day the books began. If that month is already locked, the adjustment
  lands in the earliest open month, the `02 §8.1` pattern (*"the fix appears in the year it is made"*).
  ⟦tests: A-09d-5⟧
- An entry whose `accounting_date` falls **before the book's start date is refused**. Not warned, not
  allowed with a note. ⟦tests: A-09d-3⟧
- **Why refused and not warned.** The opening balance is a *counted* figure — the user looked in the
  drawer — so everything earlier is already inside it. Posting `Dr Cash 2,000` before it leaves cash
  reading ₹17,000 against ₹15,000 in hand, and the trial balance still balances, so nothing looks broken.
  Worse, the ledger is **append-only** (CLAUDE.md rule 2): a bad back-dated entry can never be deleted,
  only reversed, leaving two entries and a permanent scar. When mistakes are irreversible the door is the
  only cheap point of control. ⟦tests: A-09d-3⟧
- **Nothing is lost by refusing.** A sale from the day before setup is *already* in the counted opening
  figure. Recording it would double it. There is no transaction the user needs that this rule denies them.
  ⟦tests: A-09d-3⟧
- **Re-running opening balances corrects the amounts, never the date.** `02 §4` 🔒 makes guided setup
  *"re-runnable until first lock"* — that exists so a mistyped balance can be fixed, and it leaves the
  start date untouched. ⟦tests: A-09d-5⟧
- **Skipping the balances changes nothing.** The stamp is at creation, so a book whose owner entered no
  balance at all still has its floor — `local_ledger.dart` skips zero balances, and the boundary does not
  depend on any of them. ⟦tests: A-09d-4⟧
- **Per book.** A family with four books has four start dates. ⟦tests: A-09d-3⟧

### 4a. The floor is an authoring guard, never a §1.4 invariant ⟦tests: A-09d-6⟧
This is the difference between a good rule and a support nightmare, so it is stated rather than left to
the implementer.

- `02` (Zero-knowledge consequence) 🔒 says an envelope violating an invariant is **quarantined and raised
  as a security event**. Ruling 4 must therefore **not** be a §1.4 invariant. ⟦tests: A-09d-6⟧
- The case it would break is an ordinary week: Amrit's phone is offline from 7 Sep; Sukhdev records the
  shop's opening balances on 9 Sep; Amrit, still offline and holding a book whose start date has not
  reached her, records a real sale dated 8 Sep. As an invariant, her genuine sale is quarantined and she
  is raised as a security event for using the app offline. ⟦tests: A-09d-6⟧
- So: **the authoring client refuses at `post()`; no reading client rejects, quarantines or hides such an
  entry.** Storing the start date on `book_config` rather than deriving it from entries narrows this race
  sharply — a device that has the book has the boundary — but cannot close it, because a book can exist
  before its opening balances are recorded. ⟦tests: A-09d-6⟧

### 4b. A pre-start entry that arrives by sync goes to the Inbox ⟦tests: A-09d-7 @M5, F1-09d-3 @M5⟧
- When §4a's race happens the book really does hold an entry before its start date, and the opening figure
  really does double-count it. That is nobody's fault and not an attack. ⟦tests: A-09d-7 @M5⟧
- It is raised as a **review flag** (`review_state = 'open'`, `02 §3`) and appears in the **Inbox**, saying
  what happened and offering the two real repairs: correct the opening balance, or reverse the entry.
  ⟦tests: F1-09d-3 @M5⟧
- **Never quarantined**, never silently summed, never hidden. ⟦tests: A-09d-7 @M5⟧

## Consequences
- **Code — shipped 10 Sep 2026, green:** `BookConfig.startDate` (+ `start_date` on the wire, absent on
  older books), `books_p.start_date` (schema **v2**, forward migration `m.addColumn`), `createBook` stamps
  `startDate ?? today()`, `LocalLedger.startDateOf`, `openingBalances` dates at the start by default, and
  `post()` refuses `ViolationKind.beforeBookStart` beside the period-lock check. `beforeBookStart` is the
  one `core_ledger` touch — an **authoring-only** kind, the same standing as `futureDate`; no invariant
  check emits it (`A-09d-6`). S3.1's quick-add no longer passes today's date.
- **Docs:** `07 §3.1` — the 🔒 seed list is edited, marker kept. ADR 2026-09-09c §1's table loses the
  `Trust Bank` and `Bank A/c` entries.
- **Design:** the five S0.6b variants already drawn this way (`partials/new-screens-d.json`). ⚠️ **`S9.5`
  in canvas 4 still draws *Bank A/c · name it later · ₹0*** beside Business Cash and now disagrees with
  the build — it must be updated when the new screens are placed, or design and code drift.
- **Milestone:** M5, lanes U1c–U1f.

## Open ⚠️
- **`E-09d-2`, the v1 → v2 in-place upgrade test, is deferred.** The forward step is one guarded
  `m.addColumn`; proving it needs a full v1 schema fixture (drift's schema-dump tooling), not a
  hand-rolled table. Tracked here so it is not forgotten. ⟦tests: E-09d-2 @M5⟧
- **The refusal copy needs writing in all three languages.** It can no longer offer *"change your starting
  date"* — the start date is immutable (ruling 4). It should say what is true: the books begin on that
  date, and anything earlier is already inside the opening balance. EN/PA/HI via the usual gate.

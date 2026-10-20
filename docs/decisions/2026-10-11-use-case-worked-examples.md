# ADR 2026-10-11 — A second reference set: bookkeeper-grade use-case worked examples for FY 2025-26

**Status:** Proposed — owner ruled 11 Oct 2026 (scope, names, period, labels); ratification waits on the owner's
reading of the README's ⚠️ SPEC list and the bookkeeper's sign-off.

The owner asked for a new accounting reference: one *final report of a ledger book* per use case — individual
with a business, shop, partnership, joint family with its businesses, trust, contractor, farmer — written from
the financial architecture specification (`docs/reference/financial-accounting-standards.md`) and the ledger
rules (`docs/02-ledger-rules.md`, the ADRs on ledger topics) **only**: not from the app's code and not from the
dev demo data. The existing set, `docs/reference/worked-examples/` (five entity types, eight books, 185
vouchers, FY 2026-27), is the behavioural reference CLAUDE.md § *Accounting authority* names and the input of
the suite-A goldens (`A-ref-1…7`); an independent audit of it on 11 Oct 2026 found eleven defects (listed in
the new README §7 with file and voucher citations — gollak used as a spending source, two cash accounts
ending negative, partnership openings not credited to partners, splits in rupees, wrong natural-balance
labels, consumer-only reconciliation wording, b/f rows on category ledgers, a layout that departs from
standards §2 and ADR 2026-09-24b §9, a generator that cannot be re-run, a register without `kind`, and
narrations that do not match their postings). The owner chose **not** to touch that set now and to build the
new one beside it.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. A second reference set lives at `docs/reference/worked-examples/usecases/` (moved there 12 Oct 2026 from `worked-examples-usecases/`, ADR 2026-10-12 §9) ⟦tests: n/a — the set is reference material; the engine test that would consume it does not exist yet (§5)⟧
- Seven use-case files (`.md`, `.html`, `.pdf` each), a `README.md` (+ `.html`/`.pdf`), `fixtures.json`,
  the one generator `build.py` that produces all of them, and `check_md.py`, an independent re-derivation of
  the printed markdown that shares no code with the generator and that `build.py` runs after every generation.
  Python 3 standard library, integer paise everywhere, no clock, no randomness, paths resolved relative to the
  script; two runs from a clean folder are byte-identical (Chrome's PDF dates are pinned).
- **The existing set is untouched** — not its files, not its golden test, not its `content_hash` — and
  **remains the golden set** for `A-ref-1…7` until the owner rules otherwise. The audit findings on it are
  recorded in the new README §7 for the owner to decide; nothing was fixed there.
- The generated files are outputs: a correction is made in `build.py` and everything is regenerated. The old
  set's `joint-business-partnership.md` was hand-edited on 5 Sep 2026 after generation; that must not recur.

### 2. Real names given by the owner are used and committed in this folder ⟦tests: n/a — content policy, not behaviour⟧
- The owner named the people and firms (Jasvinder Singh, Sukhwinder Bal, Pradeep Bal, Harjeet Singh, the
  Randhawa family — Amarjeet, Lakhbeer, Lakhwinder, Indu, Aman, Harjeet, Supreet — Nirmaljeet Gill, Ranjeet
  Singh, Amritpal Singh, Manni, Ravinder, Amar Bal) and ruled on 11 Oct 2026 that they **are** used and
  committed. This reverses, **for this folder only**, the 4 Oct 2026 note at `.gitignore:41` (*real names for
  the dev demo, never committed*); `.demo/` stays ignored and was not read while building this set.
- Names only — no phone numbers, no account numbers. Every figure is illustrative; nothing here is anyone's
  real finances, so CLAUDE.md rule 4 is not engaged.

### 3. The period is the full financial year 2025-26, closed ⟦tests: n/a — reference content⟧
- 01 Apr 2025 – 31 Mar 2026. Every book's immutable start date is 01 Apr 2025 and its openings are dated
  there (ADR 2026-09-09d §4). Every month is locked (02 §8) with cash counts — trust counts with denomination
  sheets, gollak counts with a counter and a witness (02 §8.2) — and every book shows its year close (02 §8.1,
  ADR 2026-09-05e §2): the certified closing vector of money, party, advance, partner and equity_system
  accounts, the year's surplus or deficit as one line, category accounts not carried, *Accumulated surplus* /
  *Corpus* as a computed line, and the FY 2026-27 opening b/f — never a closing journal entry.
- Truck operator and committee (kameti) use cases are deliberately absent (owner, 11 Oct 2026).

### 4. Inter-book links carry plain labels; the class is unchanged ⟦tests: n/a — naming; A-02-78…82 own the pair behaviour⟧
- In this set a 02 §6 pair account is named after the other book and its type —
  `Randhawa Agriculture (family business book)`, `Randhawa Family Fund (joint family book)`,
  `Amarjeet's Family (sub-family book)`, `Jasvinder Technologies (own business book)` — exactly as the
  existing joint-family example names them. The words *Due to/from* do not appear in any account name here.
- The engine is unchanged: the account is `equity_system`, role link, placed by sign, and the README's class
  table says so once. 02 §6's *Due to/from {Book}* stays the engine's internal name.

### 5. ~~What would make this set golden~~ — withdrawn by ADR 2026-10-12 §13 (owner, 13 Oct 2026): the set is archived once the practice set is finalized, without a golden designation ⟦tests: n/a — the test is named here so it can be allocated; it does not exist yet⟧
- **Bookkeeper sign-off** recorded in the README front matter (`approved_by`, `approved_on`), as the existing
  set's governance already requires (ADR 2026-09-05i §3).
- **The owner's ruling on every ⚠️ SPEC reading** in README §5 (S1–S12). Each is the most conservative
  reading where 02 and the ADRs are silent — the kinds carried by advance, partner and one-sided inter-book
  postings (which coincide with the engine's own ⚠️ SPEC reading in
  `packages/core_ledger/lib/src/invariants.dart`, checked 11 Oct 2026); the Suspense clearing posting; the
  accounting date of an approved advance request; FIFO ageing; the credit-only interest setting (02 §7.1's
  open ⚠️, ADR 2026-09-05e Open 2); an owner who is not on the app and `structural_quorum`; construction
  expensed; entry limits on counts and advance spends; count timing; link naming. A ruling that changes a
  reading changes `build.py`, regenerates the set and re-hashes it.
- **A new engine test** in suite A (id to be allocated by the 09 owner; proposed `A-ref-8` for the replay and
  `A-ref-9` for the certified vectors) that consumes `fixtures.json` — every book, account, voucher with
  `kind` and signed paise lines, lock, count and expected balance — and reproduces every ledger, trial
  balance and year-close vector exactly. Until it exists the set proves nothing about the engine; it proves
  only that the rules, as read here, produce books that balance.
- **The `content_hash`** (BLAKE2b-256 over the seven use-case `.md` files, printed by `build.py` and written
  into `fixtures.json`) copied into the README front matter at sign-off, after which any figure change needs
  an ADR and a new hash.


### 6. Owner rulings of 12 Oct 2026 ⟦tests: n/a — reference-document layout and account choice, no engine behaviour⟧
- **Manni Labour A/c and Ravinder Labour A/c are expense heads** (`category_expense`), not party accounts.
  Each labourer is paid his month's wages in cash on the month's last day — `Dr {name} Labour · Cr Cash`,
  a Money out — so nothing is owed at a month end and no party is needed (02 §1.2 would need the person
  as a party only if wages were left unpaid). *Labour A/c* stays for daily-wage labour. This closes the
  former README reading S9.
- **Every book reads in one order:** chart of accounts with every opening balance (Dr = Cr totals) → every
  account's ledger → supporting registers (daybook, corrections, locks and counts, advances, the use-case
  section) → **closing balances (trial balance) → the year's income and expense statement with every
  head's total for the year → Position (07 §14 *Full Position*, by sign) with the make-up of the Corpus /
  Accumulated surplus → year close and next year's b/f.** The statement is named per book type: *Income &
  Expenditure Account* (trust), *Profit & Loss Account* (business), *Income & Expenses* (personal, family).
  These are presentations of figures the engine already computes (02 §8.1, 07 §14); no closing entry is
  posted and nothing new is stored.

## Consequences
- **Docs:** this folder and this ADR only. No numbered spec and no 🔒 line is edited; CLAUDE.md, PLAN.md and
  CHANGELOG.md are left to the orchestrating session. The README's §7 lists the existing set's defects with
  citations for the owner's decision; nothing in `docs/reference/worked-examples/` changed.
- **Code:** none. `packages/`, `app/`, `scripts/`, `server/` are untouched; the suite-A goldens still replay
  the existing set.
- **Repo policy:** `.gitignore:41`'s note is narrowed by §2 for this folder; the `.demo/` ignore rule itself
  is unchanged.
- **Verification performed on 11 Oct 2026:** `build.py` run twice from a clean folder with byte-identical
  output; every trial balance, every ledger's running balances and every year-close vector re-derived from the
  printed markdown by `check_md.py` (committed beside the generator, no shared code; `build.py` runs it after
  every generation and stops on any difference); `build.py --self-test` mutates one guarded posting per
  assertion — the paise remainder, interest rounding and the credit-only setting, capital introduced, owner
  takeout, gollak counter/witness and inflow, who may amend, authored-before-dated, the pocket-expense kind,
  an uncleared Suspense line, negative cash — and confirms each is refused; one ledger per file hand-checked.

## Open ⚠️
1. The twelve ⚠️ SPEC readings (README §5) — each needs the owner's yes or an alternative. (The labourers'
   reading was ruled on 12 Oct 2026 — see §6.)
2. The eleven defects in the existing set (README §7) — correct, re-hash, or replace; until then
   `A-ref-1…7` assert figures the audit disputes (negative cash, rupee splits, b/f on category ledgers).
3. Allocation of the suite-A test ids for this set, and whether the fixtures' `kind` labels for advance,
   partner and one-sided inter-book postings (S1–S3) are the kinds the engine will emit — if the engine
   chooses differently, the fixtures change, not the ledgers.
4. The receiving-book side of an owner's or a partner's takeout is unruled (ADR 2026-09-09b fixes only the
   business side); this set avoids it rather than inventing it, and a personal book that is expected to show
   business takeouts as income needs a ruling first.

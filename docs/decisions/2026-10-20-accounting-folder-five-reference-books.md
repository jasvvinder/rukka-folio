# ADR 2026-10-20 — One accounting folder, five reference books, the original golden set archived

**Status:** Accepted (owner, 20 Oct 2026). Amends ADR 2026-10-12 §4 (where the standard lives), §9 (one home for worked examples), §10–§13 (the practice set and the use-case set), ADR 2026-10-11 §1 and §5, and the file paths in `docs/reference/research/OUTLINE.md`.

The accounting documentation had grown into three worked-example sets in one folder: the original five documents of 30 Aug (still the engine's golden input), the rule-based use-case set of 11 Oct and the ten-book practice set of 12–13 Oct, with the standard and the research beside them. The owner found this confusing and asked for one simple structure, the accounting foundations first and the app requirements after (owner, 15 Oct 2026). On 20 Oct 2026 the 124 questions the research left open were ruled in one pass (`docs/reference/research/OPEN.md`): 113 by the product architect on the owner's delegation, 11 settled by a source and accepted.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. `docs/accounting/` holds all accounting reference material ⟦tests: n/a — file layout⟧
- `README.md` (who keeps these books, what they must produce, how to read the folder), then four documents written from the research notes and the rulings:
  - `01-foundations.md` — basis of accounting, double entry and the kinds of account, books of account, opening a set of books (research topics 1–4);
  - `02-accounts-and-transactions.md` — the rule for each kind of account and transaction: cash and bank, persons, advances, loans, things owned and deposits, goods bought for sale, errors and corrections, entries that move no money (topics 5–12);
  - `03-entities.md` — sole proprietor and household, partnership, joint family, accounts between related books, trusts and committees, landlord (topics 13–18);
  - `04-year-end-and-reports.md` — year end, and what every report contains and states (topics 19–20).
- `reference-books/` — the reference books (§2).
- The documents describe real bookkeeping, independent of the app: no ADR, engine class, build status or test id appears in them (owner, 15 Oct 2026).
- The folder ranks where `docs/reference/` ranked (CLAUDE.md § Precedence 3). Whether it should rank above 02 on accounting matters after the bookkeeper's review: **ruled 22 Oct 2026, ADR 2026-10-22 §1** (yes, on accounting behaviour).

### 2. Five reference books replace the ten practice books 🔒 ⟦tests: A-ref-1, A-ref-2, A-ref-3, A-ref-4, A-ref-5, A-ref-6, A-ref-7⟧
- The five: **individual** (Jasvinder Singh, with Jasvinder Technologies), **joint family** (Randhawa: the family, three sub-families, Agriculture, Real Estate, Brick Field), **shop** (Sukhwinder Sales Co.), **partnership** (Bal Fabricators), **trust** (Radha Soami Satsang Sabha).
- The other five practice books are archived at `docs/archive/reference/practice-books-merged/`. Each of their mechanics moves into the kept book where it is most natural:
  - truck operator → the individual (a vehicle bought on a loan, the EMI split);
  - farmer → the joint family's Agriculture book (KCC, arhtiya);
  - landlord → the joint family's Real Estate book (tenants, deposits, set-off, forfeiture, improvements, rent written off);
  - contractor → Bal Fabricators (a contract job with retention money, a mobilisation advance, supplier advances);
  - committee → the trust (an earmarked fund, its deposit's interest, spending from the fund).
- `reference-books/COVERAGE.md` maps every ruling and mechanic to the book and entry that shows it, so nothing is lost in the merge.
- The books are reworked to follow the rulings of 20 Oct 2026. On the bookkeeper's sign-off they become the golden fixtures of suite A; `scripts/check_coverage.dart` hashes these five files.

### 3. The original five-document set is archived, and its golden tests skipped as superseded 🔒 ⟦tests: A-ref-1, A-ref-2, A-ref-3, A-ref-4, A-ref-5, A-ref-6, A-ref-7⟧
- The 30 Aug set (`individual-rahul-sharma`, `business-sharma-textile`, `trust-singh-sabha-gurudwara`, `joint-family-sharma`, `joint-business-partnership`, with its README, generators and index) moves to `docs/archive/reference/worked-examples-original/`. The 11 Oct audit found eleven defects in it (`docs/archive/reference/worked-examples-usecases/README.md` §7), and it contradicts the rulings of 20 Oct 2026.
- `packages/core_ledger/test/golden_worked_examples_test.dart` (`A-ref-1…7`) is marked `@Skip('superseded by ADR 2026-10-20 §3; re-lands at M14')` and reads the archived path, per the supersession rule (ADR 2026-09-05i §4). Its replacement replays the reference books and lands with the bookkeeper's sign-off, which already blocks the M14 exit.
- CLAUDE.md § *Accounting authority* and 02's header now name `docs/accounting/`.
- `docs/archive/` is excluded from `check_coverage`'s traceability scan; nothing in it is normative (ADR 2026-10-12 §1).

### 4. The use-case set is archived now ⟦tests: n/a — sequencing; no test reads the use-case set⟧
ADR 2026-10-12 §13 is carried out now rather than after the practice review: `usecases/` moves to `docs/archive/reference/worked-examples-usecases/`. ADR 2026-10-11 §5 (its golden path) no longer applies.

### 5. The standard v3 and the research are archived once the four documents land ⟦tests: n/a — sequencing⟧
- `docs/reference/financial-accounting-standards.md` (v3) is archived when `01`–`04` are written; the seven code comments and two spec lines that cite it are re-pointed in the same change.
- The research notes, `OUTLINE.md` and `OPEN.md` are then moved to `docs/archive/reference/accounting-research/` and kept for reference only (owner, 20 Oct 2026). Every rule in `01`–`04` keeps its citation to the external source, so the archived notes are needed only to trace a ruling.

## Consequences
- **Docs.** `docs/accounting/` created; the three old sets archived; CLAUDE.md, 02's header, README, `.gitignore`, the goldens skill, `lane-core`, `testing/fixtures/README.md`, `docs/ops/lead-times.md`, `docs/reference/seed-category-trees.md` and two code comments re-pointed.
- **Tests.** `A-ref-1…7` skipped as superseded (one live skip, re-land M14).
- **App.** Nothing yet. The rulings of 20 Oct 2026 contradict some app behaviour (02 §5 amends a posted entry where the rulings correct by a new entry; 02 §7 requires approval for an advance; ADR 2026-09-05e §2 keeps drawings separate where the rulings close them to capital). Per the owner's order of 15 Oct 2026 these are taken up once, in the app-requirements pass after the bookkeeper's review, not now.

## Open ⚠️
- **Rank.** Should `docs/accounting/`, once a bookkeeper has signed it off, rank above 02 on accounting matters (so 02 is fixed to agree with it), rather than at reference level below 02 as now? A 🔒 change to CLAUDE.md § Precedence; asked 20 Oct 2026. **Ruled 22 Oct 2026 → ADR 2026-10-22 §1.**
